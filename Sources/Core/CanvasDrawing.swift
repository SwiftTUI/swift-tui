/// A type that can draw itself into a ``CanvasContext``.
///
/// Conformers implement ``draw(into:)``, which mutates the context's
/// underlying Braille subpixel canvas via the context's public drawing
/// methods. ``CanvasDrawing`` is the escape hatch sitting alongside the
/// `Shape` protocol — use it when you need to render something that
/// doesn't fit the shape fill/stroke algebra (sparklines, plots,
/// hand-drawn meters, arbitrary curves).
///
/// Conformance requires both `Sendable` (so drawings can cross
/// isolation boundaries between the view tree, layout, and rasterizer
/// passes) and `Equatable` (so two canvas views carrying structurally
/// identical drawings compare equal in the draw tree and can dedup
/// across re-renders). Most drawings are small value types where
/// `Equatable` is synthesised automatically, for example:
///
/// ```swift
/// struct Sparkline: CanvasDrawing, Equatable {
///   let values: [Double]
///   func draw(into context: inout CanvasContext) { ... }
/// }
/// ```
public protocol CanvasDrawing: Sendable, Equatable {
  /// Draws this drawing into the supplied context. Coordinates passed
  /// to the context's drawing methods are in Braille subpixels — see
  /// ``CanvasContext`` for the coordinate system.
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

/// Pixel-grid packing modes for ``CanvasPixelGridDrawing``.
public enum CanvasPixelGridMode: Equatable, Sendable {
  /// One logical pixel maps to one terminal cell background.
  case fullCell

  /// Two vertical logical pixels pack into one terminal cell with block
  /// glyphs. The top logical pixel maps to the foreground half and the
  /// bottom logical pixel maps to the background or lower-half glyph.
  case verticalHalfBlock

  /// The terminal-cell height needed to display `logicalHeight` pixels.
  public func cellHeight(for logicalHeight: Int) -> Int {
    switch self {
    case .fullCell:
      return max(0, logicalHeight)
    case .verticalHalfBlock:
      return max(0, (logicalHeight + 1) / 2)
    }
  }
}

/// A dense row-major pixel grid that renders through ``Canvas``.
///
/// The grid stores pre-resolved terminal colors. Callers with indexed
/// colors or transparency policies should resolve those choices before
/// constructing the drawing. `nil` pixels are transparent and leave the
/// destination cell/half-cell untouched.
public struct CanvasPixelGridDrawing: CanvasDrawing, Equatable {
  /// Logical pixel width.
  public var width: Int

  /// Logical pixel height.
  public var height: Int

  /// Row-major logical pixels. Missing entries are treated as transparent.
  public var pixels: [Color?]

  /// Rendering density mode.
  public var mode: CanvasPixelGridMode

  public init(
    width: Int,
    height: Int,
    pixels: [Color?],
    mode: CanvasPixelGridMode = .fullCell
  ) {
    self.width = max(0, width)
    self.height = max(0, height)
    self.pixels = pixels
    self.mode = mode
  }

  public func draw(into context: inout CanvasContext) {
    switch mode {
    case .fullCell:
      drawFullCells(into: &context)
    case .verticalHalfBlock:
      drawVerticalHalfBlocks(into: &context)
    }
  }

  private func drawFullCells(into context: inout CanvasContext) {
    guard width > 0, height > 0 else {
      return
    }

    for y in 0..<height {
      for x in 0..<width {
        guard let color = pixel(x: x, y: y) else {
          continue
        }
        context.fillCell(x: x, y: y, color: color)
      }
    }
  }

  private func drawVerticalHalfBlocks(into context: inout CanvasContext) {
    guard width > 0, height > 0 else {
      return
    }

    let cellHeight = mode.cellHeight(for: height)
    for cellY in 0..<cellHeight {
      let topY = cellY * 2
      let bottomY = topY + 1
      for x in 0..<width {
        let top = pixel(x: x, y: topY)
        let bottom = pixel(x: x, y: bottomY)

        switch (top, bottom) {
        case (nil, nil):
          continue
        case (let top?, let bottom?) where top == bottom:
          context.fillCell(x: x, y: cellY, color: top)
        case (let top?, let bottom?):
          context.setCell(
            x: x,
            y: cellY,
            character: "▀",
            foreground: top,
            background: bottom
          )
        case (let top?, nil):
          context.setCell(
            x: x,
            y: cellY,
            character: "▀",
            foreground: top
          )
        case (nil, let bottom?):
          context.setCell(
            x: x,
            y: cellY,
            character: "▄",
            foreground: bottom
          )
        }
      }
    }
  }

  private func pixel(x: Int, y: Int) -> Color? {
    guard x >= 0, x < width, y >= 0, y < height else {
      return nil
    }
    let index = y * width + x
    guard pixels.indices.contains(index) else {
      return nil
    }
    return pixels[index]
  }
}

/// A mutable drawing surface handed to a ``CanvasDrawing`` conformer.
///
/// Coordinates are in **Braille subpixels**. A terminal cell occupies a
/// 2×4 subpixel grid, so a canvas sized to `(width: W, height: H)` cells
/// exposes a subpixel range of `x ∈ [0, 2W)` and `y ∈ [0, 4H)`. The
/// context's Braille drawing methods take subpixel coordinates and
/// forward to the underlying ``BrailleCanvas`` primitives. Out-of-range
/// pixels are silently clipped.
///
/// A context also carries the default ``foreground`` and ``background``
/// colours that the rasterizer writes for every lit cell the drawing
/// touches. The rasterizer reads the context's **final** values after
/// ``CanvasDrawing/draw(into:)`` returns, so mutating either colour
/// during drawing applies to every unstyled Braille cell.
public struct CanvasContext: Sendable {
  /// The subpixel width of the drawing surface (cell width × 2).
  public let width: Int

  /// The subpixel height of the drawing surface (cell height × 4).
  public let height: Int

  /// The default foreground colour written to every cell the drawing
  /// touches. Starts as the environment's resolved foreground colour.
  public var foreground: Color

  /// Optional default background colour written to every cell the
  /// drawing touches. Starts `nil` (transparent).
  public var background: Color?

  package var canvas: BrailleCanvas
  package var brailleCellStyles: [[ResolvedTextStyle?]]
  package var directCells: [[CanvasCell?]]

  package init(
    canvas: BrailleCanvas,
    foreground: Color,
    background: Color?
  ) {
    self.canvas = canvas
    self.width = canvas.subpixelWidth
    self.height = canvas.subpixelHeight
    self.foreground = foreground
    self.background = background
    self.brailleCellStyles = Array(
      repeating: Array(repeating: nil, count: canvas.width),
      count: canvas.height
    )
    self.directCells = Array(
      repeating: Array(repeating: nil, count: canvas.width),
      count: canvas.height
    )
  }

  /// Sets a single subpixel dot at `(x, y)`. Out-of-range coordinates
  /// are silently clipped.
  public mutating func setPixel(x: Int, y: Int) {
    canvas.setPixel(x: x, y: y)
  }

  /// Sets a single subpixel dot with a per-cell style.
  ///
  /// Terminal Braille glyphs have one foreground and one background per
  /// terminal cell, not per dot. If multiple styled writes touch the
  /// same Braille cell, the last style wins for that whole cell.
  public mutating func setPixel(
    x: Int,
    y: Int,
    foreground: Color,
    background: Color? = nil
  ) {
    canvas.setPixel(x: x, y: y)
    setBrailleStyle(
      ResolvedTextStyle(
        foregroundColor: foreground,
        backgroundColor: background
      ),
      forSubpixelX: x,
      y: y
    )
  }

  /// Clears a single subpixel dot at `(x, y)`.
  public mutating func clearPixel(x: Int, y: Int) {
    canvas.clearPixel(x: x, y: y)
  }

  /// Draws a Bresenham line between two subpixel points.
  public mutating func line(
    from: (x: Int, y: Int),
    to: (x: Int, y: Int)
  ) {
    canvas.line(from: from, to: to)
  }

  /// Draws the outline of a rectangle in subpixels.
  public mutating func strokeRect(
    x: Int,
    y: Int,
    width: Int,
    height: Int
  ) {
    canvas.strokeRect(x: x, y: y, width: width, height: height)
  }

  /// Fills a rectangle in subpixels.
  public mutating func fillRect(
    x: Int,
    y: Int,
    width: Int,
    height: Int
  ) {
    canvas.fillRect(x: x, y: y, width: width, height: height)
  }

  /// Draws the outline of a circle with the given subpixel radius.
  public mutating func strokeCircle(
    centerX: Int,
    centerY: Int,
    radius: Int
  ) {
    canvas.strokeCircle(centerX: centerX, centerY: centerY, radius: radius)
  }

  /// Fills a disc with the given subpixel radius.
  public mutating func fillCircle(
    centerX: Int,
    centerY: Int,
    radius: Int
  ) {
    canvas.fillCircle(centerX: centerX, centerY: centerY, radius: radius)
  }

  /// Draws the outline of an ellipse in subpixels.
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

  /// Fills an ellipse in subpixels.
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
    guard directCells.indices.contains(y),
      directCells[y].indices.contains(x)
    else {
      return
    }
    directCells[y][x] = CanvasCell(
      character: character,
      foreground: foreground,
      background: background
    )
  }

  /// Fills one terminal cell with a background color.
  public mutating func fillCell(
    x: Int,
    y: Int,
    color: Color
  ) {
    setCell(x: x, y: y, background: color)
  }

  /// Removes any direct terminal-cell write at `(x, y)`.
  public mutating func clearCell(x: Int, y: Int) {
    guard directCells.indices.contains(y),
      directCells[y].indices.contains(x)
    else {
      return
    }
    directCells[y][x] = nil
  }

  private mutating func setBrailleStyle(
    _ style: ResolvedTextStyle,
    forSubpixelX x: Int,
    y: Int
  ) {
    guard x >= 0, x < width, y >= 0, y < height else {
      return
    }
    let cellX = x / 2
    let cellY = y / 4
    guard brailleCellStyles.indices.contains(cellY),
      brailleCellStyles[cellY].indices.contains(cellX)
    else {
      return
    }
    brailleCellStyles[cellY][cellX] = style.isDefault ? nil : style
  }
}

/// The draw-tree payload that carries a type-erased ``CanvasDrawing``
/// through the pipeline. The layout engine reserves a cell frame for
/// the view, and the rasterizer instantiates a sized ``BrailleCanvas``
/// at paint time, calls ``CanvasDrawing/draw(into:)``, and emits the
/// resulting Braille glyphs into the raster buffer.
public struct CanvasPayload: Equatable, Sendable {
  /// The user-provided drawing, type-erased to the ``CanvasDrawing``
  /// existential.
  public var drawing: any CanvasDrawing

  public init(drawing: any CanvasDrawing) {
    self.drawing = drawing
  }

  public static func == (lhs: CanvasPayload, rhs: CanvasPayload) -> Bool {
    canvasDrawingsEqual(lhs.drawing, rhs.drawing)
  }
}

/// Compares two type-erased ``CanvasDrawing`` values. Two drawings of
/// the same concrete type compare equal iff their ``Equatable``
/// conformance says so; drawings of different concrete types always
/// compare unequal. The open-existential generic helper is required
/// because ``any CanvasDrawing`` is not itself ``Equatable`` — Swift's
/// "self-conforming" existential only works for a handful of standard
/// library protocols.
private func canvasDrawingsEqual(
  _ lhs: any CanvasDrawing,
  _ rhs: any CanvasDrawing
) -> Bool {
  func areEqual<T: CanvasDrawing>(_ a: T, _ b: any CanvasDrawing) -> Bool {
    guard let casted = b as? T else { return false }
    return a == casted
  }
  return areEqual(lhs, rhs)
}
