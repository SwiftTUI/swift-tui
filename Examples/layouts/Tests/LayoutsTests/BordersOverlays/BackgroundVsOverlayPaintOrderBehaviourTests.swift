import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct BackgroundVsOverlayPaintOrderBehaviourTests {
  /// Pins the paint-order semantics of `.background(...)` vs
  /// `.overlay(...)` at cell collisions.
  ///
  /// The layout puts two `Text("X").frame(width: 3, height: 1)` boxes
  /// side-by-side: the left box paints `Color.red` as a background; the
  /// right box paints `Color.blue` as an overlay. The two boxes sit
  /// under "background:" and "overlay:" labels respectively.
  ///
  /// Paint order:
  ///   - `.background` paints the red rectangle BEHIND the text, so
  ///     the `X` glyph should still be visible on top of the red fill
  ///     on the background box's content row.
  ///   - `.overlay` paints the blue rectangle OVER the text, so the
  ///     `X` glyph is obscured by the fill on the overlay box's
  ///     content row — the glyph is no longer visible there.
  @Test("overlay obscures content; background does not")
  func overlayCoversTextButBackgroundPreservesIt() {
    let raster = render(
      BackgroundVsOverlayPaintOrder(),
      width: 40,
      height: 10
    ).rasterSurface

    // The "background:" and "overlay:" labels anchor the two columns.
    guard
      let bgLabelRow = raster.firstRow(containing: "background:"),
      let ovLabelRow = raster.firstRow(containing: "overlay:")
    else {
      let joined = raster.lines.joined(separator: "\n")
      Issue.record("expected 'background:' and 'overlay:' label rows\n\(joined)")
      return
    }

    // Content row for each box is the line directly below the label.
    let bgContentRow = bgLabelRow + 1
    let ovContentRow = ovLabelRow + 1

    guard
      let bgLabelLine = raster.row(at: bgLabelRow),
      let ovLabelLine = raster.row(at: ovLabelRow),
      let bgContentLine = raster.row(at: bgContentRow),
      let ovContentLine = raster.row(at: ovContentRow),
      let bgLabelCol = column(of: "background:", in: bgLabelLine),
      let ovLabelCol = column(of: "overlay:", in: ovLabelLine)
    else {
      Issue.record("could not locate label columns")
      return
    }

    // The `X` glyph for each box sits immediately below its label, at
    // a column inside the `.frame(width: 3)` region starting at the
    // label's column.
    let bgBoxRange = bgLabelCol..<(bgLabelCol + 3)
    let ovBoxRange = ovLabelCol..<(ovLabelCol + 3)

    let bgContentCells = Array(bgContentLine)
    let ovContentCells = Array(ovContentLine)

    func hasX(_ cells: [Character], in range: Range<Int>) -> Bool {
      guard range.lowerBound >= 0, range.upperBound <= cells.count else {
        return false
      }
      return cells[range].contains("X")
    }

    let bgShowsX = hasX(bgContentCells, in: bgBoxRange)
    let ovShowsX = hasX(ovContentCells, in: ovBoxRange)

    #expect(
      bgShowsX,
      "background variant should still show 'X' in its content row; row='\(bgContentLine)' range=\(bgBoxRange)"
    )
    #expect(
      !ovShowsX,
      "overlay variant should NOT show 'X' (overlay paints over it); row='\(ovContentLine)' range=\(ovBoxRange)"
    )
  }
}
