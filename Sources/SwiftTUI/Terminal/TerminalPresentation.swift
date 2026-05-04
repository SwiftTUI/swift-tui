import SwiftTUICore

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
  public var supportsSynchronizedOutput: Bool

  /// Creates a terminal capability profile explicitly.
  public init(
    glyphLevel: GlyphLevel,
    colorLevel: ColorLevel,
    emitsStyleEscapeSequences: Bool,
    supportsHyperlinks: Bool = false,
    supportsMouseReporting: Bool = false,
    supportsSynchronizedOutput: Bool = false
  ) {
    self.glyphLevel = glyphLevel
    self.colorLevel = colorLevel
    self.emitsStyleEscapeSequences = emitsStyleEscapeSequences
    self.supportsHyperlinks = supportsHyperlinks
    self.supportsMouseReporting = supportsMouseReporting
    self.supportsSynchronizedOutput = supportsSynchronizedOutput
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
      supportsMouseReporting: supportsMouseReporting(term: term),
      supportsSynchronizedOutput: supportsSynchronizedOutput(term: term)
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

  private static func supportsSynchronizedOutput(
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
    let rowStrings = surface.cells.map { row in
      renderRow(row)
    }
    // Pre-size: each row contributes its character count plus a \r\n separator.
    let estimatedSize = rowStrings.reduce(0) { $0 + $1.utf8.count + 2 }
    var result = ""
    result.reserveCapacity(estimatedSize)
    for (index, row) in rowStrings.enumerated() {
      if index > 0 {
        result += "\r\n"
      }
      result += row
    }
    return result
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
  struct GraphicsReplayPlan: Equatable, Sendable {
    enum Scope: String, Equatable, Sendable {
      case none
      case targeted
      case full
    }

    var scope: Scope
    var attachmentsToReplay: [RasterImageAttachment]

    static let none = Self(
      scope: .none,
      attachmentsToReplay: []
    )
  }

  struct SpanUpdate: Equatable, Sendable {
    var row: Int
    var column: Int
    var renderedSpan: String
    var cellsChanged: Int
  }

  struct RowBatch: Equatable, Sendable {
    var row: Int
    var anchorColumn: Int
    var renderedBatch: String
    var spanUpdates: [SpanUpdate]

    var cellsChanged: Int {
      spanUpdates.reduce(0) { $0 + $1.cellsChanged }
    }

    func canLowerToEraseToEndOfLine(
      surfaceWidth: Int
    ) -> Bool {
      guard
        spanUpdates.count == 1,
        let span = spanUpdates.first,
        renderedBatch == span.renderedSpan,
        span.column == anchorColumn,
        span.column + span.cellsChanged >= surfaceWidth,
        !span.renderedSpan.isEmpty
      else {
        return false
      }

      return span.renderedSpan.allSatisfy { $0 == " " }
    }
  }

  enum Strategy: String, Equatable, Sendable {
    case fullRepaint
    case incremental
  }

  var strategy: Strategy
  var rowBatches: [RowBatch]
  var graphicsReplay: GraphicsReplayPlan
  var surfaceSize: CellSize

  static func fullRepaint(
    surfaceSize: CellSize
  ) -> Self {
    Self(
      strategy: .fullRepaint,
      rowBatches: [],
      graphicsReplay: .none,
      surfaceSize: surfaceSize
    )
  }

  static func incremental(
    rowBatches: [RowBatch],
    graphicsReplay: GraphicsReplayPlan,
    surfaceSize: CellSize
  ) -> Self {
    Self(
      strategy: .incremental,
      rowBatches: rowBatches,
      graphicsReplay: graphicsReplay,
      surfaceSize: surfaceSize
    )
  }

  var spanUpdates: [SpanUpdate] {
    rowBatches.flatMap(\.spanUpdates)
  }

  var linesTouched: Int {
    switch strategy {
    case .fullRepaint:
      surfaceSize.height
    case .incremental:
      Set(rowBatches.map(\.row)).count
    }
  }

  var cellsChanged: Int {
    switch strategy {
    case .fullRepaint:
      max(0, surfaceSize.width) * max(0, surfaceSize.height)
    case .incremental:
      rowBatches.reduce(0) { $0 + $1.cellsChanged }
    }
  }
}

struct TerminalPresentationPlanner {
  let capabilityProfile: TerminalCapabilityProfile
  let graphicsCapabilities: TerminalGraphicsCapabilities

  init(
    capabilityProfile: TerminalCapabilityProfile,
    graphicsCapabilities: TerminalGraphicsCapabilities = .none
  ) {
    self.capabilityProfile = capabilityProfile
    self.graphicsCapabilities = graphicsCapabilities
  }

  func plan(
    previousSurface: RasterSurface?,
    currentSurface: RasterSurface,
    damage: PresentationDamage? = nil
  ) -> TerminalPresentationPlan {
    guard let previousSurface,
      previousSurface.size == currentSurface.size,
      previousSurface.attachments == currentSurface.attachments,
      previousSurface.metadata == currentSurface.metadata
    else {
      return .fullRepaint(
        surfaceSize: currentSurface.size
      )
    }

    let supportsIncrementalGraphicsReplay = graphicsCapabilities.preferredProtocol == .kitty
    if previousSurface.imageAttachments != currentSurface.imageAttachments,
      !supportsIncrementalGraphicsReplay
    {
      return .fullRepaint(
        surfaceSize: currentSurface.size
      )
    }

    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )

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
    var rowBatches: [TerminalPresentationPlan.RowBatch] = []

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
        ),
        limitingTo: damage?.columnRanges(for: row)
      )

      if let rowBatch = renderer.renderRowBatch(
        row: row,
        currentRow: currentRow,
        spans: rowSpans
      ) {
        rowBatches.append(rowBatch)
      }
    }

    let graphicsReplay = graphicsReplayPlan(
      previousAttachments: previousSurface.imageAttachments,
      currentAttachments: currentSurface.imageAttachments,
      dirtyRows: Set(rowBatches.map(\.row)),
      supportsIncrementalGraphicsReplay: supportsIncrementalGraphicsReplay
    )

    return .incremental(
      rowBatches: rowBatches,
      graphicsReplay: graphicsReplay,
      surfaceSize: currentSurface.size
    )
  }

  private func graphicsReplayPlan(
    previousAttachments: [RasterImageAttachment],
    currentAttachments: [RasterImageAttachment],
    dirtyRows: Set<Int>,
    supportsIncrementalGraphicsReplay: Bool
  ) -> TerminalPresentationPlan.GraphicsReplayPlan {
    guard supportsIncrementalGraphicsReplay else {
      return .none
    }
    guard !previousAttachments.isEmpty || !currentAttachments.isEmpty else {
      return .none
    }

    if previousAttachments != currentAttachments {
      return .init(
        scope: .full,
        attachmentsToReplay: currentAttachments
      )
    }

    let attachmentsToReplay = currentAttachments.filter { attachment in
      attachment.visibleBoundsIntersectsAnyDirtyRow(dirtyRows)
    }
    guard !attachmentsToReplay.isEmpty else {
      return .none
    }

    return .init(
      scope: .targeted,
      attachmentsToReplay: attachmentsToReplay
    )
  }
}

extension RasterImageAttachment {
  fileprivate func visibleBoundsIntersectsAnyDirtyRow(_ dirtyRows: Set<Int>) -> Bool {
    guard !dirtyRows.isEmpty else {
      return false
    }

    let lowerRow = visibleBounds.origin.y
    let upperRow = visibleBounds.origin.y + visibleBounds.size.height
    guard lowerRow < upperRow else {
      return false
    }

    return dirtyRows.contains { dirtyRow in
      dirtyRow >= lowerRow && dirtyRow < upperRow
    }
  }
}

extension TerminalSurfaceRenderer {
  private struct RenderState {
    var activeStyle: ResolvedTextStyle?
    var activeHyperlink: String?
  }

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

    // Reserve capacity: ~2 bytes per cell for characters, plus ~16 bytes
    // per style transition for escape sequences.  Overestimates slightly
    // but avoids repeated String reallocations.
    let cellCount = max(0, end - start)
    var result = ""
    result.reserveCapacity(cellCount * 3)
    var state = RenderState()
    let renderedWidth = appendRenderedCells(
      in: row,
      from: start,
      to: max(start, end),
      into: &result,
      state: &state
    )
    closeRenderState(&state, into: &result)

    if let width {
      result += String(repeating: " ", count: max(0, width - renderedWidth))
    }

    return result
  }

  func renderRowBatch(
    row: Int,
    currentRow: [RasterCell],
    spans: [Range<Int>]
  ) -> TerminalPresentationPlan.RowBatch? {
    let orderedSpans =
      spans
      .filter { !$0.isEmpty }
      .sorted { lhs, rhs in
        lhs.lowerBound < rhs.lowerBound
      }
    guard let firstSpan = orderedSpans.first else {
      return nil
    }

    var renderedBatch = ""
    renderedBatch.reserveCapacity(
      orderedSpans.reduce(0) { partial, span in
        partial + max(0, span.upperBound - span.lowerBound) * 3
      }
    )
    var state = RenderState()
    var cursorColumn = firstSpan.lowerBound
    var spanUpdates: [TerminalPresentationPlan.SpanUpdate] = []

    for span in orderedSpans {
      if span.lowerBound > cursorColumn {
        renderedBatch += cursorForwardSequence(span.lowerBound - cursorColumn)
        cursorColumn = span.lowerBound
      }

      var renderedSpan = ""
      renderedSpan.reserveCapacity(max(0, span.upperBound - span.lowerBound) * 3)
      _ = appendRenderedCells(
        in: currentRow,
        from: span.lowerBound,
        to: span.upperBound,
        into: &renderedSpan,
        state: &state
      )
      renderedBatch += renderedSpan

      spanUpdates.append(
        .init(
          row: row,
          column: span.lowerBound,
          renderedSpan: renderedSpan,
          cellsChanged: cellsChanged(
            in: currentRow,
            from: span.lowerBound,
            to: span.upperBound
          )
        )
      )
      cursorColumn = span.upperBound
    }

    closeRenderState(&state, into: &renderedBatch)

    return .init(
      row: row,
      anchorColumn: firstSpan.lowerBound,
      renderedBatch: renderedBatch,
      spanUpdates: spanUpdates
    )
  }

  func diffSpans(
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int,
    limitingTo candidateRanges: [Range<Int>]? = nil
  ) -> [Range<Int>] {
    guard width > 0 else {
      return []
    }

    if let candidateRanges, !candidateRanges.isEmpty {
      var spans: [Range<Int>] = []
      for candidateRange in candidateRanges {
        appendDiffSpans(
          in: candidateRange,
          previousRow: previousRow,
          currentRow: currentRow,
          width: width,
          to: &spans
        )
      }
      return spans
    }

    var spans: [Range<Int>] = []
    appendDiffSpans(
      in: 0..<width,
      previousRow: previousRow,
      currentRow: currentRow,
      width: width,
      to: &spans
    )
    return spans
  }

  private func appendDiffSpans(
    in candidateRange: Range<Int>,
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int,
    to spans: inout [Range<Int>]
  ) {
    let lowerBound = max(0, min(width, candidateRange.lowerBound))
    let upperBound = max(lowerBound, min(width, candidateRange.upperBound))
    guard lowerBound < upperBound else {
      return
    }

    var index = lowerBound
    while index < upperBound {
      guard cell(at: index, in: previousRow) != cell(at: index, in: currentRow) else {
        index += 1
        continue
      }

      let rawStart = index
      index += 1
      while index < upperBound,
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

  @discardableResult
  private func appendRenderedCells(
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

  private func transitionRenderState(
    style: ResolvedTextStyle?,
    hyperlink: String?,
    state: inout RenderState,
    into result: inout String
  ) {
    if hyperlink != state.activeHyperlink {
      if state.activeHyperlink != nil, capabilityProfile.supportsHyperlinks {
        result += closeHyperlinkSequence()
      }
      if let hyperlink, capabilityProfile.supportsHyperlinks {
        result += openHyperlinkSequence(for: .init(hyperlink))
      }
      state.activeHyperlink = hyperlink
    }

    if style != state.activeStyle {
      if state.activeStyle != nil, capabilityProfile.emitsStyleEscapeSequences {
        result += "\u{001B}[0m"
      }
      if let style,
        capabilityProfile.emitsStyleEscapeSequences,
        let sequence = styleSequence(for: style)
      {
        result += sequence
      }
      state.activeStyle = style
    }
  }

  private func closeRenderState(
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

  private func cursorForwardSequence(
    _ count: Int
  ) -> String {
    guard count > 0 else {
      return ""
    }
    return "\u{001B}[\(count)C"
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
      appendCode(Int(color.red * 255))
      appendCode(Int(color.green * 255))
      appendCode(Int(color.blue * 255))
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
      appendCode(String(Int(color.red * 255)))
      appendCode(String(Int(color.green * 255)))
      appendCode(String(Int(color.blue * 255)))
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

  /// Cache for recent ANSI16 color lookups.  The deltaE computation is
  /// expensive; apps typically use a small set of colors so a tiny cache
  /// eliminates almost all redundant work across a frame.
  private static let ansi16Cache = ANSI16Cache()

  private final class ANSI16Cache: Sendable {
    private struct Storage {
      // Fixed-size ring of the last 8 mappings.
      var entries: [(color: Color, code: Int)] = []
      var cursor: Int = 0
    }

    private let storage = OSAllocatedUnfairLock<Storage>(uncheckedState: .init())

    func lookup(for color: Color) -> Int? {
      storage.withLock { storage in
        storage.entries.first(where: { $0.color == color })?.code
      }
    }

    func store(color: Color, code: Int) {
      storage.withLock { storage in
        if storage.entries.count < 8 {
          storage.entries.append((color, code))
        } else {
          storage.entries[storage.cursor] = (color, code)
          storage.cursor = (storage.cursor + 1) % 8
        }
      }
    }
  }

  private static let ansi16Palette: [(Int, Color)] = [
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

  private func closestANSI16ForegroundCode(
    for color: Color
  ) -> Int {
    if let cached = Self.ansi16Cache.lookup(for: color) {
      return cached
    }

    let code =
      Self.ansi16Palette.min {
        color.deltaE(to: $0.1) < color.deltaE(to: $1.1)
      }?.0 ?? 97

    Self.ansi16Cache.store(color: color, code: code)
    return code
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
