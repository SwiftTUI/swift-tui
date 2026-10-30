import SwiftTUICore

struct TerminalCellTextRenderer {
  struct RenderState {
    fileprivate var activeStyle: ResolvedTextStyle?
    fileprivate var activeHyperlink: String?
    /// The raw (pre-terminal-resolution) style of the last transition. Runs
    /// of same-styled cells early-out on this compare, so the terminal
    /// re-resolution (per-color mixing against the terminal backdrop) prices
    /// per transition rather than per cell. Reset wherever `activeStyle`
    /// resets, or a post-reset cell with the same raw style would skip its
    /// re-emission.
    fileprivate var activeRawStyle: ResolvedTextStyle?
    /// A single-entry cache of the presentation-boundary sanitizer. It is
    /// independent of the active OSC 8 state: closing a run must still reopen
    /// the link even when its sanitized destination can be reused.
    fileprivate var lastRawHyperlink: String?
    fileprivate var lastSanitizedHyperlink: String?

    init() {}
  }

  var capabilityProfile: TerminalCapabilityProfile
  var terminalBackgroundColor: Color? = nil

  @discardableResult
  func appendRenderedCells(
    in row: [RasterCell],
    from start: Int,
    to end: Int,
    into result: inout String,
    state: inout RenderState
  ) -> Int {
    var renderedWidth = 0

    for index in start..<max(start, end) {
      let cell = cell(at: index, in: row)
      guard !cell.isContinuation else {
        continue
      }

      transitionRenderState(
        style: cell.style,
        hyperlink: cell.hyperlink,
        state: &state,
        into: &result
      )
      appendRenderedCharacter(for: cell, into: &result)
      renderedWidth += max(1, cell.spanWidth)
    }

    return renderedWidth
  }

  func closeRenderState(
    _ state: inout RenderState,
    into result: inout String
  ) {
    if state.activeHyperlink != nil, capabilityProfile.supportsHyperlinks {
      result += closeHyperlinkSequence()
      state.activeHyperlink = nil
    }
    if state.activeStyle != nil, capabilityProfile.emitsStyleEscapeSequences {
      result += "\u{001B}[0m"
      state.activeStyle = nil
      state.activeRawStyle = nil
    }
  }

  /// Whether a cell at the end of a row writes nothing a full repaint must
  /// send: an unstyled space with no hyperlink this profile emits. A linked
  /// blank is written, or the terminal never receives its link and a later
  /// diff never repaints the unchanged cell.
  func isTrimmableTrailingBlank(_ cell: RasterCell) -> Bool {
    guard cell.character == " ", cell.style == nil else { return false }
    guard capabilityProfile.supportsHyperlinks, let destination = cell.hyperlink else {
      return true
    }
    return sanitizedHyperlinkDestination(destination).isEmpty
  }

  func cursorForwardSequence(
    _ count: Int
  ) -> String {
    guard count > 0 else {
      return ""
    }
    return "\u{001B}[\(count)C"
  }

  private func transitionRenderState(
    style: ResolvedTextStyle?,
    hyperlink: String?,
    state: inout RenderState,
    into result: inout String
  ) {
    if let destination = hyperlink {
      // String equality is canonically equivalent, but OSC 8 URI encoding
      // preserves the authored UTF-8 bytes (e.g. composed vs decomposed é).
      if state.lastRawHyperlink?.utf8.elementsEqual(destination.utf8) != true {
        let sanitized = sanitizedHyperlinkDestination(destination)
        state.lastRawHyperlink = destination
        state.lastSanitizedHyperlink = sanitized.isEmpty ? nil : sanitized
      }
    } else {
      state.lastRawHyperlink = nil
      state.lastSanitizedHyperlink = nil
    }
    let hyperlink = state.lastSanitizedHyperlink
    // A run of same-styled cells is the common shape of a span; the raw
    // compare early-outs before `styleResolvedForTerminal` re-derives the
    // terminal style. Equal raw inputs resolve to equal terminal styles (the
    // resolution is a pure function of the style and the fixed backdrop), so
    // this skips exactly the calls that could not have emitted anything.
    if style == state.activeRawStyle, hyperlink == state.activeHyperlink {
      return
    }

    let terminalStyle = style.map(styleResolvedForTerminal)

    if hyperlink != state.activeHyperlink {
      if state.activeHyperlink != nil, capabilityProfile.supportsHyperlinks {
        result += closeHyperlinkSequence()
      }
      if let hyperlink, capabilityProfile.supportsHyperlinks {
        result += openHyperlinkSequence(for: .init(hyperlink))
      }
      state.activeHyperlink = hyperlink
    }

    if terminalStyle != state.activeStyle {
      if state.activeStyle != nil, capabilityProfile.emitsStyleEscapeSequences {
        result += "\u{001B}[0m"
      }
      if let terminalStyle,
        capabilityProfile.emitsStyleEscapeSequences,
        let sequence = styleSequence(for: terminalStyle)
      {
        result += sequence
      }
      state.activeStyle = terminalStyle
    }
    state.activeRawStyle = style
  }

  private func styleResolvedForTerminal(
    _ style: ResolvedTextStyle
  ) -> ResolvedTextStyle {
    let terminalBackgroundColor = terminalBackgroundColor ?? Theme.default.background

    let backgroundColor = style.backgroundColor.map {
      colorResolvedForTerminal($0, over: terminalBackgroundColor)
    }
    let foregroundBackdrop = backgroundColor ?? terminalBackgroundColor
    let underlineStyle = style.underlineStyle.map { underlineStyle in
      TextLineStyle(
        pattern: underlineStyle.pattern,
        color: underlineStyle.color.map {
          colorResolvedForTerminal($0, over: foregroundBackdrop)
        }
      )
    }

    return ResolvedTextStyle(
      foregroundColor: style.foregroundColor.map {
        colorResolvedForTerminal($0, over: foregroundBackdrop)
      },
      backgroundColor: backgroundColor,
      emphasis: style.emphasis,
      underlineStyle: underlineStyle,
      strikethroughStyle: style.strikethroughStyle,
      opacity: style.opacity
    )
  }

  private func colorResolvedForTerminal(
    _ color: Color,
    over backdrop: Color
  ) -> Color {
    guard color.alpha < 1 else {
      return color
    }

    let opaqueSource = Color(
      red: color.red,
      green: color.green,
      blue: color.blue,
      profile: color.profile
    )
    return backdrop.mixed(with: opaqueSource, amount: color.alpha).withAlpha(1)
  }

  /// Appends the cell's rendered character directly, so the common
  /// full-glyph path appends a `Character` without materializing a
  /// per-cell `String`.
  private func appendRenderedCharacter(
    for cell: RasterCell,
    into result: inout String
  ) {
    let sanitizedCharacter = sanitizedTerminalCharacter(cell.character)
    if capabilityProfile.glyphLevel == .ascii {
      result += degradedASCIIText(
        character: sanitizedCharacter,
        spanWidth: max(1, cell.spanWidth)
      )
      return
    }
    result.append(sanitizedCharacter)
  }

  private func cell(
    at index: Int,
    in row: [RasterCell]
  ) -> RasterCell {
    row.indices.contains(index) ? row[index] : .empty
  }

  private func sanitizedTerminalCharacter(
    _ character: Character
  ) -> Character {
    let scalars = character.unicodeScalars
    if scalars.contains(where: \.isTerminalControlScalar) { return "�" }
    // A raster cell owns columns even when its authored cluster has no width.
    // Emit a spacing placeholder so full rows and damage batches agree.
    if cellWidth(of: character) == 0 { return " " }
    return character
  }

  /// Builds the SGR escape sequence for `style` directly into a String,
  /// avoiding intermediate `[String]` / `[Int]` arrays.
  private func styleSequence(
    for style: ResolvedTextStyle
  ) -> String? {
    // Build the sequence by appending SGR codes directly into a String.
    // The escape prefix and `m` suffix are added once at the edges.
    var seq = "\u{001B}["
    var hasCodes = false

    @inline(__always)
    func appendCode(_ code: String) {
      if hasCodes { seq += ";" }
      seq += code
      hasCodes = true
    }

    @inline(__always)
    func appendIntCode(_ code: Int) {
      if hasCodes { seq += ";" }
      seq += String(code)
      hasCodes = true
    }

    // Emphasis codes (inlined from former emphasisCodes(for:)).
    if style.emphasis.contains(.bold) { appendCode("1") }
    if style.emphasis.contains(.faint) || style.opacity < 1 { appendCode("2") }
    if style.emphasis.contains(.italic) { appendCode("3") }
    if let underlineStyle = style.underlineStyle {
      switch underlineStyle.pattern {
      case .solid: appendCode("4")
      case .double: appendCode("4:2")
      case .curly: appendCode("4:3")
      case .dot: appendCode("4:4")
      case .dash, .dashDot, .dashDotDot: appendCode("4:5")
      }
    }
    if style.emphasis.contains(.blink) { appendCode("5") }
    if style.emphasis.contains(.reverse) { appendCode("7") }
    if style.strikethroughStyle != nil { appendCode("9") }

    // Foreground color codes (inlined from former colorCodes).
    if let fg = style.foregroundColor {
      appendColorCodes(for: fg, isBackground: false, into: &seq, hasCodes: &hasCodes)
    }

    // Background color codes.
    if let bg = style.backgroundColor {
      appendColorCodes(for: bg, isBackground: true, into: &seq, hasCodes: &hasCodes)
    }

    // Underline color.
    if let underlineColor = style.underlineStyle?.color {
      appendUnderlineColorCodes(for: underlineColor, into: &seq, hasCodes: &hasCodes)
    }

    guard hasCodes else {
      return nil
    }

    seq += "m"
    return seq
  }

  /// Appends SGR color codes for `color` directly into `seq`.
  private func appendColorCodes(
    for color: Color,
    isBackground: Bool,
    into seq: inout String,
    hasCodes: inout Bool
  ) {
    @inline(__always)
    func appendCode(_ code: Int) {
      if hasCodes { seq += ";" }
      seq += String(code)
      hasCodes = true
    }

    switch capabilityProfile.colorLevel {
    case .none:
      break
    case .ansi16:
      let code = closestANSI16ForegroundCode(for: color)
      appendCode(isBackground ? backgroundCode(forForegroundCode: code) : code)
    case .ansi256:
      appendCode(isBackground ? 48 : 38)
      appendCode(5)
      appendCode(ansi256Code(for: color))
    case .trueColor:
      let bytes = directColorBytes(for: color)
      appendCode(isBackground ? 48 : 38)
      appendCode(2)
      appendCode(bytes.red)
      appendCode(bytes.green)
      appendCode(bytes.blue)
    }
  }

  /// Appends underline color SGR codes directly into `seq`.
  private func appendUnderlineColorCodes(
    for color: Color,
    into seq: inout String,
    hasCodes: inout Bool
  ) {
    @inline(__always)
    func appendCode(_ code: String) {
      if hasCodes { seq += ";" }
      seq += code
      hasCodes = true
    }

    switch capabilityProfile.colorLevel {
    case .none, .ansi16:
      break
    case .ansi256:
      appendCode("58")
      appendCode("5")
      appendCode(String(ansi256Code(for: color)))
    case .trueColor:
      let bytes = directColorBytes(for: color)
      appendCode("58")
      appendCode("2")
      appendCode(String(bytes.red))
      appendCode(String(bytes.green))
      appendCode(String(bytes.blue))
    }
  }

  private func degradedASCIIText(
    character: Character,
    spanWidth: Int
  ) -> String {
    switch character {
    case "│", "┃", "║":
      return "|"
    case "─", "━", "═":
      return "-"
    case "▌", "▐":
      return "|"
    case "▀", "▄", "▂":
      return "-"
    case "┌", "┐", "└", "┘",
      "╭", "╮", "╰", "╯",
      "╔", "╗", "╚", "╝",
      "┏", "┓", "┗", "┛",
      "▛", "▜", "▙", "▟",
      "▗", "▖", "▝", "▘",
      "├", "┤", "┬", "┴", "┼",
      "╠", "╣", "╦", "╩", "╬":
      return "+"
    case "█":
      return "#"
    case "•":
      return "*"
    case "◀", "◁":
      return "<"
    case "▶", "▷":
      return ">"
    case "▼", "▽":
      return "v"
    case "▲", "△":
      return "^"
    case "×":
      return "x"
    case "●", "○":
      return "o"
    case "←":
      return "<"
    case "→":
      return ">"
    case "↑":
      return "^"
    case "↓":
      return "v"
    case "…":
      return "~"
    default:
      let scalarView = String(character).unicodeScalars
      guard scalarView.allSatisfy(\.isASCII) else {
        if scalarView.count == 1, let scalar = scalarView.first,
          let degraded = degradedBoxDrawingASCII(scalar)
        {
          return degraded
        }
        return String(repeating: "?", count: max(1, spanWidth))
      }
      return String(character)
    }
  }

  /// Total ASCII degradations for the box-drawing (U+2500–U+257F) and
  /// block-elements (U+2580–U+259F) ranges — the two Unicode blocks the
  /// framework's chrome and the embedded figlet fonts draw from — plus the
  /// filled square the `future` figure font uses. The named cases in
  /// `degradedASCIIText` win first and stay byte-stable; this table serves
  /// only the scalars they do not name, so no glyph in either range ever
  /// degrades to `?`.
  private func degradedBoxDrawingASCII(
    _ scalar: UnicodeScalar
  ) -> String? {
    switch scalar.value {
    case 0x2500...0x257F:
      switch scalar {
      // Horizontal-only strokes: dashed runs and half-line stubs.
      case "┄", "┅", "┈", "┉", "╌", "╍", "╴", "╶", "╸", "╺", "╼", "╾":
        return "-"
      // Vertical-only strokes: dashed runs and half-line stubs.
      case "┆", "┇", "┊", "┋", "╎", "╏", "╵", "╷", "╹", "╻", "╽", "╿":
        return "|"
      case "╱":
        return "/"
      case "╲":
        return "\\"
      case "╳":
        return "X"
      default:
        // Corners, tees, and crossings, in every weight and doubling.
        return "+"
      }
    case 0x2580...0x259F:
      switch scalar {
      case "▁":
        return "_"
      case "▃", "▔":
        return "-"
      case "░":
        return "."
      case "▒":
        return ":"
      case "▅", "▆", "▇", "▉", "▊", "▋", "▓":
        return "#"
      case "▍", "▎", "▏", "▕":
        return "|"
      default:
        // The quadrant pairs (▚, ▞) and any remainder.
        return "+"
      }
    case 0x25A0:  // ■
      return "#"
    default:
      return nil
    }
  }

  private func escapeSequence(
    forCodes codes: [Int]
  ) -> String {
    escapeSequence(forCodeStrings: codes.map(String.init))
  }

  private func escapeSequence(
    forCodeStrings codes: [String]
  ) -> String {
    "\u{001B}[\(codes.joined(separator: ";"))m"
  }

  private func openHyperlinkSequence(
    for destination: LinkDestination
  ) -> String {
    "\u{001B}]8;;\(destination.rawValue)\u{001B}\\"
  }

  /// Removes terminal controls and `ESC \` pairs from a destination, then
  /// URI-encodes it for OSC 8: every remaining byte outside 32...126 becomes
  /// `%XX` (RFC 3986 percent-encoding, uppercase). Bytes inside the range,
  /// `%` included, pass unchanged, so an encoded destination is not encoded
  /// again.
  private func sanitizedHyperlinkDestination(
    _ destination: String
  ) -> String {
    var sanitized = String()
    sanitized.reserveCapacity(destination.utf8.count)

    var shouldDropStringTerminator = false
    for scalar in destination.unicodeScalars {
      if scalar.value == 0x1B {
        shouldDropStringTerminator = true
        continue
      }
      if scalar.isTerminalControlScalar {
        continue
      }
      if shouldDropStringTerminator && scalar.value == 0x5C {
        shouldDropStringTerminator = false
        continue
      }

      shouldDropStringTerminator = false
      if (0x20...0x7E).contains(scalar.value) {
        sanitized.unicodeScalars.append(scalar)
      } else {
        for byte in scalar.utf8 {
          sanitized.unicodeScalars.append("%")
          sanitized.unicodeScalars.append(Self.uppercaseHexDigits[Int(byte >> 4)])
          sanitized.unicodeScalars.append(Self.uppercaseHexDigits[Int(byte & 0x0F)])
        }
      }
    }
    return sanitized
  }

  private static let uppercaseHexDigits: [Unicode.Scalar] = Array("0123456789ABCDEF".unicodeScalars)

  private func closeHyperlinkSequence() -> String {
    "\u{001B}]8;;\u{001B}\\"
  }
}

extension Unicode.Scalar {
  var isTerminalControlScalar: Bool {
    switch value {
    case 0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200E...0x200F, 0x202A...0x202E, 0x2066...0x2069:
      return true
    default: return false
    }
  }
}
