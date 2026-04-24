import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct BorderBlendStaticPhaseBehaviourTests {
  /// Two boxes drawn with the SAME `BorderBlend` palette but different
  /// static `phase` values (0.0 vs 0.5) should paint different
  /// foreground colors at the same perimeter position. We compare the
  /// top-left rounded corner (`╭`) of each box — walking the perimeter
  /// clockwise from cell 0, the top-left corner is the blend's start
  /// point. At phase 0.0 it samples the first stop (`.red`); at
  /// phase 0.5 it samples roughly halfway around the palette (between
  /// `.green` and `.cyan`), so the colors must differ.
  @Test("same palette with phase 0 vs 0.5 produces different top-left corner colors")
  func phaseShiftChangesCornerColor() {
    let raster = render(BorderBlendStaticPhase(), width: 40, height: 10).rasterSurface

    // Both boxes use `.rounded`, so the TL corner glyph is "╭".
    let cornerRows = raster.rows(containing: "╭")
    guard let topRow = cornerRows.first else {
      let joined = raster.lines.joined(separator: "\n")
      Issue.record("expected rounded-corner glyph ╭\n\(joined)")
      return
    }
    // The two boxes share a row for their top border.
    guard let topLine = raster.row(at: topRow) else { return }
    let lineChars = Array(topLine)
    let cornerCols = lineChars.enumerated().compactMap { $0.element == "╭" ? $0.offset : nil }

    #expect(
      cornerCols.count == 2,
      "expected exactly 2 rounded-corner glyphs on the top row; got \(cornerCols) in '\(topLine)'"
    )
    guard cornerCols.count == 2 else { return }

    let leftCornerCol = cornerCols[0]
    let rightCornerCol = cornerCols[1]

    let cells = raster.cells
    let leftStyle = cells[topRow][leftCornerCol].style
    let rightStyle = cells[topRow][rightCornerCol].style

    // Phase shift must change the foreground color at the same
    // perimeter position — the two corners resolve to different cells
    // of the same blend.
    #expect(
      leftStyle?.foregroundColor != rightStyle?.foregroundColor,
      "phase 0.0 and phase 0.5 should paint different top-left corner colors; both got \(String(describing: leftStyle?.foregroundColor))"
    )
    // Both corners must have a resolved foreground — a blend never
    // leaves a perimeter cell unstyled.
    #expect(
      leftStyle?.foregroundColor != nil,
      "phase 0.0 top-left corner should have a foreground color"
    )
    #expect(
      rightStyle?.foregroundColor != nil,
      "phase 0.5 top-left corner should have a foreground color"
    )
  }
}
