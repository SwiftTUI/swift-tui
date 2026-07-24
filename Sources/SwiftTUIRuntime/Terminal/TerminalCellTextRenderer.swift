import SwiftTUICore

struct TerminalCellTextRenderer {
  struct RenderState {
    fileprivate var activeStyle: ResolvedTextStyle?
    fileprivate var activeHyperlink: String?

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
      result += renderedCharacter(for: cell)
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
    }
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
  }

  private func styleResolvedForTerminal(
    _ style: ResolvedTextStyle
  ) -> ResolvedTextStyle {
    guard let terminalBackgroundColor else {
      return style
    }

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

  private func renderedCharacter(
    for cell: RasterCell
  ) -> String {
    let sanitizedCharacter = sanitizedTerminalCharacter(cell.character)
    if capabilityProfile.glyphLevel == .ascii {
      return degradedASCIIText(
        character: sanitizedCharacter,
        spanWidth: max(1, cell.spanWidth)
      )
    }
    return String(sanitizedCharacter)
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
    if scalars.allSatisfy(isUnsafeTerminalControlScalar) {
      return "�"
    }
    return character
  }

  private func isUnsafeTerminalControlScalar(
    _ scalar: UnicodeScalar
  ) -> Bool {
    switch scalar.value {
    case 0x00...0x1F, 0x7F...0x9F:
      return true
    default:
      return false
    }
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
      appendCode(isBackground ? 48 : 38)
      appendCode(2)
      appendCode(colorByte(color.red))
      appendCode(colorByte(color.green))
      appendCode(colorByte(color.blue))
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
      appendCode("58")
      appendCode("2")
      appendCode(String(colorByte(color.red)))
      appendCode(String(colorByte(color.green)))
      appendCode(String(colorByte(color.blue)))
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
    case "▀", "▄":
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
        return String(repeating: "?", count: max(1, spanWidth))
      }
      return String(character)
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
    "\u{001B}]8;;\(sanitizedHyperlinkDestination(destination.rawValue))\u{001B}\\"
  }

  private func sanitizedHyperlinkDestination(
    _ destination: String
  ) -> String {
    var sanitized = String()
    sanitized.reserveCapacity(destination.count)

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
      sanitized.unicodeScalars.append(scalar)
    }
    return sanitized
  }

  private func closeHyperlinkSequence() -> String {
    "\u{001B}]8;;\u{001B}\\"
  }
}

extension Unicode.Scalar {
  fileprivate var isTerminalControlScalar: Bool {
    value < 0x20 || (value >= 0x7F && value <= 0x9F)
  }
}
