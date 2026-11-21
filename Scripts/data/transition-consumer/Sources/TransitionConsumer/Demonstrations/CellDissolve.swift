public import SwiftTUIViews

// Demonstration 4 of 6: a random-cell dissolve (STUI-1546).
//
// What it shows: the cells of the view appear one by one in an order that
// looks random and is fixed by a seed, and leave in the reverse order.
//
// What it proves: stage 4a inside stages 2 and 3, for an effect that is no
// morph at all. Each cell has a threshold, and the path of a frame holds the
// cells whose threshold is below that frame's `progress`.
//
// Known limits:
// - `path(in:)` gets the unit rectangle, so the shape cannot learn the size
//   of the frame in cells. The caller passes `columns` and `rows`. With
//   other numbers the grid is stretched and several cells share a threshold.
// - A clip that covers scattered cells is the costly case of the clip mask:
//   the rasterizer paints the clipped view once for each run of covered
//   cells (STUI-1559). `mergesRuns` only reduces the size of the path.
// - There is no `mask`, so the dissolve cannot fade a cell: it is drawn or
//   it is not.

/// The cells of a `columns` by `rows` grid whose threshold is below
/// `progress`. `progress` runs from 0 (nothing) to 1 (every cell).
public struct CellDissolveShape: Shape, Animatable {
  public var progress: Double
  public var columns: Int
  public var rows: Int
  public var seed: UInt64
  /// Whether adjacent cells of a row share one rectangle of the path. The
  /// covered cells are the same either way.
  public var mergesRuns: Bool

  public init(
    progress: Double, columns: Int, rows: Int, seed: UInt64 = 1, mergesRuns: Bool = true
  ) {
    self.progress = progress
    self.columns = columns
    self.rows = rows
    self.seed = seed
    self.mergesRuns = mergesRuns
  }

  public nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  /// The threshold of a cell, in 0..<1: the SplitMix64 output for the seed
  /// and the cell's index in reading order, scaled to the unit interval.
  public nonisolated static func threshold(
    column: Int, row: Int, columns: Int, seed: UInt64
  ) -> Double {
    let index = UInt64(truncatingIfNeeded: row &* columns &+ column)
    var value = seed &+ (index &+ 1) &* 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    value ^= value >> 31
    return Double(value >> 11) / 9_007_199_254_740_992
  }

  /// Whether the cell is drawn. A threshold is below 1 and not below 0, so
  /// a spring that takes `progress` outside 0...1 draws every cell or none.
  public nonisolated func covers(column: Int, row: Int) -> Bool {
    Self.threshold(column: column, row: row, columns: columns, seed: seed) < progress
  }

  public func path(in rect: Rect) -> Path {
    guard columns > 0, rows > 0 else {
      return Path()
    }
    let cellWidth = rect.size.width / Double(columns)
    let cellHeight = rect.size.height / Double(rows)
    return Path { path in
      for row in 0..<rows {
        var column = 0
        while column < columns {
          guard covers(column: column, row: row) else {
            column += 1
            continue
          }
          var end = column + 1
          if mergesRuns {
            while end < columns, covers(column: end, row: row) {
              end += 1
            }
          }
          path.addRect(
            Rect(
              origin: Point(
                x: rect.origin.x + Double(column) * cellWidth,
                y: rect.origin.y + Double(row) * cellHeight),
              size: Size(width: Double(end - column) * cellWidth, height: cellHeight)))
          column = end
        }
      }
    }
  }
}

/// A dissolve over the cells of a view that is `columns` by `rows` cells.
public struct CellDissolve: Transition {
  public var columns: Int
  public var rows: Int
  public var seed: UInt64
  public var mergesRuns: Bool

  public init(columns: Int, rows: Int, seed: UInt64 = 1, mergesRuns: Bool = true) {
    self.columns = columns
    self.rows = rows
    self.seed = seed
    self.mergesRuns = mergesRuns
  }

  public func body(content: Content, phase: TransitionPhase) -> some View {
    content.clipShape(
      CellDissolveShape(
        progress: phase.isIdentity ? 1 : 0, columns: columns, rows: rows, seed: seed,
        mergesRuns: mergesRuns))
  }
}
