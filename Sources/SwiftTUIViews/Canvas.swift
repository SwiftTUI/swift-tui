@_spi(Testing) public import SwiftTUICore

/// A view that renders a user-provided drawing into a cell-space canvas sized
/// to its frame.
///
/// `Canvas` is the arbitrary-drawing escape hatch that sits alongside
/// the `Shape` protocol — reach for it when you need to draw a
/// sparkline, plot, hand-drawn meter, or arbitrary curve that doesn't
/// fit the shape fill/stroke algebra. The drawing conforms to
/// ``CanvasDrawing`` and is invoked at paint time with a
/// ``CanvasContext`` sized to the frame in terminal cells. The selected
/// ``CanvasGrid`` controls how fractional in-cell samples pack into terminal
/// glyphs.
///
/// ```swift
/// struct DiagonalLine: CanvasDrawing, Equatable {
///   func draw(into context: inout CanvasContext) {
///     let end = Point(
///       x: max(0, Double(context.size.width) - 0.25),
///       y: max(0, Double(context.size.height) - 0.125)
///     )
///     context.line(
///       from: .zero,
///       to: end
///     )
///   }
/// }
///
/// Canvas(DiagonalLine())
///   .frame(width: 40, height: 8)
///   .foregroundStyle(Color.green)
/// ```
public struct Canvas<Drawing: CanvasDrawing>: View, ResolvableView {
  /// The drawing this canvas will rasterize at paint time.
  public let drawing: Drawing

  /// Grid used when rasterizing the drawing.
  public let grid: CanvasGrid

  public init(
    grid: CanvasGrid = .braille2x4,
    _ drawing: Drawing
  ) {
    self.drawing = drawing
    self.grid = grid
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: "Canvas",
        semanticMetadata: .init(
          accessibilityRole: .image,
          accessibilityVisualContent: .init(kind: "Canvas")
        ),
        drawPayload: .canvas(CanvasPayload(drawing: drawing, grid: grid)),
        in: context
      )
    ]
  }
}

extension Canvas where Drawing == CanvasPixelGridDrawing {
  /// Creates a dense pixel grid backed by Canvas.
  ///
  /// Pixels are row-major and pre-resolved to terminal colors. `nil`
  /// pixels are transparent. In `.fullCell` mode the caller should size
  /// the view to `(width, height)` cells; in `.verticalHalfBlock` mode
  /// the caller should use `mode.cellHeight(for: height)` for the frame
  /// height.
  public init(
    pixelGridWidth width: Int,
    height: Int,
    pixels: [Color?],
    mode: CanvasPixelGridMode = .fullCell
  ) {
    self.init(
      CanvasPixelGridDrawing(
        width: width,
        height: height,
        pixels: pixels,
        mode: mode
      )
    )
  }
}
