import Synchronization
@_spi(Runners) import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#endif

#if canImport(Darwin)
  private func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.read(fileDescriptor, buffer, count)
  }

  private func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.write(fileDescriptor, buffer, count)
  }
#elseif canImport(Glibc)
  private func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.read(fileDescriptor, buffer, count)
  }

  private func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.write(fileDescriptor, buffer, count)
  }
#elseif canImport(WASILibc)
  private func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe WASILibc.read(fileDescriptor, buffer, count))
  }

  private func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe WASILibc.write(fileDescriptor, buffer, count))
  }
#endif

final class WebSurfaceTransportHost: TerminalHosting, Sendable {
  private struct State: Sendable {
    var surfaceSize: Size
    var renderStyle: TerminalRenderStyle
    var graphicsCapabilities: TerminalGraphicsCapabilities
  }

  private let state: Mutex<State>
  private let outputFileDescriptor: Int32
  private let writeLock = Mutex(())

  let capabilityProfile = TerminalCapabilityProfile(
    glyphLevel: .unicode,
    colorLevel: .trueColor,
    emitsStyleEscapeSequences: false,
    supportsHyperlinks: true,
    supportsMouseReporting: true,
    supportsSynchronizedOutput: false
  )

  init(
    surfaceSize: Size,
    outputFileDescriptor: Int32 = STDOUT_FILENO,
    renderStyle: TerminalRenderStyle
  ) {
    self.outputFileDescriptor = outputFileDescriptor
    state = Mutex(
      State(
        surfaceSize: surfaceSize,
        renderStyle: renderStyle,
        graphicsCapabilities: .none
      )
    )
  }

  var surfaceSize: Size {
    state.withLock(\.surfaceSize)
  }

  var appearance: TerminalAppearance {
    state.withLock(\.renderStyle.appearance)
  }

  var theme: Theme? {
    state.withLock(\.renderStyle.theme)
  }

  var graphicsCapabilities: TerminalGraphicsCapabilities {
    state.withLock(\.graphicsCapabilities)
  }

  func updateSurfaceSize(
    _ surfaceSize: Size,
    cellPixelSize: Size? = nil
  ) {
    state.withLock { state in
      state.surfaceSize = surfaceSize
      state.graphicsCapabilities.cellPixelSize = cellPixelSize
    }
  }

  func updateStyle(
    _ style: TerminalRenderStyle
  ) {
    state.withLock { state in
      state.renderStyle = style
    }
  }

  func enableRawMode() throws {}

  func disableRawMode() throws {}

  func write(_: String) throws {}

  func clearScreen() throws {}

  func moveCursor(to _: Point) throws {}

  @discardableResult
  func present(
    _ surface: RasterSurface
  ) throws -> TerminalPresentationMetrics {
    let bytes = Array(WebSurfaceFrameEncoder.encode(surface).utf8)
    try writeBytes(bytes)
    return TerminalPresentationMetrics(
      bytesWritten: bytes.count,
      linesTouched: max(0, surface.size.height),
      cellsChanged: max(0, surface.size.width) * max(0, surface.size.height),
      strategy: .fullRepaint,
      graphicsReplayScope: surface.imageAttachments.isEmpty ? .none : .full,
      graphicsAttachmentsReplayed: surface.imageAttachments.count
    )
  }

  private func writeBytes(
    _ bytes: [UInt8]
  ) throws {
    guard !bytes.isEmpty else {
      return
    }

    try writeLock.withLock { _ in
      var written = 0
      while written < bytes.count {
        let result = unsafe bytes.withUnsafeBytes { rawBuffer in
          let baseAddress = unsafe rawBuffer.baseAddress?.advanced(by: written)
          return unsafe webSurfaceWrite(
            outputFileDescriptor,
            baseAddress,
            bytes.count - written
          )
        }

        if result < 0 {
          throw TerminalHostError.failedToWrite(errno: errno)
        }

        written += result
      }
    }
  }
}

final class WebSurfaceInputReader: TerminalInputReading, Sendable {
  private let fileDescriptor: Int32
  private let controlHandler: @Sendable (WebSurfaceInputControlMessage) -> Void

  init(
    fileDescriptor: Int32 = STDIN_FILENO,
    controlHandler: @escaping @Sendable (WebSurfaceInputControlMessage) -> Void = { _ in }
  ) {
    self.fileDescriptor = fileDescriptor
    self.controlHandler = controlHandler
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let fileDescriptor = self.fileDescriptor
      let controlHandler = self.controlHandler
      let task = Task.detached {
        var parser = WebSurfaceInputParser()

        while !Task.isCancelled {
          var buffer = Array(repeating: UInt8(0), count: 512)
          let bytesRead = unsafe webSurfaceRead(fileDescriptor, &buffer, buffer.count)

          if bytesRead > 0 {
            let chunk = Array(buffer.prefix(Int(bytesRead)))
            let parsed = parser.feed(chunk)
            for controlMessage in parsed.controlMessages {
              controlHandler(controlMessage)
            }
            for event in coalescedWebSurfaceInputEvents(parsed.events) {
              continuation.yield(event)
            }
            await Task.yield()
            continue
          }

          if bytesRead < 0, errno == EAGAIN || errno == EWOULDBLOCK {
            try? await Task.sleep(nanoseconds: 1_000_000)
            continue
          }

          continuation.finish()
          return
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

enum WebSurfaceInputControlMessage: Equatable, Sendable {
  case resize(Size, cellPixelSize: Size?)
  case style(TerminalRenderStyle)
}

private struct WebSurfaceInputParser {
  private static let introducer: UInt8 = 0x1E

  private var bufferedCommand: [UInt8]?
  private var terminalInputParser = TerminalInputParser()

  mutating func feed(
    _ bytes: [UInt8]
  ) -> (events: [InputEvent], controlMessages: [WebSurfaceInputControlMessage]) {
    var payload: [UInt8] = []
    payload.reserveCapacity(bytes.count)
    var events: [InputEvent] = []
    var controlMessages: [WebSurfaceInputControlMessage] = []

    for byte in bytes {
      if bufferedCommand != nil {
        if byte == 0x0A {
          let command = String(decoding: bufferedCommand ?? [], as: UTF8.self)
          let parsed = parseCommand(command)
          events.append(contentsOf: parsed.events)
          controlMessages.append(contentsOf: parsed.controlMessages)
          bufferedCommand = nil
        } else {
          bufferedCommand?.append(byte)
        }
        continue
      }

      if byte == Self.introducer {
        if !payload.isEmpty {
          events.append(contentsOf: terminalInputParser.feed(payload))
          payload.removeAll(keepingCapacity: true)
        }
        bufferedCommand = []
        continue
      }

      payload.append(byte)
    }

    if !payload.isEmpty {
      events.append(contentsOf: terminalInputParser.feed(payload))
    }

    return (events, controlMessages)
  }

  private func parseCommand(
    _ text: String
  ) -> (events: [InputEvent], controlMessages: [WebSurfaceInputControlMessage]) {
    if let resize = parseResizeCommand(text) {
      return ([], [resize])
    }
    if let style = parseStyleCommand(text) {
      return ([], [style])
    }
    if let event = parseKeyCommand(text) ?? parseMouseCommand(text) ?? parsePasteCommand(text) {
      return ([event], [])
    }
    return ([], [])
  }

  private func parseResizeCommand(
    _ text: String
  ) -> WebSurfaceInputControlMessage? {
    let components = splitCommand(text)
    guard components.count == 3 || components.count == 5,
      components[0] == "resize",
      let width = Int(components[1]),
      let height = Int(components[2])
    else {
      return nil
    }

    let cellPixelSize: Size?
    if components.count == 5,
      let cellWidth = Int(components[3]),
      let cellHeight = Int(components[4])
    {
      cellPixelSize = .init(
        width: max(1, cellWidth),
        height: max(1, cellHeight)
      )
    } else {
      cellPixelSize = nil
    }

    return .resize(
      .init(width: max(1, width), height: max(1, height)),
      cellPixelSize: cellPixelSize
    )
  }

  private func parseStyleCommand(
    _ text: String
  ) -> WebSurfaceInputControlMessage? {
    let prefix = "style:"
    guard text.hasPrefix(prefix) else {
      return nil
    }

    let encoded = String(text.dropFirst(prefix.count))
    guard let style = TerminalRenderStyleCodec.decodeBase64(encoded) else {
      return nil
    }
    return .style(style)
  }

  private func parseKeyCommand(
    _ text: String
  ) -> InputEvent? {
    let components = splitCommand(text)
    guard components.count >= 3, components[0] == "key" else {
      return nil
    }

    let modifiers = parseModifiers(components.last ?? "0")
    if components[1] == "character", components.count == 4,
      let decoded = percentDecodedString(components[2]),
      let character = decoded.first
    {
      return .key(KeyPress(.character(character), modifiers: modifiers))
    }

    guard components.count == 3,
      let key = keyEvent(named: components[1])
    else {
      return nil
    }
    return .key(KeyPress(key, modifiers: modifiers))
  }

  private func parseMouseCommand(
    _ text: String
  ) -> InputEvent? {
    let components = splitCommand(text)
    guard components.count == 8,
      components[0] == "mouse",
      let x = Int(components[2]),
      let y = Int(components[3]),
      let deltaX = Int(components[5]),
      let deltaY = Int(components[6])
    else {
      return nil
    }

    let button = mouseButton(named: components[4])
    let kind: MouseEvent.Kind
    switch components[1] {
    case "down":
      guard let button else { return nil }
      kind = .down(button)
    case "up":
      guard let button else { return nil }
      kind = .up(button)
    case "moved":
      kind = .moved
    case "dragged":
      guard let button else { return nil }
      kind = .dragged(button)
    case "scrolled":
      kind = .scrolled(deltaX: deltaX, deltaY: deltaY)
    default:
      return nil
    }

    return .mouse(
      MouseEvent(
        kind: kind,
        location: .init(x: max(0, x), y: max(0, y)),
        modifiers: parseModifiers(components[7])
      )
    )
  }

  private func parsePasteCommand(
    _ text: String
  ) -> InputEvent? {
    let prefix = "paste:"
    guard text.hasPrefix(prefix),
      let content = percentDecodedString(String(text.dropFirst(prefix.count)))
    else {
      return nil
    }

    return .paste(.init(content: content))
  }

  private func splitCommand(
    _ text: String
  ) -> [String] {
    text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
  }

  private func keyEvent(
    named name: String
  ) -> KeyEvent? {
    switch name {
    case "return":
      return .return
    case "space":
      return .space
    case "tab":
      return .tab
    case "arrowLeft":
      return .arrowLeft
    case "arrowRight":
      return .arrowRight
    case "arrowUp":
      return .arrowUp
    case "arrowDown":
      return .arrowDown
    case "backspace":
      return .backspace
    case "escape":
      return .escape
    case "home":
      return .home
    case "end":
      return .end
    default:
      return nil
    }
  }

  private func mouseButton(
    named name: String
  ) -> MouseButton? {
    switch name {
    case "primary":
      return .primary
    case "middle":
      return .middle
    case "secondary":
      return .secondary
    case "none":
      return nil
    default:
      return nil
    }
  }

  private func parseModifiers(
    _ text: String
  ) -> EventModifiers {
    guard let rawValue = Int(text) else {
      return []
    }
    return EventModifiers(rawValue: UInt8(max(0, min(255, rawValue))))
  }

  private func percentDecodedString(
    _ text: String
  ) -> String? {
    var bytes: [UInt8] = []
    let source = Array(text.utf8)
    var index = 0

    while index < source.count {
      let byte = source[index]
      if byte == 0x25 {
        guard index + 2 < source.count,
          let high = hexadecimalValue(source[index + 1]),
          let low = hexadecimalValue(source[index + 2])
        else {
          return nil
        }
        bytes.append(UInt8(high * 16 + low))
        index += 3
      } else {
        bytes.append(byte)
        index += 1
      }
    }

    return String(decoding: bytes, as: UTF8.self)
  }

  private func hexadecimalValue(
    _ byte: UInt8
  ) -> Int? {
    switch byte {
    case 0x30...0x39:
      return Int(byte - 0x30)
    case 0x41...0x46:
      return Int(byte - 0x41 + 10)
    case 0x61...0x66:
      return Int(byte - 0x61 + 10)
    default:
      return nil
    }
  }
}

private enum WebSurfaceFrameEncoder {
  static func encode(
    _ surface: RasterSurface
  ) -> String {
    var styles: [ResolvedTextStyle?] = [nil]
    let rows = surface.cells.enumerated().map { y, row in
      encodeRow(
        row,
        y: y,
        styles: &styles
      )
    }

    var json = "\u{001E}surface:{"
    json += "\"version\":1"
    json += ",\"width\":\(max(0, surface.size.width))"
    json += ",\"height\":\(max(0, surface.size.height))"
    json += ",\"styles\":["
    json += styles.map(encodeStyle).joined(separator: ",")
    json += "]"
    json += ",\"rows\":["
    json += rows.joined(separator: ",")
    json += "]"
    json += ",\"images\":[]"
    json += "}\n"
    return json
  }

  private static func encodeRow(
    _ row: [RasterCell],
    y _: Int,
    styles: inout [ResolvedTextStyle?]
  ) -> String {
    var encodedCells: [String] = []
    encodedCells.reserveCapacity(row.count)

    for (x, cell) in row.enumerated() {
      guard !cell.isContinuation else {
        continue
      }
      let styleIndex = index(of: cell.style, in: &styles)
      encodedCells.append(
        "[\(x),\(jsonString(String(cell.character))),\(max(1, cell.spanWidth)),\(styleIndex)]"
      )
    }

    return "[" + encodedCells.joined(separator: ",") + "]"
  }

  private static func index(
    of style: ResolvedTextStyle?,
    in styles: inout [ResolvedTextStyle?]
  ) -> Int {
    if let existing = styles.firstIndex(where: { $0 == style }) {
      return existing
    }
    styles.append(style)
    return styles.count - 1
  }

  private static func encodeStyle(
    _ style: ResolvedTextStyle?
  ) -> String {
    guard let style else {
      return "null"
    }

    var fields: [String] = []
    if let foregroundColor = style.foregroundColor {
      fields.append("\"fg\":\(jsonString(foregroundColor.hexString(format: .rrggbbaa)))")
    }
    if let backgroundColor = style.backgroundColor {
      fields.append("\"bg\":\(jsonString(backgroundColor.hexString(format: .rrggbbaa)))")
    }
    if !style.emphasis.isEmpty {
      fields.append("\"em\":\(style.emphasis.rawValue)")
    }
    if let underlineStyle = style.underlineStyle {
      fields.append("\"underline\":\(encodeLineStyle(underlineStyle))")
    }
    if let strikethroughStyle = style.strikethroughStyle {
      fields.append("\"strikethrough\":\(encodeLineStyle(strikethroughStyle))")
    }
    if style.opacity < 1 {
      fields.append("\"opacity\":\(style.opacity)")
    }

    return "{" + fields.joined(separator: ",") + "}"
  }

  private static func encodeLineStyle(
    _ style: TextLineStyle
  ) -> String {
    var fields = ["\"pattern\":\(jsonString(style.pattern.rawValue))"]
    if let color = style.color {
      fields.append("\"color\":\(jsonString(color.hexString(format: .rrggbbaa)))")
    }
    return "{" + fields.joined(separator: ",") + "}"
  }

  private static func jsonString(
    _ text: String
  ) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x22:
        result += "\\\""
      case 0x5C:
        result += "\\\\"
      case 0x08:
        result += "\\b"
      case 0x0C:
        result += "\\f"
      case 0x0A:
        result += "\\n"
      case 0x0D:
        result += "\\r"
      case 0x09:
        result += "\\t"
      case 0x00...0x1F:
        var hex = String(scalar.value, radix: 16, uppercase: true)
        while hex.count < 4 {
          hex = "0" + hex
        }
        result += "\\u\(hex)"
      default:
        result.unicodeScalars.append(scalar)
      }
    }
    result += "\""
    return result
  }
}

private func coalescedWebSurfaceInputEvents(
  _ events: [InputEvent]
) -> [InputEvent] {
  guard !events.isEmpty else {
    return []
  }

  var coalesced: [InputEvent] = []
  var pendingMouseEvent: MouseEvent?

  func flushPendingMouseEvent() {
    guard let mouseEvent = pendingMouseEvent else {
      return
    }
    coalesced.append(.mouse(mouseEvent))
    pendingMouseEvent = nil
  }

  for event in events {
    switch event {
    case .key, .paste:
      flushPendingMouseEvent()
      coalesced.append(event)
    case .mouse(let mouseEvent):
      switch mouseEvent.kind {
      case .moved, .dragged, .scrolled:
        if let existing = pendingMouseEvent,
          let merged = mergeWebSurfaceMouseEvents(existing, mouseEvent)
        {
          pendingMouseEvent = merged
        } else {
          flushPendingMouseEvent()
          pendingMouseEvent = mouseEvent
        }
      case .down, .up:
        flushPendingMouseEvent()
        coalesced.append(event)
      }
    }
  }

  flushPendingMouseEvent()
  return coalesced
}

private func mergeWebSurfaceMouseEvents(
  _ lhs: MouseEvent,
  _ rhs: MouseEvent
) -> MouseEvent? {
  guard lhs.location == rhs.location, lhs.modifiers == rhs.modifiers else {
    return nil
  }

  switch (lhs.kind, rhs.kind) {
  case (.scrolled(let lhsDeltaX, let lhsDeltaY), .scrolled(let rhsDeltaX, let rhsDeltaY)):
    return .init(
      kind: .scrolled(deltaX: lhsDeltaX + rhsDeltaX, deltaY: lhsDeltaY + rhsDeltaY),
      location: rhs.location,
      modifiers: rhs.modifiers
    )
  default:
    return rhs
  }
}
