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
public struct Canvas<Drawing: CanvasDrawing>: PrimitiveView, ResolvableView {
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

/// Closure-backed ``Canvas`` drawing.
///
/// Use this for ad-hoc drawing code where a dedicated ``CanvasDrawing`` value
/// type would be unnecessary. Equality is identity-based: copies of the same
/// `CanvasClosureDrawing` compare equal, while two separately-created closure
/// drawings compare different even if their closure bodies are textually
/// identical. Use a value type conforming to ``CanvasDrawing`` when stable
/// structural equality and renderer deduplication matter.
public struct CanvasClosureDrawing: CanvasDrawing {
  private let storage: CanvasClosureDrawingStorage

  public init(
    _ draw: @escaping @Sendable (inout CanvasContext) -> Void
  ) {
    storage = CanvasClosureDrawingStorage(draw: draw)
  }

  public func draw(into context: inout CanvasContext) {
    storage.draw(&context)
  }

  public static func == (lhs: CanvasClosureDrawing, rhs: CanvasClosureDrawing) -> Bool {
    lhs.storage === rhs.storage
  }
}

private final class CanvasClosureDrawingStorage: Sendable {
  let draw: @Sendable (inout CanvasContext) -> Void

  init(
    draw: @escaping @Sendable (inout CanvasContext) -> Void
  ) {
    self.draw = draw
  }
}

extension Canvas where Drawing == CanvasClosureDrawing {
  /// Creates a canvas from ad-hoc drawing code.
  ///
  /// The closure is retained as a drawing value and compared by identity. Use a
  /// dedicated ``CanvasDrawing`` value type for drawings that should compare
  /// structurally equal across rerenders.
  public init(
    grid: CanvasGrid = .braille2x4,
    _ draw: @escaping @Sendable (inout CanvasContext) -> Void
  ) {
    self.init(
      grid: grid,
      CanvasClosureDrawing(draw)
    )
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
