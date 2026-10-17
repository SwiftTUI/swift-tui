import SwiftTUICore

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

  /// Refreshes interpretation without discarding an incomplete input sequence.
  mutating func updateMouseCoordinateMode(_ mode: MouseCoordinateMode) {
    mouseCoordinateMode = mode
  }

  /// Feeds raw bytes into the parser and returns any completed input events.
  public mutating func feed(_ bytes: [UInt8]) -> [InputEvent] {
    bufferedBytes.append(contentsOf: bytes)

    var events: [InputEvent] = []
    while !bufferedBytes.isEmpty {
      let countBefore = bufferedBytes.count
      if let event = parseNextEvent() { events.append(event) }
      // nil can mean either a consumed, ignored envelope or an incomplete
      // prefix. Only the latter waits for another read; draining never recurses.
      if bufferedBytes.count == countBefore { break }
    }
    return events
  }

  /// True when an incomplete escape envelope cannot yet be
  /// disambiguated between a bare Escape keypress and the first byte of a
  /// longer escape sequence. The run loop arms an idle escape-timeout whenever
  /// this is set and calls ``flush()`` on expiry; an arriving continuation
  /// byte clears it by completing (or advancing) the sequence instead.
  package var isAwaitingEscapeDisambiguation: Bool {
    if bufferedBytes.count == 1 && bufferedBytes[0] == 0x1B {
      return true
    }
    // An unterminated control string (OSC/DCS/PM/APC) is also byte-wise
    // ambiguous: two bytes may be a typed Alt+letter chord, and a longer
    // prefix may be a control string whose writer died before the ST
    // terminator (F139). The idle flush resolves both; without it the
    // parser would buffer — and eat — all input forever.
    return isIncompleteSS3 || bufferedBytes.first == 0x9B
      || bufferedBytes.starts(with: [0x1B, 0x5B])
      || unterminatedControlStringIntroducer != nil
  }

  private var isIncompleteSS3: Bool { bufferedBytes == [0x1B, 0x4F] }

  /// The control-string introducer byte when the buffer holds an
  /// unterminated OSC/DCS/PM/APC prefix, else `nil`.
  private var unterminatedControlStringIntroducer: UInt8? {
    if let first = bufferedBytes.first, [0x90, 0x98, 0x9D, 0x9E, 0x9F].contains(first) {
      return controlStringEnd(prefixLength: 1, terminatesWithBEL: first == 0x9D) == nil
        ? first : nil
    }
    guard bufferedBytes.count >= 2, bufferedBytes[0] == 0x1B else {
      return nil
    }
    let introducer = bufferedBytes[1]
    switch introducer {
    case 0x5D:
      return controlStringEnd(prefixLength: 2, terminatesWithBEL: true) == nil
        ? introducer : nil
    case 0x50, 0x58, 0x5E, 0x5F:
      return controlStringEnd(prefixLength: 2, terminatesWithBEL: false) == nil
        ? introducer : nil
    default:
      return nil
    }
  }

  /// Resolves incomplete escape input at an explicit idle timeout or EOF.
  ///
  /// A bare ESC stays buffered by `parseNextEvent()` because it is
  /// byte-identical to the first byte of a real Escape keypress and of every
  /// escape sequence. The run loop calls this on a short idle timeout (the vim
  /// `ttimeoutlen` model) to commit a bare Escape once no continuation byte has
  /// followed. If a lone ESC was pending, this function returns `[.key(.escape)]`.
  /// Bare CSI, SS3 and seven-bit control introducers resolve to Alt chords;
  /// incomplete control payloads are discarded and unfinished paste text is recovered.
  public mutating func flush() -> [InputEvent] {
    guard isAwaitingEscapeDisambiguation else {
      return []
    }
    let csiPrefix = bufferedBytes.first == 0x9B ? 1 : 2
    if bufferedBytes.dropFirst(csiPrefix).starts(with: [0x32, 0x30, 0x30, 0x7E]) {
      let content = String(decoding: bufferedBytes.dropFirst(csiPrefix + 4), as: UTF8.self)
      bufferedBytes.removeAll(keepingCapacity: true)
      return [.paste(PasteEvent(content: content))]
    }
    if isIncompleteSS3 || bufferedBytes == [0x1B, 0x5B] {
      let character = Character(UnicodeScalar(bufferedBytes[1]))
      bufferedBytes.removeAll(keepingCapacity: true)
      return [.key(KeyPress(.character(character), modifiers: .alt))]
    }
    if bufferedBytes.first == 0x9B || bufferedBytes.starts(with: [0x1B, 0x5B]) {
      bufferedBytes.removeAll(keepingCapacity: true)
      return []
    }
    if let introducer = unterminatedControlStringIntroducer {
      // At an explicit timeout/EOF, ESC + introducer resolves to Alt+letter.
      // C1 introducers never represent an Alt chord. Anything longer
      // is a control string whose terminator never arrived: discard it
      // whole rather than typing the payload as literal text (F139).
      let isBareChord = bufferedBytes.count == 2 && bufferedBytes[0] == 0x1B
      bufferedBytes.removeAll(keepingCapacity: true)
      guard isBareChord else {
        return []
      }
      let character = Character(UnicodeScalar(introducer))
      return [.key(KeyPress(.character(character), modifiers: .alt))]
    }
    bufferedBytes.removeFirst()
    return [.key(KeyPress(.escape))]
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
    case 0x00:
      bufferedBytes.removeFirst()
      return .key(KeyPress(.space, modifiers: .ctrl))
    case 0x1C...0x1F:
      bufferedBytes.removeFirst()
      return .key(
        KeyPress(.character(Character(UnicodeScalar(firstByte + 0x40))), modifiers: .ctrl))
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
    case 0x9B:
      return parseCSI(prefixLength: 1)
    case 0x90, 0x98, 0x9D, 0x9E, 0x9F:
      return discardControlString(prefixLength: 1, terminatesWithBEL: firstByte == 0x9D)
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
  private mutating func parseUTF8Character(prefixLength: Int = 0) -> InputEvent? {
    let leadByte = bufferedBytes[prefixLength]
    let sequenceLength: Int
    switch leadByte {
    case 0xC2...0xDF: sequenceLength = 2
    case 0xE0...0xEF: sequenceLength = 3
    case 0xF0...0xF4: sequenceLength = 4
    default:
      bufferedBytes.removeFirst(prefixLength + 1)
      return nil
    }
    let available = bufferedBytes.dropFirst(prefixLength).prefix(sequenceLength)
    guard available.dropFirst().allSatisfy({ (0x80...0xBF).contains($0) }) else {
      bufferedBytes.removeFirst(prefixLength + 1)
      return nil
    }
    guard available.count == sequenceLength else { return nil }
    let decoded = String(validating: available, as: UTF8.self)
    bufferedBytes.removeFirst(prefixLength + sequenceLength)
    guard let decoded, decoded.unicodeScalars.count == 1 else { return nil }
    return .key(KeyPress(.character(Character(decoded)), modifiers: prefixLength == 0 ? [] : .alt))
  }

  private mutating func parseEscapeSequence() -> InputEvent? {
    guard bufferedBytes.count > 1 else {
      // Lone ESC — byte-identical to the first byte of a real Escape keypress
      // AND of every escape sequence (arrows, function keys, bracketed paste).
      // Byte-wise the parser cannot yet tell them apart, so keep the ESC
      // buffered like every other incomplete prefix instead of committing it
      // to Escape early (which byte-wise leaked bracketed-paste framing as key
      // events). Disambiguation lives out of band: the run loop arms a short
      // idle "escape timeout" — the vim `ttimeoutlen` model — and calls
      // ``flush()`` to commit a bare Escape once no continuation byte follows.
      // See ``isAwaitingEscapeDisambiguation``.
      return nil
    }

    switch bufferedBytes[1] {
    case 0x5D:
      return discardControlString(prefixLength: 2, terminatesWithBEL: true)
    case 0x50, 0x58, 0x5E, 0x5F:
      // DCS/PM/APC control strings buffer until their ST terminator
      // arrives, exactly like OSC (F139). The old fall-through parsed a
      // split-read introducer as an Alt+letter chord and then typed the
      // entire late payload (a kitty graphics reply, a tmux passthrough)
      // into the focused field. A genuinely TYPED Alt+P/Alt+^/Alt+_ chord
      // ends its read at two bytes and is committed by the idle
      // escape-timeout ``flush()`` — the same out-of-band disambiguation
      // the lone ESC uses.
      return discardControlString(prefixLength: 2, terminatesWithBEL: false)
    default:
      break
    }

    // SS3 sequences: ESC O <final>. xterm-family terminals send F1–F4 this
    // way (and arrows/Home/End in application-cursor mode). This must be
    // matched before the Alt+key fall-through: without it, ESC O P parsed as
    // Alt+O followed by a literal 'P' — actively corrupting focused text
    // fields on every F1–F4 press.
    if bufferedBytes[1] == 0x4F {
      guard bufferedBytes.count > 2 else {
        // Read boundaries do not disambiguate Alt+O from SS3. An explicit
        // idle timeout or EOF commits the chord through flush().
        return nil
      }
      let finalByte = bufferedBytes[2]
      bufferedBytes.removeFirst(3)
      guard let key = ss3Key(from: finalByte) else {
        // Unknown SS3 final: the envelope is consumed whole so the final
        // byte is never inserted as literal text. Keep draining the buffer.
        return nil
      }
      return .key(KeyPress(key))
    }

    guard bufferedBytes[1] == 0x5B else {
      if bufferedBytes[1] >= 0x80 {
        return parseUTF8Character(prefixLength: 1)
      }
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
      // Alt+control: ESC followed by a C0 byte the bare parser maps to a
      // key (Alt+Return, Alt+Backspace, Alt+Tab, Alt+Ctrl+letter). Emitting
      // a bare `.escape` here and re-parsing the control byte as a literal
      // leaked BOTH a modal-dismissing Escape AND a stray activation from
      // one chord (F165). ESC ESC deliberately stays on the fall-through:
      // some terminals prefix arrow chords with a second ESC, and consuming
      // it as Alt+Escape would strand the sequence tail as literal text.
      switch bufferedBytes[1] {
      case 0x00:
        bufferedBytes.removeFirst(2)
        return .key(KeyPress(.space, modifiers: [.ctrl, .alt]))
      case 0x1C...0x1F:
        let character = Character(UnicodeScalar(bufferedBytes[1] + 0x40))
        bufferedBytes.removeFirst(2)
        return .key(KeyPress(.character(character), modifiers: [.ctrl, .alt]))
      case 0x0A, 0x0D:
        bufferedBytes.removeFirst(2)
        return .key(KeyPress(.return, modifiers: .alt))
      case 0x08, 0x7F:
        bufferedBytes.removeFirst(2)
        return .key(KeyPress(.backspace, modifiers: .alt))
      case 0x09:
        bufferedBytes.removeFirst(2)
        return .key(KeyPress(.tab, modifiers: .alt))
      case 0x01...0x07, 0x0B...0x0C, 0x0E...0x1A:
        let controlByte = bufferedBytes[1]
        bufferedBytes.removeFirst(2)
        let letter = Character(UnicodeScalar(Int(controlByte) + 0x60)!)
        return .key(KeyPress(.character(letter), modifiers: [.ctrl, .alt]))
      default:
        bufferedBytes.removeFirst()
        return .key(KeyPress(.escape))
      }
    }

    return parseCSI(prefixLength: 2)
  }

  /// Scan one complete CSI envelope before interpreting any parameters.
  /// Unsupported replies and intermediate-byte commands stay atomic too.
  private mutating func parseCSI(prefixLength: Int) -> InputEvent? {
    guard bufferedBytes.count > prefixLength else { return nil }
    if bufferedBytes.dropFirst(prefixLength).starts(with: [0x32, 0x30, 0x30, 0x7E]) {
      return parseBracketedPaste(prefixLength: prefixLength)
    }
    if bufferedBytes[prefixLength] == 0x3C {
      return parseSGRMouseSequence(prefixLength: prefixLength)
    }
    if bufferedBytes[prefixLength] == 0x4D {
      // X10 carries exactly three binary report bytes after CSI M. This host
      // negotiates SGR mouse, but unsolicited legacy reports must not type.
      guard bufferedBytes.count >= prefixLength + 4 else { return nil }
      bufferedBytes.removeFirst(prefixLength + 4)
      return nil
    }
    var index = prefixLength
    while index < bufferedBytes.count, (0x30...0x3F).contains(bufferedBytes[index]) {
      index += 1
    }
    let parameters = Array(bufferedBytes[prefixLength..<index])
    let parameterEnd = index
    while index < bufferedBytes.count, (0x20...0x2F).contains(bufferedBytes[index]) {
      index += 1
    }
    guard index < bufferedBytes.count else { return nil }
    // Preserve atomic recovery for malformed Kitty event subparameters.
    if parameters.contains(0x3A), bufferedBytes[index] != 0x75 {
      guard index + 1 < bufferedBytes.count else { return nil }
      if bufferedBytes[index + 1] == 0x75 {
        bufferedBytes.removeFirst(index + 2)
        return nil
      }
    }
    let final = bufferedBytes[index]
    guard (0x40...0x7E).contains(final) else {
      // Drop the malformed prefix, then reconsider the offending byte as a
      // new envelope or key instead of leaking the parameter bytes.
      bufferedBytes.removeFirst(index)
      return nil
    }
    bufferedBytes.removeFirst(index + 1)
    guard index == parameterEnd else { return nil }
    switch final {
    case 0x7E: return tildeKeyEvent(parameterBytes: parameters)
    case 0x75: return kittyKeyEvent(parameterBytes: parameters)
    case 0x5A where parameters.isEmpty: return .key(KeyPress(.tab, modifiers: .shift))
    default:
      guard let key = csiTerminalKey(from: final) else { return nil }
      if parameters.isEmpty { return .key(KeyPress(key)) }
      let groups = parameters.split(separator: 0x3B, omittingEmptySubsequences: false)
      guard groups.count == 2, groups[0] == [0x31],
        let modifiers = csiModifiers(from: Array(groups[1]))
      else { return nil }
      return .key(KeyPress(key, modifiers: modifiers))
    }
  }

  private mutating func discardControlString(
    prefixLength: Int,
    terminatesWithBEL: Bool
  ) -> InputEvent? {
    guard
      let end = controlStringEnd(
        prefixLength: prefixLength,
        terminatesWithBEL: terminatesWithBEL
      )
    else {
      return nil
    }
    bufferedBytes.removeFirst(end)
    return nil
  }

  private func controlStringEnd(
    prefixLength: Int,
    terminatesWithBEL: Bool
  ) -> Int? {
    var index = prefixLength
    while index < bufferedBytes.count {
      if terminatesWithBEL, bufferedBytes[index] == 0x07 {
        return index + 1
      }
      if bufferedBytes[index] == 0x9C {
        return index + 1
      }
      if bufferedBytes[index] == 0x1B {
        guard index + 1 < bufferedBytes.count else {
          return nil
        }
        if bufferedBytes[index + 1] == 0x5C {
          return index + 2
        }
      }
      index += 1
    }
    return nil
  }

  /// Maps an already-consumed VT220 tilde key envelope (`ESC [ n [;mod] ~`) to
  /// an input event, honoring any xterm modifier parameter. Unknown numbers
  /// (unassigned VT220 slots) consume the envelope and map to nothing — the
  /// pre-F14 fall-through corrupted input with a stray Escape plus a literal
  /// '~', so consuming whole envelopes is load-bearing either way.
  private func tildeKeyEvent(parameterBytes: [UInt8]) -> InputEvent? {
    let groups = parameterBytes.split(
      separator: 0x3B,  // ';'
      omittingEmptySubsequences: false
    )
    if groups.count == 3, groups[0] == [0x32, 0x37] {
      guard let modifiers = csiModifiers(from: Array(groups[1])),
        let code = asciiInteger(from: groups[2]), let key = kittyKey(fromCodePoint: code)
      else { return nil }
      return .key(KeyPress(key, modifiers: modifiers))
    }
    guard groups.count <= 2 else {
      return nil
    }
    guard let keyGroup = groups.first, let keyID = asciiInteger(from: keyGroup) else {
      return nil
    }
    guard
      let modifiers: EventModifiers =
        groups.count > 1 ? csiModifiers(from: Array(groups[1])) : []
    else { return nil }
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
      if modifierParts.count > 1 {
        guard let eventType = asciiInteger(from: modifierParts[1]) else {
          return nil
        }
        switch eventType {
        case 1, 2:
          break
        case 3:
          return nil
        default:
          return nil
        }
      }
      // Kitty encodes the modifier parameter as 1 + bitmask: shift=1,
      // alt=2, ctrl=4, super=8, hyper=16, meta=32, caps_lock=64,
      // num_lock=128. Lock-state bits do not change the key; drop them.
      // Any other bit the framework cannot represent swallows the event:
      // delivering super+j as a plain "j" would type text the user never
      // intended.
      guard let decoded = keyboardModifiers(value: modifierValue, ignoringLocks: true) else {
        return nil
      }
      modifiers = decoded
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

  private func csiModifiers(from bytes: [UInt8]) -> EventModifiers? {
    guard let value = asciiInteger(from: ArraySlice(bytes)) else { return nil }
    // Legacy zero has the default value, one. Never subtract from zero or
    // silently turn unsupported Meta/Super chords into unmodified input.
    return keyboardModifiers(value: max(1, value), ignoringLocks: false)
  }

  private func keyboardModifiers(value: Int, ignoringLocks: Bool) -> EventModifiers? {
    guard value >= 1 else { return nil }
    let bitmask = (value - 1) & ~(ignoringLocks ? (64 | 128) : 0)
    guard bitmask & ~7 == 0 else { return nil }
    var modifiers: EventModifiers = []
    if bitmask & 1 != 0 { modifiers.insert(.shift) }
    if bitmask & 2 != 0 { modifiers.insert(.alt) }
    if bitmask & 4 != 0 { modifiers.insert(.ctrl) }
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
  private mutating func parseBracketedPaste(prefixLength: Int) -> InputEvent? {
    let payloadStart = prefixLength + 4
    let endMarkers: [[UInt8]] = [
      [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E], [0x9B, 0x32, 0x30, 0x31, 0x7E],
    ]
    for index in payloadStart..<bufferedBytes.count {
      for marker in endMarkers where bufferedBytes[index...].starts(with: marker) {
        let content = String(decoding: bufferedBytes[payloadStart..<index], as: UTF8.self)
        bufferedBytes.removeFirst(index + marker.count)
        return .paste(PasteEvent(content: content))
      }
    }
    return nil
  }

  private mutating func parseSGRMouseSequence(prefixLength: Int) -> InputEvent? {
    var index = prefixLength + 1
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
    let parameterBytes = Array(bufferedBytes[(prefixLength + 1)..<index])
    bufferedBytes.removeFirst(index + 1)

    let parameters = parameterBytes.split(separator: 0x3B)
    // Every rejection below the removeFirst above has consumed the whole
    // envelope — keep draining the buffer so a following event in the same
    // chunk is not stranded until the next read.
    guard parameters.count == 3,
      let encodedButton = asciiInteger(from: parameters[0]),
      let encodedX = asciiSignedInteger(from: parameters[1]),
      let encodedY = asciiSignedInteger(from: parameters[2])
    else {
      return nil
    }

    // SGR extended buttons 8-11 (back/forward and beyond) set bit 128. The
    // framework's MouseButton vocabulary has no back/forward, and masking
    // only the low bits made button 8 masquerade as a PRIMARY click
    // (128 & 0b11 == 0) — a back-button press activated the focused control
    // (F78). Reject the whole family explicitly; the envelope is already
    // consumed, so nothing leaks as text.
    guard encodedButton & 128 == 0 else {
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
