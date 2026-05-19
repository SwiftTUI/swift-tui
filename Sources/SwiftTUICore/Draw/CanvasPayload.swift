/// The draw-tree payload that carries a type-erased ``CanvasDrawing``
/// through the pipeline. The layout engine reserves a cell frame for the
/// view, and the rasterizer instantiates a sized ``CanvasGrid`` buffer at
/// paint time, calls ``CanvasDrawing/draw(into:)``, and emits the resulting
/// glyphs into the raster buffer.
public struct CanvasPayload: Equatable, Sendable {
  /// The user-provided drawing, type-erased to the ``CanvasDrawing``
  /// existential.
  public var drawing: any CanvasDrawing

  /// Grid used when rasterizing the drawing.
  public var grid: CanvasGrid

  public init(
    drawing: any CanvasDrawing,
    grid: CanvasGrid = .braille2x4
  ) {
    self.drawing = drawing
    self.grid = grid
  }

  public static func == (lhs: CanvasPayload, rhs: CanvasPayload) -> Bool {
    lhs.grid == rhs.grid && canvasDrawingsEqual(lhs.drawing, rhs.drawing)
  }
}

/// Compares two type-erased ``CanvasDrawing`` values. Two drawings of
/// the same concrete type compare equal iff their ``Equatable``
/// conformance says so; drawings of different concrete types always
/// compare unequal. The open-existential generic helper is required
/// because ``any CanvasDrawing`` is not itself ``Equatable`` - Swift's
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
