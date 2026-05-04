import SwiftTUI

/// Draws a Conway's Life grid into a SwiftTUI ``Canvas`` at one of the
/// three supported zoom levels.
///
/// `LifeDrawing` is a ``CanvasDrawing`` value that captures an immutable
/// snapshot of just the visible region of a ``LifeGrid``. The framework
/// compares two `LifeDrawing` values to decide whether the rasterizer
/// needs to repaint the canvas at all, so capturing only the visible
/// cells (rather than the full 320×160 backing buffer) keeps both the
/// equality compare and per-frame allocation cheap.
///
/// **Coordinate mapping** (drawing space → terminal cells), keyed off
/// the Canvas's ``CanvasGrid``:
///
///   - braille (`.braille2x4`): one game cell at `(x, y)` lights one
///     2×4 sub-pixel; the rasterizer packs it into a U+2800–U+28FF
///     braille glyph per terminal cell.
///   - halfCell (`.verticalHalfBlock`): one game cell at `(x, y)`
///     lights one of the two vertical sub-pixels; the rasterizer emits
///     ▀ / ▄ / █.
///   - squareCell (`.fullCell`): the canvas frame is doubled
///     horizontally so each game cell becomes two adjacent terminal
///     cells, preserving the square 2:1 visual aspect from the previous
///     `██` text renderer.
///
/// Each call leaves `context.foreground` untouched so a parent
/// `.foregroundStyle(...)` continues to color the alive cells.
struct LifeDrawing: CanvasDrawing, Equatable {
  /// Row-major snapshot of just the visible region. Length = `width * height`.
  let cells: [Bool]

  /// Visible game-cell width that `cells` represents.
  let width: Int

  /// Visible game-cell height that `cells` represents.
  let height: Int

  /// Zoom level governing how `cells` packs into terminal glyphs.
  let zoom: LifeZoom

  func draw(into context: inout CanvasContext) {
    guard width > 0, height > 0, cells.count == width * height else { return }

    switch zoom {
    case .braille, .halfCell:
      // One game cell = one sub-pixel in the active grid.
      for y in 0..<height {
        let row = y * width
        for x in 0..<width where cells[row + x] {
          context.setPixel(x: x, y: y)
        }
      }

    case .squareCell:
      // `.fullCell` grid: one sub-pixel per terminal cell. Each game
      // cell occupies two adjacent terminal cells horizontally to keep
      // the 2:1 cell aspect ratio looking square.
      for y in 0..<height {
        let row = y * width
        for x in 0..<width where cells[row + x] {
          context.setPixel(x: 2 * x, y: y)
          context.setPixel(x: 2 * x + 1, y: y)
        }
      }
    }
  }
}

@MainActor
enum LifeRenderer {
  /// Snapshots the visible region of `grid` as a row-major `[Bool]`
  /// suitable for ``LifeDrawing``. The snapshot ignores the fixed
  /// backing buffer's `maxWidth × maxHeight` dimensions and only emits
  /// `width × height` cells, so the resulting drawing's `Equatable`
  /// compare and the rasterizer's diff key both stay tight.
  static func snapshot(
    of grid: LifeGrid,
    width: Int,
    height: Int
  ) -> [Bool] {
    let w = max(0, min(width, grid.width))
    let h = max(0, min(height, grid.height))
    guard w > 0, h > 0 else { return [] }

    var out = [Bool](repeating: false, count: width * height)
    for y in 0..<h {
      let row = y * width
      for x in 0..<w {
        out[row + x] = grid.at(x, y)
      }
    }
    return out
  }
}
