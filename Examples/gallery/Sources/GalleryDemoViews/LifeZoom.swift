import SwiftTUI

/// Zoom levels for the Life grid. Each level packs a different number
/// of game cells into a single terminal cell tile.
///
/// - ``braille``: 2×4 game cells per terminal cell (8× density). Uses
///   Unicode braille block U+2800–U+28FF. Skipped on ASCII-only profiles.
/// - ``halfCell``: 1×2 game cells per terminal cell (2× density). Uses
///   half-block glyphs ▀ ▄ █. Skipped on ASCII-only profiles.
/// - ``squareCell``: 1×1 game cell per *two* terminal cells. The
///   doubled width compensates for the typical 2:1 cell aspect ratio so
///   each game cell looks square. Always available — alive cells render
///   as `██` (Unicode) or `[]` (ASCII fallback).
enum LifeZoom: Int, CaseIterable, Hashable, Sendable {
  case braille = 0
  case halfCell = 1
  case squareCell = 2

  var label: String {
    switch self {
    case .braille: return "braille · 8×"
    case .halfCell: return "half · 2×"
    case .squareCell: return "square · 1×"
    }
  }

  /// Whether this zoom level requires the host terminal to advertise
  /// Unicode glyph support. ASCII-only sessions should skip levels that
  /// return `true`.
  var requiresUnicode: Bool {
    switch self {
    case .braille, .halfCell: return true
    case .squareCell: return false
    }
  }

  /// Game cells along each axis inside a single terminal-cell tile.
  var gameCellsPerTile: (x: Int, y: Int) {
    switch self {
    case .braille: return (2, 4)
    case .halfCell: return (1, 2)
    case .squareCell: return (1, 1)
    }
  }

  /// Terminal cells consumed along each axis to draw one game cell tile.
  /// Square mode doubles horizontally so each game cell looks square at
  /// typical font aspect ratios.
  var terminalCellsPerTile: (x: Int, y: Int) {
    switch self {
    case .braille: return (1, 1)
    case .halfCell: return (1, 1)
    case .squareCell: return (2, 1)
    }
  }

  /// Game-cell extent that fits in `terminalSize`.
  func gridDimensions(for terminalSize: CellSize) -> (width: Int, height: Int) {
    let tx = terminalCellsPerTile.x
    let ty = terminalCellsPerTile.y
    let gx = gameCellsPerTile.x
    let gy = gameCellsPerTile.y
    let w = max(1, (terminalSize.width / tx) * gx)
    let h = max(1, (terminalSize.height / ty) * gy)
    return (w, h)
  }

  /// Inverse of ``gridDimensions(for:)``: given a game-cell extent,
  /// returns the terminal-cell frame the ``Canvas`` needs in order to
  /// render exactly those cells without truncation or padding.
  func terminalSize(forGameWidth width: Int, gameHeight height: Int) -> CellSize {
    let tx = terminalCellsPerTile.x
    let ty = terminalCellsPerTile.y
    let gx = gameCellsPerTile.x
    let gy = gameCellsPerTile.y
    return CellSize(
      width: max(0, (width / gx) * tx),
      height: max(0, (height / gy) * ty)
    )
  }

  /// Rasterization grid the ``Canvas`` should use for this zoom. Pairs
  /// each zoom mode with a glyph family whose sub-cell layout matches
  /// the game-cells-per-terminal-cell tile: braille for 2×4, vertical
  /// half-block for 1×2, and full-cell for square (with the canvas
  /// width doubled by ``terminalSize(forGameWidth:gameHeight:)`` so
  /// each game cell still reads as a square at typical 2:1 cell
  /// aspect).
  var canvasGrid: CanvasGrid {
    switch self {
    case .braille: return .braille2x4
    case .halfCell: return .verticalHalfBlock
    case .squareCell: return .fullCell
    }
  }

  /// Maps a continuous pointer location (in the grid view's local
  /// coordinate space) to a game-cell coordinate. Returns `nil` if
  /// the point falls outside `gridSize`.
  func gameCell(at point: Point, gridSize: (width: Int, height: Int)) -> (x: Int, y: Int)? {
    // Defensive: pointer coordinates can land slightly outside the
    // resolved local rect during teardown of a drag captured across a
    // re-resolve. Bail without writing instead of clamping to (0,0).
    guard point.x >= 0, point.y >= 0 else { return nil }

    switch self {
    case .braille:
      let tx = Int(point.x.rounded(.down))
      let ty = Int(point.y.rounded(.down))
      let fx = max(0, min(0.999, point.x - Double(tx)))
      let fy = max(0, min(0.999, point.y - Double(ty)))
      let sx = Int((fx * 2).rounded(.down))  // 0..<2
      let sy = Int((fy * 4).rounded(.down))  // 0..<4
      let gx = tx * 2 + sx
      let gy = ty * 4 + sy
      return inBounds(gx: gx, gy: gy, gridSize: gridSize)

    case .halfCell:
      let tx = Int(point.x.rounded(.down))
      let ty = Int(point.y.rounded(.down))
      let fy = max(0, min(0.999, point.y - Double(ty)))
      let sy = Int((fy * 2).rounded(.down))  // 0..<2
      let gx = tx
      let gy = ty * 2 + sy
      return inBounds(gx: gx, gy: gy, gridSize: gridSize)

    case .squareCell:
      let tx = Int(point.x.rounded(.down))
      let ty = Int(point.y.rounded(.down))
      let gx = tx / 2
      let gy = ty
      return inBounds(gx: gx, gy: gy, gridSize: gridSize)
    }
  }

  private func inBounds(
    gx: Int,
    gy: Int,
    gridSize: (width: Int, height: Int)
  ) -> (x: Int, y: Int)? {
    guard gx >= 0, gx < gridSize.width, gy >= 0, gy < gridSize.height else { return nil }
    return (gx, gy)
  }
}
