/// A type that can draw itself into a ``CanvasContext``.
///
/// Conformers implement ``draw(into:)``, which mutates the context's
/// underlying Braille subpixel canvas via the context's public drawing
/// methods. ``CanvasDrawing`` is the escape hatch sitting alongside the
/// `Shape` protocol — use it when you need to render something that
/// doesn't fit the shape fill/stroke algebra (sparklines, plots,
/// hand-drawn meters, arbitrary curves).
///
/// Conformance requires both ``Sendable`` (so drawings can cross
/// isolation boundaries between the view tree, layout, and rasterizer
/// passes) and ``Equatable`` (so two canvas views carrying structurally
/// identical drawings compare equal in the draw tree and can dedup
/// across re-renders). Most drawings are small value types where
/// ``Equatable`` is synthesised automatically, for example:
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

/// A mutable drawing surface handed to a ``CanvasDrawing`` conformer.
///
/// Coordinates are in **Braille subpixels**. A terminal cell occupies a
/// 2×4 subpixel grid, so a canvas sized to `(width: W, height: H)` cells
/// exposes a subpixel range of `x ∈ [0, 2W)` and `y ∈ [0, 4H)`. The
/// context's drawing methods take subpixel coordinates and forward to
/// the underlying ``BrailleCanvas`` primitives. Out-of-range pixels are
/// silently clipped.
///
/// A context also carries the default ``foreground`` and ``background``
/// colours that the rasterizer writes for every lit cell the drawing
/// touches. The rasterizer reads the context's **final** values after
/// ``CanvasDrawing/draw(into:)`` returns, so mutating either colour
/// during drawing applies to every cell (not per-primitive).
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
  }

  /// Sets a single subpixel dot at `(x, y)`. Out-of-range coordinates
  /// are silently clipped.
  public mutating func setPixel(x: Int, y: Int) {
    canvas.setPixel(x: x, y: y)
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
