import SwiftTUI

/// Composes a single multi-line `String` for a Life grid at a given zoom.
///
/// Each terminal-cell row of the output corresponds to:
/// - braille: 4 game-cell rows (per row) × 2 game-cell columns (per char)
/// - halfCell: 2 game-cell rows × 1 game-cell column
/// - squareCell: 1 game-cell row × 1 game-cell column rendered into 2 chars
///
/// Allocates one `String` per render. The framework's `Text` re-emits
/// glyphs only for cells whose draw-command differs from the prior
/// frame, so this is cheap in practice.
@MainActor
enum LifeRenderer {
  static func render(
    grid: LifeGrid,
    zoom: LifeZoom,
    visibleSize: CellSize
  ) -> String {
    let dims = zoom.gridDimensions(for: visibleSize)
    switch zoom {
    case .braille:    return renderBraille(grid: grid, gridWidth: dims.width, gridHeight: dims.height)
    case .halfCell:   return renderHalfCell(grid: grid, gridWidth: dims.width, gridHeight: dims.height)
    case .squareCell: return renderSquare(grid: grid, gridWidth: dims.width, gridHeight: dims.height)
    }
  }

  // MARK: - Braille (2x4 per terminal cell)

  /// Unicode bit ordering for braille patterns U+2800..U+28FF, indexed
  /// by `(col, row)` within the 2×4 sub-grid.
  ///   col=0,row=0 → bit 0
  ///   col=0,row=1 → bit 1
  ///   col=0,row=2 → bit 2
  ///   col=1,row=0 → bit 3
  ///   col=1,row=1 → bit 4
  ///   col=1,row=2 → bit 5
  ///   col=0,row=3 → bit 6
  ///   col=1,row=3 → bit 7
  private static let brailleBitTable: [(col: Int, row: Int, bit: UInt32)] = [
    (0, 0, 0x01), (0, 1, 0x02), (0, 2, 0x04),
    (1, 0, 0x08), (1, 1, 0x10), (1, 2, 0x20),
    (0, 3, 0x40), (1, 3, 0x80),
  ]

  private static func renderBraille(
    grid: LifeGrid,
    gridWidth: Int,
    gridHeight: Int
  ) -> String {
    let termRows = gridHeight / 4
    var output = String()
    output.reserveCapacity(termRows * (gridWidth / 2 + 1))

    for tr in 0..<termRows {
      for tc in 0..<(gridWidth / 2) {
        var bits: UInt32 = 0
        for entry in brailleBitTable {
          let gx = tc * 2 + entry.col
          let gy = tr * 4 + entry.row
          if grid.at(gx, gy) {
            bits |= entry.bit
          }
        }
        if let scalar = Unicode.Scalar(0x2800 &+ bits) {
          output.append(Character(scalar))
        } else {
          output.append(" ")
        }
      }
      if tr < termRows - 1 { output.append("\n") }
    }
    return output
  }

  // MARK: - Half-cell (1x2 per terminal cell)

  private static func renderHalfCell(
    grid: LifeGrid,
    gridWidth: Int,
    gridHeight: Int
  ) -> String {
    let termRows = gridHeight / 2
    var output = String()
    output.reserveCapacity(termRows * (gridWidth + 1))

    for tr in 0..<termRows {
      for tc in 0..<gridWidth {
        let top = grid.at(tc, tr * 2)
        let bot = grid.at(tc, tr * 2 + 1)
        switch (top, bot) {
        case (false, false): output.append(" ")
        case (true,  false): output.append("\u{2580}") // ▀
        case (false, true):  output.append("\u{2584}") // ▄
        case (true,  true):  output.append("\u{2588}") // █
        }
      }
      if tr < termRows - 1 { output.append("\n") }
    }
    return output
  }

  // MARK: - Square (1x1 per pair of terminal cells)

  /// Two-character glyph for an alive cell. Uses `██` so the cell
  /// reads as a solid square at 2:1 cell aspect. Falls back to `[]`
  /// for ASCII-only contexts; the public `render(...)` entry point
  /// only selects squareCell when the host advertises Unicode, but
  /// callers that wire ASCII fallback can pass `useASCII: true`.
  static func aliveGlyph(useASCII: Bool = false) -> String {
    useASCII ? "[]" : "\u{2588}\u{2588}"
  }

  static func deadGlyph() -> String { "  " }

  private static func renderSquare(
    grid: LifeGrid,
    gridWidth: Int,
    gridHeight: Int
  ) -> String {
    var output = String()
    output.reserveCapacity(gridHeight * (gridWidth * 2 + 1))

    for tr in 0..<gridHeight {
      for tc in 0..<gridWidth {
        if grid.at(tc, tr) {
          output.append("\u{2588}\u{2588}")
        } else {
          output.append("  ")
        }
      }
      if tr < gridHeight - 1 { output.append("\n") }
    }
    return output
  }
}
