import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct ThreeSpacerSharingBehaviourTests {
  /// Three `Spacer()` siblings inside an `HStack` split the residual
  /// horizontal space equally. With two text markers `[A]` (3 cells)
  /// and `[B]` (3 cells) inside a 40-cell-wide proposal, the three
  /// spacers share `40 - 6 = 34` residual cells: ≈ 11 each.
  ///
  /// The geometry implies:
  ///   - `[A]` lands roughly one third of the way in (column ≈ 11).
  ///   - `[B]` lands roughly two thirds of the way in (column ≈ 25).
  ///   - The gap between the two markers approximately equals the
  ///     leading inset of `[A]` (each of the three spacers contributes
  ///     the same residual share).
  ///
  /// The exact column depends on integer-rounding of `34 / 3`, so the
  /// assertions accept a generous tolerance window rather than pinning
  /// the precise column.
  @Test("Three spacers split residual width into ~equal thirds at width 40")
  func threeSpacersSplitResidualEqually() {
    let raster = render(ThreeSpacerSharing(), width: 40, height: 6).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    guard let row = raster.firstRow(containing: "[A]"),
      let line = raster.row(at: row),
      let colA = column(of: "[A]", in: line),
      let colB = column(of: "[B]", in: line)
    else {
      Issue.record(
        "expected `[A]` and `[B]` on the same row\n\(joined)"
      )
      return
    }

    // A is left of B.
    #expect(
      colA < colB,
      "expected [A] (col=\(colA)) left of [B] (col=\(colB))\nrow: '\(line)'"
    )

    // [A] sits "in the left third but pushed in" — the leading spacer
    // shoves it ~11 cells from column 0. Tolerance: 9..<18.
    #expect(
      colA >= 9 && colA < 18,
      "expected [A] near col ~11 (left third pushed in); got \(colA)\nrow: '\(line)'"
    )

    // [B] sits "in the right third but pushed in" — the trailing
    // spacer pulls it ~11 cells from column 40. With [B] being 3 cells
    // wide, its left column sits near 40 - 11 - 3 = 26. Tolerance:
    // 22..<31.
    #expect(
      colB >= 22 && colB < 31,
      "expected [B] near col ~26 (right third pushed in); got \(colB)\nrow: '\(line)'"
    )

    // Equal-spacer invariant: the leading inset of [A] (= colA) and
    // the inter-marker gap (= colB - (colA + 3) since [A] is 3 cells)
    // must agree within 1 cell of integer rounding.
    let leadingInset = colA
    let interMarkerGap = colB - (colA + 3)
    let drift = abs(leadingInset - interMarkerGap)
    #expect(
      drift <= 2,
      """
      expected leading inset (\(leadingInset)) ~= inter-marker gap \
      (\(interMarkerGap)) within 2 cells; got drift=\(drift)
      row: '\(line)'
      """
    )
  }
}
