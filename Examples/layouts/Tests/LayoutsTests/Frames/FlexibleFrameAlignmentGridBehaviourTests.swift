import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct FlexibleFrameAlignmentGridBehaviourTests {
  /// Nine markers each claim the full outer frame via
  /// `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment:)`
  /// at a distinct `Alignment`. Within the outer 60×20 box that means:
  ///
  ///   Vertical:   TL row  <  [C] row  <  BR row
  ///               TC row  <  [C] row  <  BC row
  ///   Horizontal: TL col  <  [C] col  <  BR col
  ///               LC col  <  [C] col  <  RC col
  ///
  /// The header row (`"Flexible frame alignment grid"`) sits above
  /// the grid; because the corner/center markers are two-character
  /// strings that never appear in the header text, the header never
  /// perturbs the assertions.
  @Test("Grid markers preserve TL→C→BR + LC→C→RC + TC→C→BC ordering")
  func markersOrderMonotonically() {
    let raster = render(FlexibleFrameAlignmentGrid(), width: 70, height: 28).rasterSurface

    guard
      let tlRow = raster.firstRow(containing: "TL"),
      let tcRow = raster.firstRow(containing: "TC"),
      let centerRow = raster.firstRow(containing: "[C]"),
      let bcRow = raster.lastRow(containing: "BC"),
      let brRow = raster.lastRow(containing: "BR")
    else {
      Issue.record(
        "expected TL/TC/[C]/BC/BR anchor rows in raster:\n\(raster.lines.joined(separator: "\n"))"
      )
      return
    }

    #expect(
      tlRow < centerRow,
      "TL row (\(tlRow)) should be above [C] row (\(centerRow))"
    )
    #expect(
      centerRow < brRow,
      "[C] row (\(centerRow)) should be above BR row (\(brRow))"
    )
    #expect(
      tcRow < centerRow,
      "TC row (\(tcRow)) should be above [C] row (\(centerRow))"
    )
    #expect(
      centerRow < bcRow,
      "[C] row (\(centerRow)) should be above BC row (\(bcRow))"
    )

    // Column positions within their anchoring rows.
    guard
      let lcRow = raster.firstRow(containing: "LC"),
      let rcRow = raster.firstRow(containing: "RC")
    else {
      Issue.record("expected LC/RC anchor rows in raster")
      return
    }

    let tlCol = column(of: "TL", in: raster.row(at: tlRow))
    let centerCol = column(of: "[C]", in: raster.row(at: centerRow))
    let brCol = column(of: "BR", in: raster.row(at: brRow))
    let lcCol = column(of: "LC", in: raster.row(at: lcRow))
    let rcCol = column(of: "RC", in: raster.row(at: rcRow))

    guard
      let tlCol, let centerCol, let brCol, let lcCol, let rcCol
    else {
      Issue.record("could not locate one of the column anchors")
      return
    }

    #expect(
      tlCol < centerCol,
      "TL col (\(tlCol)) should be left of [C] col (\(centerCol))"
    )
    #expect(
      centerCol < brCol,
      "[C] col (\(centerCol)) should be left of BR col (\(brCol))"
    )
    #expect(
      lcCol < centerCol,
      "LC col (\(lcCol)) should be left of [C] col (\(centerCol))"
    )
    #expect(
      centerCol < rcCol,
      "[C] col (\(centerCol)) should be left of RC col (\(rcCol))"
    )
  }
}
