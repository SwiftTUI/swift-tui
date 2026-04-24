import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct PerSideBorderColorsBehaviourTests {
  /// Pins per-side foreground colors on a `.heavy` border applied via
  /// `BorderEdgeStyle(top: .red, right: .yellow, bottom: .green, left: .blue)`.
  ///
  /// The renderer emits glyphs like `━ ┃ ┏ ┓ ┗ ┛`; each side's run
  /// carries its declared color through to the `RasterCell.style`
  /// foreground. The assertion inspects each non-corner edge cell:
  ///
  ///   - top row cell (between corners)    → red
  ///   - bottom row cell (between corners) → green
  ///   - left column cell (between corners)  → blue
  ///   - right column cell (between corners) → yellow
  @Test("each edge glyph carries its declared per-side color")
  func edgeCellsCarryDeclaredColors() {
    let raster = render(PerSideBorderColors(), width: 30, height: 12).rasterSurface

    // Find the four corners of the `.heavy` ring.
    guard
      let topRow = raster.firstRow(containing: "┏"),
      let bottomRow = raster.lastRow(containing: "┗")
    else {
      let joined = raster.lines.joined(separator: "\n")
      Issue.record("expected heavy-box corner glyphs ┏ / ┗\n\(joined)")
      return
    }
    guard
      let topLine = raster.row(at: topRow),
      let bottomLine = raster.row(at: bottomRow),
      let topLeft = column(of: "┏", in: topLine),
      let topRight = column(of: "┓", in: topLine),
      let bottomLeft = column(of: "┗", in: bottomLine),
      let bottomRight = column(of: "┛", in: bottomLine)
    else {
      Issue.record("could not locate all 4 corner columns")
      return
    }

    // Require that corners align (square-ish ring).
    #expect(
      topLeft == bottomLeft,
      "top-left col (\(topLeft)) should equal bottom-left col (\(bottomLeft))"
    )
    #expect(
      topRight == bottomRight,
      "top-right col (\(topRight)) should equal bottom-right col (\(bottomRight))"
    )

    // Pick a cell strictly INSIDE each edge (between the corners,
    // never on a corner) to test the per-side color.
    let midCol = (topLeft + topRight) / 2
    let midRow = (topRow + bottomRow) / 2

    guard midCol > topLeft, midCol < topRight else {
      Issue.record("ring too narrow to sample mid-edge columns")
      return
    }
    guard midRow > topRow, midRow < bottomRow else {
      Issue.record("ring too short to sample mid-edge rows")
      return
    }

    // Inspect per-cell styles in the raster.
    let cells = raster.cells
    let topCellStyle = cells[topRow][midCol].style
    let bottomCellStyle = cells[bottomRow][midCol].style
    let leftCellStyle = cells[midRow][topLeft].style
    let rightCellStyle = cells[midRow][topRight].style

    #expect(
      topCellStyle?.foregroundColor == Color.red,
      "expected top-edge foreground Color.red; got \(String(describing: topCellStyle?.foregroundColor))"
    )
    #expect(
      bottomCellStyle?.foregroundColor == Color.green,
      "expected bottom-edge foreground Color.green; got \(String(describing: bottomCellStyle?.foregroundColor))"
    )
    #expect(
      leftCellStyle?.foregroundColor == Color.blue,
      "expected left-edge foreground Color.blue; got \(String(describing: leftCellStyle?.foregroundColor))"
    )
    #expect(
      rightCellStyle?.foregroundColor == Color.yellow,
      "expected right-edge foreground Color.yellow; got \(String(describing: rightCellStyle?.foregroundColor))"
    )
  }
}
