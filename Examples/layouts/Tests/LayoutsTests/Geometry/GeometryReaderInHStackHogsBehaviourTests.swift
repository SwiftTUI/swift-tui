import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct GeometryReaderInHStackHogsBehaviourTests {
  /// The classic SwiftUI gotcha is that an unconstrained
  /// `GeometryReader` inside an `HStack` claims as much horizontal
  /// space as the parent will give it, starving its `Text` sibling.
  /// A SwiftUI-faithful outcome at 80×28 with an HStack having no
  /// width constraint (only `.frame(height: 5)`) would be: the
  /// GeometryReader fills the terminal width and `[SIBLING]` gets
  /// pushed off-screen (or truncated at the far right).
  ///
  /// Observed raster at 80×28 after GeometryReader adopts flexible
  /// proposal-filling behaviour:
  ///
  /// ```
  /// [1]  Geometry reader in HStack hogs|
  /// [2]  ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
  /// [3]  ▌[G]                                                                         ▐|
  /// [5]  ▌                                                                   [SIBLING]▐|
  /// [8]  ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
  /// ```
  ///
  /// The HStack now expands to the available horizontal proposal and
  /// the GeometryReader receives the slack before the sibling.
  ///
  /// See `docs/proposals/layout/BEHAVIOUR_FINDINGS.md` finding #6 —
  /// before the fix the GeometryReader shrank to content (related to
  /// finding #4). It now lowers content through a flexible
  /// `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment:
  /// .topLeading)` so the stack hands it the flexible-content slack.
  @Test("GeometryReader hogs available HStack width")
  func bothChildrenVisibleHStackShrinksToContent() {
    let raster = render(GeometryReaderInHStackHogs(), width: 80, height: 28).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    guard let gRow = raster.firstRow(containing: "[G]") else {
      Issue.record("expected `[G]` in raster\n\(joined)")
      return
    }
    guard let sibRow = raster.firstRow(containing: "[SIBLING]") else {
      Issue.record(
        """
        expected `[SIBLING]` in raster at the trailing edge after \
        the GeometryReader takes the available slack.
        \(joined)
        """
      )
      return
    }

    // `[G]` starts near the leading edge and `[SIBLING]` is pushed
    // toward the trailing edge by the reader's flexible allocation.
    let gLine = raster.row(at: gRow) ?? ""
    let sibLine = raster.row(at: sibRow) ?? ""
    guard let gCol = column(of: "[G]", in: gLine),
      let sibCol = column(of: "[SIBLING]", in: sibLine)
    else {
      Issue.record("failed to locate columns for [G]/[SIBLING]\n\(joined)")
      return
    }
    #expect(
      gCol < 5,
      "expected `[G]` near the leading edge; got col=\(gCol)\n\(joined)"
    )
    #expect(
      sibCol > 60,
      "expected `[SIBLING]` near the trailing edge; got col=\(sibCol)\n\(joined)"
    )

    // The HStack now takes the available horizontal proposal.
    if let borderRow = raster.firstRow(containing: "▛") {
      let borderLine = raster.row(at: borderRow) ?? ""
      if let leftCol = column(of: "▛", in: borderLine),
        let rightCol = column(of: "▜", in: borderLine)
      {
        let borderWidth = rightCol - leftCol + 1
        #expect(
          borderWidth >= 70,
          "expected HStack border to expand toward the 80-cell proposal; got \(borderWidth)\n\(joined)"
        )
      }
    }
  }

  /// Vacuity check: swapping the GeometryReader for a plain sibling
  /// visibly changes the raster (both HStack width and child composition).
  /// Without this, a regression that made the GeometryReader render
  /// as nothing would be indistinguishable from the real behaviour.
  @Test("removing the GeometryReader visibly changes the raster")
  func geometryReaderIsNonVacuous() {
    let withReader = render(
      GeometryReaderInHStackHogs(),
      width: 80,
      height: 28,
      id: "with-reader"
    ).rasterSurface
    let withoutReader = render(
      WithoutGeometryReaderHogVariant(),
      width: 80,
      height: 28,
      id: "without-reader"
    ).rasterSurface

    let withDump = withReader.lines.joined(separator: "\n")
    let withoutDump = withoutReader.lines.joined(separator: "\n")

    #expect(
      withDump.contains("[G]"),
      "WITH variant should contain `[G]` from the GeometryReader child\n\(withDump)"
    )
    #expect(
      !withoutDump.contains("[G]"),
      "WITHOUT variant should not contain `[G]`\n\(withoutDump)"
    )
    #expect(
      withoutDump.contains("[PLAIN]"),
      "WITHOUT variant should contain the plain replacement `[PLAIN]`\n\(withoutDump)"
    )
  }
}

/// Identical to `GeometryReaderInHStackHogs` except the
/// `GeometryReader` is replaced by a plain `Text("[PLAIN]")`.
private struct WithoutGeometryReaderHogVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Geometry reader in HStack hogs").foregroundStyle(.muted)
      HStack(spacing: 1) {
        Text("[PLAIN]")
        Text("[SIBLING]")
      }
      .frame(height: 5)
      .border(.separator)
    }
    .padding(1)
  }
}
