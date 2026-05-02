import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct NestedBorderOrderingBehaviourTests {
  /// Renders two concentric rings — inner single-box set, outer
  /// double-box set — with a 1-cell padding gap between them. Pins:
  ///
  ///   1. Both ring styles coexist in the raster: single-box corner
  ///      glyphs (`┌`, `┘`) and double-box corner glyphs (`╔`, `╝`)
  ///      are both present.
  ///   2. The outer ring's top row sits strictly above the inner
  ///      ring's top row, and the gap between them is at least 1 row
  ///      (the nested `.padding(1)`).
  ///   3. The outer ring is strictly wider than the inner ring on
  ///      their respective top rows.
  @Test("inner single ring sits inside outer double ring with ≥1 cell radial gap")
  func concentricRingsWithGap() {
    let raster = render(NestedBorderOrdering(), width: 30, height: 15).rasterSurface

    // The outer ring's top-leading corner is "╔" (double-box);
    // the inner ring's top-leading corner is "┌" (single-box).
    guard
      let outerTopRow = raster.firstRow(containing: "╔"),
      let innerTopRow = raster.firstRow(containing: "┌"),
      let outerBottomRow = raster.lastRow(containing: "╝"),
      let innerBottomRow = raster.lastRow(containing: "┘")
    else {
      let joined = raster.lines.joined(separator: "\n")
      Issue.record("expected both single-box and double-box corner glyphs\n\(joined)")
      return
    }

    // Outer ring must contain the inner ring vertically.
    #expect(
      outerTopRow < innerTopRow,
      "outer-double top row (\(outerTopRow)) should be above inner-single top row (\(innerTopRow))"
    )
    #expect(
      innerBottomRow < outerBottomRow,
      "inner-single bottom row (\(innerBottomRow)) should be above outer-double bottom row (\(outerBottomRow))"
    )

    // At least 1-cell padding between the outer and inner rings
    // (both top and bottom).
    #expect(
      innerTopRow - outerTopRow >= 1,
      "expected ≥1 row gap between outer top (\(outerTopRow)) and inner top (\(innerTopRow))"
    )
    #expect(
      outerBottomRow - innerBottomRow >= 1,
      "expected ≥1 row gap between inner bottom (\(innerBottomRow)) and outer bottom (\(outerBottomRow))"
    )

    // The outer ring should be strictly wider than the inner ring.
    guard
      let outerTop = raster.row(at: outerTopRow),
      let innerTop = raster.row(at: innerTopRow),
      let outerLeft = column(of: "╔", in: outerTop),
      let outerRight = column(of: "╗", in: outerTop),
      let innerLeft = column(of: "┌", in: innerTop),
      let innerRight = column(of: "┐", in: innerTop)
    else {
      Issue.record("could not locate ring corner columns")
      return
    }

    let outerSpan = outerRight - outerLeft + 1
    let innerSpan = innerRight - innerLeft + 1
    #expect(
      outerSpan > innerSpan,
      "outer ring span (\(outerSpan)) should be wider than inner ring span (\(innerSpan))"
    )

    // The inner ring should sit strictly inside the outer ring.
    #expect(
      outerLeft < innerLeft,
      "outer-left col (\(outerLeft)) should be left of inner-left col (\(innerLeft))"
    )
    #expect(
      innerRight < outerRight,
      "inner-right col (\(innerRight)) should be left of outer-right col (\(outerRight))"
    )
  }
}
