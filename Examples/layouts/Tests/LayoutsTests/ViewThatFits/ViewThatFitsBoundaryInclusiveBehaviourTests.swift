import SwiftTUI
import Testing

@testable import Layouts

/// A/B variant: same outer shape but with the `ViewThatFits`
/// containers replaced by flat `Text` nodes with distinguishable
/// markers. Proves the `HELLO`/`HI` selection comes from
/// `ViewThatFits` and not from incidental layout.
@MainActor
private struct ViewThatFitsBoundaryInclusiveFlattenedVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("View that fits boundary inclusive")
      HStack(alignment: .top, spacing: 4) {
        VStack(alignment: .leading, spacing: 0) {
          Text("at width 5:").foregroundStyle(.muted)
          Text("F5")
            .frame(width: 5)
            .border(.separator)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("at width 4:").foregroundStyle(.muted)
          Text("F4")
            .frame(width: 4)
            .border(.separator)
        }
      }
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct ViewThatFitsBoundaryInclusiveBehaviourTests {
  /// Boundary semantics for `ViewThatFits` selection.
  ///
  /// At `.frame(width: 5)` the first candidate `Text("HELLO")` is
  /// exactly 5 cells wide.  The library's `LayoutEngine.fits` uses
  /// `value <= limit`, so this is INCLUSIVE: `HELLO` fits and is
  /// chosen.
  ///
  /// At `.frame(width: 4)` the same `HELLO` candidate is one cell too
  /// wide, fails the fits check, and the fallback `Text("HI")` (2
  /// cells) is chosen instead.
  ///
  /// Observed raster (excerpt) at 80×30:
  ///
  /// ```
  /// View that fits boundary inclusive
  /// at width 5:    at width 4:
  /// ▛▀▀▀▀▀▀▜      ▛▀▀▀▀▀▀▜
  /// ▌HELLO ▐      ▌  HI ▐
  /// ▙▄▄▄▄▄▄▟      ▙▄▄▄▄▄▄▟
  /// ```
  ///
  /// (the borders include 1-cell padding rings around the inner frame
  /// so the visible cell counts are slightly larger than the raw
  /// `.frame(width:)` numbers; the asserted invariant is that `HELLO`
  /// appears in the boundary case and `HI` appears in the just-under
  /// case.)
  @Test("at width == intrinsic, ViewThatFits picks HELLO (inclusive); at width-1 it picks HI")
  func boundaryIsInclusive() {
    let raster = render(ViewThatFitsBoundaryInclusive(), width: 80, height: 30).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    // INCLUSIVE pin: at width 5 (== HELLO's intrinsic width), HELLO
    // appears in the raster. If a future change makes `fits` use `<`
    // instead of `<=`, this expectation will flip and `HELLO` will be
    // absent — at which point this layout becomes the canonical
    // exclusive-boundary regression marker.
    #expect(
      joined.contains("HELLO"),
      """
      expected `HELLO` somewhere in the raster — the width-5 container's \
      first candidate is `HELLO` (5 cells) and the library's `fits` is \
      INCLUSIVE (value <= limit). If this fails, ViewThatFits has \
      switched to exclusive boundary semantics; flip this test and file \
      a finding.
      \(joined)
      """
    )

    // The width-4 container picks the `HI` fallback because `HELLO`
    // does not fit. `HI` must appear at least once.
    #expect(
      joined.contains("HI"),
      """
      expected `HI` in the raster — the width-4 container falls back \
      to the 2-cell `HI` candidate when `HELLO` (5 cells) does not fit \
      in 4. If this fails, the fallback path is broken.
      \(joined)
      """
    )

    // Exactly ONE row contains `HELLO` (the boundary container picks
    // it; the just-under container does not). Without this, a
    // regression that ignores the proposal and always picks the first
    // child would still pass the simple "contains HELLO" check above.
    #expect(
      raster.rows(containing: "HELLO").count == 1,
      """
      expected exactly one row containing `HELLO` (the width-5 pick). \
      If the width-4 container also painted `HELLO`, ViewThatFits is \
      not respecting the smaller proposal.
      Got count=\(raster.rows(containing: "HELLO").count).
      \(joined)
      """
    )
  }

  /// A/B vacuity: replacing each `ViewThatFits` with a flat `Text`
  /// node visibly changes the raster — neither `HELLO` nor `HI`
  /// remains. Without this A/B, a regression that always rendered
  /// every child or always picked one literal could still pass.
  @Test("flattening ViewThatFits removes the per-pick markers")
  func viewThatFitsIsNonVacuous() {
    let withVTF = render(
      ViewThatFitsBoundaryInclusive(),
      width: 80,
      height: 30,
      id: "with-vtf"
    ).rasterSurface
    let withoutVTF = render(
      ViewThatFitsBoundaryInclusiveFlattenedVariant(),
      width: 80,
      height: 30,
      id: "without-vtf"
    ).rasterSurface

    let withDump = withVTF.lines.joined(separator: "\n")
    let withoutDump = withoutVTF.lines.joined(separator: "\n")

    #expect(
      withDump.contains("HELLO") && withDump.contains("HI"),
      "WITH-ViewThatFits should contain HELLO and HI\n\(withDump)"
    )
    #expect(
      !withoutDump.contains("HELLO") && !withoutDump.contains("HI"),
      """
      WITHOUT-ViewThatFits should not contain HELLO or HI (only the \
      flat substitutes F5/F4).
      \(withoutDump)
      """
    )
    #expect(
      withoutDump.contains("F5") && withoutDump.contains("F4"),
      "WITHOUT-ViewThatFits should contain the flat substitutes\n\(withoutDump)"
    )
  }
}
