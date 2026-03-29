/// A trivial root used by the generic ``Renderer`` helper.
public struct NoOpRoot: Equatable, Sendable {
  public var identity: Identity
  public var intrinsicSize: Size

  public init(
    identity: Identity = .init(components: []),
    intrinsicSize: Size = .zero
  ) {
    self.identity = identity
    self.intrinsicSize = intrinsicSize
  }
}

/// A generic renderer assembled from explicit pipeline phases.
public struct Renderer<Root> {
  /// Closure used for the resolve phase.
  public typealias ResolvePhase = (_ root: Root, _ context: FrameContext) -> ResolvedNode
  /// Closure used for the measure phase.
  public typealias MeasurePhase = (_ resolved: ResolvedNode, _ context: FrameContext) ->
    MeasuredNode
  /// Closure used for the place phase.
  public typealias PlacePhase = (_ measured: MeasuredNode, _ context: FrameContext) -> PlacedNode
  /// Closure used for the semantics phase.
  public typealias SemanticsPhase = (_ placed: PlacedNode, _ context: FrameContext) ->
    SemanticSnapshot
  /// Closure used for the draw phase.
  public typealias DrawPhase = (_ placed: PlacedNode, _ context: FrameContext) -> DrawNode
  /// Closure used for the raster phase.
  public typealias RasterPhase = (_ draw: DrawNode, _ context: FrameContext) -> RasterSurface
  /// Closure used for the commit phase.
  public typealias CommitPhase = (
    _ resolved: ResolvedNode,
    _ measured: MeasuredNode,
    _ placed: PlacedNode,
    _ semantics: SemanticSnapshot,
    _ draw: DrawNode,
    _ raster: RasterSurface,
    _ context: FrameContext
  ) -> CommitPlan

  public let resolvePhase: ResolvePhase
  public let measurePhase: MeasurePhase
  public let placePhase: PlacePhase
  public let semanticsPhase: SemanticsPhase
  public let drawPhase: DrawPhase
  public let rasterPhase: RasterPhase
  public let commitPhase: CommitPhase

  /// Creates a renderer from explicit pipeline closures.
  public init(
    resolvePhase: @escaping ResolvePhase,
    measurePhase: @escaping MeasurePhase,
    placePhase: @escaping PlacePhase,
    semanticsPhase: @escaping SemanticsPhase,
    drawPhase: @escaping DrawPhase,
    rasterPhase: @escaping RasterPhase,
    commitPhase: @escaping CommitPhase
  ) {
    self.resolvePhase = resolvePhase
    self.measurePhase = measurePhase
    self.placePhase = placePhase
    self.semanticsPhase = semanticsPhase
    self.drawPhase = drawPhase
    self.rasterPhase = rasterPhase
    self.commitPhase = commitPhase
  }

  /// Renders `root` through all configured phases.
  public func renderFrame(root: Root, context: FrameContext = .init()) -> FrameArtifacts {
    let resolved = resolvePhase(root, context)
    let measured = measurePhase(resolved, context)
    let placed = placePhase(measured, context)
    let semantics = semanticsPhase(placed, context)
    let draw = drawPhase(placed, context)
    let raster = rasterPhase(draw, context)
    let commit = commitPhase(resolved, measured, placed, semantics, draw, raster, context)
    let diagnostics = FrameDiagnostics.summarize(
      resolved: resolved,
      measured: measured,
      placed: placed,
      semantics: semantics,
      draw: draw,
      invalidatedIdentities: context.invalidatedIdentities
    )

    return FrameArtifacts(
      resolvedTree: resolved,
      measuredTree: measured,
      placedTree: placed,
      semanticSnapshot: semantics,
      drawTree: draw,
      rasterSurface: raster,
      commitPlan: commit,
      diagnostics: diagnostics
    )
  }
}

extension Renderer where Root == NoOpRoot {
  /// Returns a renderer that produces empty frame artifacts.
  public static func noOp() -> Self {
    Self(
      resolvePhase: { root, context in
        ResolvedNode(
          identity: root.identity,
          kind: .root,
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction,
          intrinsicSize: root.intrinsicSize
        )
      },
      measurePhase: { resolved, _ in
        let size = resolved.intrinsicSize ?? .zero
        return MeasuredNode(
          identity: resolved.identity,
          proposal: ProposedSize(width: size.width, height: size.height),
          measuredSize: size
        )
      },
      placePhase: { measured, _ in
        let bounds = Rect(origin: .zero, size: measured.measuredSize)
        return PlacedNode(
          identity: measured.identity,
          bounds: bounds,
          semanticRole: .container
        )
      },
      semanticsPhase: { _, _ in
        SemanticSnapshot()
      },
      drawPhase: { placed, _ in
        DrawNode(identity: placed.identity, bounds: placed.bounds)
      },
      rasterPhase: { _, _ in
        RasterSurface()
      },
      commitPhase: { _, _, _, semantics, _, _, context in
        CommitPlan(
          transaction: context.transaction,
          semanticSnapshot: semantics
        )
      }
    )
  }
}
