/// A type that can draw itself into a ``CanvasContext``.
///
/// Conformers implement ``draw(into:)``, which mutates the context's
/// configurable cell-space drawing grid via the context's public drawing
/// methods. ``CanvasDrawing`` is the escape hatch sitting alongside the
/// `Shape` protocol — use it when you need to render something that doesn't
/// fit the shape fill/stroke algebra (sparklines, plots, hand-drawn meters,
/// arbitrary curves).
///
/// Conformance requires both `Sendable` (so drawings can cross
/// isolation boundaries between the view tree, layout, and rasterizer
/// passes) and `Equatable` (so two canvas views carrying structurally
/// identical drawings compare equal in the draw tree and can dedup
/// across re-renders). Most drawings are small value types where
/// `Equatable` is synthesized automatically, for example:
///
/// ```swift
/// struct Sparkline: CanvasDrawing, Equatable {
///   let values: [Double]
///   func draw(into context: inout CanvasContext) { ... }
/// }
/// ```
public protocol CanvasDrawing: Sendable, Equatable {
  /// Draws this drawing into the supplied context. Primary drawing
  /// coordinates are continuous terminal cells — see ``CanvasContext`` for
  /// the coordinate system.
  func draw(into context: inout CanvasContext)
}

/// A single terminal-cell write emitted by a ``CanvasDrawing``.
///
/// `CanvasCell` is cell-denominated, unlike the Braille drawing methods
/// on ``CanvasContext``. It exists for dense terminal-cell rendering
/// where each cell needs its own style, such as pixel editors, heatmaps,
/// and terminal-native previews.
public struct CanvasCell: Equatable, Sendable {
  /// The glyph written into the terminal cell.
  public var character: Character

  /// Optional foreground color for the glyph.
  public var foreground: Color?

  /// Optional background color for the cell.
  public var background: Color?

  public init(
    character: Character = " ",
    foreground: Color? = nil,
    background: Color? = nil
  ) {
    self.character = character
    self.foreground = foreground
    self.background = background
  }
}

/// A mutable drawing surface handed to a ``CanvasDrawing`` conformer.
///
/// Coordinates are in continuous terminal cell space. A line from
/// `(0, 0)` to `(10, 1.5)` spans ten cells horizontally and one and a half
/// cells vertically; ``CanvasGrid`` decides how those fractional cell
/// locations pack back into terminal glyphs. Out-of-range samples are
/// silently clipped.
///
/// A context also carries the default ``foreground`` and ``background``
/// colors that the rasterizer writes for every lit cell the drawing
/// touches. The rasterizer reads the context's **final** values after
/// ``CanvasDrawing/draw(into:)`` returns, so mutating either color
/// during drawing applies to every unstyled grid cell.
public struct CanvasContext: Sendable {
  /// The terminal-cell size of the drawing surface.
  public let size: CellSize

  /// The grid used to pack in-cell drawing samples into terminal glyphs.
  public let grid: CanvasGrid

  /// The grid-sample width of the drawing surface.
  ///
  /// This is retained while existing drawings migrate from integer grid
  /// coordinates to primary cell-space APIs.
  public let width: Int

  /// The grid-sample height of the drawing surface.
  ///
  /// This is retained while existing drawings migrate from integer grid
  /// coordinates to primary cell-space APIs.
  public let height: Int

  /// The default foreground color written to every cell the drawing
  /// touches. Starts as the environment's resolved foreground color.
  public var foreground: Color

  /// Optional default background color written to every cell the
  /// drawing touches. Starts `nil` (transparent).
  public var background: Color?

  package var canvas: CanvasGridBuffer
  package var gridCellStyles: [[ResolvedTextStyle?]]
  package var directCells: [[CanvasCell?]]

  package init(
    canvas: CanvasGridBuffer,
    foreground: Color,
    background: Color?
  ) {
    self.canvas = canvas
    self.size = canvas.size
    self.grid = canvas.grid
    self.width = canvas.pixelWidth
    self.height = canvas.pixelHeight
    self.foreground = foreground
    self.background = background
    self.gridCellStyles = Array(
      repeating: Array(repeating: nil, count: canvas.size.width),
      count: canvas.size.height
    )
    self.directCells = Array(
      repeating: Array(repeating: nil, count: canvas.size.width),
      count: canvas.size.height
    )
  }

  /// Maps a continuous cell-space location to the active grid sample.
  public func gridPoint(for location: Point) -> CellPoint {
    CellPoint(
      x: Self.gridCoordinate(
        location.x,
        subdivisions: grid.subdivisionsX,
        rounding: .down
      ),
      y: Self.gridCoordinate(
        location.y,
        subdivisions: grid.subdivisionsY,
        rounding: .down
      )
    )
  }

  /// Maps a pointer event location to the active grid sample.
  public func gridPoint(for pointer: PointerLocation) -> CellPoint {
    gridPoint(for: pointer.location)
  }

  /// Sets the grid sample containing `location`.
  public mutating func setPixel(at location: Point) {
    let point = gridPoint(for: location)
    canvas.setPixel(x: point.x, y: point.y)
  }

  /// Sets the grid sample containing `location` with a per-cell style.
  ///
  /// Terminal glyphs have one foreground and one background per terminal cell,
  /// not per grid sample. If multiple styled writes touch the same terminal
  /// cell, the last style wins for that whole cell.
  public mutating func setPixel(
    at location: Point,
    foreground: Color,
    background: Color? = nil
  ) {
    let point = gridPoint(for: location)
    canvas.setPixel(x: point.x, y: point.y)
    setGridStyle(
      ResolvedTextStyle(
        foregroundColor: foreground,
        backgroundColor: background
      ),
      forGridX: point.x,
      y: point.y
    )
  }

  /// Clears the grid sample containing `location`.
  public mutating func clearPixel(at location: Point) {
    let point = gridPoint(for: location)
    canvas.clearPixel(x: point.x, y: point.y)
  }

  /// Draws a line between two continuous cell-space points.
  public mutating func line(
    from start: Point,
    to end: Point
  ) {
    let startPoint = gridPoint(for: start)
    let endPoint = gridPoint(for: end)
    canvas.line(
      from: (x: startPoint.x, y: startPoint.y),
      to: (x: endPoint.x, y: endPoint.y)
    )
  }

  /// Draws the outline of a continuous cell-space rectangle.
  public mutating func strokeRect(_ rect: Rect) {
    guard let rect = gridRect(for: rect) else {
      return
    }
    canvas.strokeRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
  }

  /// Fills a continuous cell-space rectangle.
  public mutating func fillRect(_ rect: Rect) {
    guard let rect = gridRect(for: rect) else {
      return
    }
    canvas.fillRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
  }

  /// Draws the outline of a circle in continuous cell space.
  public mutating func strokeCircle(
    center: Point,
    radius: Double
  ) {
    let centerPoint = gridPoint(for: center)
    canvas.strokeEllipse(
      centerX: centerPoint.x,
      centerY: centerPoint.y,
      radiusX: Self.gridRadius(radius, subdivisions: grid.subdivisionsX),
      radiusY: Self.gridRadius(radius, subdivisions: grid.subdivisionsY)
    )
  }

  /// Fills a disc in continuous cell space.
  public mutating func fillCircle(
    center: Point,
    radius: Double
  ) {
    let centerPoint = gridPoint(for: center)
    canvas.fillEllipse(
      centerX: centerPoint.x,
      centerY: centerPoint.y,
      radiusX: Self.gridRadius(radius, subdivisions: grid.subdivisionsX),
      radiusY: Self.gridRadius(radius, subdivisions: grid.subdivisionsY)
    )
  }

  /// Draws the outline of an ellipse in continuous cell space.
  public mutating func strokeEllipse(
    center: Point,
    radiusX: Double,
    radiusY: Double
  ) {
    let centerPoint = gridPoint(for: center)
    canvas.strokeEllipse(
      centerX: centerPoint.x,
      centerY: centerPoint.y,
      radiusX: Self.gridRadius(radiusX, subdivisions: grid.subdivisionsX),
      radiusY: Self.gridRadius(radiusY, subdivisions: grid.subdivisionsY)
    )
  }

  /// Fills an ellipse in continuous cell space.
  public mutating func fillEllipse(
    center: Point,
    radiusX: Double,
    radiusY: Double
  ) {
    let centerPoint = gridPoint(for: center)
    canvas.fillEllipse(
      centerX: centerPoint.x,
      centerY: centerPoint.y,
      radiusX: Self.gridRadius(radiusX, subdivisions: grid.subdivisionsX),
      radiusY: Self.gridRadius(radiusY, subdivisions: grid.subdivisionsY)
    )
  }

  /// Sets a single grid sample at `(x, y)`. Out-of-range coordinates are
  /// silently clipped.
  public mutating func setPixel(x: Int, y: Int) {
    canvas.setPixel(x: x, y: y)
  }

  /// Sets a single grid sample with a per-cell style.
  ///
  /// Terminal glyphs have one foreground and one background per terminal
  /// cell, not per grid sample. If multiple styled writes touch the same
  /// terminal cell, the last style wins for that whole cell.
  public mutating func setPixel(
    x: Int,
    y: Int,
    foreground: Color,
    background: Color? = nil
  ) {
    canvas.setPixel(x: x, y: y)
    setGridStyle(
      ResolvedTextStyle(
        foregroundColor: foreground,
        backgroundColor: background
      ),
      forGridX: x,
      y: y
    )
  }

  /// Clears a single grid sample at `(x, y)`.
  public mutating func clearPixel(x: Int, y: Int) {
    canvas.clearPixel(x: x, y: y)
  }

  /// Draws a Bresenham line between two grid-sample points.
  public mutating func line(
    from: (x: Int, y: Int),
    to: (x: Int, y: Int)
  ) {
    canvas.line(from: from, to: to)
  }

  /// Draws the outline of a rectangle in grid samples.
  public mutating func strokeRect(
    x: Int,
    y: Int,
    width: Int,
    height: Int
  ) {
    canvas.strokeRect(x: x, y: y, width: width, height: height)
  }

  /// Fills a rectangle in grid samples.
  public mutating func fillRect(
    x: Int,
    y: Int,
    width: Int,
    height: Int
  ) {
    canvas.fillRect(x: x, y: y, width: width, height: height)
  }

  /// Draws the outline of a circle with the given grid-sample radius.
  public mutating func strokeCircle(
    centerX: Int,
    centerY: Int,
    radius: Int
  ) {
    canvas.strokeCircle(centerX: centerX, centerY: centerY, radius: radius)
  }

  /// Fills a disc with the given grid-sample radius.
  public mutating func fillCircle(
    centerX: Int,
    centerY: Int,
    radius: Int
  ) {
    canvas.fillCircle(centerX: centerX, centerY: centerY, radius: radius)
  }

  /// Draws the outline of an ellipse in grid samples.
  public mutating func strokeEllipse(
    centerX: Int,
    centerY: Int,
    radiusX: Int,
    radiusY: Int
  ) {
    canvas.strokeEllipse(
      centerX: centerX,
      centerY: centerY,
      radiusX: radiusX,
      radiusY: radiusY
    )
  }

  /// Fills an ellipse in grid samples.
  public mutating func fillEllipse(
    centerX: Int,
    centerY: Int,
    radiusX: Int,
    radiusY: Int
  ) {
    canvas.fillEllipse(
      centerX: centerX,
      centerY: centerY,
      radiusX: radiusX,
      radiusY: radiusY
    )
  }

  /// Writes one terminal cell directly.
  ///
  /// Coordinates are in terminal cells, not Braille subpixels. Direct
  /// cell writes are painted before Braille writes, so Braille output can
  /// overlay a dense cell background while preserving that background.
  public mutating func setCell(
    x: Int,
    y: Int,
    character: Character = " ",
    foreground: Color? = nil,
    background: Color? = nil
  ) {
    setCell(
      CanvasCell(
        character: character,
        foreground: foreground,
        background: background
      ),
      at: CellPoint(x: x, y: y)
    )
  }

  /// Writes one terminal cell directly.
  public mutating func setCell(
    _ cell: CanvasCell,
    at location: CellPoint
  ) {
    guard directCells.indices.contains(location.y),
      directCells[location.y].indices.contains(location.x)
    else {
      return
    }
    directCells[location.y][location.x] = cell
  }

  /// Writes one terminal cell directly.
  public mutating func setCell(
    at location: CellPoint,
    character: Character = " ",
    foreground: Color? = nil,
    background: Color? = nil
  ) {
    setCell(
      CanvasCell(
        character: character,
        foreground: foreground,
        background: background
      ),
      at: location
    )
  }

  /// Fills one terminal cell with a background color.
  public mutating func fillCell(
    x: Int,
    y: Int,
    color: Color
  ) {
    fillCell(color, at: CellPoint(x: x, y: y))
  }

  /// Fills one terminal cell with a background color.
  public mutating func fillCell(
    _ color: Color,
    at location: CellPoint
  ) {
    setCell(CanvasCell(background: color), at: location)
  }

  /// Removes any direct terminal-cell write at `(x, y)`.
  public mutating func clearCell(x: Int, y: Int) {
    clearCell(at: CellPoint(x: x, y: y))
  }

  /// Removes any direct terminal-cell write at `location`.
  public mutating func clearCell(at location: CellPoint) {
    guard directCells.indices.contains(location.y),
      directCells[location.y].indices.contains(location.x)
    else {
      return
    }
    directCells[location.y][location.x] = nil
  }

  private mutating func setGridStyle(
    _ style: ResolvedTextStyle,
    forGridX x: Int,
    y: Int
  ) {
    guard x >= 0, x < width, y >= 0, y < height else {
      return
    }
    let cellX = x / grid.subdivisionsX
    let cellY = y / grid.subdivisionsY
    guard gridCellStyles.indices.contains(cellY),
      gridCellStyles[cellY].indices.contains(cellX)
    else {
      return
    }
    gridCellStyles[cellY][cellX] = style.isDefault ? nil : style
  }

  private func gridRect(
    for rect: Rect
  ) -> (x: Int, y: Int, width: Int, height: Int)? {
    guard rect.size.width > 0, rect.size.height > 0 else {
      return nil
    }
    let x0 = Self.gridCoordinate(
      rect.origin.x,
      subdivisions: grid.subdivisionsX,
      rounding: .down
    )
    let y0 = Self.gridCoordinate(
      rect.origin.y,
      subdivisions: grid.subdivisionsY,
      rounding: .down
    )
    let x1 = Self.gridCoordinate(
      rect.maxX,
      subdivisions: grid.subdivisionsX,
      rounding: .up
    )
    let y1 = Self.gridCoordinate(
      rect.maxY,
      subdivisions: grid.subdivisionsY,
      rounding: .up
    )
    guard x1 > x0, y1 > y0 else {
      return nil
    }
    return (x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  private static func gridRadius(
    _ radius: Double,
    subdivisions: Int
  ) -> Int {
    guard radius > 0 else {
      return 0
    }
    return max(
      0,
      gridCoordinate(
        radius,
        subdivisions: subdivisions,
        rounding: .toNearestOrAwayFromZero
      )
    )
  }

  private static func gridCoordinate(
    _ value: Double,
    subdivisions: Int,
    rounding: FloatingPointRoundingRule
  ) -> Int {
    let scaled = value * Double(subdivisions)
    guard scaled.isFinite else {
      if scaled.isNaN {
        return Int.min / 2
      }
      return scaled.sign == .minus ? Int.min / 2 : Int.max / 2
    }
    let rounded = scaled.rounded(rounding)
    let lower = Double(Int.min / 2)
    let upper = Double(Int.max / 2)
    if rounded <= lower {
      return Int.min / 2
    }
    if rounded >= upper {
      return Int.max / 2
    }
    return Int(rounded)
  }
}
