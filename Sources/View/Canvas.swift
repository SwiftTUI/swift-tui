public import Core
@_spi(Testing) import Core

/// A view that renders a user-provided drawing into a Braille subpixel
/// canvas sized to its frame.
///
/// `Canvas` is the arbitrary-drawing escape hatch that sits alongside
/// the `Shape` protocol — reach for it when you need to draw a
/// sparkline, plot, hand-drawn meter, or arbitrary curve that doesn't
/// fit the shape fill/stroke algebra. The drawing conforms to
/// ``CanvasDrawing`` and is invoked at paint time with a
/// ``CanvasContext`` sized to the frame in **Braille subpixels** (each
/// terminal cell is a 2×4 dot grid).
///
/// ```swift
/// struct DiagonalLine: CanvasDrawing, Equatable {
///   func draw(into context: inout CanvasContext) {
///     context.line(
///       from: (x: 0, y: 0),
///       to: (x: context.width - 1, y: context.height - 1)
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

  public init(_ drawing: Drawing) {
    self.drawing = drawing
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: "Canvas",
        drawPayload: .canvas(CanvasPayload(drawing: drawing)),
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
