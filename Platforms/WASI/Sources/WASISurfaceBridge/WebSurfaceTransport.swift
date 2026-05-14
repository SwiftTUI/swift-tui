@_spi(Runners) public import SwiftTUIRuntime
import Synchronization

/// Container format the web-surface transport advertises to the JS
/// side. Mirrors the JSON `format` field on each transmitted image
/// record, and disambiguates the MIME type that the consumer will
/// pass to `Blob`/`<img>` when decoding.
enum WebSurfaceImageFormat: Sendable, Equatable {
  case png
  case jpeg
  case gif

  /// String that appears in the surface JSON's `format` field — and
  /// becomes the suffix of `image/<value>` in the consumer's MIME.
  var jsonValue: String {
    switch self {
    case .png: return "png"
    case .jpeg: return "jpeg"
    case .gif: return "gif"
    }
  }
}

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#endif

#if canImport(Darwin)
  private func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe Darwin.open(pathPointer, O_RDONLY)
    }
  }

  private func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    Darwin.close(fileDescriptor)
  }

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
  private func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe Glibc.open(pathPointer, Glibc.O_RDONLY)
    }
  }

  private func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    Glibc.close(fileDescriptor)
  }

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
  private func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe WASILibc.open(pathPointer, WASILibc.O_RDONLY)
    }
  }

  private func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    WASILibc.close(fileDescriptor)
  }

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

package final class WebSurfaceTransport: PresentationSurface, ClipboardWritingPresentationSurface,
  DamageAwareSemanticPresentationSurface, Sendable
{
  private struct State: Sendable {
    var surfaceSize: CellSize
    var renderStyle: TerminalRenderStyle
    var graphicsCapabilities: TerminalGraphicsCapabilities
    var pointerInputCapabilities: PointerInputCapabilities
    var transmittedImageIDs: Set<String>
  }

  private let state: Mutex<State>
  private let outputFileDescriptor: Int32
  private let writeLock = Mutex(())

  package let capabilityProfile = TerminalCapabilityProfile(
    glyphLevel: .unicode,
    colorLevel: .trueColor,
    emitsStyleEscapeSequences: false,
    supportsHyperlinks: true,
    supportsMouseReporting: true,
    supportsSynchronizedOutput: false
  )

  package init(
    surfaceSize: CellSize,
    outputFileDescriptor: Int32 = STDOUT_FILENO,
    renderStyle: TerminalRenderStyle
  ) {
    self.outputFileDescriptor = outputFileDescriptor
    state = Mutex(
      State(
        surfaceSize: surfaceSize,
        renderStyle: renderStyle,
        graphicsCapabilities: .none,
        pointerInputCapabilities: .cellOnly,
        transmittedImageIDs: []
      )
    )
  }

  package var surfaceSize: CellSize {
    state.withLock(\.surfaceSize)
  }

  package var appearance: TerminalAppearance {
    state.withLock(\.renderStyle.appearance)
  }

  package var theme: Theme? {
    state.withLock(\.renderStyle.theme)
  }

  package var graphicsCapabilities: TerminalGraphicsCapabilities {
    state.withLock(\.graphicsCapabilities)
  }

  package var pointerInputCapabilities: PointerInputCapabilities {
    state.withLock(\.pointerInputCapabilities)
  }

  package func updateSurfaceSize(
    _ surfaceSize: CellSize,
    cellPixelSize: PixelSize? = nil
  ) {
    state.withLock { state in
      state.surfaceSize = surfaceSize
      state.graphicsCapabilities.cellPixelSize = cellPixelSize
      state.pointerInputCapabilities = Self.pointerInputCapabilities(
        for: cellPixelSize
      )
    }
  }

  private static func pointerInputCapabilities(
    for cellPixelSize: PixelSize?
  ) -> PointerInputCapabilities {
    guard let cellPixelSize else {
      return .cellOnly
    }
    return PointerInputCapabilities(
      precision: .subCell(
        source: .webPixels,
        metrics: CellPixelMetrics(
          width: cellPixelSize.width,
          height: cellPixelSize.height,
          source: .reported
        )
      ),
      supportsHover: true
    )
  }

  package func updateStyle(
    _ style: TerminalRenderStyle
  ) {
    state.withLock { state in
      state.renderStyle = style
    }
  }

  package func enableRawMode() throws {}

  package func disableRawMode() throws {}

  package func write(_: String) throws {}

  package func clearScreen() throws {}

  package func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  @MainActor
  package func writeClipboard(_ text: String) throws -> Bool {
    let bytes = Array(WebSurfaceFrameEncoder.encodeClipboard(text).utf8)
    try writeBytes(bytes)
    return true
  }

  package func notifyRuntimeIssue(_ issue: RuntimeIssue) throws {
    try writeBytes(Array(WebSurfaceFrameEncoder.encodeRuntimeIssue(issue).utf8))
  }

  @discardableResult
  package func present(
    _ surface: RasterSurface
  ) throws -> TerminalPresentationMetrics {
    let bytes = state.withLock { state in
      Array(
        WebSurfaceFrameEncoder.encode(
          surface,
          damage: nil,
          knownImageIDs: &state.transmittedImageIDs
        ).utf8
      )
    }
    try writeBytes(bytes)
    return .rasterHostMetrics(
      for: surface,
      damage: nil,
      bytesWritten: bytes.count
    )
  }

  @discardableResult
  package func present(
    _ surface: RasterSurface,
    semanticSnapshot: SemanticSnapshot,
    focusedIdentity: Identity?,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    let bytes = state.withLock { state in
      Array(
        WebSurfaceFrameEncoder.encode(
          surface,
          semanticSnapshot: semanticSnapshot,
          focusedIdentity: focusedIdentity,
          damage: damage,
          knownImageIDs: &state.transmittedImageIDs
        ).utf8
      )
    }
    try writeBytes(bytes)
    return .rasterHostMetrics(
      for: surface,
      damage: damage,
      bytesWritten: bytes.count
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

package final class WebSurfaceInputReader: TerminalInputReading, Sendable {
  private let fileDescriptor: Int32
  private let controlHandler: @Sendable (WebSurfaceInputControlMessage) -> Void

  package init(
    fileDescriptor: Int32 = STDIN_FILENO,
    controlHandler: @escaping @Sendable (WebSurfaceInputControlMessage) -> Void = { _ in }
  ) {
    self.fileDescriptor = fileDescriptor
    self.controlHandler = controlHandler
  }

  package func inputEvents() -> AsyncStream<InputEvent> {
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

@_spi(WebHost) public enum WebSurfaceInputControlMessage: Equatable, Sendable {
  case resize(CellSize, cellPixelSize: PixelSize?)
  case style(TerminalRenderStyle)
}

@_spi(WebHost) public struct WebSurfaceInputParser {
  private static let introducer: UInt8 = 0x1E

  private var bufferedCommand: [UInt8]?
  private var terminalInputParser = TerminalInputParser()
  private var cellPixelSize: PixelSize?

  @_spi(WebHost) public init() {}

  @_spi(WebHost) public mutating func feed(
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

  private mutating func parseCommand(
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

  private mutating func parseResizeCommand(
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

    let cellPixelSize: PixelSize?
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
    self.cellPixelSize = cellPixelSize

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
      let x = Double(components[2]),
      let y = Double(components[3]),
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
        location: pointerLocation(x: x, y: y),
        modifiers: parseModifiers(components[7])
      )
    )
  }

  private func pointerLocation(
    x: Double,
    y: Double
  ) -> PointerLocation {
    guard let cellPixelSize else {
      return .cellFallback(Point(x: x, y: y).containingCell)
    }
    let location = Point(x: x, y: y)
    return .subCell(
      location: location,
      source: .webPixels,
      metrics: CellPixelMetrics(
        width: cellPixelSize.width,
        height: cellPixelSize.height,
        source: .reported
      ),
      rawPixel: PixelPoint(
        x: x * Double(cellPixelSize.width),
        y: y * Double(cellPixelSize.height)
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

@_spi(WebHost) public enum WebSurfaceFrameEncoder {
  @_spi(WebHost) public static func encodeClipboard(
    _ text: String
  ) -> String {
    "\u{001E}clipboard:{\"text\":\(jsonString(text))}\n"
  }

  @_spi(WebHost) public static func encodeRuntimeIssue(
    _ issue: RuntimeIssue
  ) -> String {
    var fields = [
      "\"severity\":\(jsonString(issue.severity.rawValue))",
      "\"code\":\(jsonString(issue.code))",
      "\"message\":\(jsonString(issue.message))",
      "\"description\":\(jsonString(issue.description))",
    ]
    if let identity = issue.identity {
      fields.append("\"identity\":\(jsonString(identity.path))")
    }
    if let source = issue.source {
      fields.append("\"source\":\(jsonString(source))")
    }
    return "\u{001E}runtimeIssue:{\(fields.joined(separator: ","))}\n"
  }

  @_spi(WebHost) public static func encode(
    _ surface: RasterSurface
  ) -> String {
    var knownImageIDs: Set<String> = []
    return encode(
      surface,
      damage: nil,
      knownImageIDs: &knownImageIDs
    )
  }

  @_spi(WebHost) public static func encode(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) -> String {
    var knownImageIDs: Set<String> = []
    return encode(
      surface,
      damage: damage,
      knownImageIDs: &knownImageIDs
    )
  }

  @_spi(WebHost) public static func encode(
    _ surface: RasterSurface,
    damage: PresentationDamage? = nil,
    knownImageIDs: inout Set<String>
  ) -> String {
    encode(
      surface,
      semanticSnapshot: nil,
      focusedIdentity: nil,
      damage: damage,
      knownImageIDs: &knownImageIDs
    )
  }

  @_spi(WebHost) public static func encode(
    _ surface: RasterSurface,
    semanticSnapshot: SemanticSnapshot,
    focusedIdentity: Identity? = nil,
    damage: PresentationDamage? = nil
  ) -> String {
    var knownImageIDs: Set<String> = []
    return encode(
      surface,
      semanticSnapshot: semanticSnapshot,
      focusedIdentity: focusedIdentity,
      damage: damage,
      knownImageIDs: &knownImageIDs
    )
  }

  @_spi(WebHost) public static func encode(
    _ surface: RasterSurface,
    semanticSnapshot: SemanticSnapshot,
    focusedIdentity: Identity? = nil,
    damage: PresentationDamage? = nil,
    knownImageIDs: inout Set<String>
  ) -> String {
    encode(
      surface,
      semanticSnapshot: Optional(semanticSnapshot),
      focusedIdentity: focusedIdentity,
      damage: damage,
      knownImageIDs: &knownImageIDs
    )
  }

  private static func encode(
    _ surface: RasterSurface,
    semanticSnapshot: SemanticSnapshot?,
    focusedIdentity: Identity?,
    damage: PresentationDamage?,
    knownImageIDs: inout Set<String>
  ) -> String {
    var styles: [ResolvedTextStyle?] = [nil]
    let rows = surface.cells.enumerated().map { y, row in
      encodeRow(
        row,
        y: y,
        styles: &styles
      )
    }
    let accessibilityTree = semanticSnapshot.map {
      encodeAccessibilityTree(
        $0.accessibilityNodes,
        focusedIdentity: focusedIdentity
      )
    }
    let accessibilityAnnouncements = semanticSnapshot.map {
      encodeAccessibilityAnnouncements($0.accessibilityAnnouncements)
    }
    let version =
      accessibilityTree?.isEmpty == false || accessibilityAnnouncements?.isEmpty == false ? 2 : 1

    var json = "\u{001E}surface:{"
    json += "\"version\":\(version)"
    json += ",\"width\":\(max(0, surface.size.width))"
    json += ",\"height\":\(max(0, surface.size.height))"
    json += ",\"styles\":["
    json += styles.map(encodeStyle).joined(separator: ",")
    json += "]"
    json += ",\"rows\":["
    json += rows.joined(separator: ",")
    json += "]"
    json += ",\"images\":["
    json += encodeImages(
      surface.imageAttachments,
      knownImageIDs: &knownImageIDs
    ).joined(separator: ",")
    json += "]"
    if let damage {
      json += ",\"damage\":"
      json += encodeDamage(damage)
    }
    if let accessibilityTree, !accessibilityTree.isEmpty {
      json += ",\"accessibilityTree\":["
      json += accessibilityTree.joined(separator: ",")
      json += "]"
    }
    if let accessibilityAnnouncements, !accessibilityAnnouncements.isEmpty {
      json += ",\"accessibilityAnnouncements\":["
      json += accessibilityAnnouncements.joined(separator: ",")
      json += "]"
    }
    json += "}\n"
    return json
  }

  private static func encodeDamage(
    _ damage: PresentationDamage
  ) -> String {
    let fields = [
      "\"textRows\":[\(damage.textRows.map(encodeDamageTextRow).joined(separator: ","))]",
      "\"requiresFullTextRepaint\":\(damage.requiresFullTextRepaint ? "true" : "false")",
      "\"requiresFullGraphicsReplay\":\(damage.requiresFullGraphicsReplay ? "true" : "false")",
    ]
    return "{" + fields.joined(separator: ",") + "}"
  }

  private static func encodeDamageTextRow(
    _ row: PresentationDamage.TextRow
  ) -> String {
    let ranges = row.columnRanges.map { range in
      "[\(range.lowerBound),\(range.upperBound)]"
    }.joined(separator: ",")
    return "[\(row.row),[\(ranges)]]"
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

  private static func encodeAccessibilityTree(
    _ nodes: [AccessibilityNode],
    focusedIdentity: Identity?
  ) -> [String] {
    nodes.map { node in
      var fields = [
        "\"id\":\(jsonString(node.identity.path))",
        "\"rect\":\(encodeRect(node.rect))",
        "\"role\":\(jsonString(node.role.description))",
        "\"isFocused\":\(node.identity == focusedIdentity ? "true" : "false")",
      ]
      if let parentIdentity = node.parentIdentity {
        fields.append("\"parentId\":\(jsonString(parentIdentity.path))")
      }
      if let label = node.label {
        fields.append("\"label\":\(jsonString(label))")
      }
      if let hint = node.hint {
        fields.append("\"hint\":\(jsonString(hint))")
      }
      if let liveRegion = node.liveRegion {
        fields.append("\"liveRegion\":\(jsonString(liveRegion.description))")
      }
      if let cursorAnchor = node.cursorAnchor {
        fields.append("\"cursorAnchor\":\(encodePoint(cursorAnchor))")
      }
      return "{" + fields.joined(separator: ",") + "}"
    }
  }

  private static func encodeAccessibilityAnnouncements(
    _ announcements: [AccessibilityAnnouncement]
  ) -> [String] {
    announcements.map { announcement in
      "{"
        + "\"message\":\(jsonString(announcement.message)),"
        + "\"politeness\":\(jsonString(announcement.politeness.description))"
        + "}"
    }
  }

  private static func encodeImages(
    _ attachments: [RasterImageAttachment],
    knownImageIDs: inout Set<String>
  ) -> [String] {
    attachments.compactMap { attachment in
      encodeImage(
        attachment,
        knownImageIDs: &knownImageIDs
      )
    }
  }

  private static func encodeImage(
    _ attachment: RasterImageAttachment,
    knownImageIDs: inout Set<String>
  ) -> String? {
    guard let bytes = imageBytes(for: attachment), !attachment.visibleBounds.isEmpty else {
      return nil
    }
    let format = imageFormat(for: bytes)

    let imageID = webImageID(for: bytes, format: format)
    let shouldTransmitData = knownImageIDs.insert(imageID).inserted
    var fields = [
      "\"id\":\(jsonString(imageID))",
      "\"format\":\(jsonString(format.jsonValue))",
      "\"bounds\":\(encodeRect(attachment.bounds))",
      "\"visibleBounds\":\(encodeRect(attachment.visibleBounds))",
      "\"scalingMode\":\(jsonString(attachment.scalingMode.rawValue))",
    ]
    if let pixelSize = attachment.pixelSize {
      fields.append("\"pixelSize\":\(encodeSize(pixelSize))")
    }
    if shouldTransmitData {
      fields.append("\"dataBase64\":\(jsonString(base64Encoded(bytes)))")
    }
    return "{" + fields.joined(separator: ",") + "}"
  }

  private static func imageBytes(
    for attachment: RasterImageAttachment
  ) -> [UInt8]? {
    switch attachment.resolvedReference {
    case .embeddedImage(let bytes):
      return bytes
    case .filePath(let path):
      return webSurfaceReadFileBytes(at: path)
    case .namedResource, nil:
      break
    }

    if case .data(let bytes) = attachment.source {
      return bytes
    }
    return nil
  }

  /// Detects the container format from the leading magic bytes. Used
  /// to set the JSON `format` field and pick a MIME type on the JS
  /// side. Defaults to PNG so unknown blobs at least try the most
  /// common path.
  private static func imageFormat(
    for bytes: [UInt8]
  ) -> WebSurfaceImageFormat {
    if bytes.count >= 8,
      bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
      bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A
    {
      return .png
    }
    if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
      return .jpeg
    }
    if bytes.count >= 6,
      bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38,
      bytes[4] == 0x37 || bytes[4] == 0x39, bytes[5] == 0x61
    {
      return .gif
    }
    return .png
  }

  private static func encodeRect(
    _ rect: CellRect
  ) -> String {
    "[\(rect.origin.x),\(rect.origin.y),\(rect.size.width),\(rect.size.height)]"
  }

  private static func encodeSize(
    _ size: PixelSize
  ) -> String {
    "[\(size.width),\(size.height)]"
  }

  private static func encodePoint(
    _ point: CellPoint
  ) -> String {
    "[\(point.x),\(point.y)]"
  }

  private static func webImageID(
    for bytes: [UInt8],
    format: WebSurfaceImageFormat
  ) -> String {
    "\(format.jsonValue):\(hexString(fnv1a64(bytes))):\(bytes.count)"
  }

  private static func fnv1a64(
    _ bytes: [UInt8]
  ) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in bytes {
      hash ^= UInt64(byte)
      hash &*= 0x100_0000_01b3
    }
    return hash
  }

  private static func hexString(
    _ value: UInt64
  ) -> String {
    var text = String(value, radix: 16, uppercase: false)
    while text.count < 16 {
      text = "0" + text
    }
    return text
  }

  private static func base64Encoded(
    _ bytes: [UInt8]
  ) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    var result: [UInt8] = []
    result.reserveCapacity(((bytes.count + 2) / 3) * 4)

    var index = 0
    while index < bytes.count {
      let first = Int(bytes[index])
      let second = index + 1 < bytes.count ? Int(bytes[index + 1]) : 0
      let third = index + 2 < bytes.count ? Int(bytes[index + 2]) : 0
      let combined = (first << 16) | (second << 8) | third

      result.append(alphabet[(combined >> 18) & 0x3F])
      result.append(alphabet[(combined >> 12) & 0x3F])
      result.append(
        index + 1 < bytes.count ? alphabet[(combined >> 6) & 0x3F] : UInt8(ascii: "=")
      )
      result.append(index + 2 < bytes.count ? alphabet[combined & 0x3F] : UInt8(ascii: "="))
      index += 3
    }

    return String(decoding: result, as: UTF8.self)
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

private func webSurfaceReadFileBytes(
  at path: String
) -> [UInt8]? {
  let fileDescriptor = webSurfaceOpenRead(path)
  guard fileDescriptor >= 0 else {
    return nil
  }
  defer {
    _ = webSurfaceClose(fileDescriptor)
  }

  var bytes: [UInt8] = []
  var buffer = [UInt8](repeating: 0, count: 8 * 1024)
  let bufferCount = buffer.count
  while true {
    let readCount = unsafe buffer.withUnsafeMutableBytes { rawBuffer in
      unsafe webSurfaceRead(
        fileDescriptor,
        rawBuffer.baseAddress,
        bufferCount
      )
    }
    if readCount < 0 {
      return nil
    }
    if readCount == 0 {
      return bytes
    }
    bytes.append(contentsOf: buffer.prefix(readCount))
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
    case .key, .paste, .drop:
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
  guard lhs.location.precision == rhs.location.precision,
    lhs.modifiers == rhs.modifiers
  else {
    return nil
  }

  switch (lhs.kind, rhs.kind) {
  case (.scrolled(let lhsDeltaX, let lhsDeltaY), .scrolled(let rhsDeltaX, let rhsDeltaY))
  where lhs.location.cell == rhs.location.cell:
    return .init(
      kind: .scrolled(deltaX: lhsDeltaX + rhsDeltaX, deltaY: lhsDeltaY + rhsDeltaY),
      location: rhs.location,
      modifiers: rhs.modifiers
    )
  case (.moved, .moved):
    return rhs
  case (.dragged(let lhsButton), .dragged(let rhsButton)) where lhsButton == rhsButton:
    return rhs
  default:
    return nil
  }
}
