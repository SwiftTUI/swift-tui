import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct ZStackAlignmentGridBehaviourTests {
  /// Five markers (`TL`, `TR`, `[C]`, `BL`, `BR`) each claim the
  /// ZStack's full frame at distinct `Alignment`s. The anchor sets
  /// pin two monotonic progressions through the raster:
  ///
  ///   Vertical:   TL row  <  [C] row  <  BR row
  ///   Horizontal: TL col  <  [C] col  <  BR col
  ///
  /// The ZStack is rendered inside a 60×30 viewport; the header row
  /// ("ZStack alignment grid") sits above the stack and is ignored
  /// for these assertions because the corner/center markers never
  /// appear on the header row.
  @Test("Corner and center markers preserve TL→C→BR ordering")
  func cornerAndCenterMarkersOrderMonotonically() {
    let raster = render(ZStackAlignmentGrid(), width: 60, height: 30).rasterSurface

    let tlRow = raster.firstRow(containing: "TL")
    let centerRow = raster.firstRow(containing: "[C]")
    let brRow = raster.lastRow(containing: "BR")

    #expect(tlRow != nil, "expected TL marker somewhere in raster")
    #expect(centerRow != nil, "expected [C] marker somewhere in raster")
    #expect(brRow != nil, "expected BR marker somewhere in raster")

    guard let tlRow, let centerRow, let brRow else { return }

    #expect(
      tlRow < centerRow,
      "TL row (\(tlRow)) should be above [C] row (\(centerRow))"
    )
    #expect(
      centerRow < brRow,
      "[C] row (\(centerRow)) should be above BR row (\(brRow))"
    )

    // Column positions within each anchoring row.
    let tlCol = column(of: "TL", in: raster.row(at: tlRow))
    let centerCol = column(of: "[C]", in: raster.row(at: centerRow))
    let brCol = column(of: "BR", in: raster.row(at: brRow))

    #expect(tlCol != nil, "could not locate TL column in row \(tlRow)")
    #expect(centerCol != nil, "could not locate [C] column in row \(centerRow)")
    #expect(brCol != nil, "could not locate BR column in row \(brRow)")

    guard let tlCol, let centerCol, let brCol else { return }

    #expect(
      tlCol < centerCol,
      "TL col (\(tlCol)) should be left of [C] col (\(centerCol))"
    )
    #expect(
      centerCol < brCol,
      "[C] col (\(centerCol)) should be left of BR col (\(brCol))"
    )
  }
}
