@_spi(Runners) package import SwiftTUIRuntime

// The web-surface input parser.
//
// `WebSurfaceInputParser` is the incremental byte parser for the WASI web
// surface's input protocol: it separates the raw terminal-input byte stream
// from newline-terminated control commands introduced by a `0x1E` byte
// (`resize`, `style`, `key`, `mouse`, `paste`). The parser is stateful — it
// buffers a partial command across `feed` calls and tracks the most recent
// reported cell-pixel size so pointer locations can be resolved to sub-cell
// precision.
//
// Split out of `WebSurfaceInput.swift` so that file stays focused on the
// `WebSurfaceInputReader` async stream and its event coalescing.

package struct WebSurfaceInputParser {
  private static let introducer: UInt8 = 0x1E

  private var bufferedCommand: [UInt8]?
  private var terminalInputParser = TerminalInputParser()
  private var cellPixelSize: PixelSize?

  package init() {}

  package mutating func feed(
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

    // The web surface delivers input as complete messages, so a lone ESC the
    // byte parser is holding for escape disambiguation is a finished Escape
    // keypress — flush it now rather than stranding it until the next message.
    events.append(contentsOf: terminalInputParser.flush())

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
    let location = Point(x: x, y: y)
    guard let cellPixelSize else {
      return .subCell(
        location: location,
        source: .webPixels,
        metrics: .estimated
      )
    }
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
    case "insert":
      return .insert
    case "delete":
      return .delete
    case "pageUp":
      return .pageUp
    case "pageDown":
      return .pageDown
    default:
      // Function keys arrive as "f1"…"f24" (mirroring DOM `key` values
      // lowercased into this wire's naming convention). Unknown names keep
      // falling through to nil, so an older page bundle degrades to dropping
      // the key rather than misdelivering it.
      if name.count >= 2, name.hasPrefix("f"),
        let number = Int(name.dropFirst()), (1...24).contains(number)
      {
        return .functionKey(number)
      }
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
