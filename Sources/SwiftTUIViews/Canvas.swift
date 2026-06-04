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
///
/// ## Constructing a canvas
///
/// - ``init(_:grid:)`` takes a value-type ``CanvasDrawing``. This is the
///   preferred form: the drawing's `Equatable` conformance lets the framework
///   dedup identical canvases across re-renders.
/// - ``init(_:grid:_:)`` keys an ad-hoc drawing closure to an `Equatable`
///   input, keeping the dedup benefit without a dedicated drawing type.
/// - ``init(grid:_:)-(CanvasGrid,_)`` takes a bare drawing closure for quick,
///   throwaway drawing code. Its drawing compares by identity, so it
///   re-rasterizes on every re-render.
/// - ``pixelGrid(width:height:pixels:mode:)`` renders a dense, pre-resolved
///   `[Color?]` bitmap and applies the matching frame for you.
public struct Canvas<Drawing: CanvasDrawing>: PrimitiveView, ResolvableView {
  /// The drawing this canvas will rasterize at paint time.
  public let drawing: Drawing

  /// Grid used when rasterizing the drawing.
  public let grid: CanvasGrid

  /// Creates a canvas backed by a value-type drawing.
  ///
  /// - Parameters:
  ///   - drawing: The drawing rasterized at paint time. Its `Equatable`
  ///     conformance lets two canvases with structurally equal drawings dedup
  ///     across re-renders.
  ///   - grid: The grid used to pack in-cell samples into terminal glyphs.
  public init(
    _ drawing: Drawing,
    grid: CanvasGrid = .braille2x4
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
/// identical. Use ``CanvasInputDrawing`` (or a value type conforming to
/// ``CanvasDrawing``) when stable structural equality and renderer
/// deduplication matter.
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
  /// The closure is retained as a drawing value and compared by identity, so
  /// the canvas re-rasterizes on every re-render. Use ``init(_:grid:_:)`` to
  /// key the closure to an `Equatable` input, or a dedicated ``CanvasDrawing``
  /// value type, when dedup across re-renders matters.
  public init(
    grid: CanvasGrid = .braille2x4,
    _ draw: @escaping @Sendable (inout CanvasContext) -> Void
  ) {
    self.init(CanvasClosureDrawing(draw), grid: grid)
  }

  /// Creates a canvas from ad-hoc drawing code that also receives the surface
  /// size in terminal cells.
  ///
  /// A convenience for SwiftUI-shaped drawing code that expects the size
  /// alongside the context; equivalent to reading ``CanvasContext/size``. Like
  /// ``init(grid:_:)-(CanvasGrid,_)``, the drawing compares by identity.
  public init(
    grid: CanvasGrid = .braille2x4,
    _ draw: @escaping @Sendable (inout CanvasContext, CellSize) -> Void
  ) {
    self.init(grid: grid) { context in
      let size = context.size
      draw(&context, size)
    }
  }
}

/// Input-keyed closure-backed ``Canvas`` drawing.
///
/// Stores an ad-hoc drawing closure together with an `Equatable` `input`. Two
/// `CanvasInputDrawing` values compare equal when their inputs are equal,
/// regardless of closure identity — so a canvas built from one dedups across
/// re-renders while `input` is unchanged and repaints when it changes. This
/// gives closure ergonomics without the identity-equality penalty of
/// ``CanvasClosureDrawing``.
public struct CanvasInputDrawing<Input: Equatable & Sendable>: CanvasDrawing {
  /// The value the drawing is keyed to. Equality compares on this.
  public let input: Input
  private let storage: CanvasInputDrawingStorage<Input>

  public init(
    _ input: Input,
    _ draw: @escaping @Sendable (inout CanvasContext, Input) -> Void
  ) {
    self.input = input
    self.storage = CanvasInputDrawingStorage(draw: draw)
  }

  public func draw(into context: inout CanvasContext) {
    storage.draw(&context, input)
  }

  public static func == (lhs: CanvasInputDrawing, rhs: CanvasInputDrawing) -> Bool {
    lhs.input == rhs.input
  }
}

private final class CanvasInputDrawingStorage<Input>: Sendable {
  let draw: @Sendable (inout CanvasContext, Input) -> Void

  init(
    draw: @escaping @Sendable (inout CanvasContext, Input) -> Void
  ) {
    self.draw = draw
  }
}

extension Canvas {
  /// Creates a canvas from ad-hoc drawing code keyed to an `Equatable` input.
  ///
  /// Unlike ``init(grid:_:)-(CanvasGrid,_)`` — whose drawing compares by
  /// identity and re-rasterizes on every re-render — this form derives the
  /// drawing's identity from `input`. The canvas dedups across re-renders while
  /// `input` is unchanged and repaints when it changes. Prefer it whenever the
  /// drawing is a pure function of some state value.
  ///
  /// ```swift
  /// Canvas(samples) { context, samples in
  ///   // redraws only when `samples` changes
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - input: The value the drawing is a function of; drives equality.
  ///   - grid: The grid used to pack in-cell samples into terminal glyphs.
  ///   - draw: Drawing code receiving the context and `input`.
  public init<Input>(
    _ input: Input,
    grid: CanvasGrid = .braille2x4,
    _ draw: @escaping @Sendable (inout CanvasContext, Input) -> Void
  ) where Drawing == CanvasInputDrawing<Input> {
    self.init(CanvasInputDrawing(input, draw), grid: grid)
  }
}

extension Canvas where Drawing == CanvasPixelGridDrawing {
  /// Renders a dense pixel grid and applies the matching frame.
  ///
  /// Pixels are row-major and pre-resolved to terminal colors; `nil` pixels are
  /// transparent. The returned view is already sized to hold the grid: `(width,
  /// height)` cells in `.fullCell` mode, and `(width, mode.cellHeight(for:
  /// height))` cells in `.verticalHalfBlock` mode. Add further modifiers
  /// (`.border`, `.foregroundStyle`, …) by chaining onto the result.
  ///
  /// ```swift
  /// Canvas.pixelGrid(
  ///   width: art.width,
  ///   height: art.height,
  ///   pixels: art.pixels,
  ///   mode: .verticalHalfBlock
  /// )
  /// ```
  public static func pixelGrid(
    width: Int,
    height: Int,
    pixels: [Color?],
    mode: CanvasPixelGridMode = .fullCell
  ) -> some View {
    let drawing = CanvasPixelGridDrawing(
      width: width,
      height: height,
      pixels: pixels,
      mode: mode
    )
    return Canvas(drawing)
      .frame(
        width: drawing.width,
        height: mode.cellHeight(for: drawing.height)
      )
  }
}
