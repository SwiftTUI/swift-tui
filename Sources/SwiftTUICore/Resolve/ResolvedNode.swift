/// A node produced by the resolve phase before measurement.
///
/// Resolve owns the lowered tree shape, identity, environment, transaction,
/// layout behavior, metadata, handlers, draw payloads, and authored-state
/// snapshots that later phases consume.  Fields such as `preferenceValues`,
/// `subtreeNodeCount`, `supportsRetainedReuse`, and
/// `subtreeRuntimeNodeIDsStamped` are derived cache inputs
/// maintained beside the authoritative resolved data.  Later phase products may
/// mirror subsets of this data, but every retained reuse path must refresh those
/// mirrors from the current `ResolvedNode` before semantics, draw, lifecycle, or
/// animation code observes them.
package struct ResolvedNode: Equatable, Sendable {
  /// Runtime graph node this value was committed for, stamped by
  /// `ViewNode` applies.  Coupled to `subtreeRuntimeNodeIDsStamped`: writers
  /// that stamp this field outside the `ViewNode` apply walk must call
  /// `recomputeSubtreeRuntimeNodeIDsStamped()` afterwards or the derived
  /// flag goes stale-false and silently disables the stamping fast path.
  package var viewNodeID: ViewNodeID?
  package var identity: Identity
  package var structuralPath: StructuralPath
  package var structuralEdgeRole: StructuralEdgeRole
  package var entityIdentity: EntityIdentity?
  package var entityStructuralPath: StructuralPath?
  package var declarationOwnerEdge: DeclarationOwnerEdge?
  package var kind: NodeKind
  /// Stable per-Swift-type discriminator carried alongside `kind`.
  ///
  /// `NodeKind.view(String)` is a human-readable role name (e.g. `"Text"`,
  /// `"Padding"`) that any call site can produce.  When two unrelated views
  /// happen to pick the same name — intentionally for modifier roles or by
  /// accident for primitives — the string alone cannot tell them apart, and
  /// a structural diff would fuse them.  A concrete primitive that
  /// populates this field with `ObjectIdentifier(Self.self)` refines the
  /// String identity with a type-level guarantee.
  ///
  /// Left `nil` by most call sites during the incremental migration.
  /// `ChildDescriptor` equality treats `nil` as "compatible with either
  /// side" so populated and legacy descriptors still match when their
  /// names agree, keeping the migration churn-free.
  package var typeDiscriminator: ObjectIdentifier?
  /// Backing storage for ``children``.  Direct access is
  /// package-scoped so animation tick frames can replace interpolated
  /// children in place via ``setChildrenPreservingDerivedState(_:)``
  /// without paying for preference/node-count/reuse recomputes on
  /// every frame.  All external writes must go through the public
  /// ``children`` setter, which keeps the derived state correct.
  package var _storedChildren: [ResolvedNode]
  package var children: [ResolvedNode] {
    get { _storedChildren }
    set {
      _storedChildren = newValue
      recomputePreferenceValues()
      recomputeSubtreeNodeCount()
      recomputeCustomLayoutFallbackSummary()
      recomputeSupportsRetainedReuse()
      recomputeSubtreeRuntimeNodeIDsStamped()
    }
  }

  /// Package-only write path that skips the derived-state recomputes
  /// triggered by the normal ``children`` setter.  Intended for
  /// animation tick frames, where each child is replaced with an
  /// interpolated copy that has the same shape — so the derived
  /// subtree node count, preference aggregate, and retained-reuse bit
  /// cannot change.
  ///
  /// If the replacement changes the child count, preference set, or
  /// support-retained-reuse bit, use the normal setter instead — this
  /// method makes no correctness guarantee for structural changes.
  package mutating func setChildrenPreservingDerivedState(_ newChildren: [ResolvedNode]) {
    _storedChildren = newChildren
  }
  package var environmentSnapshot: EnvironmentSnapshot
  package var transactionSnapshot: TransactionSnapshot
  /// Backing storage for ``layoutBehavior``.  Direct access is
  /// package-scoped so animation tick frames can overwrite the
  /// layout behavior with an interpolated copy without paying for
  /// the ``recomputeSupportsRetainedReuse`` recompute, which is a
  /// no-op for animation tick frames that only change numeric
  /// dimensions within the same layout variant.
  package var _storedLayoutBehavior: LayoutBehavior
  package var layoutBehavior: LayoutBehavior {
    get { _storedLayoutBehavior }
    set {
      _storedLayoutBehavior = newValue
      recomputeCustomLayoutFallbackSummary()
      recomputeSupportsRetainedReuse()
    }
  }

  /// Package-only write path that skips the
  /// ``recomputeSupportsRetainedReuse`` call fired by the normal
  /// ``layoutBehavior`` setter.  Intended for animation tick frames
  /// that mutate numeric dimensions within the same layout variant
  /// (e.g. updating `.frame(width:)` or `.padding(_:)` without
  /// changing the variant itself), where the reuse bit is stable.
  package mutating func setLayoutBehaviorPreservingDerivedState(_ newBehavior: LayoutBehavior) {
    _storedLayoutBehavior = newBehavior
    recomputeCustomLayoutFallbackSummary()
  }
  package var layoutMetadata: LayoutMetadata
  package var drawMetadata: DrawMetadata {
    get { _boxedDrawMetadata.value }
    set { _boxedDrawMetadata.value = newValue }
  }
  package var _boxedDrawMetadata: Boxed<DrawMetadata>
  package var drawEffects: DrawEffects
  package var surfaceComposition: SurfaceCompositionMetadata
  package var semanticMetadata: SemanticMetadata
  package var lifecycleMetadata: LifecycleMetadata
  package var drawPayload: DrawPayload
  package var intrinsicSize: CellSize?
  package var indexedChildSource: (any IndexedChildSource)? {
    didSet {
      if indexedChildSource != nil, structuralEdgeRole == .normal {
        structuralEdgeRole = .viewportBarrier
      } else if indexedChildSource == nil, structuralEdgeRole == .viewportBarrier {
        structuralEdgeRole = .normal
      }
      recomputeCustomLayoutFallbackSummary()
      recomputeSupportsRetainedReuse()
    }
  }
  package var layoutRealizedContent: LayoutRealizedContentBoundary? {
    didSet {
      recomputeSupportsRetainedReuse()
    }
  }
  package var preferenceValues: PreferenceValues
  package private(set) var subtreeNodeCount: Int
  package private(set) var customLayoutFallbackSummary: CustomLayoutFallbackSummary
  package var supportsRetainedReuse: Bool
  /// Derived cache: `true` when this node and every descendant in
  /// `_storedChildren` carry a non-nil `viewNodeID`.  `ViewNode`'s runtime-ID
  /// stamping walk early-returns on fully stamped subtree values, which keeps
  /// fresh-parent applies O(changed frontier) instead of re-stamping large
  /// reused subtrees every frame.  Maintained by the inits, the public
  /// `children` setter, and explicit `recomputeSubtreeRuntimeNodeIDsStamped()`
  /// calls at the stamping sites; deliberately preserved (not recomputed) by
  /// `setChildrenPreservingDerivedState(_:)`, whose animation-tick callers
  /// substitute same-shape copies that keep their stamps.  Transient overlay
  /// transforms may install unstamped wrappers under a preserved `true`
  /// parent; such trees never re-enter graph applies.  Excluded from `==`
  /// alongside `viewNodeID`.
  package private(set) var subtreeRuntimeNodeIDsStamped: Bool
  /// Matched-geometry configuration set by
  /// `View.matchedGeometryEffect(id:in:isSource:)`.  When two
  /// views in different frames (typically behind an `if`/`else`
  /// branch) share the same key, the animation controller treats
  /// the swap as a single view moving from the previous frame's
  /// placed bounds to the new frame's placed bounds and animates
  /// the translation under `withAnimation`.
  package var matchedGeometry: MatchedGeometryConfig? = nil
  /// Marks the node (and transitively any node that inherits this
  /// flag via the layout engine) as a non-semantic visual overlay.
  /// The animation controller sets this on every node in a removal
  /// overlay subtree it injects during a `.transition(...)` exit.
  ///
  /// Transient nodes flow through the draw/raster path normally, so
  /// they stay visible for the duration of the exit animation, but
  /// are skipped by the semantic extractor, focus tracker, lifecycle
  /// coordinator, and interaction hit testing.  Anything sitting on
  /// the "is the committed tree still the authoritative source for
  /// routing?" axis must filter transient nodes out.
  package var isTransient: Bool = false

  package init(
    viewNodeID: ViewNodeID? = nil,
    identity: Identity,
    structuralPath: StructuralPath? = nil,
    structuralEdgeRole: StructuralEdgeRole? = nil,
    kind: NodeKind,
    children: [ResolvedNode] = [],
    environmentSnapshot: EnvironmentSnapshot = .init(),
    transactionSnapshot: TransactionSnapshot = .init(),
    layoutBehavior: LayoutBehavior = .intrinsic,
    layoutMetadata: LayoutMetadata = .init(),
    drawMetadata: DrawMetadata = DrawMetadata(),
    drawEffects: DrawEffects = .init(),
    surfaceComposition: SurfaceCompositionMetadata = .normal,
    semanticMetadata: SemanticMetadata = SemanticMetadata(),
    lifecycleMetadata: LifecycleMetadata = .init(),
    drawPayload: DrawPayload = .none,
    intrinsicSize: CellSize? = nil,
    layoutRealizedContent: LayoutRealizedContentBoundary? = nil
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    self.structuralPath = structuralPath ?? StructuralPath(identity: identity)
    self.structuralEdgeRole = structuralEdgeRole ?? surfaceComposition.role
    self.entityIdentity = nil
    self.entityStructuralPath = nil
    self.declarationOwnerEdge = nil
    self.kind = kind
    self.typeDiscriminator = nil
    // Assign the backing stores directly — the computed setters would
    // touch the derived stored properties (preferenceValues, etc.)
    // which are not yet initialized at this point.  We run the
    // derived-state computation once at the end of init.
    self._storedChildren = children
    self.environmentSnapshot = environmentSnapshot
    self.transactionSnapshot = transactionSnapshot
    self._storedLayoutBehavior = layoutBehavior
    self.layoutMetadata = layoutMetadata
    self._boxedDrawMetadata = Boxed(drawMetadata)
    self.drawEffects = drawEffects
    self.surfaceComposition = surfaceComposition
    self.semanticMetadata = semanticMetadata
    self.lifecycleMetadata = lifecycleMetadata
    self.drawPayload = drawPayload
    self.intrinsicSize = intrinsicSize
    self.indexedChildSource = nil
    self.layoutRealizedContent = layoutRealizedContent
    preferenceValues = Self.combinedPreferenceValues(for: children)
    subtreeNodeCount = 1
    customLayoutFallbackSummary = .init()
    self.supportsRetainedReuse = true
    subtreeRuntimeNodeIDsStamped = false
    recomputeSubtreeNodeCount()
    recomputeCustomLayoutFallbackSummary()
    recomputeSupportsRetainedReuse()
    recomputeSubtreeRuntimeNodeIDsStamped()
  }

  package init(
    viewNodeID: ViewNodeID? = nil,
    identity: Identity,
    structuralPath: StructuralPath? = nil,
    structuralEdgeRole: StructuralEdgeRole? = nil,
    kind: NodeKind,
    typeDiscriminator: ObjectIdentifier? = nil,
    children: [ResolvedNode] = [],
    environmentSnapshot: EnvironmentSnapshot = .init(),
    transactionSnapshot: TransactionSnapshot = .init(),
    layoutBehavior: LayoutBehavior = .intrinsic,
    layoutMetadata: LayoutMetadata = .init(),
    drawMetadata: DrawMetadata = DrawMetadata(),
    drawEffects: DrawEffects = .init(),
    surfaceComposition: SurfaceCompositionMetadata = .normal,
    semanticMetadata: SemanticMetadata = SemanticMetadata(),
    lifecycleMetadata: LifecycleMetadata = .init(),
    drawPayload: DrawPayload = .none,
    intrinsicSize: CellSize? = nil,
    indexedChildSource: (any IndexedChildSource)? = nil,
    layoutRealizedContent: LayoutRealizedContentBoundary? = nil
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    self.structuralPath = structuralPath ?? StructuralPath(identity: identity)
    self.structuralEdgeRole =
      structuralEdgeRole ?? (indexedChildSource == nil ? surfaceComposition.role : .viewportBarrier)
    self.entityIdentity = nil
    self.entityStructuralPath = nil
    self.declarationOwnerEdge = nil
    self.kind = kind
    self.typeDiscriminator = typeDiscriminator
    self._storedChildren = children
    self.environmentSnapshot = environmentSnapshot
    self.transactionSnapshot = transactionSnapshot
    self._storedLayoutBehavior = layoutBehavior
    self.layoutMetadata = layoutMetadata
    self._boxedDrawMetadata = Boxed(drawMetadata)
    self.drawEffects = drawEffects
    self.surfaceComposition = surfaceComposition
    self.semanticMetadata = semanticMetadata
    self.lifecycleMetadata = lifecycleMetadata
    self.drawPayload = drawPayload
    self.intrinsicSize = intrinsicSize
    self.indexedChildSource = indexedChildSource
    self.layoutRealizedContent = layoutRealizedContent
    preferenceValues = Self.combinedPreferenceValues(for: children)
    subtreeNodeCount = 1
    customLayoutFallbackSummary = .init()
    self.supportsRetainedReuse = true
    subtreeRuntimeNodeIDsStamped = false
    recomputeSubtreeNodeCount()
    recomputeCustomLayoutFallbackSummary()
    recomputeSupportsRetainedReuse()
    recomputeSubtreeRuntimeNodeIDsStamped()
  }

  private mutating func recomputePreferenceValues() {
    preferenceValues = Self.combinedPreferenceValues(for: children)
  }

  private mutating func recomputeSubtreeNodeCount() {
    subtreeNodeCount = 1 + children.reduce(0) { $0 + $1.subtreeNodeCount }
  }

  private mutating func recomputeCustomLayoutFallbackSummary() {
    customLayoutFallbackSummary = Self.computeCustomLayoutFallbackSummary(
      identity: identity,
      layoutBehavior: layoutBehavior,
      children: children,
      indexedChildSource: indexedChildSource
    )
  }

  private mutating func recomputeSupportsRetainedReuse() {
    supportsRetainedReuse = Self.computeSupportsRetainedReuse(
      layoutBehavior: layoutBehavior,
      children: children,
      structuralEdgeRole: structuralEdgeRole,
      layoutRealizedContent: layoutRealizedContent
    )
  }

  /// Single source of truth for the `subtreeRuntimeNodeIDsStamped` formula.
  /// Every site that stamps `viewNodeID` outside the public `children`
  /// setter (the `ViewNode` apply walk, retained-snapshot commits, the
  /// nested-depth root stamp in view resolution) must call this afterwards.
  package mutating func recomputeSubtreeRuntimeNodeIDsStamped() {
    subtreeRuntimeNodeIDsStamped =
      viewNodeID != nil
      && _storedChildren.allSatisfy(\.subtreeRuntimeNodeIDsStamped)
  }

  /// Withdraws the subtree-completeness claim without touching the stamps
  /// themselves.  The stamping walk calls this when it cannot pair this
  /// value's children with the live node's children (count-mismatched Group
  /// splices, capture-host injections): the child stamps may belong to other
  /// live nodes, so the value must stay on the slow restamping path instead
  /// of qualifying ancestors for the fast skip.
  package mutating func markSubtreeRuntimeNodeIDsUnstamped() {
    subtreeRuntimeNodeIDsStamped = false
  }

  private static func combinedPreferenceValues(
    for children: [ResolvedNode]
  ) -> PreferenceValues {
    var combined = PreferenceValues()
    for child in children {
      combined.merge(child.preferenceValues)
    }
    return combined
  }

  private static func computeCustomLayoutFallbackSummary(
    identity: Identity,
    layoutBehavior: LayoutBehavior,
    children: [ResolvedNode],
    indexedChildSource: (any IndexedChildSource)?
  ) -> CustomLayoutFallbackSummary {
    var summary = CustomLayoutFallbackSummary()
    if case .custom(let handle) = layoutBehavior,
      !handle.canRunOnWorker
    {
      summary.record(identity)
    }
    if let workerChildren = indexedChildSource?.workerResolvedChildren {
      for child in workerChildren {
        summary.merge(child.customLayoutFallbackSummary)
      }
    }
    for child in children {
      summary.merge(child.customLayoutFallbackSummary)
    }
    return summary
  }

  private static func computeSupportsRetainedReuse(
    layoutBehavior: LayoutBehavior,
    children: [ResolvedNode],
    structuralEdgeRole: StructuralEdgeRole,
    layoutRealizedContent: LayoutRealizedContentBoundary?
  ) -> Bool {
    // A `.viewportBarrier` edge (Stage 4) marks a lazy/indexed source whose
    // placed children are a viewport-clipped subset — its interior is never
    // retained-reusable. Driven off the typed edge role rather than re-deriving
    // it from `indexedChildSource`, so the role is a live consumer, not a label
    // that shadows the real predicate. (The role is maintained equivalent to
    // `indexedChildSource != nil` at construction and on mutation.)
    if structuralEdgeRole == .viewportBarrier {
      return false
    }
    if layoutRealizedContent != nil {
      return false
    }

    switch layoutBehavior {
    case .viewThatFits:
      return false
    case .custom(let handle):
      return handle.measurementReuseSignature != nil
        && handle.placementReuseSignature != nil
        && children.allSatisfy(\.supportsRetainedReuse)
    default:
      return children.allSatisfy(\.supportsRetainedReuse)
    }
  }

}

extension ResolvedNode {
  package mutating func attachingEntityIdentity(
    _ entityIdentity: EntityIdentity,
    at entityStructuralPath: StructuralPath
  ) {
    self.entityIdentity = entityIdentity
    self.entityStructuralPath = entityStructuralPath
  }
}
