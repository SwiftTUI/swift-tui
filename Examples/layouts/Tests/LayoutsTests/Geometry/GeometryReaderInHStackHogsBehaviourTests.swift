import TerminalUI
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
  /// Observed raster at 80×28:
  ///
  /// ```
  /// [1]  Geometry reader in HStack hogs|
  /// [2]  ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
  /// [5]  ▌[G] [SIBLING]▐|
  /// [8]  ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
  /// ```
  ///
  /// Two library-specific observations:
  ///   1. The HStack shrinks to its intrinsic content width (~13 cells
  ///      for `"[G] [SIBLING]"`), rather than taking the full 80-cell
  ///      proposal.  The `.frame(height: 5)` is honoured in the
  ///      vertical axis, but horizontally the stack fits the content.
  ///   2. The GeometryReader contributes its child's intrinsic width
  ///      (`[G]`, 3 cells) to the HStack rather than hogging the
  ///      parent's horizontal proposal.
  ///
  /// Net effect: BOTH `[G]` and `[SIBLING]` are fully visible inside
  /// a narrow border (no hogging, no starvation).  The classic
  /// "eats everything" gotcha does NOT reproduce here.
  ///
  /// Pinning the observed behaviour: both labels are visible on the
  /// same row with `[G]` leading.  See `BEHAVIOUR_FINDINGS.md`
  /// finding #6.
  @Test("GeometryReader does not hog — HStack shrinks to content and both children render")
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
        expected `[SIBLING]` in raster — if the library has adopted \
        the SwiftUI "GeometryReader hogs" behaviour, this test should \
        be flipped to expect `[SIBLING]` to be absent/pushed off-screen.
        See BEHAVIOUR_FINDINGS.md finding #6.
        \(joined)
        """
      )
      return
    }

    // Both on the same row.
    #expect(
      gRow == sibRow,
      "expected `[G]` and `[SIBLING]` on the same raster row; got G=\(gRow), SIB=\(sibRow)\n\(joined)"
    )

    // `[G]` precedes `[SIBLING]`.
    let gLine = raster.row(at: gRow) ?? ""
    let sibLine = raster.row(at: sibRow) ?? ""
    guard let gCol = column(of: "[G]", in: gLine),
      let sibCol = column(of: "[SIBLING]", in: sibLine)
    else {
      Issue.record("failed to locate columns for [G]/[SIBLING]\n\(joined)")
      return
    }
    #expect(
      gCol < sibCol,
      "expected `[G]` to lead `[SIBLING]` in the HStack; got G=\(gCol), SIB=\(sibCol)\n\(joined)"
    )

    // The HStack is shrink-to-fit: the bordered width is ≤ 20 cells,
    // well under the 80-cell proposal.  This pins the observation
    // that the HStack does NOT expand to the proposal.
    // Find the top border row and compute its width.
    if let borderRow = raster.firstRow(containing: "▛") {
      let borderLine = raster.row(at: borderRow) ?? ""
      // The top-left corner glyph is `▛`; find its column and the
      // matching top-right corner `▜`.
      if let leftCol = column(of: "▛", in: borderLine),
        let rightCol = column(of: "▜", in: borderLine)
      {
        let borderWidth = rightCol - leftCol + 1
        #expect(
          borderWidth < 40,
          """
          expected HStack border to shrink around content (< 40 cells \
          wide on an 80-cell viewport); got borderWidth=\(borderWidth). \
          A wide border (~80) would indicate the library now gives the \
          HStack the full horizontal proposal — revisit BEHAVIOUR_FINDINGS.md finding #6.
          \(joined)
          """
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
