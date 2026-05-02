import SwiftTUI
import Testing

@testable import Layouts

/// A/B variant of `ViewThatFitsAxisChoice` whose `ViewThatFits`
/// containers are flattened into single `Text` nodes — proves the
/// selection signature comes from `ViewThatFits` and not from some
/// other layout quirk.
@MainActor
private struct ViewThatFitsAxisChoiceFlattenedVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("View that fits axis choice")
      Group {
        Text("at width 60:").foregroundStyle(.muted)
        Text("[FLAT-60]")
          .frame(width: 60)
          .border(.separator)

        Text("at width 12:").foregroundStyle(.muted)
        Text("[FLAT-12]")
          .frame(width: 12)
          .border(.separator)

        Text("at width 4:").foregroundStyle(.muted)
        Text("F4")
          .frame(width: 4)
          .border(.separator)
      }
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct ViewThatFitsAxisChoiceBehaviourTests {
  /// Pins the per-frame-width pick from `ViewThatFits`.
  ///
  /// Three identical candidate sets `(LONG, MEDIUM, S)` are wrapped in
  /// outer `.frame(width:)`s of 60, 12, and 4. The expected picks are
  /// the WIDEST candidate that still fits in the proposal:
  ///
  ///   - width 60 → `[LONG: a long candidate]` (24 cells, fits in 60)
  ///   - width 12 → `[MEDIUM]` (8 cells, fits in 12; LONG does not)
  ///   - width 4  → `[S]` (3 cells, fits in 4; MEDIUM does not)
  ///
  /// Because the three containers are stacked top-to-bottom in the
  /// outer `VStack`, the chosen rows must appear in declaration order.
  @Test("Each ViewThatFits picks the widest candidate that fits its frame")
  func eachContainerPicksWidestThatFits() {
    let raster = render(ViewThatFitsAxisChoice(), width: 80, height: 30).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    guard let longRow = raster.firstRow(containing: "[LONG"),
      let mediumRow = raster.firstRow(containing: "[MEDIUM]"),
      let shortRow = raster.firstRow(containing: "[S]")
    else {
      Issue.record(
        """
        expected `[LONG`, `[MEDIUM]`, `[S]` to all appear on their own \
        rows in the raster.
        \(joined)
        """
      )
      return
    }

    // Picks appear in declaration (top-to-bottom) order: the 60-wide
    // container is first in the VStack, then 12, then 4.
    #expect(
      longRow < mediumRow && mediumRow < shortRow,
      """
      expected pick rows in declaration order: long (\(longRow)) < \
      medium (\(mediumRow)) < short (\(shortRow)).
      \(joined)
      """
    )

    // Each pick must NOT bleed into the wrong container's region.
    // Specifically, the 12-wide container must not paint `[LONG`, and
    // the 4-wide container must not paint `[MEDIUM]`. Because we picked
    // each row uniquely above (firstRow), assert there is exactly ONE
    // row containing each marker.
    #expect(
      raster.rows(containing: "[LONG").count == 1,
      """
      expected exactly one row containing `[LONG` (the 60-wide pick); \
      got \(raster.rows(containing: "[LONG").count).
      \(joined)
      """
    )
    #expect(
      raster.rows(containing: "[MEDIUM]").count == 1,
      """
      expected exactly one row containing `[MEDIUM]` (the 12-wide pick); \
      got \(raster.rows(containing: "[MEDIUM]").count).
      \(joined)
      """
    )
    // `[S]` is short and could occur as a substring inside other
    // markers (e.g. `[SOMETHING]`). None of our other candidates
    // contain `[S]`, so a single occurrence is the tight assertion.
    #expect(
      raster.rows(containing: "[S]").count == 1,
      """
      expected exactly one row containing `[S]` (the 4-wide pick); \
      got \(raster.rows(containing: "[S]").count).
      \(joined)
      """
    )
  }

  /// A/B vacuity: replacing each `ViewThatFits` with a flat `Text`
  /// node visibly changes the raster — none of the bracket markers
  /// from the original (`[LONG`, `[MEDIUM]`, `[S]`) survive.  Without
  /// this A/B, a regression that always picked the first child (or
  /// rendered all children) could still pass the primary assertion
  /// for the wrong reason.
  @Test("flattening ViewThatFits removes the per-pick markers")
  func viewThatFitsIsNonVacuous() {
    let withVTF = render(
      ViewThatFitsAxisChoice(),
      width: 80,
      height: 30,
      id: "with-vtf"
    ).rasterSurface
    let withoutVTF = render(
      ViewThatFitsAxisChoiceFlattenedVariant(),
      width: 80,
      height: 30,
      id: "without-vtf"
    ).rasterSurface

    let withDump = withVTF.lines.joined(separator: "\n")
    let withoutDump = withoutVTF.lines.joined(separator: "\n")

    #expect(
      withDump.contains("[LONG") && withDump.contains("[MEDIUM]"),
      "WITH-ViewThatFits should contain bracket markers\n\(withDump)"
    )
    #expect(
      !withoutDump.contains("[LONG") && !withoutDump.contains("[MEDIUM]"),
      """
      WITHOUT-ViewThatFits should not contain the candidate markers \
      (only the flat substitutes).
      \(withoutDump)
      """
    )
    #expect(
      withoutDump.contains("[FLAT-60]") && withoutDump.contains("[FLAT-12]")
        && withoutDump.contains("F4"),
      "WITHOUT-ViewThatFits should contain the flat substitutes\n\(withoutDump)"
    )
  }
}
