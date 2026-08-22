import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Regression coverage for GitHub issue SwiftTUI/swift-tui#5: a segmented row
// of `.bordered` Buttons whose labels swap text + bold on selection change was
// reported to trip the F13 incremental-vs-fresh raster oracle (DEBUG trap:
// "incremental raster mismatch: rows [...] diverged from fresh raster").
//
// The reported journey — arrow the focused row through its segments — must
// reach the incremental rasterizer (otherwise the oracle has nothing to check)
// and must leave the oracle's counter untouched. See
// `SegmentedRowJourneyHarness.swift` for why the counter, not the trap, is the
// observable here.

private struct IssueReproRoot: View {
  @State private var selection: SegmentedRowOption = .red
  var body: some View {
    SegmentedRowPicker(selection: $selection)
      .padding(1)
  }
}

@MainActor
@Suite("Segmented bordered-button row incremental raster", .serialized)
struct SegmentedButtonRowIncrementalRasterTests {
  @Test("arrowing through a segmented bordered-button row keeps incremental raster sound")
  func arrowingThroughSegmentsKeepsIncrementalRasterSound() async throws {
    let terminalSize = CellSize(width: 40, height: 8)
    let result = try await runSegmentedRowJourney(
      rootIdentity: testIdentity("SegmentedButtonRowIncrementalRaster"),
      terminalSize: terminalSize,
      steps: [
        .keys([.arrowRight, .arrowRight, .arrowLeft])
      ]
    ) {
      IssueReproRoot()
    }

    let first = try #require(result.frames.first?.lines)
    let last = try #require(result.frames.last?.lines)
    #expect(
      first != last,
      "the journey should have moved the selection:\n\(result.renderedFrames)"
    )
    #expect(
      last.contains(where: { $0.contains("│ ● ││[●]││ ● │") }),
      "→ → ← should select the middle segment:\n\(result.renderedFrames)"
    )
    #expect(
      result.reachedIncrementalRaster,
      "the selection changes never reached the incremental rasterizer: \(result.summary)"
    )
    #expect(
      result.mismatchGrowth == 0,
      "incremental raster mismatch during the segmented-row journey: \(result.summary)\n\(result.renderedFrames)"
    )
  }
}
