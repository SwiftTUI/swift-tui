public struct PreformattedTextRun: Equatable, Sendable {
  public var content: String
  public var style: TextStyle

  public init(
    content: String,
    style: TextStyle = .init()
  ) {
    self.content = content
    self.style = style
  }
}

public struct PreformattedTextLine: Equatable, Sendable {
  public var runs: [PreformattedTextRun]

  public init(runs: [PreformattedTextRun]) {
    self.runs = Self.normalizedRuns(from: runs)
  }

  public var content: String {
    runs.map(\.content).joined()
  }

  private static func normalizedRuns(from runs: [PreformattedTextRun]) -> [PreformattedTextRun] {
    var normalized: [PreformattedTextRun] = []

    for run in runs where !run.content.isEmpty {
      if var previous = normalized.last, previous.style == run.style {
        previous.content += run.content
        normalized[normalized.count - 1] = previous
      } else {
        normalized.append(run)
      }
    }

    return normalized
  }
}

public indirect enum DrawCommand: Equatable, Sendable {
  case group(bounds: CellRect, children: [DrawCommand])
  case text(
    bounds: CellRect,
    content: String,
    style: TextStyle,
    lineLimit: Int?,
    truncationMode: TextTruncationMode,
    wrappingStrategy: TextWrappingStrategy
  )
  case preformattedText(
    bounds: CellRect,
    lines: [String],
    style: TextStyle
  )
  case styledPreformattedText(
    bounds: CellRect,
    lines: [PreformattedTextLine],
    style: TextStyle
  )
  case richText(
    bounds: CellRect,
    payload: RichTextPayload,
    lineLimit: Int?,
    truncationMode: TextTruncationMode,
    wrappingStrategy: TextWrappingStrategy
  )
  case image(bounds: CellRect, identity: Identity, payload: ImagePayload)
  case fill(
    bounds: CellRect,
    geometry: ShapeGeometry,
    insetAmount: Int,
    style: AnyShapeStyle,
    mode: ShapeFillMode
  )
  case stroke(
    bounds: CellRect,
    geometry: ShapeGeometry,
    insetAmount: Int,
    style: AnyShapeStyle,
    strokeStyle: StrokeStyle,
    strokeBorder: Bool,
    backgroundStyle: BorderBackgroundStyle? = nil
  )
  case rule(bounds: CellRect, style: AnyShapeStyle, strokeStyle: StrokeStyle, stackAxis: Axis?)
  /// A layout-reserved border drawn by the rasterizer into the cells
  /// that `LayoutBehavior.border(...)`
  /// reserved during layout.  The outer `bounds` is the full wrapper
  /// frame, including the reserved border rows/cols — the rasterizer
  /// inset this by the border set's per-side display widths to compute
  /// the interior (content) region that the border surrounds.
  ///
  /// When `blend` is non-nil the rasterizer ignores the per-side
  /// `foreground` and instead samples a color for every perimeter cell
  /// from ``BorderBlend/samplePerimeter(width:height:phase:)``, walking
  /// the cells clockwise.  `blendPhase` rotates the gradient start
  /// point around the perimeter for chasing-light animation.
  case border(
    bounds: CellRect,
    set: BorderSet,
    foreground: BorderEdgeStyle?,
    background: BorderBackgroundStyle?,
    blend: BorderBlend?,
    blendPhase: Double,
    sides: Edge.Set
  )
  /// A `Canvas` view's draw payload + the cell bounds the rasterizer
  /// should size a ``CanvasGrid`` buffer to before invoking the user's
  /// ``CanvasDrawing/draw(into:)``. The rasterizer resolves the
  /// `foregroundStyle` to a concrete ``Color`` at paint time and
  /// passes it to the ``CanvasContext`` as its initial foreground.
  case canvas(
    bounds: CellRect,
    payload: CanvasPayload,
    foregroundStyle: AnyShapeStyle
  )
  case clip(bounds: CellRect, child: DrawCommand)
}

/// A node in the draw tree emitted before rasterization.
public struct DrawNode: Equatable, Sendable {
  public var identity: Identity
  public var environmentSnapshot: EnvironmentSnapshot
  public var bounds: CellRect
  public var clipBounds: CellRect?
  package var metadata: DrawMetadata
  public var commands: [DrawCommand]
  /// Commands that must paint **after** this node's children have been
  /// fully painted.  Used by features that overdraw their children, such
  /// as inset-placement borders whose edge glyphs occupy the outermost
  /// cells of the child's frame and must therefore win the paint order
  /// against the child's own content.  Most nodes leave this empty.
  public var postCommands: [DrawCommand]
  public var children: [DrawNode] {
    didSet {
      recomputeSubtreeNodeCount()
    }
  }
  package private(set) var subtreeNodeCount: Int

  package init(
    identity: Identity,
    environmentSnapshot: EnvironmentSnapshot = .init(),
    bounds: CellRect,
    clipBounds: CellRect? = nil,
    metadata: DrawMetadata = .init(),
    commands: [DrawCommand] = [],
    postCommands: [DrawCommand] = [],
    children: [DrawNode] = []
  ) {
    self.identity = identity
    self.environmentSnapshot = environmentSnapshot
    self.bounds = bounds
    self.clipBounds = clipBounds
    self.metadata = metadata
    self.commands = commands
    self.postCommands = postCommands
    self.children = children
    subtreeNodeCount = 1
    recomputeSubtreeNodeCount()
  }

  private mutating func recomputeSubtreeNodeCount() {
    subtreeNodeCount = 1 + children.reduce(0) { $0 + $1.subtreeNodeCount }
  }
}
