import TerminalUI
import Testing

@testable import Layouts

/// Drawing reused by the A/B vacuity variant — paints a horizontal line
/// spanning three times the canvas's cell-space width.
private struct OverflowLine: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    let y = Double(context.size.height) / 2
    context.line(
      from: Point(x: 0, y: y),
      to: Point(x: Double(context.size.width * 3), y: y)
    )
  }
}

/// A/B vacuity variant: identical layout shape but the canvas frame
/// is widened from 10 cells to 30 cells. The cyan-painted region must
/// grow proportionally — proving the "no cyan past col N" assertion
/// in the BASE test is genuinely detecting the frame's right edge,
/// not vacuously true because the canvas paints nothing past col 11
/// regardless.
@MainActor
private struct CanvasHonorsClippedWideVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Canvas honors clipped").foregroundStyle(.muted)
      Canvas(OverflowLine())
        .foregroundStyle(Color.cyan)
        .frame(width: 30, height: 4)
        .clipped()
        .border(.separator)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct CanvasHonorsClippedBehaviourTests {
  /// Observed raster (30×12 viewport, `.padding(1)` outer):
  ///
  /// ```
  /// [1] | Canvas honors clipped|
  /// [2] | ▛▀▀▀▀▀▀▀▀▀▀▜|             <- top border at row 2, cols 1..12
  /// [3] | ▌          ▐|
  /// [4] | ▌          ▐|
  /// [5] | ▌⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉▐|             <- canvas line: cyan at cols 2..11
  /// [6] | ▌          ▐|
  /// [7] | ▙▄▄▄▄▄▄▄▄▄▄▟|             <- bottom border at row 7
  /// ```
  ///
  /// The drawing tries to paint a horizontal line spanning
  /// three times the canvas's cell-space width — well past the 10-cell canvas
  /// frame. With `.clipped()` (and the canvas's own grid-bounds
  /// auto-clipping; see Finding below) the visible painted region is
  /// strictly contained inside the 10 interior columns of the canvas
  /// frame.
  ///
  /// Pinned invariants:
  ///   - The line row contains at least one cyan cell.
  ///   - Every cyan cell's column is within the 10-cell frame
  ///     interior (cols 2..11 inclusive — col 1 is the left border,
  ///     col 12 is the right border).
  ///   - No cyan cell exists at col >= 12 (anywhere on the line row
  ///     or otherwise) — the overflow has been dropped.
  @Test(".clipped() (with canvas subpixel auto-clip) bounds cyan to the 10-cell frame")
  func canvasOverflowDropped() {
    let raster = render(CanvasHonorsClipped(), width: 30, height: 12).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    // 10-cell canvas frame: border at col 1 and col 12 → interior cols 2..11.
    let leftInterior = 2
    let rightInterior = 11
    let firstOverflowCol = 12

    var cyanCells: [(row: Int, col: Int)] = []
    for (r, row) in raster.cells.enumerated() {
      for (c, cell) in row.enumerated() {
        if cell.style?.foregroundColor == Color.cyan {
          cyanCells.append((r, c))
        }
      }
    }

    #expect(
      !cyanCells.isEmpty,
      "expected at least one cyan cell from the canvas line\n\(joined)"
    )

    // Every cyan cell's column must be inside the 10-cell interior.
    for (row, col) in cyanCells {
      #expect(
        col >= leftInterior && col <= rightInterior,
        """
        cyan cell at (row=\(row), col=\(col)) escapes the 10-cell \
        canvas interior [\(leftInterior)..\(rightInterior)]; \
        .clipped() should drop overflow
        \(joined)
        """
      )
    }

    // Explicit "no cyan past the frame's right edge" check.
    let overflowCyan = cyanCells.filter { $0.col >= firstOverflowCol }
    #expect(
      overflowCyan.isEmpty,
      """
      expected no cyan cells at col >= \(firstOverflowCol) (past the \
      10-cell frame's right border); got \(overflowCyan)
      \(joined)
      """
    )
  }

  /// A/B vacuity: widening the canvas frame from 10 to 30 cells must
  /// extend the cyan-painted region into columns past the original
  /// right edge (col 11). If it didn't, the BASE assertion ("no cyan
  /// past col 11") would be vacuously true regardless of `.clipped()`.
  ///
  /// Note: this layout is also where the "removing `.clipped()`" hand-
  /// wave from the plan does not give a useful vacuity check — see the
  /// "Canvas auto-clips at subpixel level" finding in
  /// `docs/proposals/layout/BEHAVIOUR_FINDINGS.md`. Instead, growing
  /// the frame widens the cyan region — that's the genuine A/B that
  /// the assertion is observing the frame edge.
  @Test("widening the frame to 30 paints cyan past the original 10-cell edge")
  func clippedInvariantIsNonVacuous() {
    let baseRaster = render(
      CanvasHonorsClipped(),
      width: 60,
      height: 12,
      id: "base"
    ).rasterSurface
    let wideRaster = render(
      CanvasHonorsClippedWideVariant(),
      width: 60,
      height: 12,
      id: "wide"
    ).rasterSurface
    let baseDump = baseRaster.lines.joined(separator: "\n")
    let wideDump = wideRaster.lines.joined(separator: "\n")

    let baseMaxCyanCol = maxCyanColumn(in: baseRaster)
    let wideMaxCyanCol = maxCyanColumn(in: wideRaster)

    // BASE: cyan stops at the 10-cell frame's right interior col 11.
    #expect(
      baseMaxCyanCol == 11,
      """
      BASE expected rightmost cyan col == 11 (right interior col of \
      the 10-cell frame); got \(String(describing: baseMaxCyanCol))
      \(baseDump)
      """
    )

    // WIDE: cyan now extends to col 31 (right interior col of the
    // 30-cell frame: border col 1 + 30 interior + border col 32 → \
    // rightmost interior col = 31). If this fails the A/B vacuity \
    // check is no longer informative.
    #expect(
      wideMaxCyanCol == 31,
      """
      WIDE-frame variant (frame width 30) expected rightmost cyan col \
      == 31; got \(String(describing: wideMaxCyanCol)). If this fails \
      the A/B vacuity check is no longer meaningful.
      \(wideDump)
      """
    )
  }
}

/// The largest column index containing a cyan-foreground cell, or
/// nil if no cell carries cyan.
private func maxCyanColumn(in raster: RasterSurface) -> Int? {
  var best: Int? = nil
  for row in raster.cells {
    for (c, cell) in row.enumerated() {
      if cell.style?.foregroundColor == Color.cyan {
        if let current = best {
          best = max(current, c)
        } else {
          best = c
        }
      }
    }
  }
  return best
}
