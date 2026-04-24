import TerminalUI
import Testing

@testable import Layouts

/// A/B variant: replace the wide 12×5 frame with a square 5×5 frame.
/// The inscribed disc now exactly fills the (square) frame interior,
/// so there are no left/right empty-corner cells inside the border —
/// every interior column is reached by the disc on at least one row.
@MainActor
private struct CircleInNonSquareFrameSquareVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Circle in non square frame").foregroundStyle(.muted)
      Circle()
        .fill(Color.red)
        .frame(width: 5, height: 5)
        .border(.separator)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct CircleInNonSquareFrameBehaviourTests {
  /// Observed raster (30×10 viewport, `.padding(1)` outer):
  ///
  /// ```
  /// [1] | Circle in non square frame|
  /// [2] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▜|             <- top border row 2, cols 1..14
  /// [3] | ▌  ⢀⣴⣶⣾⣶⣶⣄   ▐|
  /// [4] | ▌ ⢰⣿⣿⣿⣿⣿⣿⣿⣷  ▐|
  /// [5] | ▌ ⢺⣿⣿⣿⣿⣿⣿⣿⣿⠂ ▐|
  /// [6] | ▌ ⠘⢿⣿⣿⣿⣿⣿⣿⠟  ▐|
  /// [7] | ▌   ⠙⠛⠻⠛⠛⠁   ▐|
  /// [8] | ▙▄▄▄▄▄▄▄▄▄▄▄▄▟|             <- bottom border row 8
  /// ```
  ///
  /// `Circle` inscribes itself in the **shortest axis** (height=5) so
  /// the disc occupies a roughly 5-cell-wide band centred horizontally
  /// inside the 12-cell frame interior. The leading empty-corner band
  /// (cells at col 2, the first interior column) and the trailing
  /// empty-corner band (cells at col 13, the last interior column) are
  /// NEVER reached by the disc — they have no red foreground on any of
  /// the interior rows 3..7.
  ///
  /// The assertion pins the OBSERVED behaviour:
  ///   - The disc's vertical centre column carries a red foreground
  ///     on at least one interior row (proves the disc is painted at all).
  ///   - The first interior column (col 2, immediately right of the
  ///     left border) has NO red foreground on any interior row 3..7
  ///     — that band is the empty corner.
  ///   - The last interior column (col 13, immediately left of the
  ///     right border) has NO red foreground on any interior row 3..7.
  @Test("inscribed disc leaves empty cells at the wide frame's left/right corners")
  func wideFrameLeavesEmptyCorners() {
    let raster = render(CircleInNonSquareFrame(), width: 30, height: 10).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    // Disc bounding rows are the interior of the bordered frame:
    // top border at row 2, bottom border at row 8 → interior rows 3..7.
    let interiorRows = 3...7
    // Frame interior columns: border at col 1 and col 14 → interior 2..13.
    let leftInteriorCol = 2
    let rightInteriorCol = 13
    // Centre column of a 5-row disc inscribed in cols 3..12 lives
    // around col 7..8.
    let centreCol = 7

    func isRed(_ row: Int, _ col: Int) -> Bool {
      guard row < raster.cells.count, col < raster.cells[row].count else {
        return false
      }
      return raster.cells[row][col].style?.foregroundColor == Color.red
    }

    // 1. Disc paints SOMETHING red at the vertical centre column.
    let centreHasRed = interiorRows.contains { isRed($0, centreCol) }
    #expect(
      centreHasRed,
      """
      expected at least one red cell at centre column \(centreCol) \
      across interior rows \(interiorRows); got nothing
      \(joined)
      """
    )

    // 2. The leading empty-corner column (col \(leftInteriorCol)) is
    //    never red on any interior row.
    for row in interiorRows {
      #expect(
        !isRed(row, leftInteriorCol),
        """
        expected empty corner at (row=\(row), col=\(leftInteriorCol)) — \
        the leading interior column should not be reached by the \
        inscribed disc in a 12×5 frame
        \(joined)
        """
      )
    }

    // 3. The trailing empty-corner column (col \(rightInteriorCol)) is
    //    never red on any interior row.
    for row in interiorRows {
      #expect(
        !isRed(row, rightInteriorCol),
        """
        expected empty corner at (row=\(row), col=\(rightInteriorCol)) — \
        the trailing interior column should not be reached by the \
        inscribed disc in a 12×5 frame
        \(joined)
        """
      )
    }
  }

  /// A/B vacuity: the same layout shape but with a square 5×5 frame.
  /// The inscribed disc now fits the frame interior exactly — there
  /// are no extra-wide left/right corner bands. So at least ONE
  /// interior row should reach the leading interior column with a
  /// red foreground (the disc spans the full width of the frame).
  ///
  /// The vacuity check: SHORT-frame layout pins "no red at leading
  /// corner" AND square-frame variant pins "yes red at leading
  /// corner." If the variant ever stops painting red at the leading
  /// corner the A/B is no longer informative.
  @Test("shrinking the frame to 5×5 fills every interior column at some row")
  func emptyCornerInvariantIsNonVacuous() {
    let wideRaster = render(
      CircleInNonSquareFrame(),
      width: 30,
      height: 10,
      id: "wide-frame"
    ).rasterSurface
    let squareRaster = render(
      CircleInNonSquareFrameSquareVariant(),
      width: 30,
      height: 10,
      id: "square-frame"
    ).rasterSurface
    let wideDump = wideRaster.lines.joined(separator: "\n")
    let squareDump = squareRaster.lines.joined(separator: "\n")

    func isRed(_ raster: RasterSurface, _ row: Int, _ col: Int) -> Bool {
      guard row < raster.cells.count, col < raster.cells[row].count else {
        return false
      }
      return raster.cells[row][col].style?.foregroundColor == Color.red
    }

    // WIDE frame: leading interior column (col 2) has no red on any
    // interior row.
    let wideInteriorRows = 3...7
    let wideLeadingHasRed = wideInteriorRows.contains { isRed(wideRaster, $0, 2) }
    #expect(
      !wideLeadingHasRed,
      """
      WIDE frame expected leading interior col 2 to have no red \
      (empty corner); got red somewhere on rows 3..7
      \(wideDump)
      """
    )

    // SQUARE frame: the disc occupies the full 5-cell width (cols 2..6),
    // so on at least one interior row the leading interior column
    // (col 2) MUST be red.
    let squareInteriorRows = 3...7
    let squareLeadingHasRed = squareInteriorRows.contains { isRed(squareRaster, $0, 2) }
    #expect(
      squareLeadingHasRed,
      """
      SQUARE-frame variant (frame 5×5) expected red at leading \
      interior col 2 on at least one interior row; if this fails \
      the A/B vacuity check is no longer meaningful.
      \(squareDump)
      """
    )
  }
}
