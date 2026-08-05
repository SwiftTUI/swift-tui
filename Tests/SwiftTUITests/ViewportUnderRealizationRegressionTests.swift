import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Regression pins for org report 2026-08-03-003 (viewport under-realization
// in the example apps). Three framework defects rendered first-paint frames
// with silently missing content:
//
// 1. `derivedMaximumMainSize` derived a ZERO own-axis maximum for an
//    indexed-source lazy stack (its product stores no child measurements, so
//    the composite walk zipped children against an empty array). Under an
//    enclosing stack's allocation the row's offer was capped at its rigid
//    sibling's extent — mrkdwn list items rendered exactly one display line.
// 2. Windowed lazy-stack placement chose its visible index range from the
//    ESTIMATED geometry and never extended it after the refined (real)
//    extents packed the run shorter — blocks entering the viewport's bottom
//    edge never realized, and re-entry did not heal.
// 3. Stack deficit allocation counted along-axis Spacers as equal-share
//    claimants, so a long Text split the pane ~50/50 with a trailing Spacer
//    instead of the Spacer collapsing — sextant's preview clamped mid-file.
@MainActor
@Suite(.serialized)
struct ViewportUnderRealizationRegressionTests {
  private func renderedLines<V: View>(
    _ view: V,
    width: Int,
    height: Int,
    name: String,
    renderer: DefaultRenderer = DefaultRenderer()
  ) -> [String] {
    let fixedRoot = view.frame(width: width, height: height, alignment: .topLeading)
    let artifacts = renderer.renderArtifacts(
      fixedRoot,
      context: .init(identity: testIdentity(name), applyEnvironmentValues: false),
      proposal: .init(width: .finite(width), height: .finite(height))
    )
    let output = TerminalSurfaceRenderer(
      capabilityProfile: .previewASCII
    ).render(artifacts.rasterSurface)
    return
      output
      .split(whereSeparator: \.isNewline)
      .map(String.init)
  }

  @Test("nested list rows keep their wrapped lines under a windowed document")
  func nestedListRowsKeepWrappedLines() {
    // The mrkdwn list composition: windowed document stack -> list stack ->
    // marker HStack -> item-content stack whose ForEach element resolves
    // through a conditional branch. Each item's text wraps to 3 display
    // lines; the defect clamped every item to its first line.
    let wrapped =
      "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi "
      + "omicron pi rho sigma tau upsilon phi chi psi omega one two three four five"
    let lines = renderedLines(
      ScrollView(position: .constant(ScrollCellOffset(x: 0, y: 0))) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<40, id: \.self) { index in
            if index == 2 {
              LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<3, id: \.self) { item in
                  HStack(alignment: .top, spacing: 1) {
                    Text("-")
                    LazyVStack(alignment: .leading, spacing: 0) {
                      ForEach(0..<1, id: \.self) { block in
                        if block == 0 {
                          Text("item \(item) \(wrapped)")
                        } else {
                          Text("unreachable")
                        }
                      }
                    }
                  }
                }
              }
            } else {
              Text("block \(index)")
            }
          }
        }
      },
      width: 60,
      height: 30,
      name: "NestedListWrap"
    )
    // Every item renders its continuation lines, not just its first row.
    let continuations = lines.filter { $0.contains("kappa") }.count
    #expect(continuations == 3, "items rendered \(continuations)/3 wrap continuations")
    let tails = lines.filter { $0.contains("five") }.count
    #expect(tails == 3, "items rendered \(tails)/3 final wrap lines")
  }

  @Test("placement extends the estimated visible run until the viewport is full")
  func bottomEdgeBlocksRealizeAtEveryOffset() {
    // Heterogeneous document (tall code blocks early, short paragraphs
    // later): the running-mean stride over-estimates the short rows, so the
    // estimated-visible index range under-covers the viewport once refined.
    // The scroll sequence mirrors the report's repro: first paint, down,
    // overshoot, return — with a settle frame after each move.
    func blockText(_ index: Int) -> String {
      if index < 4 || index.isMultiple(of: 7) {
        return (0..<12).map { "code \(index) line \($0)" }.joined(separator: "\n")
      }
      return "para \(index)"
    }
    let renderer = DefaultRenderer()
    for offset in [0, 0, 31, 31, 66, 66, 42, 42] {
      let lines = renderedLines(
        ScrollView(position: .constant(ScrollCellOffset(x: 0, y: offset))) {
          LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(0..<80, id: \.self) { index in
              Text(blockText(index))
            }
          }
        },
        width: 40,
        height: 24,
        name: "BottomEdgeFill",
        renderer: renderer
      )
      // The viewport must be full apart from the 1-row spacing between
      // blocks: a run of 2+ blank rows means a block failed to realize.
      var blankRun = 0
      var longestBlankRun = 0
      for line in lines {
        if line.allSatisfy({ $0 == " " }) {
          blankRun += 1
          longestBlankRun = max(longestBlankRun, blankRun)
        } else {
          blankRun = 0
        }
      }
      #expect(
        longestBlankRun <= 1,
        "offset \(offset): \(longestBlankRun) consecutive blank rows — unrealized content"
      )
    }
  }

  @Test("a trailing Spacer collapses before a truncating sibling loses content")
  func deficitSpacerCollapsesBeforeContent() {
    // The sextant preview shape: fixed pane, one long multiline Text, a
    // trailing Spacer. The Text must keep every row the pane can show; the
    // Spacer must not hold blank cells in deficit.
    let content = (1...60).map { "content line \($0)" }.joined(separator: "\n")
    let lines = renderedLines(
      VStack(alignment: .leading, spacing: 0) {
        Text("title")
        Divider()
        Text(content)
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
      width: 40,
      height: 37,
      name: "DeficitSpacer"
    )
    let contentLines = lines.filter { $0.contains("content line") }.count
    #expect(contentLines == 35, "rendered \(contentLines) content lines, expected 35")
  }

  @Test("a deficit Spacer keeps exactly its minimum length")
  func deficitSpacerKeepsMinimumLength() {
    let content = (1...60).map { "content line \($0)" }.joined(separator: "\n")
    let lines = renderedLines(
      VStack(alignment: .leading, spacing: 0) {
        Text(content)
        Spacer(minLength: 5)
        Text("footer")
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
      width: 40,
      height: 30,
      name: "DeficitSpacerMinimum"
    )
    let contentLines = lines.filter { $0.contains("content line") }.count
    #expect(contentLines == 24, "rendered \(contentLines) content lines, expected 24")
    #expect(lines.contains { $0.contains("footer") }, "footer must stay visible")
  }
}
