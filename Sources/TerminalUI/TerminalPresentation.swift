import Core

/// The terminal capabilities assumed when presenting a raster surface.
public struct TerminalCapabilityProfile: Equatable, Sendable {
  /// The glyph repertoire the presentation layer may emit.
  public enum GlyphLevel: String, Equatable, Sendable {
    case ascii
    case unicode
  }

  /// The color repertoire the presentation layer may emit.
  public enum ColorLevel: String, Equatable, Sendable {
    case none
    case ansi16
    case ansi256
    case trueColor
  }

  public var glyphLevel: GlyphLevel
  public var colorLevel: ColorLevel
  public var emitsStyleEscapeSequences: Bool
  public var supportsHyperlinks: Bool
  public var supportsMouseReporting: Bool

  /// Creates a terminal capability profile explicitly.
  public init(
    glyphLevel: GlyphLevel,
    colorLevel: ColorLevel,
    emitsStyleEscapeSequences: Bool,
    supportsHyperlinks: Bool = false,
    supportsMouseReporting: Bool = false
  ) {
    self.glyphLevel = glyphLevel
    self.colorLevel = colorLevel
    self.emitsStyleEscapeSequences = emitsStyleEscapeSequences
    self.supportsHyperlinks = supportsHyperlinks
    self.supportsMouseReporting = supportsMouseReporting
  }

  public static let previewUnicode = Self(
    glyphLevel: .unicode,
    colorLevel: .none,
    emitsStyleEscapeSequences: false,
    supportsHyperlinks: false,
    supportsMouseReporting: false
  )

  public static let previewASCII = Self(
    glyphLevel: .ascii,
    colorLevel: .none,
    emitsStyleEscapeSequences: false,
    supportsHyperlinks: false,
    supportsMouseReporting: false
  )

  public static let ansi16 = Self(
    glyphLevel: .unicode,
    colorLevel: .ansi16,
    emitsStyleEscapeSequences: true,
    supportsHyperlinks: true,
    supportsMouseReporting: true
  )

  public static let ansi256 = Self(
    glyphLevel: .unicode,
    colorLevel: .ansi256,
    emitsStyleEscapeSequences: true,
    supportsHyperlinks: true,
    supportsMouseReporting: true
  )

  public static let trueColor = Self(
    glyphLevel: .unicode,
    colorLevel: .trueColor,
    emitsStyleEscapeSequences: true,
    supportsHyperlinks: true,
    supportsMouseReporting: true
  )

  /// Detects a capability profile from environment variables and TTY status.
  public static func detect(
    environment: [String: String],
    isTTY: Bool
  ) -> Self {
    let term = environment["TERM"]?.lowercased() ?? ""
    let colorTerm = environment["COLORTERM"]?.lowercased() ?? ""
    let localeValues = [
      environment["LC_ALL"],
      environment["LC_CTYPE"],
      environment["LANG"],
    ]

    let supportsUnicode =
      localeValues
      .compactMap { $0?.lowercased() }
      .contains { value in
        value.contains("utf-8") || value.contains("utf8")
      }

    let glyphLevel: GlyphLevel = supportsUnicode ? .unicode : .ascii

    guard isTTY, term != "dumb" else {
      return Self(
        glyphLevel: glyphLevel,
        colorLevel: .none,
        emitsStyleEscapeSequences: false,
        supportsHyperlinks: false,
        supportsMouseReporting: false
      )
    }

    let colorLevel: ColorLevel
    if environment["NO_COLOR"] != nil {
      colorLevel = .none
    } else if colorTerm.contains("truecolor") || colorTerm.contains("24bit") {
      colorLevel = .trueColor
    } else if term.contains("256color") {
      colorLevel = .ansi256
    } else {
      colorLevel = .ansi16
    }

    return Self(
      glyphLevel: glyphLevel,
      colorLevel: colorLevel,
      emitsStyleEscapeSequences: colorLevel != .none,
      supportsHyperlinks: supportsHyperlinks(term: term),
      supportsMouseReporting: supportsMouseReporting(term: term)
    )
  }

  private static func supportsHyperlinks(
    term: String
  ) -> Bool {
    supportsRichTerminalFeatures(term: term)
  }

  private static func supportsMouseReporting(
    term: String
  ) -> Bool {
    supportsRichTerminalFeatures(term: term)
  }

  private static func supportsRichTerminalFeatures(
    term: String
  ) -> Bool {
    guard !term.isEmpty, term != "dumb" else {
      return false
    }

    let sgrCapableTerms = [
      "xterm",
      "screen",
      "tmux",
      "wezterm",
      "kitty",
      "ghostty",
      "rxvt",
      "alacritty",
      "foot",
      "st",
    ]

    return sgrCapableTerms.contains { candidate in
      term.contains(candidate)
    }
  }
}

/// Renders a raster surface into terminal text for a specific capability
/// profile.
public struct TerminalSurfaceRenderer {
  public let capabilityProfile: TerminalCapabilityProfile

  /// Creates a renderer for the supplied capability profile.
  public init(
    capabilityProfile: TerminalCapabilityProfile
  ) {
    self.capabilityProfile = capabilityProfile
  }

  /// Renders a full raster surface into terminal text.
  public func render(_ surface: RasterSurface) -> String {
    surface.cells.enumerated().map { _, row in
      renderRow(row)
    }.joined(separator: "\r\n")
  }

  func renderRow(
    _ row: [RasterCell],
    width: Int? = nil,
    preservingTrailingWhitespace: Bool = false
  ) -> String {
    var end = row.count
    if !preservingTrailingWhitespace {
      while end > 0 {
        let cell = row[end - 1]
        if cell.isContinuation {
          end -= 1
          continue
        }
        if cell.character == " ", cell.style == nil {
          end -= 1
          continue
        }
        break
      }
    }

    return renderCells(
      in: row,
      from: 0,
      to: end,
      width: width
    )
  }

  func renderSpan(
    _ row: [RasterCell],
    from start: Int,
    to end: Int
  ) -> String {
    guard start < end else {
      return ""
    }
    return renderCells(
      in: row,
      from: max(0, start),
      to: max(start, end),
      width: end - start,
      preservingTrailingWhitespace: true
    )
  }
}

struct TerminalPresentationPlan: Sendable {
  struct SpanUpdate: Equatable, Sendable {
    var row: Int
    var column: Int
    var renderedSpan: String
    var cellsChanged: Int
  }

  enum Strategy: String, Equatable, Sendable {
    case fullRepaint
    case incremental
  }

  var strategy: Strategy
  var renderedOutput: String
  var spanUpdates: [SpanUpdate]
  var surfaceSize: Size

  static func fullRepaint(
    renderedOutput: String,
    surfaceSize: Size
  ) -> Self {
    Self(
      strategy: .fullRepaint,
      renderedOutput: renderedOutput,
      spanUpdates: [],
      surfaceSize: surfaceSize
    )
  }

  static func incremental(
    spanUpdates: [SpanUpdate],
    surfaceSize: Size
  ) -> Self {
    Self(
      strategy: .incremental,
      renderedOutput: "",
      spanUpdates: spanUpdates,
      surfaceSize: surfaceSize
    )
  }

  var linesTouched: Int {
    switch strategy {
    case .fullRepaint:
      surfaceSize.height
    case .incremental:
      Set(spanUpdates.map(\.row)).count
    }
  }

  var cellsChanged: Int {
    switch strategy {
    case .fullRepaint:
      max(0, surfaceSize.width) * max(0, surfaceSize.height)
    case .incremental:
      spanUpdates.reduce(0) { $0 + $1.cellsChanged }
    }
  }
}

struct TerminalPresentationPlanner {
  let capabilityProfile: TerminalCapabilityProfile

  func plan(
    previousSurface: RasterSurface?,
    currentSurface: RasterSurface,
    damage: PresentationDamage? = nil
  ) -> TerminalPresentationPlan {
    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )

    guard let previousSurface,
      previousSurface.size == currentSurface.size,
      previousSurface.attachments == currentSurface.attachments,
      previousSurface.imageAttachments == currentSurface.imageAttachments,
      previousSurface.metadata == currentSurface.metadata
    else {
      return .fullRepaint(
        renderedOutput: renderer.render(currentSurface),
        surfaceSize: currentSurface.size
      )
    }

    let rowCount = max(
      max(previousSurface.cells.count, currentSurface.cells.count),
      currentSurface.size.height
    )
    let rowsToDiff: [Int] =
      if let damage {
        damage.dirtyRows
          .filter { $0 >= 0 && $0 < rowCount }
          .sorted()
      } else {
        Array(0..<rowCount)
      }
    var spanUpdates: [TerminalPresentationPlan.SpanUpdate] = []

    for row in rowsToDiff {
      let previousRow = row < previousSurface.cells.count ? previousSurface.cells[row] : []
      let currentRow = row < currentSurface.cells.count ? currentSurface.cells[row] : []
      let rowSpans = renderer.diffSpans(
        previousRow: previousRow,
        currentRow: currentRow,
        width: max(
          previousSurface.size.width,
          currentSurface.size.width,
          previousRow.count,
          currentRow.count
        )
      )

      for span in rowSpans {
        spanUpdates.append(
          .init(
            row: row,
            column: span.lowerBound,
            renderedSpan: renderer.renderSpan(
              currentRow,
              from: span.lowerBound,
              to: span.upperBound
            ),
            cellsChanged: renderer.cellsChanged(
              in: currentRow,
              from: span.lowerBound,
              to: span.upperBound
            )
          )
        )
      }
    }

    return .incremental(
      spanUpdates: spanUpdates,
      surfaceSize: currentSurface.size
    )
  }
}

extension TerminalSurfaceRenderer {
  private func renderCells(
    in row: [RasterCell],
    from start: Int,
    to end: Int,
    width: Int? = nil,
    preservingTrailingWhitespace: Bool = false
  ) -> String {
    if !preservingTrailingWhitespace {
      var trimmedEnd = max(start, min(end, row.count))
      while trimmedEnd > start {
        let cell = cell(at: trimmedEnd - 1, in: row)
        if cell.isContinuation {
          trimmedEnd -= 1
          continue
        }
        if cell.character == " ", cell.style == nil {
          trimmedEnd -= 1
          continue
        }
        break
      }
      return renderCells(
        in: row,
        from: start,
        to: trimmedEnd,
        width: width,
        preservingTrailingWhitespace: true
      )
    }

    var result = ""
    var activeStyle: ResolvedTextStyle?
    var activeHyperlink: String?
    var renderedWidth = 0

    for index in start..<max(start, end) {
      let cell = cell(at: index, in: row)
      guard !cell.isContinuation else {
        continue
      }
      let style = cell.style
      let hyperlink = cell.hyperlink

      if hyperlink != activeHyperlink {
        if activeHyperlink != nil, capabilityProfile.supportsHyperlinks {
          result += closeHyperlinkSequence()
        }
        if let hyperlink, capabilityProfile.supportsHyperlinks {
          result += openHyperlinkSequence(for: .init(hyperlink))
        }
        activeHyperlink = hyperlink
      }

      if style != activeStyle {
        if activeStyle != nil, capabilityProfile.emitsStyleEscapeSequences {
          result += escapeSequence(forCodes: [0])
        }
        if let style,
          capabilityProfile.emitsStyleEscapeSequences,
          let sequence = styleSequence(for: style)
        {
          result += sequence
        }
        activeStyle = style
      }

      result += renderedCharacter(for: cell)
      renderedWidth += max(1, cell.spanWidth)
    }

    if activeHyperlink != nil, capabilityProfile.supportsHyperlinks {
      result += closeHyperlinkSequence()
    }
    if activeStyle != nil, capabilityProfile.emitsStyleEscapeSequences {
      result += escapeSequence(forCodes: [0])
    }

    if let width {
      result += String(repeating: " ", count: max(0, width - renderedWidth))
    }

    return result
  }

  func diffSpans(
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int
  ) -> [Range<Int>] {
    guard width > 0 else {
      return []
    }

    var spans: [Range<Int>] = []
    var index = 0
    while index < width {
      guard cell(at: index, in: previousRow) != cell(at: index, in: currentRow) else {
        index += 1
        continue
      }

      let rawStart = index
      index += 1
      while index < width,
        cell(at: index, in: previousRow) != cell(at: index, in: currentRow)
      {
        index += 1
      }

      let normalized = normalizeSpan(
        rawStart..<index,
        previousRow: previousRow,
        currentRow: currentRow,
        width: width
      )

      if let last = spans.last,
        last.upperBound >= normalized.lowerBound
      {
        spans[spans.count - 1] = last.lowerBound..<max(last.upperBound, normalized.upperBound)
      } else {
        spans.append(normalized)
      }
    }

    return spans
  }

  func normalizeSpan(
    _ span: Range<Int>,
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int
  ) -> Range<Int> {
    guard !span.isEmpty else {
      return span
    }

    var start = max(0, min(span.lowerBound, width))
    var end = max(start, min(span.upperBound, width))

    while start > 0 {
      let candidate = min(
        leadIndexIfContinuation(at: start, in: currentRow),
        leadIndexIfContinuation(at: start, in: previousRow)
      )
      guard candidate < start else {
        break
      }
      start = candidate
    }

    while end < width {
      if cell(at: end, in: currentRow).isContinuation
        || cell(at: end, in: previousRow).isContinuation
      {
        end += 1
        continue
      }
      break
    }

    return start..<end
  }

  func leadIndexIfContinuation(
    at index: Int,
    in row: [RasterCell]
  ) -> Int {
    guard cell(at: index, in: row).isContinuation else {
      return index
    }
    return max(0, min(index, cell(at: index, in: row).continuationLeadX ?? index))
  }

  func cell(
    at index: Int,
    in row: [RasterCell]
  ) -> RasterCell {
    row.indices.contains(index) ? row[index] : .empty
  }

  func cellsChanged(
    in row: [RasterCell],
    from start: Int,
    to end: Int
  ) -> Int {
    guard start < end else {
      return 0
    }

    var total = 0
    for index in start..<end {
      let cell = cell(at: index, in: row)
      guard !cell.isContinuation else {
        continue
      }
      total += max(1, cell.spanWidth)
    }
    return total
  }

  private func renderedCharacter(
    for cell: RasterCell
  ) -> String {
    if capabilityProfile.glyphLevel == .ascii {
      return degradedASCIIText(
        character: cell.character,
        spanWidth: max(1, cell.spanWidth)
      )
    }
    return String(cell.character)
  }

  private func styleSequence(
    for style: ResolvedTextStyle
  ) -> String? {
    var codes: [String] = []
    codes.append(contentsOf: emphasisCodes(for: style))

    if let foregroundColor = style.foregroundColor,
      let foregroundCodes = colorCodes(
        color: foregroundColor,
        isBackground: false
      )
    {
      codes.append(contentsOf: foregroundCodes.map(String.init))
    }

    if let backgroundColor = style.backgroundColor,
      let backgroundCodes = colorCodes(
        color: backgroundColor,
        isBackground: true
      )
    {
      codes.append(contentsOf: backgroundCodes.map(String.init))
    }

    if let underlineColor = style.underlineStyle?.color,
      let underlineColorCodes = underlineColorCodes(for: underlineColor)
    {
      codes.append(contentsOf: underlineColorCodes)
    }

    guard !codes.isEmpty else {
      return nil
    }

    return escapeSequence(forCodeStrings: codes)
  }

  private func emphasisCodes(
    for style: ResolvedTextStyle
  ) -> [String] {
    var codes: [String] = []

    if style.emphasis.contains(.bold) {
      codes.append("1")
    }
    if style.emphasis.contains(.faint) || style.opacity < 1 {
      codes.append("2")
    }
    if style.emphasis.contains(.italic) {
      codes.append("3")
    }
    if let underlineStyle = style.underlineStyle {
      codes.append(underlineCode(for: underlineStyle))
    }
    if style.emphasis.contains(.blink) {
      codes.append("5")
    }
    if style.emphasis.contains(.reverse) {
      codes.append("7")
    }
    if style.strikethroughStyle != nil {
      codes.append("9")
    }

    return codes
  }

  private func underlineCode(
    for style: TextLineStyle
  ) -> String {
    switch style.pattern {
    case .solid:
      return "4"
    case .double:
      return "4:2"
    case .curly:
      return "4:3"
    case .dot:
      return "4:4"
    case .dash, .dashDot, .dashDotDot:
      return "4:5"
    }
  }

  private func underlineColorCodes(
    for color: Color
  ) -> [String]? {
    guard capabilityProfile.colorLevel != .none else {
      return nil
    }

    switch capabilityProfile.colorLevel {
    case .none, .ansi16:
      return nil
    case .ansi256:
      return ["58", "5", String(ansi256Code(for: color))]
    case .trueColor:
      return [
        "58",
        "2",
        String(Int(color.red * 255)),
        String(Int(color.green * 255)),
        String(Int(color.blue * 255)),
      ]
    }
  }

  private func colorCodes(
    color: Color,
    isBackground: Bool
  ) -> [Int]? {
    guard capabilityProfile.colorLevel != .none else {
      return nil
    }

    switch capabilityProfile.colorLevel {
    case .none:
      return nil
    case .ansi16:
      let code = closestANSI16ForegroundCode(for: color)
      return [isBackground ? backgroundCode(forForegroundCode: code) : code]
    case .ansi256:
      return [isBackground ? 48 : 38, 5, ansi256Code(for: color)]
    case .trueColor:
      return [
        isBackground ? 48 : 38,
        2,
        Int(color.red * 255),
        Int(color.green * 255),
        Int(color.blue * 255),
      ]
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
    "\u{001B}]8;;\(destination.rawValue)\u{001B}\\"
  }

  private func closeHyperlinkSequence() -> String {
    "\u{001B}]8;;\u{001B}\\"
  }

  private func backgroundCode(
    forForegroundCode code: Int
  ) -> Int {
    code + 10
  }

  private func closestANSI16ForegroundCode(
    for color: Color
  ) -> Int {
    let palette: [(Int, Color)] = [
      (30, .init(hexRGB: 0x000000)),
      (91, .init(hexRGB: 0xFF5555)),
      (92, .init(hexRGB: 0x50C878)),
      (93, .init(hexRGB: 0xFFD700)),
      (94, .init(hexRGB: 0x6495ED)),
      (95, .init(hexRGB: 0xDA70D6)),
      (96, .init(hexRGB: 0x40E0D0)),
      (97, .init(hexRGB: 0xF5F5F5)),
      (90, .init(hexRGB: 0x808080)),
    ]

    return palette.min {
      color.deltaE(to: $0.1) < color.deltaE(to: $1.1)
    }?.0 ?? 97
  }

  private func ansi256Code(
    for color: Color
  ) -> Int {
    switch color {
    case .black:
      return 16
    case .red:
      return 203
    case .green:
      return 114
    case .yellow:
      return 179
    case .blue:
      return 111
    case .magenta:
      return 176
    case .cyan:
      return 117
    case .white:
      return 255
    case .gray:
      return 145
    default:
      break
    }

    let red = Int((color.red * 5).rounded())
    let green = Int((color.green * 5).rounded())
    let blue = Int((color.blue * 5).rounded())
    return 16 + (36 * red) + (6 * green) + blue
  }

}
