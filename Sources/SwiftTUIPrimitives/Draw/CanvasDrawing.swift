/// A type that can draw itself into a ``CanvasContext``.
///
/// Conformers implement ``draw(into:)``, which mutates the context's
/// configurable cell-space drawing grid via the context's public drawing
/// methods. ``CanvasDrawing`` supplies a drawing path in addition to the `Shape` protocol.
/// Use it for content that does not fit the shape fill and stroke model.
/// Examples include sparklines, plots, hand-drawn meters, and arbitrary curves.
///
/// Conformance requires `Sendable`, so drawings can cross isolation boundaries.
/// These boundaries occur between the view tree, layout, and rasterizer passes.
/// Conformance also requires `Equatable`.
/// Thus, canvas views with structurally identical drawings compare equal in the draw tree.
/// The renderer can reuse this work across renders. Most drawings are small value types where
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
  /// coordinates are continuous terminal cells. See ``CanvasContext`` for
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
/// cells vertically. ``CanvasGrid`` decides how those fractional cell
/// locations pack back into terminal glyphs. Out-of-range samples are
/// silently clipped.
///
/// A context also carries the default ``foreground`` and ``background``
/// colors that the rasterizer writes for every lit cell the drawing touches.
/// Until ``foreground`` is assigned, the inherited foreground style is sampled
/// at each cell, preserving gradients. Assigning it applies its final color
/// to every unstyled grid cell and direct glyph without an explicit foreground.
/// The rasterizer reads the final ``background`` after drawing returns.
public struct CanvasContext: Sendable {
  /// The terminal-cell size of the drawing surface.
  public let size: CellSize

  /// The grid used to pack in-cell drawing samples into terminal glyphs.
  public let grid: CanvasGrid

  /// The grid-sample extent of the drawing surface.
  ///
  /// This is ``size`` scaled by the active ``CanvasGrid``'s subdivisions, the
  /// valid range for ``GridSample`` coordinates. Authored drawings normally
  /// work in continuous cell space with ``size`` and the ``Point`` APIs.
  /// Use `gridSize` only to address individual samples through ``GridSample``.
  public var gridSize: GridSize {
    GridSize(width: gridWidth, height: gridHeight)
  }

  /// The grid-sample width of the drawing surface.
  package let gridWidth: Int

  /// The grid-sample height of the drawing surface.
  package let gridHeight: Int

  /// The default foreground color written to every cell the drawing
  /// touches. Starts as the environment's resolved foreground color.
  public var foreground: Color {
    didSet { foregroundWasAssigned = true }
  }

  /// Preserve inherited spatial styles unless the drawing explicitly writes
  /// its final foreground (even if that color equals the initial sample).
  package private(set) var foregroundWasAssigned = false

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
    self.gridWidth = canvas.pixelWidth
    self.gridHeight = canvas.pixelHeight
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
  public func gridSample(for location: Point) -> GridSample {
    GridSample(
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
  public func gridSample(for pointer: PointerLocation) -> GridSample {
    gridSample(for: pointer.location)
  }

  /// Sets the grid sample containing `location`.
  public mutating func setPixel(at location: Point) {
    let point = gridSample(for: location)
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
    let point = gridSample(for: location)
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
    let point = gridSample(for: location)
    canvas.clearPixel(x: point.x, y: point.y)
  }

  /// Draws a line between two continuous cell-space points.
  ///
  /// A line with a non-finite endpoint draws nothing. Only the part of the
  /// line inside the canvas is rasterized, so its cost is bounded by the
  /// canvas however far the endpoints lie.
  public mutating func line(
    from start: Point,
    to end: Point
  ) {
    guard let segment = SegmentClipping.clipped(from: start, to: end, within: Self.lineLimit)
    else { return }
    let startPoint = gridSample(for: segment.start)
    let endPoint = gridSample(for: segment.end)
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
  ///
  /// A non-finite center or radius draws nothing.
  public mutating func strokeCircle(
    center: Point,
    radius: Double
  ) {
    guard center.x.isFinite, center.y.isFinite, radius.isFinite else { return }
    let centerPoint = gridSample(for: center)
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
    fillEllipse(center: center, radiusX: radius, radiusY: radius)
  }

  /// Draws the outline of an ellipse in continuous cell space.
  ///
  /// A non-finite center or radius draws nothing.
  public mutating func strokeEllipse(
    center: Point,
    radiusX: Double,
    radiusY: Double
  ) {
    guard center.x.isFinite, center.y.isFinite, radiusX.isFinite, radiusY.isFinite else {
      return
    }
    let centerPoint = gridSample(for: center)
    canvas.strokeEllipse(
      centerX: centerPoint.x,
      centerY: centerPoint.y,
      radiusX: Self.gridRadius(radiusX, subdivisions: grid.subdivisionsX),
      radiusY: Self.gridRadius(radiusY, subdivisions: grid.subdivisionsY)
    )
  }

  /// Fills an ellipse in continuous cell space.
  ///
  /// A non-finite center or radius draws nothing.
  public mutating func fillEllipse(
    center: Point,
    radiusX: Double,
    radiusY: Double
  ) {
    let rx = abs(radiusX)
    let ry = abs(radiusY)
    guard center.x.isFinite, center.y.isFinite, rx.isFinite, ry.isFinite,
      gridWidth > 0, gridHeight > 0
    else { return }
    if rx == 0 || ry == 0 {
      let point = gridSample(for: center)
      canvas.fillEllipse(
        centerX: point.x, centerY: point.y,
        radiusX: Self.gridRadius(rx, subdivisions: grid.subdivisionsX),
        radiusY: Self.gridRadius(ry, subdivisions: grid.subdivisionsY))
      return
    }
    // Keep continuous geometry until sampling. Quantizing the center and
    // radii separately can enlarge a disc into a neighbouring cell.
    let x0 = max(
      0, Self.gridCoordinate(center.x - rx, subdivisions: grid.subdivisionsX, rounding: .down))
    let x1 = min(
      gridWidth - 1,
      Self.gridCoordinate(center.x + rx, subdivisions: grid.subdivisionsX, rounding: .up))
    let y0 = max(
      0, Self.gridCoordinate(center.y - ry, subdivisions: grid.subdivisionsY, rounding: .down))
    let y1 = min(
      gridHeight - 1,
      Self.gridCoordinate(center.y + ry, subdivisions: grid.subdivisionsY, rounding: .up))
    guard x0 <= x1, y0 <= y1 else { return }
    for y in y0...y1 {
      let dy = (Double(y) / Double(grid.subdivisionsY) - center.y) / ry
      for x in x0...x1 {
        let dx = (Double(x) / Double(grid.subdivisionsX) - center.x) / rx
        if dx * dx + dy * dy <= 1 { canvas.setPixel(x: x, y: y) }
      }
    }
  }

  /// Lights a single grid sample. Out-of-range coordinates are silently
  /// clipped.
  ///
  /// Grid samples are discrete sub-cell coordinates in the active
  /// ``CanvasGrid`` (for example, the 2×4 Braille dots inside one terminal
  /// cell). This is the escape hatch for drawings that already work in sample
  /// coordinates. For continuous, resolution-independent drawing, use ``setPixel(at:)`` with a ``Point``.
  /// Map a ``Point`` to the sample
  /// containing it with ``gridSample(for:)-(Point)``.
  public mutating func setSample(_ sample: GridSample) {
    canvas.setPixel(x: sample.x, y: sample.y)
  }

  /// Clears a single grid sample.
  public mutating func clearSample(_ sample: GridSample) {
    canvas.clearPixel(x: sample.x, y: sample.y)
  }

  /// Writes one terminal cell directly.
  ///
  /// Direct cell writes are painted before Braille writes, so Braille output
  /// can overlay a dense cell background while preserving that background.
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
    _ color: Color,
    at location: CellPoint
  ) {
    setCell(CanvasCell(background: color), at: location)
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
    guard x >= 0, x < gridWidth, y >= 0, y < gridHeight else {
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
    guard rect.size.width != 0, rect.size.height != 0,
      rect.origin.x.isFinite, rect.origin.y.isFinite, rect.maxX.isFinite, rect.maxY.isFinite
    else {
      return nil
    }
    let x0 = Self.gridCoordinate(
      min(rect.origin.x, rect.maxX),
      subdivisions: grid.subdivisionsX,
      rounding: .down
    )
    let y0 = Self.gridCoordinate(
      min(rect.origin.y, rect.maxY),
      subdivisions: grid.subdivisionsY,
      rounding: .down
    )
    let x1 = Self.gridCoordinate(
      max(rect.origin.x, rect.maxX),
      subdivisions: grid.subdivisionsX,
      rounding: .up
    )
    let y1 = Self.gridCoordinate(
      max(rect.origin.y, rect.maxY),
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

  /// Lines are clipped to this many cells from the origin before sampling,
  /// so their grid samples never saturate and keep the line's direction.
  private static let lineLimit = Double(Int.max / 16)

  /// Scales a cell coordinate to grid samples. NaN and values outside
  /// `±(Int.max / 2)` saturate (`SaturatingConversion`).
  private static func gridCoordinate(
    _ value: Double,
    subdivisions: Int,
    rounding: FloatingPointRoundingRule
  ) -> Int {
    SaturatingConversion.int(value * Double(subdivisions), rounding: rounding)
  }
}
