@_spi(Testing) import SwiftTUIPrimitives

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
      recomputeSubtreeDynamicPropertyReuseCertification()
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
  package var handlerInventory: CommittedHandlerInventory
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
      recomputeCustomLayoutFallbackSummary()
      recomputeSupportsRetainedReuse()
    }
  }
  package var preferenceValues: PreferenceValues
  package private(set) var subtreeNodeCount: Int
  package private(set) var customLayoutFallbackSummary: CustomLayoutFallbackSummary
  /// Whether this node's own dynamic-property update is reusable on a later
  /// frame. `.uncertified` clears this bit; `.unchanged` and `.changed` both
  /// describe certified storage (the latter denies only the current serve).
  package var directDynamicPropertyReuseCertified: Bool {
    didSet {
      recomputeSubtreeDynamicPropertyReuseCertification()
      recomputeSupportsRetainedReuse()
    }
  }
  /// Transitive dynamic-property certification kept independently from layout
  /// reuse capability so child/layout recomputes cannot launder a direct
  /// uncertified result back to reusable.
  package private(set) var subtreeDynamicPropertyReuseCertified: Bool
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
  /// `View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`.  When
  /// two views in different frames (typically behind an `if`/`else`
  /// branch) share the same key, the animation controller treats
  /// the swap as a single view moving from the previous frame's
  /// placed bounds to the new frame's placed bounds and animates
  /// the translation (and, per `properties`, the size) under
  /// `withAnimation`.
  ///
  /// Boxed and optional on purpose: the config carries a key string, a
  /// `UnitPoint`, and flags, and storing it inline pushed `ResolvedNode`
  /// past its teardown size budget (`DeepTreeTeardownTests`). `nil` is the
  /// common case; only matched nodes populate it.
  package var matchedGeometry: MatchedGeometryConfig? {
    get { _boxedMatchedGeometry?.value }
    set { _boxedMatchedGeometry = newValue.map(Boxed.init) }
  }
  private var _boxedMatchedGeometry: Boxed<MatchedGeometryConfig>? = nil
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
    handlerInventory: CommittedHandlerInventory = .init(),
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
    self.handlerInventory = handlerInventory
    self.drawPayload = drawPayload
    self.intrinsicSize = intrinsicSize
    self.indexedChildSource = nil
    self.layoutRealizedContent = layoutRealizedContent
    preferenceValues = Self.combinedPreferenceValues(for: children)
    subtreeNodeCount = 1
    customLayoutFallbackSummary = .init()
    directDynamicPropertyReuseCertified = true
    subtreeDynamicPropertyReuseCertified = true
    self.supportsRetainedReuse = true
    subtreeRuntimeNodeIDsStamped = false
    recomputeSubtreeNodeCount()
    recomputeCustomLayoutFallbackSummary()
    recomputeSubtreeDynamicPropertyReuseCertification()
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
    handlerInventory: CommittedHandlerInventory = .init(),
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
    self.handlerInventory = handlerInventory
    self.drawPayload = drawPayload
    self.intrinsicSize = intrinsicSize
    self.indexedChildSource = indexedChildSource
    self.layoutRealizedContent = layoutRealizedContent
    preferenceValues = Self.combinedPreferenceValues(for: children)
    subtreeNodeCount = 1
    customLayoutFallbackSummary = .init()
    directDynamicPropertyReuseCertified = true
    subtreeDynamicPropertyReuseCertified = true
    self.supportsRetainedReuse = true
    subtreeRuntimeNodeIDsStamped = false
    recomputeSubtreeNodeCount()
    recomputeCustomLayoutFallbackSummary()
    recomputeSubtreeDynamicPropertyReuseCertification()
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
      indexedChildSource: indexedChildSource,
      layoutRealizedContent: layoutRealizedContent
    )
  }

  private mutating func recomputeSubtreeDynamicPropertyReuseCertification() {
    subtreeDynamicPropertyReuseCertified =
      directDynamicPropertyReuseCertified
      && children.allSatisfy(\.subtreeDynamicPropertyReuseCertified)
  }

  private mutating func recomputeSupportsRetainedReuse() {
    supportsRetainedReuse = Self.computeSupportsRetainedReuse(
      layoutBehavior: layoutBehavior,
      children: children,
      structuralEdgeRole: structuralEdgeRole,
      layoutRealizedContent: layoutRealizedContent,
      subtreeDynamicPropertyReuseCertified: subtreeDynamicPropertyReuseCertified
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

  /// Recursively withdraws the subtree-completeness claim at EVERY level of
  /// this value tree. A capture-host injection (the toolbar reconcile
  /// re-hosting content children captured from an earlier resolve) applies
  /// values whose stamps were written under a DIFFERENT live-graph state —
  /// the async frame protocol suspends the prepared graph back to baseline
  /// while the tail reconciles, so a node the prepared resolve re-minted can
  /// pair against its suspended predecessor. The root-only withdrawal is not
  /// enough there: the stamping walk re-checks each level's own claim, so a
  /// still-claimed interior would qualify for the fast skip and carry the
  /// foreign stamps into the committed value (the stamp-coherence trap).
  package mutating func withdrawSubtreeRuntimeNodeIDStampsRecursively() {
    subtreeRuntimeNodeIDsStamped = false
    for index in _storedChildren.indices {
      _storedChildren[index].withdrawSubtreeRuntimeNodeIDStampsRecursively()
    }
  }

  /// Reconciles the derived handler-bookkeeping currency against the runtime
  /// node store after teardown has settled.
  ///
  /// Committed child values intentionally rewire lazily: a removed runtime
  /// node can remain as an inert value copy in an ancestor's committed
  /// children until that ancestor next applies. Its structural/render payload
  /// remains valid for that lazy-rewire contract, but its handler inventory
  /// must not continue to describe a runtime owner that no longer exists.
  /// Surviving stamped values take their runtime owner's current committed
  /// projection; departed stamped values clear only this derived metadata.
  /// Unstamped values retain their authored inventory.
  package mutating func reconcileCommittedHandlerInventory(
    inventoryForRuntimeNodeID: (ViewNodeID) -> CommittedHandlerInventory?
  ) {
    // The common case is already canonical. Prove that with a read-only walk
    // before opening the value tree for mutation: reconstructing every
    // committed node on every sampled frame made the oracle materially more
    // expensive even when no handler currency changed.
    var inspectionStack = [self]
    var needsRepair = false
    while let node = inspectionStack.popLast() {
      if let viewNodeID = node.viewNodeID,
        node.handlerInventory
          != (inventoryForRuntimeNodeID(viewNodeID) ?? .init())
      {
        needsRepair = true
        break
      }
      inspectionStack.append(contentsOf: node._storedChildren)
    }
    guard needsRepair else {
      return
    }

    var stack = [
      HandlerInventoryReconciliationFrame(node: self)
    ]

    while !stack.isEmpty {
      let frameIndex = stack.index(before: stack.endIndex)
      if stack[frameIndex].nextChildIndex
        < stack[frameIndex].node._storedChildren.count
      {
        let childIndex = stack[frameIndex].nextChildIndex
        let child = stack[frameIndex].node._storedChildren[childIndex]
        stack[frameIndex].nextChildIndex += 1
        stack.append(HandlerInventoryReconciliationFrame(node: child))
        continue
      }

      var completed = stack.removeLast()
      if let viewNodeID = completed.node.viewNodeID {
        completed.node.handlerInventory =
          inventoryForRuntimeNodeID(viewNodeID) ?? .init()
      }
      if !completed.node._storedChildren.isEmpty {
        completed.node.setChildrenPreservingDerivedState(
          completed.reconciledChildren
        )
      }

      guard !stack.isEmpty else {
        self = completed.node
        return
      }
      stack[stack.index(before: stack.endIndex)]
        .reconciledChildren.append(completed.node)
    }
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
    indexedChildSource: (any IndexedChildSource)?,
    layoutRealizedContent: LayoutRealizedContentBoundary?
  ) -> CustomLayoutFallbackSummary {
    var summary = CustomLayoutFallbackSummary()
    if case .custom(let handle) = layoutBehavior,
      !handle.canRunOnWorker
    {
      summary.record(identity)
    }
    if let indexedChildSource, !indexedChildSource.canRunOnWorker {
      summary.recordMainActorOnlyIndexedChildSource(elementCount: indexedChildSource.count)
    }
    if layoutRealizedContent != nil {
      summary.recordLayoutRealizedContent()
    }
    if let workerChildren = indexedChildSource?.workerResolvedChildren {
      for child in workerChildren {
        summary.merge(child.customLayoutFallbackSummary)
      }
    }
    for child in children {
      summary.merge(child.customLayoutFallbackSummary)
    }
    // Both arms re-enter the layout engine on the native stack when measured:
    // a custom layout through the compatibility boundary, and an intrinsic
    // indexed container (the hosted-collection windowing path — `List`/
    // `Table`) through its per-row `measure` re-entry. Lazy stacks carry an
    // indexed source too but measure through the explicit work stack, so
    // only the intrinsic shape counts. Keyed off `layoutBehavior` +
    // `indexedChildSource` (never `semanticMetadata`) because only those two
    // fields recompute this summary on mutation.
    switch layoutBehavior {
    case .custom:
      summary.recordEngineReentryNestingLevel()
    case .intrinsic where indexedChildSource != nil:
      summary.recordEngineReentryNestingLevel()
    default:
      break
    }
    return summary
  }

  private static func computeSupportsRetainedReuse(
    layoutBehavior: LayoutBehavior,
    children: [ResolvedNode],
    structuralEdgeRole: StructuralEdgeRole,
    layoutRealizedContent: LayoutRealizedContentBoundary?,
    subtreeDynamicPropertyReuseCertified: Bool
  ) -> Bool {
    if !subtreeDynamicPropertyReuseCertified {
      return false
    }
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

private struct HandlerInventoryReconciliationFrame {
  var node: ResolvedNode
  var nextChildIndex = 0
  var reconciledChildren: [ResolvedNode] = []

  init(node: ResolvedNode) {
    self.node = node
    reconciledChildren.reserveCapacity(node._storedChildren.count)
  }
}

extension ResolvedNode: DeeplyNestedValueTree {
  /// Storage-level child access for ``flattenForRelease()``. Deliberately not
  /// the public ``children`` setter: the drain runs on a value that is about to
  /// be destroyed, so the derived preference/node-count/reuse recomputes that
  /// setter fires would be pure waste.
  package var _childrenForRelease: [ResolvedNode] {
    get { _storedChildren }
    set { _storedChildren = newValue }
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

extension ResolvedNode {
  /// Re-stamps onto this rebuilt child value the semantic decorations only its
  /// parent authors, read from `slice` — the parent's committed copy of the
  /// child from the parent's last apply.
  ///
  /// A hosted collection (`List`, `Table`) writes each row's
  /// `hostedCollectionItem` onto ITS copy of the row at resolve time; the row's
  /// own committed value never carries it, and the semantics pass derives every
  /// row focus/interaction region from that stamp. A `snapshot()` rebuild that
  /// re-pulls the children's committed values would otherwise serve the
  /// collection with unstamped rows until the collection itself re-resolves —
  /// one frame with zero row regions, which clears focus and silently re-seats
  /// it on row 0 (swift-tui issue #4).
  ///
  /// Only parent-authored decorations are carried: a child never writes its own
  /// `hostedCollectionItem`, so the parent's slice is authoritative for it, and
  /// positional pairing keeps it attached to the same row.
  package mutating func carryParentAuthoredSemantics(from slice: ResolvedNode) {
    guard let hostedCollectionItem = slice.semanticMetadata.hostedCollectionItem else {
      return
    }
    semanticMetadata.hostedCollectionItem = hostedCollectionItem
  }
}
