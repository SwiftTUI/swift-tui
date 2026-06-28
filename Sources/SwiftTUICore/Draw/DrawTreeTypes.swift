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
  case foreignSurface(bounds: CellRect, payload: any ForeignSurfacePayload)
  case clip(bounds: CellRect, child: DrawCommand)
}

extension DrawCommand {
  public static func == (lhs: DrawCommand, rhs: DrawCommand) -> Bool {
    switch (lhs, rhs) {
    case (.group(let lhsBounds, let lhsChildren), .group(let rhsBounds, let rhsChildren)):
      return lhsBounds == rhsBounds && lhsChildren == rhsChildren
    case (
      .text(
        let lhsBounds,
        let lhsContent,
        let lhsStyle,
        let lhsLineLimit,
        let lhsTruncationMode,
        let lhsWrappingStrategy
      ),
      .text(
        let rhsBounds,
        let rhsContent,
        let rhsStyle,
        let rhsLineLimit,
        let rhsTruncationMode,
        let rhsWrappingStrategy
      )
    ):
      return lhsBounds == rhsBounds
        && lhsContent == rhsContent
        && lhsStyle == rhsStyle
        && lhsLineLimit == rhsLineLimit
        && lhsTruncationMode == rhsTruncationMode
        && lhsWrappingStrategy == rhsWrappingStrategy
    case (
      .preformattedText(let lhsBounds, let lhsLines, let lhsStyle),
      .preformattedText(let rhsBounds, let rhsLines, let rhsStyle)
    ):
      return lhsBounds == rhsBounds && lhsLines == rhsLines && lhsStyle == rhsStyle
    case (
      .styledPreformattedText(let lhsBounds, let lhsLines, let lhsStyle),
      .styledPreformattedText(let rhsBounds, let rhsLines, let rhsStyle)
    ):
      return lhsBounds == rhsBounds && lhsLines == rhsLines && lhsStyle == rhsStyle
    case (
      .richText(
        let lhsBounds,
        let lhsPayload,
        let lhsLineLimit,
        let lhsTruncationMode,
        let lhsWrappingStrategy
      ),
      .richText(
        let rhsBounds,
        let rhsPayload,
        let rhsLineLimit,
        let rhsTruncationMode,
        let rhsWrappingStrategy
      )
    ):
      return lhsBounds == rhsBounds
        && lhsPayload == rhsPayload
        && lhsLineLimit == rhsLineLimit
        && lhsTruncationMode == rhsTruncationMode
        && lhsWrappingStrategy == rhsWrappingStrategy
    case (
      .image(let lhsBounds, let lhsIdentity, let lhsPayload),
      .image(let rhsBounds, let rhsIdentity, let rhsPayload)
    ):
      return lhsBounds == rhsBounds && lhsIdentity == rhsIdentity && lhsPayload == rhsPayload
    case (
      .fill(let lhsBounds, let lhsGeometry, let lhsInsetAmount, let lhsStyle, let lhsMode),
      .fill(let rhsBounds, let rhsGeometry, let rhsInsetAmount, let rhsStyle, let rhsMode)
    ):
      return lhsBounds == rhsBounds
        && lhsGeometry == rhsGeometry
        && lhsInsetAmount == rhsInsetAmount
        && lhsStyle == rhsStyle
        && lhsMode == rhsMode
    case (
      .stroke(
        let lhsBounds,
        let lhsGeometry,
        let lhsInsetAmount,
        let lhsStyle,
        let lhsStrokeStyle,
        let lhsStrokeBorder,
        let lhsBackgroundStyle
      ),
      .stroke(
        let rhsBounds,
        let rhsGeometry,
        let rhsInsetAmount,
        let rhsStyle,
        let rhsStrokeStyle,
        let rhsStrokeBorder,
        let rhsBackgroundStyle
      )
    ):
      return lhsBounds == rhsBounds
        && lhsGeometry == rhsGeometry
        && lhsInsetAmount == rhsInsetAmount
        && lhsStyle == rhsStyle
        && lhsStrokeStyle == rhsStrokeStyle
        && lhsStrokeBorder == rhsStrokeBorder
        && lhsBackgroundStyle == rhsBackgroundStyle
    case (
      .rule(let lhsBounds, let lhsStyle, let lhsStrokeStyle, let lhsStackAxis),
      .rule(let rhsBounds, let rhsStyle, let rhsStrokeStyle, let rhsStackAxis)
    ):
      return lhsBounds == rhsBounds
        && lhsStyle == rhsStyle
        && lhsStrokeStyle == rhsStrokeStyle
        && lhsStackAxis == rhsStackAxis
    case (
      .border(
        let lhsBounds,
        let lhsSet,
        let lhsForeground,
        let lhsBackground,
        let lhsBlend,
        let lhsBlendPhase,
        let lhsSides
      ),
      .border(
        let rhsBounds,
        let rhsSet,
        let rhsForeground,
        let rhsBackground,
        let rhsBlend,
        let rhsBlendPhase,
        let rhsSides
      )
    ):
      return lhsBounds == rhsBounds
        && lhsSet == rhsSet
        && lhsForeground == rhsForeground
        && lhsBackground == rhsBackground
        && lhsBlend == rhsBlend
        && lhsBlendPhase == rhsBlendPhase
        && lhsSides == rhsSides
    case (
      .canvas(let lhsBounds, let lhsPayload, let lhsForegroundStyle),
      .canvas(let rhsBounds, let rhsPayload, let rhsForegroundStyle)
    ):
      return lhsBounds == rhsBounds
        && lhsPayload == rhsPayload
        && lhsForegroundStyle == rhsForegroundStyle
    case (.foreignSurface(let lhsBounds, _), .foreignSurface(let rhsBounds, _)):
      return lhsBounds == rhsBounds
    case (.clip(let lhsBounds, let lhsChild), .clip(let rhsBounds, let rhsChild)):
      return lhsBounds == rhsBounds && lhsChild == rhsChild
    default:
      return false
    }
  }
}

/// A node in the draw tree emitted before rasterization.
///
/// Draw extraction owns lowered paint commands, post-child paint commands, and
/// the style/environment snapshots rasterization needs to paint those commands.
/// Geometry and resolved metadata are read from the current placed tree and
/// projected here; `DrawNode` is not a retained layout or semantic source of
/// truth.
package struct DrawNode: Equatable, Sendable {
  package var viewNodeID: ViewNodeID?
  package var identity: Identity
  package var environmentSnapshot: EnvironmentSnapshot
  package var bounds: CellRect
  package var clipBounds: CellRect?
  package var metadata: DrawMetadata
  package var drawEffects: DrawEffects
  package var commands: [DrawCommand]
  /// Commands that must paint **after** this node's children have been
  /// fully painted.  Used by features that overdraw their children, such
  /// as inset-placement borders whose edge glyphs occupy the outermost
  /// cells of the child's frame and must therefore win the paint order
  /// against the child's own content.  Most nodes leave this empty.
  package var postCommands: [DrawCommand]
  package var children: [DrawNode] {
    didSet {
      recomputeSubtreeAggregates()
    }
  }
  package private(set) var subtreeNodeCount: Int
  /// The absolute union of this node's `bounds` and every descendant's
  /// `subtreeBounds`. `.offset`/`.position` bake their translation into the
  /// *child's* absolute bounds (the wrapper keeps its own slot), so a node's own
  /// `bounds` is not a sound basis for the incremental-repaint row cull: a
  /// translated descendant can paint rows far outside its ancestor's slot. The
  /// cull must test this subtree extent instead. For normally-contained layouts
  /// children sit within the parent, so `subtreeBounds == bounds` and the cull is
  /// unchanged.
  package private(set) var subtreeBounds: CellRect

  package init(
    viewNodeID: ViewNodeID? = nil,
    identity: Identity,
    environmentSnapshot: EnvironmentSnapshot = .init(),
    bounds: CellRect,
    clipBounds: CellRect? = nil,
    metadata: DrawMetadata = .init(),
    drawEffects: DrawEffects = .init(),
    commands: [DrawCommand] = [],
    postCommands: [DrawCommand] = [],
    children: [DrawNode] = []
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    self.environmentSnapshot = environmentSnapshot
    self.bounds = bounds
    self.clipBounds = clipBounds
    self.metadata = metadata
    self.drawEffects = drawEffects
    self.commands = commands
    self.postCommands = postCommands
    self.children = children
    subtreeNodeCount = 1
    subtreeBounds = bounds
    recomputeSubtreeAggregates()
  }

  private mutating func recomputeSubtreeAggregates() {
    var count = 1
    var extent = bounds
    for child in children {
      count += child.subtreeNodeCount
      extent = extent.union(child.subtreeBounds)
    }
    subtreeNodeCount = count
    subtreeBounds = extent
  }
}
