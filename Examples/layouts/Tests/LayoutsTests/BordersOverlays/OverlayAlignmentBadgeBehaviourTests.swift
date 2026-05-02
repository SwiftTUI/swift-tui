import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct OverlayAlignmentBadgeBehaviourTests {
  /// A bordered 20×5 box with a `●` badge anchored via
  /// `.overlay(alignment: .bottomTrailing)`. The badge glyph should
  /// paint at the bottom-trailing corner of the base frame — i.e. on
  /// the bottom border row and at (or adjacent to) the right border
  /// column of the box.
  @Test("bottomTrailing overlay anchors the badge at the box's bottom-right corner")
  func badgeLandsAtBottomRight() {
    let raster = render(OverlayAlignmentBadge(), width: 30, height: 10).rasterSurface

    // Locate the base box's bottom border corners ("└" and "┘").
    guard
      let bottomRow = raster.lastRow(containing: "└"),
      let topRow = raster.firstRow(containing: "┌"),
      let bottomLine = raster.row(at: bottomRow),
      let topLine = raster.row(at: topRow),
      let leftCol = column(of: "┌", in: topLine),
      let rightCol = column(of: "┐", in: topLine)
    else {
      let joined = raster.lines.joined(separator: "\n")
      Issue.record("expected single-box corner glyphs ┌ / ┐ / └\n\(joined)")
      return
    }

    // Locate the badge glyph.
    guard let badgeRow = raster.lastRow(containing: "●") else {
      let joined = raster.lines.joined(separator: "\n")
      Issue.record("expected badge glyph ●\n\(joined)")
      return
    }
    guard let badgeLine = raster.row(at: badgeRow),
      let badgeCol = column(of: "●", in: badgeLine)
    else {
      Issue.record("could not locate badge column")
      return
    }

    // Vertical: the badge must sit ON the bottom border row of the
    // 20×5 box (the overlay aligns to the base frame's bottom edge).
    #expect(
      badgeRow == bottomRow,
      "expected badge row (\(badgeRow)) == bottom-border row (\(bottomRow))"
    )

    // Horizontal: the badge must sit at the right edge of the box —
    // at or adjacent to the bottom-right corner column. Accept a
    // 1-cell tolerance on either side of the corner column to absorb
    // any reasonable corner-vs-interior placement choice.
    #expect(
      abs(badgeCol - rightCol) <= 1,
      "expected badge col (\(badgeCol)) within 1 of right-corner col (\(rightCol))"
    )

    // The badge must be on the RIGHT half, not the left.
    let midCol = (leftCol + rightCol) / 2
    #expect(
      badgeCol > midCol,
      "expected badge col (\(badgeCol)) to be right of midCol (\(midCol)); bottom='\(bottomLine)'"
    )

    // Sanity: also confirm the badge sits on the BOTTOM half of the
    // box's vertical extent.
    let midRow = (topRow + bottomRow) / 2
    #expect(
      badgeRow > midRow,
      "expected badge row (\(badgeRow)) below midRow (\(midRow))"
    )
  }
}
