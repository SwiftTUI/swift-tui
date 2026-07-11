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
    case 0x80...0xFF:
      return parseUTF8Character()
    default:
      bufferedBytes.removeFirst()
      return nil
    }
  }

  /// Parses a multibyte UTF-8 scalar at the head of the buffer. Terminals
  /// transmit typed non-ASCII text (IME input, dead-key composition,
  /// unbracketed pastes) as raw UTF-8, and a read boundary can split a
  /// sequence anywhere — a sequence whose continuation bytes have not
  /// arrived yet stays buffered instead of being dropped byte-by-byte.
  private mutating func parseUTF8Character() -> InputEvent? {
    let leadByte = bufferedBytes[0]
    let continuationCount: Int
    switch leadByte {
    case 0xC2...0xDF: continuationCount = 1
    case 0xE0...0xEF: continuationCount = 2
    case 0xF0...0xF4: continuationCount = 3
    default:
      // Stray continuation byte or invalid lead — drop it, keep draining.
      bufferedBytes.removeFirst()
      return parseNextEvent()
    }
    let sequenceLength = 1 + continuationCount
    guard bufferedBytes.count >= sequenceLength else {
      return nil  // split across reads — wait for the continuation bytes
    }
    let sequence = Array(bufferedBytes[0..<sequenceLength])
    guard sequence.dropFirst().allSatisfy({ (0x80...0xBF).contains($0) }) else {
      bufferedBytes.removeFirst()
      return parseNextEvent()
    }
    bufferedBytes.removeFirst(sequenceLength)
    let decoded = String(decoding: sequence, as: UTF8.self)
    // Overlong/surrogate encodings decode to U+FFFD replacement characters;
    // consume them silently rather than emitting synthetic text.
    guard decoded.unicodeScalars.count == 1, decoded != "\u{FFFD}" else {
      return parseNextEvent()
    }
    return .key(KeyPress(.character(Character(decoded))))
  }

  private mutating func parseEscapeSequence() -> InputEvent? {
    guard bufferedBytes.count > 1 else {
      // Lone ESC — emit a bare escape key press so consumers receive
      // the keystroke instead of stalling until the next byte arrives.
      bufferedBytes.removeFirst()
      return .key(KeyPress(.escape))
    }

    // SS3 sequences: ESC O <final>. xterm-family terminals send F1–F4 this
    // way (and arrows/Home/End in application-cursor mode). This must be
    // matched before the Alt+key fall-through: without it, ESC O P parsed as
    // Alt+O followed by a literal 'P' — actively corrupting focused text
    // fields on every F1–F4 press.
    if bufferedBytes[1] == 0x4F {
      guard bufferedBytes.count > 2 else {
        // The chunk ends at ESC O: treat it as Alt+O, mirroring the lone-ESC
        // convention (a chunk boundary is the implicit ESC timeout — real SS3
        // sequences arrive atomically in one terminal read, while a typed
        // Alt+O ends its read here). Waiting instead would stall Alt+O until
        // the NEXT keystroke and then swallow that key as an SS3 final.
        bufferedBytes.removeFirst(2)
        return .key(KeyPress(.character("O"), modifiers: .alt))
      }
      let finalByte = bufferedBytes[2]
      bufferedBytes.removeFirst(3)
      guard let key = ss3Key(from: finalByte) else {
        // Unknown SS3 final: the envelope is consumed whole so the final
        // byte is never inserted as literal text. Keep draining the buffer.
        return parseNextEvent()
      }
      return .key(KeyPress(key))
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
      // Kitty keyboard protocol key: ESC [ <params> u. Parsed whether or not
      // this host pushed the enhancement flags: terminals never emit CSI u
      // envelopes unprompted, and consuming them whole means a stray envelope
      // can never mangle into an Escape plus literal parameter text.
      if bufferedBytes[index] == 0x75 {
        let parameterBytes = Array(bufferedBytes[2..<index])
        bufferedBytes.removeFirst(index + 1)
        if let event = kittyKeyEvent(parameterBytes: parameterBytes) {
          return event
        }
        // Consumed whole with no deliverable event (key release, modifier
        // set the framework cannot represent, or an unmapped functional
        // code). Keep draining the buffer.
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
  /// an input event, honoring any xterm modifier parameter. Unknown numbers
  /// (unassigned VT220 slots) consume the envelope and map to nothing — the
  /// pre-F14 fall-through corrupted input with a stray Escape plus a literal
  /// '~', so consuming whole envelopes is load-bearing either way.
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
    case 2:
      key = .insert
    case 3:
      key = .delete
    case 4, 8:
      key = .end
    case 5:
      key = .pageUp
    case 6:
      key = .pageDown
    // The VT220 function-key map is discontiguous (16, 22, 27, and 30 are
    // unassigned): 11–15 = F1–F5, 17–21 = F6–F10, 23–24 = F11–F12, and the
    // less common 25–26 = F13–F14, 28–29 = F15–F16, 31–34 = F17–F20.
    case 11...15:
      key = .functionKey(keyID - 10)
    case 17...21:
      key = .functionKey(keyID - 11)
    case 23...24:
      key = .functionKey(keyID - 12)
    case 25...26:
      key = .functionKey(keyID - 12)
    case 28...29:
      key = .functionKey(keyID - 13)
    case 31...34:
      key = .functionKey(keyID - 14)
    default:
      return nil
    }
    return .key(KeyPress(key, modifiers: modifiers))
  }

  /// Maps an already-consumed kitty keyboard envelope (`ESC [ <params> u`)
  /// to an input event. Parameter layout per the kitty keyboard protocol:
  /// `<code>[:<shifted>[:<base>]] [; <modifiers>[:<event>] [; <text…>]]`.
  /// Only the base code point, the modifier bitmask, and the event type are
  /// consulted; the alternate-key and associated-text sections arrive only
  /// under enhancement flags this host never requests and are tolerated by
  /// ignoring them. Returns nil — envelope consumed, no event — for key
  /// releases, modifier bitmasks the framework cannot represent, and
  /// functional code points with no `KeyEvent` mapping.
  private func kittyKeyEvent(parameterBytes: [UInt8]) -> InputEvent? {
    let sections = parameterBytes.split(
      separator: 0x3B,  // ';'
      omittingEmptySubsequences: false
    )
    guard
      let keySection = sections.first,
      let keyPart = keySection.split(
        separator: 0x3A,  // ':'
        omittingEmptySubsequences: false
      ).first,
      let keyCode = asciiInteger(from: keyPart)
    else {
      return nil
    }

    var modifiers: EventModifiers = []
    if sections.count > 1, !sections[1].isEmpty {
      let modifierParts = sections[1].split(
        separator: 0x3A,  // ':'
        omittingEmptySubsequences: false
      )
      guard
        let modifierValue = asciiInteger(from: modifierParts[0]),
        modifierValue >= 1
      else {
        return nil
      }
      // Event-type subparameter: 1 = press, 2 = repeat, 3 = release.
      // Releases arrive only under enhancement flags this host never
      // requests; swallow them so a stray one can never double-fire.
      if modifierParts.count > 1,
        let eventType = asciiInteger(from: modifierParts[1]),
        eventType == 3
      {
        return nil
      }
      // Kitty encodes the modifier parameter as 1 + bitmask: shift=1,
      // alt=2, ctrl=4, super=8, hyper=16, meta=32, caps_lock=64,
      // num_lock=128. Lock-state bits do not change the key; drop them.
      // Any other bit the framework cannot represent swallows the event:
      // delivering super+j as a plain "j" would type text the user never
      // intended.
      let bitmask = (modifierValue - 1) & ~(64 | 128)
      guard bitmask & ~(1 | 2 | 4) == 0 else {
        return nil
      }
      if bitmask & 1 != 0 {
        modifiers.insert(.shift)
      }
      if bitmask & 2 != 0 {
        modifiers.insert(.alt)
      }
      if bitmask & 4 != 0 {
        modifiers.insert(.ctrl)
      }
    }

    guard let key = kittyKey(fromCodePoint: keyCode) else {
      return nil
    }
    return .key(KeyPress(key, modifiers: modifiers))
  }

  /// Maps a kitty key code point to its `KeyEvent`. Text code points map to
  /// `.character`; keys with legacy escape encodings (arrows, Home/End,
  /// Insert/Delete, PageUp/PageDown, F1–F12) keep those encodings even in
  /// enhanced mode, so only the code points kitty actually ships as CSI u
  /// need mapping here. Functional code points in the protocol's
  /// private-use block with no `KeyEvent` case return nil (consumed silent).
  private func kittyKey(fromCodePoint code: Int) -> KeyEvent? {
    switch code {
    case 9:
      return .tab
    case 13:
      return .return
    case 27:
      return .escape
    case 32:
      return .space
    case 127:
      return .backspace
    // F1–F24 occupy 57364–57387. F1–F12 normally arrive in legacy form,
    // but the block is contiguous and reserved, so map it whole.
    case 57364...57387:
      return .functionKey(code - 57363)
    case 57414:
      return .return  // keypad Enter — no legacy CSI form of its own
    case 57344...63743:
      // Remaining private-use functional codes (lock/media/keypad keys,
      // F25+) have no KeyEvent mapping; consume their envelopes silently.
      return nil
    case 33...0x10FFFF:
      guard let scalar = UnicodeScalar(code) else {
        return nil
      }
      return .character(Character(scalar))
    default:
      return nil
    }
  }

  /// Maps an SS3 final byte (`ESC O <final>`) to its key. PC-style function
  /// keys F1–F4 plus the application-cursor-mode aliases for the arrows,
  /// Home/End, and keypad Enter.
  private func ss3Key(from finalByte: UInt8) -> KeyEvent? {
    switch finalByte {
    case 0x50: return .functionKey(1)  // P
    case 0x51: return .functionKey(2)  // Q
    case 0x52: return .functionKey(3)  // R
    case 0x53: return .functionKey(4)  // S
    case 0x41: return .arrowUp  // A
    case 0x42: return .arrowDown  // B
    case 0x43: return .arrowRight  // C
    case 0x44: return .arrowLeft  // D
    case 0x48: return .home  // H
    case 0x46: return .end  // F
    case 0x4D: return .return  // M (keypad Enter)
    default: return nil
    }
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
    // Modified F1–F4 arrive in CSI form (`ESC [ 1 ; <mod> P…S`) even on
    // terminals that send the unmodified keys as SS3.
    case 0x50: return .functionKey(1)
    case 0x51: return .functionKey(2)
    case 0x52: return .functionKey(3)
    case 0x53: return .functionKey(4)
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
