import SwiftTUICore

/// Returns `true` when `buffer` begins with the 6-byte bracketed-paste
/// start marker `ESC [ 2 0 0 ~`.  Pure and side-effect free.
private func matchesBracketedPasteStart(_ buffer: [UInt8]) -> Bool {
  let marker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
  guard buffer.count >= marker.count else { return false }
  for index in 0..<marker.count where buffer[index] != marker[index] {
    return false
  }
  return true
}

/// Incrementally parses terminal bytes into normalized keyboard and mouse
/// events.
public struct TerminalInputParser: Sendable {
  private var bufferedBytes: [UInt8] = []
  private var mouseCoordinateMode: MouseCoordinateMode

  public init() {
    self.init(mouseCoordinateMode: .cells)
  }

  package init(
    mouseCoordinateMode: MouseCoordinateMode
  ) {
    self.mouseCoordinateMode = mouseCoordinateMode
  }

  /// Feeds raw bytes into the parser and returns any completed input events.
  public mutating func feed(_ bytes: [UInt8]) -> [InputEvent] {
    bufferedBytes.append(contentsOf: bytes)

    var events: [InputEvent] = []
    while let event = parseNextEvent() {
      events.append(event)
    }
    return events
  }
}

/// A keyboard-only view of ``TerminalInputParser``.
public struct KeyParser: Sendable {
  private var parser = TerminalInputParser()

  public init() {}

  /// Feeds raw bytes into the parser and returns only keyboard events.
  public mutating func feed(_ bytes: [UInt8]) -> [KeyPress] {
    parser.feed(bytes).compactMap {
      guard case .key(let keyPress) = $0 else {
        return nil
      }
      return keyPress
    }
  }
}

extension TerminalInputParser {
  private mutating func parseNextEvent() -> InputEvent? {
    guard let firstByte = bufferedBytes.first else {
      return nil
    }

    switch firstByte {
    case 0x08, 0x7F:
      // 0x08 (Ctrl+H) and 0x7F (DEL) both map to backspace. This must be
      // matched before the Ctrl-letter range so 0x08 is not swallowed as Ctrl+H.
      bufferedBytes.removeFirst()
      return .key(KeyPress(.backspace))
    case 0x01...0x02, 0x04...0x07, 0x0B...0x0C, 0x0E...0x1A:
      // Ctrl+A through Ctrl+Z (excluding 0x03=Ctrl+C, 0x08=backspace,
      // 0x09=Tab, 0x0A/0x0D=Return).
      bufferedBytes.removeFirst()
      let letter = Character(UnicodeScalar(Int(firstByte) + 0x60)!)
      return .key(KeyPress(.character(letter), modifiers: .ctrl))
    case 0x03:
      bufferedBytes.removeFirst()
      return .key(KeyPress(.character("c"), modifiers: .ctrl))
    case 0x09:
      bufferedBytes.removeFirst()
      return .key(KeyPress(.tab))
    case 0x0A, 0x0D:
      bufferedBytes.removeFirst()
      return .key(KeyPress(.return))
    case 0x1B:
      return parseEscapeSequence()
    case 0x20:
      bufferedBytes.removeFirst()
      return .key(KeyPress(.space))
    case 0x21...0x7E:
      bufferedBytes.removeFirst()
      let scalar = UnicodeScalar(Int(firstByte))!
      return .key(KeyPress(.character(Character(scalar))))
    default:
      bufferedBytes.removeFirst()
      return nil
    }
  }

  private mutating func parseEscapeSequence() -> InputEvent? {
    guard bufferedBytes.count > 1 else {
      // Lone ESC — emit a bare escape key press so consumers receive
      // the keystroke instead of stalling until the next byte arrives.
      bufferedBytes.removeFirst()
      return .key(KeyPress(.escape))
    }

    guard bufferedBytes[1] == 0x5B else {
      // Alt+key: ESC followed by a printable byte
      if (0x20...0x7E).contains(bufferedBytes[1]) {
        let byte = bufferedBytes[1]
        bufferedBytes.removeFirst(2)
        let character = Character(UnicodeScalar(Int(byte))!)
        let key: KeyEvent
        switch byte {
        case 0x20:
          key = .space
        default:
          key = .character(character)
        }
        return .key(KeyPress(key, modifiers: .alt))
      }
      bufferedBytes.removeFirst()
      return .key(KeyPress(.escape))
    }

    guard bufferedBytes.count > 2 else {
      return nil
    }

    // Bracketed-paste start: ESC [ 2 0 0 ~ ... ESC [ 2 0 1 ~
    if matchesBracketedPasteStart(bufferedBytes) {
      return parseBracketedPaste()
    }

    if bufferedBytes[2] == 0x3C {
      return parseSGRMouseSequence()
    }

    // VT220 "tilde" function keys arrive as ESC [ <number> [;<modifier>] ~
    // (Home/End/Insert/Delete/PageUp/PageDown and F-keys) and are 4+ bytes
    // long. Detect the digit-led parameter run and, when it terminates in '~',
    // consume the whole envelope as a unit. Without this the 3-byte
    // fall-through below emits a bare Escape (which can dismiss a modal or pop
    // navigation) and leaves the trailing '~' to be inserted as literal text.
    if (0x30...0x39).contains(bufferedBytes[2]) {
      var index = 2
      while index < bufferedBytes.count, (0x30...0x3B).contains(bufferedBytes[index]) {
        index += 1
      }
      guard index < bufferedBytes.count else {
        return nil  // terminator not buffered yet — wait for more bytes
      }
      if bufferedBytes[index] == 0x7E {
        let parameterBytes = Array(bufferedBytes[2..<index])
        bufferedBytes.removeFirst(index + 1)
        if let event = tildeKeyEvent(parameterBytes: parameterBytes) {
          return event
        }
        // The envelope was consumed but maps to no KeyEvent (e.g. Delete).
        // Keep draining the buffer instead of reporting end-of-input, so a
        // following keystroke in the same chunk is not stranded.
        return parseNextEvent()
      }
      // Letter-terminated parameterized sequence (e.g. ESC[1;5A): fall through
      // to the existing modifier handling below.
    }

    // CSI sequences with modifier parameters: ESC[1;{mod}{key}
    if bufferedBytes[2] == 0x31 {
      return parseCSIModifierSequence()
    }

    switch bufferedBytes[2] {
    case 0x41:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.arrowUp))
    case 0x42:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.arrowDown))
    case 0x43:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.arrowRight))
    case 0x44:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.arrowLeft))
    case 0x48:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.home))
    case 0x46:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.end))
    case 0x5A:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.tab, modifiers: .shift))
    default:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.escape))
    }
  }

  /// Parses CSI sequences with modifier parameters: `ESC[1;{mod}{key}`
  ///
  /// The xterm modifier parameter convention is: value = 1 + bitmask
  /// where shift=1, alt=2, ctrl=4.
  private mutating func parseCSIModifierSequence() -> InputEvent? {
    // Expect at least ESC [ 1 ; {mod} {key} = 6 bytes minimum
    guard bufferedBytes.count >= 6,
      bufferedBytes[3] == 0x3B  // semicolon
    else {
      // Not a modifier sequence — fall through to consume as unknown
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.escape))
    }

    // Find the terminal byte (an uppercase letter)
    var index = 4
    while index < bufferedBytes.count, (0x30...0x39).contains(bufferedBytes[index]) {
      index += 1
    }

    guard index < bufferedBytes.count else {
      return nil  // incomplete sequence, wait for more bytes
    }

    let terminalByte = bufferedBytes[index]
    let modifierBytes = Array(bufferedBytes[4..<index])
    bufferedBytes.removeFirst(index + 1)

    let modifiers = csiModifiers(from: modifierBytes)

    guard let key = csiTerminalKey(from: terminalByte) else {
      return .key(KeyPress(.escape, modifiers: modifiers))
    }

    return .key(KeyPress(key, modifiers: modifiers))
  }

  /// Maps an already-consumed VT220 tilde key envelope (`ESC [ n [;mod] ~`) to
  /// an input event.
  ///
  /// Numbers with an existing ``KeyEvent`` representation (Home = 1 or 7,
  /// End = 4 or 8) are mapped through, honoring any xterm modifier parameter.
  /// The remainder (Insert = 2, Delete = 3, PageUp = 5, PageDown = 6, and the
  /// function keys 11...24) currently have no ``KeyEvent`` case; they are
  /// dropped rather than surfaced, which is correct precisely because the
  /// previous fall-through corrupted input with a stray Escape plus a literal
  /// '~'. Adding first-class cases for these is a separate public-API change.
  private func tildeKeyEvent(parameterBytes: [UInt8]) -> InputEvent? {
    let groups = parameterBytes.split(separator: 0x3B)  // ';'
    guard let keyGroup = groups.first, let keyID = asciiInteger(from: keyGroup) else {
      return nil
    }
    let modifiers: EventModifiers =
      groups.count > 1 ? csiModifiers(from: Array(groups[1])) : []
    let key: KeyEvent
    switch keyID {
    case 1, 7:
      key = .home
    case 4, 8:
      key = .end
    default:
      return nil
    }
    return .key(KeyPress(key, modifiers: modifiers))
  }

  private func csiModifiers(from bytes: [UInt8]) -> EventModifiers {
    guard let value = asciiInteger(from: ArraySlice(bytes)) else {
      return []
    }
    // xterm convention: modifier = 1 + bitmask (shift=1, alt=2, ctrl=4)
    let bitmask = value - 1
    var modifiers: EventModifiers = []
    if (bitmask & 1) != 0 {
      modifiers.insert(.shift)
    }
    if (bitmask & 2) != 0 {
      modifiers.insert(.alt)
    }
    if (bitmask & 4) != 0 {
      modifiers.insert(.ctrl)
    }
    return modifiers
  }

  private func csiTerminalKey(from byte: UInt8) -> KeyEvent? {
    switch byte {
    case 0x41: return .arrowUp
    case 0x42: return .arrowDown
    case 0x43: return .arrowRight
    case 0x44: return .arrowLeft
    case 0x48: return .home
    case 0x46: return .end
    default: return nil
    }
  }

  /// Parses a bracketed-paste envelope: `ESC [ 2 0 0 ~ <payload> ESC [ 2 0 1 ~`.
  ///
  /// On entry the buffer is guaranteed to begin with the 6-byte start marker.
  /// If the matching end marker is already buffered, the whole envelope is
  /// consumed and a `.paste` event is returned.  Otherwise the buffer is left
  /// untouched so the caller can wait for more bytes.
  private mutating func parseBracketedPaste() -> InputEvent? {
    // Buffer layout at entry: ESC [ 2 0 0 ~ <payload> ESC [ 2 0 1 ~
    let startMarker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
    let endMarker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]
    guard bufferedBytes.count >= startMarker.count else { return nil }
    // Look for the end marker anywhere after the start marker.
    let payloadStart = startMarker.count
    var searchIndex = payloadStart
    let totalCount = bufferedBytes.count
    while searchIndex + endMarker.count <= totalCount {
      var matches = true
      for offset in 0..<endMarker.count
      where bufferedBytes[searchIndex + offset] != endMarker[offset] {
        matches = false
        break
      }
      if matches {
        let payloadBytes = Array(bufferedBytes[payloadStart..<searchIndex])
        bufferedBytes.removeFirst(searchIndex + endMarker.count)
        let content = String(decoding: payloadBytes, as: UTF8.self)
        return .paste(PasteEvent(content: content))
      }
      searchIndex += 1
    }
    // End marker not yet seen — keep buffering.
    return nil
  }

  private mutating func parseSGRMouseSequence() -> InputEvent? {
    var index = 3
    while index < bufferedBytes.count,
      bufferedBytes[index] != 0x4D,
      bufferedBytes[index] != 0x6D
    {
      let byte = bufferedBytes[index]
      guard (0x30...0x39).contains(byte) || byte == 0x2D || byte == 0x3B else {
        bufferedBytes.removeFirst(index + 1)
        return nil
      }
      index += 1
    }

    guard index < bufferedBytes.count else {
      return nil
    }

    let terminator = bufferedBytes[index]
    let parameterBytes = Array(bufferedBytes[3..<index])
    bufferedBytes.removeFirst(index + 1)

    let parameters = parameterBytes.split(separator: 0x3B)
    guard parameters.count == 3,
      let encodedButton = asciiInteger(from: parameters[0]),
      let encodedX = asciiSignedInteger(from: parameters[1]),
      let encodedY = asciiSignedInteger(from: parameters[2])
    else {
      return nil
    }

    let location = pointerLocation(encodedX: encodedX, encodedY: encodedY)
    let modifiers = mouseModifiers(from: encodedButton)
    let baseCode = encodedButton & 0b11
    let isMotion = (encodedButton & 32) != 0
    let isWheel = (encodedButton & 64) != 0

    if isWheel {
      let delta: (x: Int, y: Int)?
      switch baseCode {
      case 0:
        delta = (0, -1)
      case 1:
        delta = (0, 1)
      case 2:
        delta = (-1, 0)
      case 3:
        delta = (1, 0)
      default:
        delta = nil
      }

      guard let delta else {
        return nil
      }

      return .mouse(
        MouseEvent(
          kind: .scrolled(deltaX: delta.x, deltaY: delta.y),
          location: location,
          modifiers: modifiers
        )
      )
    }

    if isMotion {
      let kind: MouseEvent.Kind
      switch baseCode {
      case 0:
        kind = .dragged(.primary)
      case 1:
        kind = .dragged(.middle)
      case 2:
        kind = .dragged(.secondary)
      case 3:
        kind = .moved
      default:
        return nil
      }

      return .mouse(
        MouseEvent(
          kind: kind,
          location: location,
          modifiers: modifiers
        )
      )
    }

    guard let button = mouseButton(from: baseCode) else {
      return nil
    }

    let kind: MouseEvent.Kind =
      terminator == 0x6D
      ? .up(button)
      : .down(button)

    return .mouse(
      MouseEvent(
        kind: kind,
        location: location,
        modifiers: modifiers
      )
    )
  }

  private func asciiInteger(
    from bytes: ArraySlice<UInt8>
  ) -> Int? {
    guard !bytes.isEmpty else {
      return nil
    }

    var value = 0
    for byte in bytes {
      guard (0x30...0x39).contains(byte) else {
        return nil
      }
      // Overflow-safe accumulation. A malformed or adversarial sequence with an
      // absurdly long numeric parameter must not trap the process: the previous
      // checked `value * 10 + digit` arithmetic crashed on overflow (SIGILL).
      // On overflow we drop the whole sequence by returning nil, which every
      // caller already handles. This is especially load-bearing on wasm32
      // (WebHost), where Int is 32-bit and overflows after ~10 digits of
      // attacker-controlled input.
      let (scaled, mulOverflow) = value.multipliedReportingOverflow(by: 10)
      let (sum, addOverflow) = scaled.addingReportingOverflow(Int(byte - 0x30))
      guard !mulOverflow, !addOverflow else {
        return nil
      }
      value = sum
    }
    return value
  }

  private func asciiSignedInteger(
    from bytes: ArraySlice<UInt8>
  ) -> Int? {
    guard !bytes.isEmpty else {
      return nil
    }

    // Avoid shadowing a `var ArraySlice<UInt8>` parameter and reassigning
    // it through `dropFirst()`. Under -Osize that pattern crashed the
    // OwnershipModelEliminator SIL pass on the wasm target in
    // Swift 6.3.1. Computing the digit subslice as a `let` once
    // sidesteps the bug and is also clearer.
    let isNegative = bytes.first == 0x2D
    let digits = isNegative ? bytes.dropFirst() : bytes

    guard !digits.isEmpty else {
      return nil
    }

    guard let value = asciiInteger(from: digits) else {
      return nil
    }
    return isNegative ? -value : value
  }

  private func pointerLocation(
    encodedX: Int,
    encodedY: Int
  ) -> PointerLocation {
    switch mouseCoordinateMode {
    case .disabled, .cells:
      return .cellFallback(
        CellPoint(
          x: max(0, encodedX - 1),
          y: max(0, encodedY - 1)
        )
      )
    case .pixels(let metrics, let source):
      let pixelX = encodedX - 1
      let pixelY = encodedY - 1
      let cellWidth = max(1, metrics.width)
      let cellHeight = max(1, metrics.height)
      return .subCell(
        location: Point(
          x: Double(pixelX) / Double(cellWidth),
          y: Double(pixelY) / Double(cellHeight)
        ),
        source: source,
        metrics: metrics,
        rawPixel: PixelPoint(x: Double(pixelX), y: Double(pixelY))
      )
    }
  }

  private func mouseButton(
    from baseCode: Int
  ) -> MouseButton? {
    switch baseCode {
    case 0:
      .primary
    case 1:
      .middle
    case 2:
      .secondary
    default:
      nil
    }
  }

  private func mouseModifiers(
    from encodedButton: Int
  ) -> MouseEvent.Modifiers {
    var modifiers: MouseEvent.Modifiers = []
    if (encodedButton & 4) != 0 {
      modifiers.insert(.shift)
    }
    if (encodedButton & 8) != 0 {
      modifiers.insert(.alt)
    }
    if (encodedButton & 16) != 0 {
      modifiers.insert(.ctrl)
    }
    return modifiers
  }
}
