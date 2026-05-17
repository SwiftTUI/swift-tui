/// Semantic role assigned to a placed node for extraction and rendering.
public enum SemanticRole: String, Equatable, Sendable {
  case generic
  case container
  case control
  case scroll
  case overlay
}

/// Resolved-to-placed metadata projection.
///
/// Placement owns geometry, but semantics, draw, lifecycle, and animation still
/// need a current snapshot of selected resolved metadata after retained
/// placement reuse. This value names that projection and is the only
/// construction/synchronization path for mirrors copied from `ResolvedNode` into
/// `PlacedNode`. It deliberately does not prescribe `PlacedNode`'s physical
/// storage shape.
package struct PlacedNodeResolvedMetadata: Equatable, Sendable {
  package var kind: NodeKind
  package var environmentSnapshot: EnvironmentSnapshot
  package var semanticRole: SemanticRole
  package var layoutMetadata: LayoutMetadata
  package var drawMetadata: DrawMetadata
  package var semanticMetadata: SemanticMetadata
  package var lifecycleMetadata: LifecycleMetadata
  package var drawPayload: DrawPayload
  package var layoutBehavior: LayoutBehavior
  package var isTransient: Bool
  package var matchedGeometry: MatchedGeometryConfig?

  package init(
    kind: NodeKind = .view("Unknown"),
    environmentSnapshot: EnvironmentSnapshot = .init(),
    semanticRole: SemanticRole = .generic,
    layoutMetadata: LayoutMetadata = .init(),
    drawMetadata: DrawMetadata = DrawMetadata(),
    semanticMetadata: SemanticMetadata = SemanticMetadata(),
    lifecycleMetadata: LifecycleMetadata = .init(),
    drawPayload: DrawPayload = .none,
    layoutBehavior: LayoutBehavior = .intrinsic,
    isTransient: Bool = false,
    matchedGeometry: MatchedGeometryConfig? = nil
  ) {
    self.kind = kind
    self.environmentSnapshot = environmentSnapshot
    self.semanticRole = semanticRole
    self.layoutMetadata = layoutMetadata
    self.drawMetadata = drawMetadata
    self.semanticMetadata = semanticMetadata
    self.lifecycleMetadata = lifecycleMetadata
    self.drawPayload = drawPayload
    self.layoutBehavior = layoutBehavior
    self.isTransient = isTransient
    self.matchedGeometry = matchedGeometry
  }

  package init(
    resolved: ResolvedNode,
    semanticRole: SemanticRole
  ) {
    self.init(
      kind: resolved.kind,
      environmentSnapshot: resolved.environmentSnapshot,
      semanticRole: semanticRole,
      layoutMetadata: resolved.layoutMetadata,
      drawMetadata: resolved.drawMetadata,
      semanticMetadata: resolved.semanticMetadata,
      lifecycleMetadata: resolved.lifecycleMetadata,
      drawPayload: resolved.drawPayload,
      layoutBehavior: resolved.layoutBehavior,
      isTransient: resolved.isTransient,
      matchedGeometry: resolved.matchedGeometry
    )
  }
}

/// A node after layout has assigned concrete bounds.
///
/// Placement owns final bounds, content bounds, clipping, z-order, child
/// placement, and subtree counts. The resolved-derived fields are projections
/// refreshed through `PlacedNodeResolvedMetadata`; they are not independent
/// sources of resolved truth.
public struct PlacedNode: Equatable, Sendable {
  public var identity: Identity
  package var kind: NodeKind
  public var environmentSnapshot: EnvironmentSnapshot
  public var bounds: CellRect
  public var contentBounds: CellRect
  public var clipBounds: CellRect?
  public var zIndex: Double
  public var children: [PlacedNode] {
    didSet {
      recomputeSubtreeNodeCount()
    }
  }
  public var semanticRole: SemanticRole
  package var layoutMetadata: LayoutMetadata
  package var drawMetadata: DrawMetadata
  private var _semanticMetadata: Boxed<SemanticMetadata>?
  public var semanticMetadata: SemanticMetadata {
    get { _semanticMetadata?.value ?? SemanticMetadata() }
    set {
      if newValue == SemanticMetadata() {
        _semanticMetadata = nil
      } else {
        _semanticMetadata = Boxed(newValue)
      }
    }
    _modify {
      if _semanticMetadata == nil {
        _semanticMetadata = Boxed(SemanticMetadata())
      }
      defer {
        if _semanticMetadata?.value == SemanticMetadata() {
          _semanticMetadata = nil
        }
      }
      yield &_semanticMetadata!.value
    }
  }
  public var lifecycleMetadata: LifecycleMetadata
  @_spi(Testing) public var drawPayload: DrawPayload
  /// Mirror of ``ResolvedNode/layoutBehavior`` for cases that need to
  /// flow through to the draw extractor / rasterizer (currently just
  /// `LayoutBehavior.border(...)`).
  ///
  /// Boxed and optional on purpose — storing a bare `LayoutBehavior`
  /// inline would grow ``PlacedNode`` by ~1.6 kB per node (because
  /// `LayoutBehavior` has non-indirect large cases like `.stack` and
  /// `.flexibleFrame`) and recursively destroying deep trees would
  /// then overflow the thread stack. `nil` is the common case: only
  /// border wrappers actually populate this field.
  package var _boxedLayoutBehavior: Boxed<LayoutBehavior>?
  public var layoutBehavior: LayoutBehavior {
    get { _boxedLayoutBehavior?.value ?? .intrinsic }
    set {
      if case .intrinsic = newValue {
        _boxedLayoutBehavior = nil
      } else {
        _boxedLayoutBehavior = Boxed(newValue)
      }
    }
  }
  package private(set) var subtreeNodeCount: Int
  /// Mirror of ``ResolvedNode/isTransient``.  Set by the animation
  /// controller's removal-overlay injection path, propagated through
  /// measure and place by the layout engine, and filtered out by the
  /// semantic extractor and every other consumer whose state must
  /// track only the committed tree.
  public var isTransient: Bool = false
  /// Mirror of ``ResolvedNode/matchedGeometry``.  Propagated from
  /// the resolved tree by the layout engine so the animation
  /// controller can compute matched-geometry bounds during
  /// capture+diff.
  public var matchedGeometry: MatchedGeometryConfig?
  package var resolvedMetadata: PlacedNodeResolvedMetadata {
    get {
      PlacedNodeResolvedMetadata(
        kind: kind,
        environmentSnapshot: environmentSnapshot,
        semanticRole: semanticRole,
        layoutMetadata: layoutMetadata,
        drawMetadata: drawMetadata,
        semanticMetadata: semanticMetadata,
        lifecycleMetadata: lifecycleMetadata,
        drawPayload: drawPayload,
        layoutBehavior: layoutBehavior,
        isTransient: isTransient,
        matchedGeometry: matchedGeometry
      )
    }
    set {
      applyResolvedMetadata(newValue)
    }
  }

  package init(
    identity: Identity,
    resolvedMetadata: PlacedNodeResolvedMetadata,
    bounds: CellRect,
    contentBounds: CellRect? = nil,
    clipBounds: CellRect? = nil,
    zIndex: Double = 0,
    children: [PlacedNode] = []
  ) {
    self.init(
      identity: identity,
      kind: resolvedMetadata.kind,
      environmentSnapshot: resolvedMetadata.environmentSnapshot,
      bounds: bounds,
      contentBounds: contentBounds,
      clipBounds: clipBounds,
      zIndex: zIndex,
      children: children,
      semanticRole: resolvedMetadata.semanticRole,
      layoutMetadata: resolvedMetadata.layoutMetadata,
      drawMetadata: resolvedMetadata.drawMetadata,
      semanticMetadata: resolvedMetadata.semanticMetadata,
      lifecycleMetadata: resolvedMetadata.lifecycleMetadata,
      drawPayload: resolvedMetadata.drawPayload,
      layoutBehavior: resolvedMetadata.layoutBehavior,
      isTransient: resolvedMetadata.isTransient,
      matchedGeometry: resolvedMetadata.matchedGeometry
    )
  }

  package init(
    identity: Identity,
    kind: NodeKind = .view("Unknown"),
    environmentSnapshot: EnvironmentSnapshot = .init(),
    bounds: CellRect,
    contentBounds: CellRect? = nil,
    clipBounds: CellRect? = nil,
    zIndex: Double = 0,
    children: [PlacedNode] = [],
    semanticRole: SemanticRole = .generic,
    layoutMetadata: LayoutMetadata = .init(),
    drawMetadata: DrawMetadata = DrawMetadata(),
    semanticMetadata: SemanticMetadata = SemanticMetadata(),
    lifecycleMetadata: LifecycleMetadata = .init(),
    drawPayload: DrawPayload = .none,
    layoutBehavior: LayoutBehavior = .intrinsic,
    isTransient: Bool = false,
    matchedGeometry: MatchedGeometryConfig? = nil
  ) {
    self.identity = identity
    self.kind = kind
    self.environmentSnapshot = environmentSnapshot
    self.bounds = bounds
    self.contentBounds = contentBounds ?? bounds
    self.clipBounds = clipBounds
    self.zIndex = zIndex
    self.children = children
    self.semanticRole = semanticRole
    self.layoutMetadata = layoutMetadata
    self.drawMetadata = drawMetadata
    if semanticMetadata == SemanticMetadata() {
      _semanticMetadata = nil
    } else {
      _semanticMetadata = Boxed(semanticMetadata)
    }
    self.lifecycleMetadata = lifecycleMetadata
    self.drawPayload = drawPayload
    if case .intrinsic = layoutBehavior {
      _boxedLayoutBehavior = nil
    } else {
      _boxedLayoutBehavior = Boxed(layoutBehavior)
    }
    self.isTransient = isTransient
    self.matchedGeometry = matchedGeometry
    subtreeNodeCount = 1
    recomputeSubtreeNodeCount()
  }

  private mutating func applyResolvedMetadata(_ metadata: PlacedNodeResolvedMetadata) {
    kind = metadata.kind
    environmentSnapshot = metadata.environmentSnapshot
    semanticRole = metadata.semanticRole
    layoutMetadata = metadata.layoutMetadata
    drawMetadata = metadata.drawMetadata
    semanticMetadata = metadata.semanticMetadata
    lifecycleMetadata = metadata.lifecycleMetadata
    drawPayload = metadata.drawPayload
    layoutBehavior = metadata.layoutBehavior
    isTransient = metadata.isTransient
    matchedGeometry = metadata.matchedGeometry
  }

  private mutating func recomputeSubtreeNodeCount() {
    subtreeNodeCount = 1 + children.reduce(0) { $0 + $1.subtreeNodeCount }
  }

  package mutating func synchronizeResolvedPhaseMetadata(
    from resolved: ResolvedNode,
    semanticRole: SemanticRole
  ) {
    resolvedMetadata = .init(resolved: resolved, semanticRole: semanticRole)
  }

  package func collectLifecycleNodes(
    into nodes: inout [LifecycleStateNode]
  ) {
    var stack: [PlacedNode] = [self]
    while let node = stack.popLast() {
      // Transient (animation removal overlay) subtrees do not
      // participate in the lifecycle coordinator.  Their onAppear /
      // onDisappear / task closures already fired against the
      // committed tree's lifetime, and the exit animation is a
      // purely visual afterimage.
      if node.isTransient { continue }
      if !node.lifecycleMetadata.isEmpty {
        nodes.append(
          LifecycleStateNode(
            identity: node.identity,
            appearHandlerIDs: node.lifecycleMetadata.appearHandlerIDs,
            disappearHandlerIDs: node.lifecycleMetadata.disappearHandlerIDs,
            task: node.lifecycleMetadata.task
          )
        )
      }

      for child in node.children.reversed() {
        stack.append(child)
      }
    }
  }
}
