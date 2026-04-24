import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct OffsetPreservesMeasuredSizeBehaviourTests {
  /// `.offset(x:)` on a middle child must NOT disturb sibling layout:
  /// `[C]` should sit at the column where the HStack lays it (after
  /// A's 3 cells + B's measured 3 cells = col 6), not at col 12 (as
  /// would happen if the offset shifted siblings).  `[B]` itself
  /// should paint at col 9 (layout col 3 + offset 6).
  ///
  /// The outer `.padding(1)` pushes everything 1 column right, so the
  /// expected raster columns are `[A]` at 1, `[B]` at 10, `[C]` at 7.
  /// The assertion is framed as "column of C − column of A == 6" so it
  /// does not depend on the outer padding constant and pins the
  /// paint-only contract directly.
  @Test("offset is paint-only; siblings keep their measured layout")
  func offsetDoesNotShiftSiblings() {
    let raster = render(
      OffsetPreservesMeasuredSize(),
      width: 40,
      height: 5
    ).rasterSurface

    let joined = raster.lines.joined(separator: "\n")

    guard let rowA = raster.firstRow(containing: "[A]"),
      let rowC = raster.firstRow(containing: "[C]"),
      let rowB = raster.firstRow(containing: "[B]")
    else {
      Issue.record("missing one of [A]/[B]/[C] in raster\n\(joined)")
      return
    }

    // A, B, and C should all live on the same row of the HStack.
    #expect(
      rowA == rowC,
      "expected [A] and [C] on the same row; rowA=\(rowA), rowC=\(rowC)\n\(joined)"
    )
    #expect(
      rowA == rowB,
      "expected [A] and [B] on the same row (offset is paint-only on x); rowA=\(rowA), rowB=\(rowB)\n\(joined)"
    )

    guard let lineA = raster.row(at: rowA),
      let colA = column(of: "[A]", in: lineA),
      let colB = column(of: "[B]", in: lineA),
      let colC = column(of: "[C]", in: lineA)
    else {
      Issue.record(
        "could not find [A]/[B]/[C] columns on row \(rowA): '\(raster.row(at: rowA) ?? "")'")
      return
    }

    // Invariant 1: C is at col A + 6 (A's 3 + B's measured 3).
    // This is the paint-only contract: B's offset does NOT push C.
    #expect(
      colC - colA == 6,
      "expected [C] at col A+6 (paint-only offset); got A=\(colA), C=\(colC) diff=\(colC - colA)\n\(joined)"
    )

    // Invariant 2: B paints at col A + 3 + 6 = A + 9 (layout col 3 + offset 6).
    #expect(
      colB - colA == 9,
      "expected [B] at col A+9 (layout 3 + offset 6); got A=\(colA), B=\(colB) diff=\(colB - colA)\n\(joined)"
    )
  }
}
