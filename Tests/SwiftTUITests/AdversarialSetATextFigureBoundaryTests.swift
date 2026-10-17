@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetATextFigureBoundaryTests {
  @Test func setA726StyledFragmentsCannotSplitOneExtendedGraphemeIntoTwoGlyphs() throws {
    // Hypothesis: clusterizing each styled run independently changes the width of a grapheme spanning a run seam.
    let text = Text("\(Text("👩").bold())\(Text("\u{200D}💻").italic())X")
    #expect(text.content == "👩‍💻X")
    #expect(text.content.count == 2)
    let payload = try #require(richPayloads(in: render(text).resolvedTree).first)
    #expect(payload.runs.count == 3)
    let plain = layoutText(for: text.content, width: nil)
    #expect(plain.size == .init(width: 3, height: 1))
    let composed = layoutRichText(for: payload, options: .init())
    withKnownIssue("STUI-1007: rich runs independently split a grapheme spanning a style seam") {
      #expect(composed.size == plain.size)
    }
  }

  @Test func setA727IndependentTextCopiesDoNotShareWritableStyleMetadata() throws {
    // Hypothesis: boxed Text metadata aliases an earlier value when a copied fragment removes one emphasis and adds a decoration.
    let original = Text("X").bold().italic()
    let second = original.bold(false).underline()
    let third = second.italic(false)
    let payload = try #require(
      richPayloads(in: render(Text("\(original)|\(second)|\(third)")).resolvedTree).first)
    let fragments = payload.runs.filter { $0.text == "X" }
    #expect(fragments.count == 3)
    #expect(fragments.map(\.style.emphasis) == [[.bold, .italic], .italic, []])
    #expect(fragments.map { $0.style.underlineStyle != nil } == [false, true, true])
    #expect(original == Text("X").bold().italic())
  }

  @Test func setA728AbsentInterpolatedValuesPreserveTheNeighboringStyledBoundary() throws {
    // Hypothesis: an absent optional flushes or discards the literal buffer around a styled fragment.
    let absent: Int? = nil
    let present: Int? = 7
    let text = Text("L\(absent)\(Text("M").bold())\(present)R")
    #expect(text.content == "LM7R")
    let payload = try #require(richPayloads(in: render(text).resolvedTree).first)
    #expect(payload.runs.map(\.text) == ["L", "M", "7R"])
    #expect(payload.runs.map { $0.style.emphasis.contains(.bold) } == [false, true, false])
  }

  @Test func setA729SubstringInterpolationDoesNotRecoverItsParentStringsIndices() {
    // Hypothesis: StringProtocol interpolation retains the source's full backing storage or miscounts a nonzero slice origin.
    let source = "discardA界Bdiscard"
    let slice = source.dropFirst(7).dropLast(7)
    let text = Text("[\(slice)]")
    #expect(text.content == "[A界B]")
    let snapshot = render(text)
    #expect(snapshot.measuredTree.measuredSize == .init(width: 6, height: 1))
    #expect(snapshot.rasterSurface.lines == ["[A界B]"])
  }

  @Test func setA730NestedRichFragmentsAllocateIndependentInlineLinkActions() throws {
    // Hypothesis: recursive rich-text flattening resets inline-link numbering and dispatches two different labels to one owner.
    let destinations = SetATextDestinationLog()
    let first = Link("FIRST", destination: "https://example.org/first")
    let second = Link("SECOND", destination: "https://example.org/second")
    let nested = Text("(\(first))")
    let h = try make(730) {
      Text("\(nested) + \(second)").environment(
        \.openLinkAction,
        OpenLinkAction { destination in
          destinations.values.append(destination)
          return true
        })
    }
    defer { h.shutdown() }
    let firstID = try h.focusIdentity(forText: "FIRST")
    let secondID = try h.focusIdentity(forText: "SECOND")
    #expect(firstID != secondID)
    #expect(h.focusRegionCount == 2)
    try h.clickText("FIRST")
    try h.clickText("SECOND")
    #expect(destinations.values == ["https://example.org/first", "https://example.org/second"])
  }

  @Test func setA731AnEmptyInlineLinkCannotCreateAnInvisibleKeyboardStop() throws {
    // Hypothesis: registering an empty inline link gives it a zero-width focus stop before the visible link.
    let destinations = SetATextDestinationLog()
    let h = try make(731) {
      Text("\(Link("", destination: "empty"))\(Link("VISIBLE", destination: "visible"))")
        .environment(
          \.openLinkAction,
          OpenLinkAction { destination in
            destinations.values.append(destination)
            return true
          })
    }
    defer { h.shutdown() }
    #expect(h.focusRegionCount == 1)
    let visible = try h.focusIdentity(forText: "VISIBLE")
    try h.pressKey(.init(.tab))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == visible)
    try h.pressKey(.init(.return))
    #expect(destinations.values == ["visible"])
  }

  @Test func setA732ReplacingAnInlineLinkWithEqualPlainTextRetiresItsAction() throws {
    // Hypothesis: equal visible text lets the retained frame keep an inline link's semantic region and registered action.
    let destinations = SetATextDestinationLog()
    var linked = true
    let h = try make(732) {
      let value = linked ? Text("\(Link("SAME", destination: "old"))") : Text("SAME")
      value.environment(
        \.openLinkAction,
        OpenLinkAction { destination in
          destinations.values.append(destination)
          return true
        })
    }
    defer { h.shutdown() }
    #expect(h.focusRegionCount == 1)
    try h.clickText("SAME")
    #expect(destinations.values == ["old"])
    linked = false
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("SAME"))
    #expect(h.focusRegionCount == 0)
    #expect(h.actionRegistrationCount == 0)
    try h.clickText("SAME")
    #expect(destinations.values == ["old"])
  }

  @Test func setA733RemovingAnExplicitDecorationClearRestoresAmbientInheritance() throws {
    // Hypothesis: a rich fragment's retained explicit-clear bit survives replacement by an unstyled value with identical text.
    var clears = true
    let h = try make(733) {
      let fragment = clears ? Text("MID").underline(false) : Text("MID")
      VStack { Text("L\(fragment)R") }.underline(pattern: .dotted)
    }
    defer { h.shutdown() }
    var payload = try #require(richPayloads(in: runtimeTree(h)).first)
    #expect(try #require(payload.runs.first { $0.text == "MID" }).style.underlineStyle == nil)
    #expect(payload.runs.first?.style.underlineStyle == .init(pattern: .dotted))
    clears = false
    try h.renderAfterExternalMutation()
    payload = try #require(richPayloads(in: runtimeTree(h)).first)
    #expect(payload.visibleText == "LMIDR")
    #expect(payload.runs.allSatisfy { $0.style.underlineStyle == .init(pattern: .dotted) })
    clears = true
    try h.renderAfterExternalMutation()
    payload = try #require(richPayloads(in: runtimeTree(h)).first)
    #expect(try #require(payload.runs.first { $0.text == "MID" }).style.underlineStyle == nil)
  }

  @Test func setA734AWrappedRichParagraphKeepsOneAuthoredParagraphBoundary() throws {
    // Hypothesis: flattening styled runs or wrapping rows duplicates paragraph metadata and its host-requested spacing.
    let snapshot = render(
      VStack(alignment: .leading, spacing: 0) {
        Text("A\(Text("BC").bold()) D").paragraph()
        Text("Z")
      }, proposal: .init(width: 3, height: .unspecified), paragraphSpacing: 2)
    #expect(snapshot.semanticSnapshot.paragraphs.count == 1)
    let paragraph = try #require(snapshot.semanticSnapshot.paragraphs.first)
    #expect(paragraph.rect.size == .init(width: 3, height: 2))
    #expect(snapshot.rasterSurface.lines == ["ABC", "D", "", "", "Z"])
  }

  @Test func setA735ExplicitBlankLinesInsideAParagraphDoNotMultiplyHostSpacing() throws {
    // Hypothesis: authored newlines are treated as paragraph boundaries, adding host spacing inside a single paragraph.
    let snapshot = render(
      VStack(alignment: .leading, spacing: 0) {
        Text("A\n\nB").paragraph()
        Text("C")
      }, paragraphSpacing: 2)
    let paragraph = try #require(snapshot.semanticSnapshot.paragraphs.first)
    #expect(snapshot.semanticSnapshot.paragraphs.count == 1)
    #expect(paragraph.rect.size.height == 3)
    #expect(snapshot.rasterSurface.lines == ["A", "", "B", "", "", "C"])
  }

  @Test func setA736ChangingAParagraphLineLimitUpdatesItsSemanticExtent() throws {
    // Hypothesis: the paragraph wrapper retains an old multirow semantic rectangle after its text acquires a one-line limit.
    var limit: Int? = nil
    let h = try make(736) {
      VStack(alignment: .leading, spacing: 0) {
        Text("one two three").paragraph().lineLimit(limit)
        Text("END")
      }.frame(width: 7, alignment: .topLeading)
    }
    defer { h.shutdown() }
    let initial = try #require(h.runLoop.latestSemanticSnapshot.paragraphs.first)
    #expect(initial.rect.size.height == 2)
    let before = try #require(h.point(forText: "END"))
    limit = 1
    try h.renderAfterExternalMutation()
    let changed = try #require(h.runLoop.latestSemanticSnapshot.paragraphs.first)
    #expect(changed.rect.size.height == 1)
    let after = try #require(h.point(forText: "END"))
    #expect(before.y - after.y == 1)
    #expect(h.frame.contains("one tw…"))
  }

  @Test func setA737AmbientTextLimitsCannotTruncatePreformattedFontRows() {
    // Hypothesis: ambient plain-text layout attributes are stamped on a FIGlet leaf and truncate or rewrap its authored rows.
    let baseline = render(TextFigure("Hi"))
    let decorated = render(
      VStack(spacing: 0) { TextFigure("Hi") }.lineLimit(1).truncationMode(.head))
    #expect(baseline.rasterSurface.lines == standardHi)
    #expect(decorated.measuredTree.measuredSize == .init(width: 9, height: 6))
    #expect(decorated.rasterSurface.lines == standardHi)
  }

  @Test func setA738DecoratingFontOutputPreservesItsInternalPreformattedSpaces() {
    // Hypothesis: applying text decorations sends ASCII art through word wrapping and collapses its interior alignment spaces.
    let snapshot = render(TextFigure("Hi").underline(pattern: .dashed).strikethrough())
    #expect(snapshot.rasterSurface.lines == standardHi)
    #expect(snapshot.rasterSurface.cells[1][3].character == " ")
    #expect(snapshot.rasterSurface.cells[1][3].style?.underlineStyle == .init(pattern: .dashed))
    #expect(snapshot.rasterSurface.cells[1][3].style?.strikethroughStyle != nil)
  }

  @Test func setA739ChangingFontsRepositionsTheFollowingRuntimeSibling() throws {
    // Hypothesis: a retained TextFigure measurement is keyed by content but omits the font's different row height.
    var font = TextFigure.Font.standard
    let h = try make(739) {
      VStack(alignment: .leading, spacing: 0) {
        TextFigure("Hi", font: font)
        Text("END")
      }.frame(width: 30, height: 20, alignment: .topLeading)
    }
    defer { h.shutdown() }
    let originalFrame = h.frame
    let original = try #require(h.point(forText: "END"))
    font = .small
    try h.renderAfterExternalMutation()
    let small = try #require(h.point(forText: "END"))
    // The embedded standard and small font headers declare six and five rows.
    #expect(original.y - small.y == 1)
    #expect(h.frame != originalFrame)
    font = .standard
    try h.renderAfterExternalMutation()
    #expect(h.frame == originalFrame)
  }

  @Test func setA740WideningAFontRunRejoinsPreviouslyWrappedGlyphs() throws {
    // Hypothesis: a warm figure measurement or draw product keeps the narrow proposal's glyph-per-line reflow after widening.
    var width = 8
    let h = try make(740) {
      VStack(alignment: .leading, spacing: 0) {
        TextFigure("Hi").frame(width: width, alignment: .topLeading)
        Text("END")
      }.frame(width: 30, height: 20, alignment: .topLeading)
    }
    defer { h.shutdown() }
    let original = h.frame
    let before = try #require(h.point(forText: "END"))
    width = 9
    try h.renderAfterExternalMutation()
    let after = try #require(h.point(forText: "END"))
    #expect(before.y - after.y == 6)
    #expect(h.frame.contains("| |_| | |"))
    width = 8
    try h.renderAfterExternalMutation()
    #expect(h.frame == original)
  }

  @Test func setA741EmptyFontContentReleasesItsHeightAndErasesThePreviousArt() throws {
    // Hypothesis: TextFigure's empty fast path leaves a retained nonempty measurement or raster after the content becomes empty.
    var value = "Hi"
    let h = try make(741) {
      VStack(alignment: .leading, spacing: 0) {
        TextFigure(value)
        Text("END")
      }.frame(width: 30, height: 20, alignment: .topLeading)
    }
    defer { h.shutdown() }
    let before = try #require(h.point(forText: "END"))
    #expect(h.frame.contains("| |_| | |"))
    value = ""
    try h.renderAfterExternalMutation()
    let after = try #require(h.point(forText: "END"))
    #expect(before.y - after.y == 6)
    #expect(!h.frame.contains("|") && !h.frame.contains("_"))
  }

  @Test func setA742ExplicitFontNewlinesDoNotSmushTheNextLogicalLine() {
    // Hypothesis: FIGlet's smush state crosses an explicit newline and changes the first glyph of the following line.
    let snapshot = render(TextFigure("Hi\nHi"))
    #expect(snapshot.measuredTree.measuredSize == .init(width: 9, height: 12))
    #expect(snapshot.rasterSurface.lines == standardHi + standardHi)
  }

  @Test func setA743AnUnsupportedFontScalarCannotCorruptAdjacentSupportedGlyphs() {
    // Hypothesis: skipping a missing embedded-font glyph advances kerning state or replaces the entire banner with fallback text.
    // The standard font contains Latin glyphs; the font renderer's missing-
    // glyph path skips unsupported scalars, including this supplementary emoji.
    let snapshot = render(TextFigure("H🦊i"))
    #expect(snapshot.measuredTree.measuredSize == .init(width: 9, height: 6))
    #expect(snapshot.rasterSurface.lines == standardHi)
  }

  @Test func setA744ZeroWidthFontMeasurementStillUsesAWholeRenderableGlyph() {
    // Hypothesis: a zero-width proposal reaches FIGlet without its minimum-width floor and silently falls back to ordinary text metrics.
    let payload = TextFigurePayload(content: "Hi", font: .standard)
    let metrics = TextFigureSupport.layoutMetrics(for: payload)
    #expect(metrics.minimumWidth == 8)
    let narrow = TextFigureSupport.measuredSize(
      for: payload, proposal: .init(width: 0, height: .unspecified))
    #expect(narrow == .init(width: 7, height: 12))
    #expect(narrow.width < metrics.idealSize.width)
  }

  @Test func setA745UnspecifiedFontWidthDoesNotInheritTheFIGletDefaultEightyColumns() {
    // Hypothesis: the font adapter's default width of eighty leaks into ideal measurement and inserts unrequested banner rows.
    let value = String(repeating: "W", count: 32)
    let snapshot = render(TextFigure(value))
    #expect(snapshot.measuredTree.measuredSize.width > 80)
    #expect(snapshot.measuredTree.measuredSize.height == 6)
    #expect(snapshot.rasterSurface.lines.count == 6)
    #expect(snapshot.rasterSurface.lines.map(\.count).max() ?? 0 > 80)
  }

  @Test func setA746RepeatedFontMetricsHitsDoNotGrowRecencyStorageWithoutBound() throws {
    // Hypothesis: every cache hit appends recency history, but pruning only runs when a new distinct payload exceeds capacity.
    let payload = TextFigurePayload(content: "Set A stable metrics", font: .standard)
    let expected = TextFigureSupport.layoutMetrics(for: payload)
    for _ in 0..<4096 { _ = TextFigureSupport.layoutMetrics(for: payload) }
    let before = try metricsOccupancy()
    for _ in 0..<4096 { _ = TextFigureSupport.layoutMetrics(for: payload) }
    let after = try metricsOccupancy()
    #expect(TextFigureSupport.layoutMetrics(for: payload) == expected)
    #expect(after.count == before.count)
    #expect(after.count <= 256)
    let beforeOrder = try #require(before.detail?["order"])
    let afterOrder = try #require(after.detail?["order"])
    // A settled 256-entry cache may retain some stale records, but another
    // identical 4096-hit epoch must not add a proportional history forever.
    withKnownIssue("STUI-1008: fixed metric-cache occupancy retains unbounded hit history") {
      #expect(
        afterOrder - beforeOrder <= 1024,
        "Fixed cache occupancy \(after.count); recency records grew \(beforeOrder) → \(afterOrder)")
    }
  }

  @Test func setA747AuthoredFontColorsOverrideAnAmbientTextForeground() throws {
    // Hypothesis: an environment foreground replaces per-cell authored TheDraw colors during preformatted style merging.
    let baseline = render(TextFigure("x", font: .font208)).rasterSurface
    let ambient = render(TextFigure("x", font: .font208).foregroundStyle(Color.green)).rasterSurface
    #expect(ambient.lines == baseline.lines)
    let colored = coloredCells(in: baseline)
    #expect(!colored.isEmpty)
    for point in colored {
      let expected = try #require(baseline.cells[point.y][point.x].style?.foregroundColor)
      #expect(ambient.cells[point.y][point.x].style?.foregroundColor == expected)
    }
  }

  @Test func setA748FillUnstyledFontModePreservesAuthoredCellsAndFillsPlainGlyphs() {
    // Hypothesis: fillUnstyled is treated as a global override or fails to supply paint to a plain embedded font.
    let plain = render(TextFigure("Hi", colorMode: .fillUnstyled(Color.cyan))).rasterSurface
    #expect(plain.lines == standardHi)
    let ink = plain.cells.flatMap { $0 }.filter { $0.character != " " && !$0.isContinuation }
    #expect(!ink.isEmpty)
    #expect(ink.allSatisfy { $0.style?.foregroundColor == .cyan })
    let original = render(TextFigure("x", font: .font208)).rasterSurface
    let filled = render(TextFigure("x", font: .font208, colorMode: .fillUnstyled(Color.cyan)))
      .rasterSurface
    #expect(!coloredCells(in: original).isEmpty)
    for point in coloredCells(in: original) {
      #expect(
        filled.cells[point.y][point.x].style?.foregroundColor
          == original.cells[point.y][point.x].style?.foregroundColor)
    }
  }

  @Test func setA749EqualVisibleTextDoesNotCollapseDistinctRichValuesInAHashSet() {
    // Hypothesis: Text's structural-content hash is incorrectly reused as equality, collapsing different inline destinations or explicit clears.
    let first = Text("Read \(Link("DOC", destination: "first"))")
    let second = Text("Read \(Link("DOC", destination: "second"))")
    let cleared = first.underline(false)
    #expect(first.content == second.content && first.content == cleared.content)
    #expect(first != second && first != cleared)
    let values: Set<Text> = [first, second, cleared, first]
    #expect(values.count == 3)
    #expect(values.contains(Text("Read \(Link("DOC", destination: "first"))")))
  }

  @Test func setA750ClippingPreformattedBlankRowsPreservesLaterRowCoordinates() {
    // Hypothesis: empty preformatted rows are discarded before applying the clip's vertical origin, shifting later font rows upward.
    let bounds = CellRect(origin: .zero, size: .init(width: 5, height: 5))
    let lines: [PreformattedTextLine] = [
      .init(runs: [.init(content: "TOP")]),
      .init(runs: []),
      .init(runs: [.init(content: "MID", style: .init(emphasis: .bold))]),
      .init(runs: []),
      .init(runs: [.init(content: "BOT")]),
    ]
    let surface = Rasterizer().rasterize(
      DrawNode(
        identity: testIdentity("SetAText750"), bounds: bounds,
        clipBounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 5, height: 4)),
        commands: [.styledPreformattedText(bounds: bounds, lines: lines, style: .init())]),
      minimumSize: bounds.size)
    #expect(surface.lines == ["", "", "MID", "", "BOT"])
    #expect(surface.cells[2][0].style?.emphasis.contains(.bold) == true)
    #expect(surface.cells[4][0].style?.emphasis.contains(.bold) != true)
  }

  private var standardHi: [String] {
    [" _   _ _", "| | | (_)", "| |_| | |", "|  _  | |", "|_| |_|_|", ""]
  }

  private func render<V: View>(
    _ view: V, proposal: ProposedSize = .unspecified, paragraphSpacing: Int = 0
  ) -> RenderSnapshot {
    var environment = EnvironmentValues()
    environment.hostParagraphSpacing = paragraphSpacing
    return DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("SetATextStatic"), environmentValues: environment),
      proposal: proposal)
  }

  private func make<V: View>(_ id: Int, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAText\(id)"), size: .init(width: 40, height: 24),
      content: content)
  }

  private func runtimeTree<V: View>(_ h: StressRuntimeHarness<V>) throws -> ResolvedNode {
    try #require(
      h.runLoop.renderer.debugRuntimeSubsystemSnapshot().animationController.previousTreeRoot)
  }

  private func richPayloads(in node: ResolvedNode) -> [RichTextPayload] {
    let own: [RichTextPayload]
    if case .richText(let payload) = node.drawPayload { own = [payload] } else { own = [] }
    return own + node.children.flatMap { richPayloads(in: $0) }
  }

  private func metricsOccupancy() throws -> MemoryMetricSnapshot {
    try #require(
      MemoryMetricRegistry.shared.snapshotAll().first {
        $0.name == "TextFigureSupport.metricsCache"
      })
  }

  private func coloredCells(in surface: RasterSurface) -> [CellPoint] {
    surface.cells.enumerated().flatMap { y, row in
      row.enumerated().compactMap { x, cell in
        cell.style?.foregroundColor == nil ? nil : CellPoint(x: x, y: y)
      }
    }
  }
}

@MainActor
private final class SetATextDestinationLog {
  var values: [LinkDestination] = []
}
