import TerminalUI
import Testing

@testable import Layouts

/// A/B variant: same outer shape (3 bordered frames at heights 5/2/1)
/// but each `ViewThatFits(in: .vertical)` is replaced by a flat `Text`
/// node. This proves the per-pick markers come from `ViewThatFits`
/// selection logic and not from incidental layout.
@MainActor
private struct ViewThatFitsVerticalOnlyFlattenedVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("View that fits vertical only")

      Text("at height 5:").foregroundStyle(.muted)
      Text("[FLAT-H5]")
        .frame(width: 12, height: 5)
        .border(.separator)

      Text("at height 2:").foregroundStyle(.muted)
      Text("[FLAT-H2]")
        .frame(width: 12, height: 2)
        .border(.separator)

      Text("at height 1:").foregroundStyle(.muted)
      Text("[FLAT-H1]")
        .frame(width: 12, height: 1)
        .border(.separator)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct ViewThatFitsVerticalOnlyBehaviourTests {
  /// Pins the per-frame-height pick from
  /// `ViewThatFits(in: .vertical)`.
  ///
  /// Three identical candidate sets (TALL3, MED2, SHORT1) are wrapped
  /// in outer `.frame(width: 12, height: H)` proposals at H = 5, 2,
  /// and 1. Vertical-axis-only fitting selects:
  ///
  ///   - height 5 → TALL3 (3 lines, fits in 5)
  ///   - height 2 → MED2  (2 lines, fits in 2; TALL3 does not)
  ///   - height 1 → SHORT1 (1 line, fits in 1; MED2 does not)
  ///
  /// Because the three containers are stacked top-to-bottom in the
  /// outer `VStack`, the chosen marker rows must appear in declaration
  /// order in the raster.
  @Test("ViewThatFits(in: .vertical) picks the tallest candidate that fits each frame")
  func eachContainerPicksTallestThatFits() {
    let raster = render(ViewThatFitsVerticalOnly(), width: 80, height: 30).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    guard let tallRow = raster.firstRow(containing: "[TALL3]"),
      let medRow = raster.firstRow(containing: "[MED2]"),
      let shortRow = raster.firstRow(containing: "[SHORT1]")
    else {
      Issue.record(
        """
        expected `[TALL3]`, `[MED2]`, `[SHORT1]` to all appear in the \
        raster (tallest-fits / medium / shortest pick respectively).
        \(joined)
        """
      )
      return
    }

    // Picks appear in declaration (top-to-bottom) order: the H=5
    // container is first in the VStack, then H=2, then H=1.
    #expect(
      tallRow < medRow && medRow < shortRow,
      """
      expected pick rows in declaration order: tall (\(tallRow)) < \
      med (\(medRow)) < short (\(shortRow)).
      \(joined)
      """
    )

    // The H=5 container picks the 3-line `[TALL3]` candidate, which
    // paints `[TALL3]` on three consecutive rows. Pin "≥ 2" rows so a
    // future change to the inner spacing (still TALL3) doesn't false-
    // red the test, but absolutely DO assert > 1 — that proves the
    // picked candidate is the multi-row one and not a fallback.
    #expect(
      raster.rows(containing: "[TALL3]").count >= 2,
      """
      expected `[TALL3]` to paint on ≥ 2 rows (the 3-line candidate); \
      got \(raster.rows(containing: "[TALL3]").count).
      \(joined)
      """
    )

    // The H=2 container picks the 2-line `[MED2]` candidate, which
    // paints `[MED2]` on two consecutive rows.
    #expect(
      raster.rows(containing: "[MED2]").count == 2,
      """
      expected `[MED2]` to paint on exactly 2 rows (the 2-line pick); \
      got \(raster.rows(containing: "[MED2]").count).
      \(joined)
      """
    )

    // The H=1 container picks the single-line `[SHORT1]` candidate.
    #expect(
      raster.rows(containing: "[SHORT1]").count == 1,
      """
      expected `[SHORT1]` to paint on exactly 1 row (the 1-line pick); \
      got \(raster.rows(containing: "[SHORT1]").count).
      \(joined)
      """
    )
  }

  /// A/B vacuity: replacing each `ViewThatFits(in: .vertical)` with a
  /// flat `Text` node visibly changes the raster — none of the
  /// per-pick markers from the original (`[TALL3]`, `[MED2]`,
  /// `[SHORT1]`) survive. Without this A/B, a regression that always
  /// picked the same candidate could still pass for the wrong reason.
  @Test("flattening ViewThatFits removes the per-pick markers")
  func viewThatFitsIsNonVacuous() {
    let withVTF = render(
      ViewThatFitsVerticalOnly(),
      width: 80,
      height: 30,
      id: "with-vtf"
    ).rasterSurface
    let withoutVTF = render(
      ViewThatFitsVerticalOnlyFlattenedVariant(),
      width: 80,
      height: 30,
      id: "without-vtf"
    ).rasterSurface

    let withDump = withVTF.lines.joined(separator: "\n")
    let withoutDump = withoutVTF.lines.joined(separator: "\n")

    #expect(
      withDump.contains("[TALL3]") && withDump.contains("[MED2]")
        && withDump.contains("[SHORT1]"),
      "WITH-ViewThatFits should contain all three candidate markers\n\(withDump)"
    )
    #expect(
      !withoutDump.contains("[TALL3]") && !withoutDump.contains("[MED2]")
        && !withoutDump.contains("[SHORT1]"),
      """
      WITHOUT-ViewThatFits should not contain the candidate markers \
      (only the flat substitutes).
      \(withoutDump)
      """
    )
  }
}
