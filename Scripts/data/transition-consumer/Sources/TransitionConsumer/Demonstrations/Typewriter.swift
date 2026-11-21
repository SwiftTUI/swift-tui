public import SwiftTUIViews

// Demonstration 5 of 6: a typewriter reveal (STUI-1546).
//
// What it shows: the cells of the view appear in reading order, a row at a
// time from the leading edge, and leave in the reverse order.
//
// What it proves: stage 4a inside stages 2 and 3, for a path that changes
// its outline in steps: a whole number of cells is drawn in every frame. It
// works on any content, because it clips the view and does not need its
// text.
//
// Known limits:
// - `path(in:)` gets the unit rectangle, so the shape cannot learn the size
//   of the frame in cells. The caller passes `columns` and `rows`.
// - It reveals cells and not characters: a cell with no glyph takes as long
//   as one with a glyph, and a wide glyph is drawn only when both of its
//   cells are revealed.
// - On removal the content is the view as it was last drawn, so the reveal
//   cannot type other text than the view had.

/// The first cells of a `columns` by `rows` grid in reading order.
/// `progress` runs from 0 (nothing) to 1 (every cell).
public struct TypewriterShape: Shape, Animatable {
  public var progress: Double
  public var columns: Int
  public var rows: Int

  public init(progress: Double, columns: Int, rows: Int) {
    self.progress = progress
    self.columns = columns
    self.rows = rows
  }

  public nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  /// How many cells are drawn. A spring takes `progress` outside 0...1; the
  /// count stays between none and all.
  public nonisolated var revealedCells: Int {
    let total = max(0, columns) * max(0, rows)
    return Int((min(1, max(0, progress)) * Double(total)).rounded())
  }

  public func path(in rect: Rect) -> Path {
    let revealed = revealedCells
    guard revealed > 0 else {
      return Path()
    }
    let fullRows = revealed / columns
    let rest = revealed % columns
    let rowHeight = rect.size.height / Double(rows)
    return Path { path in
      if fullRows > 0 {
        path.addRect(
          Rect(
            origin: rect.origin,
            size: Size(width: rect.size.width, height: Double(fullRows) * rowHeight)))
      }
      if rest > 0 {
        path.addRect(
          Rect(
            origin: Point(x: rect.origin.x, y: rect.origin.y + Double(fullRows) * rowHeight),
            size: Size(
              width: rect.size.width * Double(rest) / Double(columns), height: rowHeight)))
      }
    }
  }
}

/// A reveal in reading order over a view that is `columns` by `rows` cells.
public struct Typewriter: Transition {
  public var columns: Int
  public var rows: Int

  public init(columns: Int, rows: Int) {
    self.columns = columns
    self.rows = rows
  }

  public func body(content: Content, phase: TransitionPhase) -> some View {
    content.clipShape(
      TypewriterShape(progress: phase.isIdentity ? 1 : 0, columns: columns, rows: rows))
  }
}
