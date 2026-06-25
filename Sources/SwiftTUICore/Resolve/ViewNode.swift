@MainActor
package final class ViewNode {
  package let viewNodeID: ViewNodeID
  package let identity: Identity
  package weak var invalidator: (any Invalidating)?
  package weak var ownerGraph: ViewGraph?
  package weak var parent: ViewNode?
  /// The node whose body resolution evaluated this node, captured at
  /// outermost `beginEvaluation`. Bridges island seams in the upward
  /// invalidation walks: capture-hosted content (scoped content payloads, AnyView
  /// shells, `.id`-re-rooted subtrees) is reachable from its host only
  /// through body resolution, not `parent` links, so a dirty island could
  /// not reach its host spine and the spine was wrongly retained-reused
  /// over it (the divergent-identity orphaning bug). Past the seam the walk
  /// sets `hasStaleIslandDescendant` (reuse denial) rather than clearing
  /// snapshot freshness — see `invalidateCachedSnapshots(startingAt:)`.
  /// Never cleared when a frontier evaluator re-runs outside an enclosing
  /// resolution (`ViewNodeContext.current == nil` there); weak, so a
  /// vanished host degrades to the old walk-stops-here behavior.
  package private(set) weak var evaluationHost: ViewNode?

  /// Set when a node behind an island seam below this node was dirtied or
  /// re-applied; consumed only by `canReuse`, so retained reuse cannot skip
  /// the body re-resolve that re-captures the island content by value.
  /// Cleared by `apply(resolved:children:)` (the body re-run that produced
  /// the apply re-resolved everything below, islands included). Kept
  /// separate from `isCommittedSnapshotFresh` deliberately: freshness
  /// drives `snapshot()`'s rebuild-from-live-children, which cannot span an
  /// island seam — clearing it above a seam truncates the rebuilt tree.
  package private(set) var hasStaleIslandDescendant: Bool

  /// The most-recently-committed `ResolvedNode` for this node.
  ///
  /// This is the single source of truth for the per-node render-tree
  /// state that used to live in ~14 scattered mirror fields (`kind`,
  /// `layoutBehavior`, `drawMetadata`, and so on).  Those accessors still
  /// exist as computed properties that forward to `committed`, so
  /// external readers see the same API they did before Item 6.
  ///
  /// Two invariants to be aware of:
  ///
  /// 1. `committed.children` holds the child `ResolvedNode`s passed to
  ///    the most recent `apply(resolved:children:)`.  It may go stale
  ///    between commits — if a descendant is re-applied, the parent's
  ///    `committed.children` is not automatically updated.
  ///    `isCommittedSnapshotFresh` tracks that.
  /// 2. `committed.identity` plays the role of the old
  ///    `resolvedIdentity` field: it's the identity the resolved tree
  ///    was built with, which may differ from `self.identity` when a
  ///    registration alias remaps identity during resolve.
  package private(set) var committed: ResolvedNode

  /// Whether `committed.children` still reflects the current state of
  /// descendant `ViewNode`s.
  ///
  /// Flipped `false` when any descendant is dirtied or re-applied (via
  /// `invalidateCachedSnapshotUpward` / `invalidateAncestorCachedSnapshots`).
  /// Flipped `true` by `apply(resolved:children:)` and by successful
  /// `snapshot()` rebuilds.
  ///
  /// Also doubles as the "have I been committed at least once" flag —
  /// `init` leaves it `false` until the first `apply`, so `canReuse`
  /// correctly refuses to reuse an untouched node.
  private var isCommittedSnapshotFresh: Bool

  package private(set) var children: [ViewNode]
  package private(set) var stateSlots: [Int: AnyStateSlot]
  package private(set) var dependencies: DependencySet
  package private(set) var lifecycleState: NodeLifecycleState
  package private(set) var registeredHandlers: NodeHandlers

  package var isDirty: Bool

  package var wasPresentAtFrameStart: Bool
  package var wasVisitedThisFrame: Bool
  package var previousChildrenIdentities: [Identity]
  package var previousLifecycleMetadata: LifecycleMetadata
  package var bodyStateSlotCount: Int?
  package var currentBodyStateSlotCount: Int
  package private(set) var pendingChangeHandlerIDs: [String]

  private let dependencyTracker: DependencyTracker
  private var registrationCaptureDepth: Int
  private var runtimeRegistrationMutationGeneration: UInt64
  private var checkpointMutationGeneration: UInt64
  private var evaluationDepth: Int
  private var hasCommittedPresence: Bool
  private var suppressesStructuralLifecycle: Bool
  private var nextChangeModifierOrdinal: Int
  private var nextNavigationDestinationModifierOrdinal: Int
  private var nextTaskModifierOrdinal: Int
  private var preparedFrameID: UInt64
  private var visitedFrameID: UInt64
  private var evaluator: (@MainActor () -> Void)?

  package init(
    viewNodeID: ViewNodeID,
    identity: Identity
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    committed = ResolvedNode(
      identity: identity,
      kind: .view("EmptyView")
    )
    isCommittedSnapshotFresh = false
    hasStaleIslandDescendant = false
    children = []
    stateSlots = [:]
    dependencies = .init()
    lifecycleState = .alive
    registeredHandlers = .init()
    isDirty = true
    wasPresentAtFrameStart = false
    wasVisitedThisFrame = false
    previousChildrenIdentities = []
    previousLifecycleMetadata = .init()
    bodyStateSlotCount = nil
    currentBodyStateSlotCount = 0
    pendingChangeHandlerIDs = []
    dependencyTracker = .init()
    registrationCaptureDepth = 0
    runtimeRegistrationMutationGeneration = 0
    checkpointMutationGeneration = 0
    evaluationDepth = 0
    hasCommittedPresence = false
    suppressesStructuralLifecycle = false
    nextChangeModifierOrdinal = 0
    nextNavigationDestinationModifierOrdinal = 0
    nextTaskModifierOrdinal = 0
    preparedFrameID = 0
    visitedFrameID = 0
    evaluator = nil
  }

  package func recordCheckpointMutation() {
    checkpointMutationGeneration &+= 1
  }

  package var currentCheckpointMutationGeneration: UInt64 {
    checkpointMutationGeneration
  }

  package convenience init(
    identity: Identity
  ) {
    self.init(
      viewNodeID: ViewNodeID(rawValue: 0),
      identity: identity
    )
  }

  package func prepareForFrame(
    _ frameID: UInt64
  ) {
    guard preparedFrameID != frameID else {
      return
    }

    recordCheckpointMutation()
    wasPresentAtFrameStart = hasCommittedPresence
    wasVisitedThisFrame = false
    previousChildrenIdentities = children.map(\.identity)
    previousLifecycleMetadata = lifecycleMetadata
    currentBodyStateSlotCount = 0
    pendingChangeHandlerIDs.removeAll(keepingCapacity: true)
    nextChangeModifierOrdinal = 0
    nextNavigationDestinationModifierOrdinal = 0
    nextTaskModifierOrdinal = 0
    preparedFrameID = frameID
  }

  package func beginEvaluation(
    frameID: UInt64,
    invalidator: (any Invalidating)?,
    suppressesStructuralLifecycle: Bool = false
  ) {
    prepareForFrame(frameID)
    recordCheckpointMutation()
    self.suppressesStructuralLifecycle = suppressesStructuralLifecycle
    if evaluationDepth == 0 {
      self.invalidator = invalidator
      if let host = ViewNodeContext.current, host !== self {
        evaluationHost = host
      }
      wasVisitedThisFrame = true
      visitedFrameID = frameID
      isDirty = false
      currentBodyStateSlotCount = 0
      nextChangeModifierOrdinal = 0
      nextNavigationDestinationModifierOrdinal = 0
      nextTaskModifierOrdinal = 0
      _ = dependencyTracker.reset()
    }
    evaluationDepth += 1
  }

  package func beginReuse(
    frameID: UInt64,
    invalidator: (any Invalidating)?
  ) {
    prepareForFrame(frameID)
    recordCheckpointMutation()
    self.invalidator = invalidator
    wasVisitedThisFrame = true
    visitedFrameID = frameID
    isDirty = false
  }

  package func finishEvaluation(
    accessedStateSlots: Int
  ) -> Bool {
    recordCheckpointMutation()
    bodyStateSlotCount = max(bodyStateSlotCount ?? 0, accessedStateSlots)
    evaluationDepth = max(0, evaluationDepth - 1)
    guard evaluationDepth == 0 else {
      return false
    }

    dependencies = dependencyTracker.reset()
    return true
  }

  package func hasStateSlot(
    ordinal: Int
  ) -> Bool {
    stateSlots[ordinal] != nil
  }

  package func stateSlot<Value>(
    ordinal: Int,
    seed: @autoclosure () -> Value
  ) -> Value {
    recordCheckpointMutation()
    var slot = stateSlots[ordinal] ?? .init()
    slot.initializeIfNeeded(with: seed())
    stateSlots[ordinal] = slot

    let readKey = StateSlotKey(owner: viewNodeID, ordinal: ordinal)
    if ReaderAttributionConfiguration.isEnabled,
      let reader = ViewNodeContext.current
    {
      // Reader-attributed: the dependency belongs to the node actually
      // evaluating this read (which may be a descendant consuming a projected
      // binding), not the slot owner. A genuine self-read records on self
      // (reader == self == owner), exactly as before.
      reader.recordStateReadDependency(readKey)
    } else {
      dependencyTracker.recordStateRead(readKey)
    }

    guard slot.stores(Value.self) else {
      let slotTypes = stateSlots.keys.sorted().map { index in
        "\(index):\(stateSlots[index]?.storedTypeDescription ?? "missing")"
      }.joined(separator: ", ")
      fatalError(
        "State slot type mismatch on node \(identity) ordinal \(ordinal). Expected \(Value.self), found \(slot.storedTypeDescription). Slots: [\(slotTypes)]"
      )
    }

    return slot.value(as: Value.self)
  }

  /// Records a state-read dependency on *this* node's tracker. Used by
  /// reader-attributed reads so the dependency lands on the evaluating reader
  /// rather than the slot owner (see ``ReaderAttributionConfiguration``).
  package func recordStateReadDependency(
    _ key: StateSlotKey
  ) {
    recordCheckpointMutation()
    dependencyTracker.recordStateRead(key)
  }

  package func setStateSlot<Value>(
    ordinal: Int,
    value: Value,
    invalidationIdentity: Identity? = nil
  ) {
    recordCheckpointMutation()
    var slot = stateSlots[ordinal] ?? .init()
    let didChange = slot.set(value)
    stateSlots[ordinal] = slot
    if didChange {
      let key = StateSlotKey(owner: viewNodeID, ordinal: ordinal)
      ownerGraph?.queueDirtyForStateChange(key)
      let invalidationIdentities = stateChangeInvalidationIdentities(
        for: key,
        explicit: invalidationIdentity
      )
      InvalidationSourceTrace.note("state-write", invalidationIdentities)
      let animationRequest = AnimationContextStorage.currentRequest
      let batchID = AnimationContextStorage.currentBatchID
      if animationRequest != .inherit || batchID != nil,
        let animationAware = invalidator as? any AnimationAwareInvalidating
      {
        animationAware.requestInvalidation(
          of: invalidationIdentities,
          animation: animationRequest,
          batchID: batchID
        )
      } else {
        invalidator?.requestInvalidation(of: invalidationIdentities)
      }
    }
  }

  /// The identities to invalidate for a state-slot write.
  ///
  /// Legacy (reader attribution off): a single owner identity — the explicit
  /// override when provided, else this node's identity — so the owner's whole
  /// subtree re-resolves. This is the write-side mirror of the always-dirty-owner
  /// term in ``ViewGraphInvalidationPlanner/stateChangeDirtyNodeIDs(for:stateSlotDependents:)``.
  ///
  /// Reader-attributed (flag on): the genuine readers recorded for this slot, so
  /// a disjoint subtree (such as a sheet/palette background that only *projects*
  /// the binding) is spared — completing the read-side attribution in
  /// ``stateSlot(ordinal:seed:)``. Without this, the owner identity is still
  /// invalidated and `conflictsWithInvalidation` blocks the whole background as
  /// an ancestor, defeating reader attribution on open. Falls back to the owner
  /// identity when no readers were recorded (deferred / conditional reads) so a
  /// change is never dropped.
  private func stateChangeInvalidationIdentities(
    for key: StateSlotKey,
    explicit: Identity?
  ) -> Set<Identity> {
    let ownerIdentity = explicit ?? identity
    guard ReaderAttributionConfiguration.isEnabled,
      let ownerGraph
    else {
      return [ownerIdentity]
    }
    let readers = ownerGraph.stateDependentIdentities(for: key)
    return readers.isEmpty ? [ownerIdentity] : readers
  }

  /// Stores a value in a state slot without triggering invalidation or
  /// dirtying the graph.  Used by ``ValueAnimationModifier`` to remember
  /// the previous watched value during resolve without causing a
  /// re-resolve cycle.
  package func setStateSlotSilently<Value>(
    ordinal: Int,
    value: Value
  ) {
    recordCheckpointMutation()
    var slot = stateSlots[ordinal] ?? .init()
    _ = slot.set(value)
    stateSlots[ordinal] = slot
  }

  package func stateSlotStorage(
    ordinal: Int
  ) -> AnyStateSlot? {
    stateSlots[ordinal]
  }

  package func restoreStateSlot(
    ordinal: Int,
    slot: AnyStateSlot
  ) {
    recordCheckpointMutation()
    stateSlots[ordinal] = slot
  }

  package func resetStateSlots() {
    recordCheckpointMutation()
    stateSlots.removeAll(keepingCapacity: false)
  }

  package func markDirty() {
    let wasDirty = isDirty
    recordCheckpointMutation()
    isDirty = true
    if !wasDirty {
      invalidateCachedSnapshotUpward()
    }
  }

  package func setEvaluator(
    _ evaluator: @escaping @MainActor () -> Void
  ) {
    recordCheckpointMutation()
    self.evaluator = evaluator
  }

  package func evaluate() {
    evaluator?()
  }

  package var hasEvaluator: Bool {
    evaluator != nil
  }

  package var isAtOutermostEvaluationDepth: Bool {
    evaluationDepth == 1
  }

  package func recordEnvironmentRead(
    _ key: ObjectIdentifier
  ) {
    recordCheckpointMutation()
    dependencyTracker.recordEnvironmentRead(key)
  }

  package func recordObservableRead(
    _ key: ObjectIdentifier
  ) {
    recordCheckpointMutation()
    dependencyTracker.recordObservableRead(key)
  }

  /// Records an observable read *with* the key path that was read. Records the
  /// bare object token too (additive), so the node stays discoverable in the
  /// object-token index and a key-path miss always falls back to object
  /// granularity. Used by the key-path holding seams (`@Bindable`).
  package func recordObservableRead(
    _ key: ObjectIdentifier,
    keyPath: AnyKeyPath
  ) {
    recordCheckpointMutation()
    dependencyTracker.recordObservableRead(key)
    dependencyTracker.recordObservableKeyPathRead(
      ObservableKeyPathKey(object: key, keyPath: keyPath)
    )
  }

  package func requestInvalidation() {
    ownerGraph?.queueDirty([identity])
    invalidator?.requestInvalidation(of: [identity])
  }

  package func setLifecycleState(
    _ lifecycleState: NodeLifecycleState
  ) {
    recordCheckpointMutation()
    self.lifecycleState = lifecycleState
  }

  package func claimChangeModifierOrdinal() -> Int {
    recordCheckpointMutation()
    defer {
      nextChangeModifierOrdinal += 1
    }
    return nextChangeModifierOrdinal
  }

  package func claimNavigationDestinationModifierOrdinal() -> Int {
    recordCheckpointMutation()
    defer {
      nextNavigationDestinationModifierOrdinal += 1
    }
    return nextNavigationDestinationModifierOrdinal
  }

  package func claimTaskModifierOrdinal() -> Int {
    recordCheckpointMutation()
    defer {
      nextTaskModifierOrdinal += 1
    }
    return nextTaskModifierOrdinal
  }

  package func queueChangeHandler(
    _ handlerID: String
  ) {
    guard !pendingChangeHandlerIDs.contains(handlerID) else {
      return
    }
    recordCheckpointMutation()
    pendingChangeHandlerIDs.append(handlerID)
  }

  package func apply(
    resolved: ResolvedNode,
    children: [ViewNode]
  ) {
    recordCheckpointMutation()
    refreshChildResolvedMetadata(
      from: resolved.children,
      children: children
    )
    let resolved = resolvedWithRuntimeNodeIDs(
      resolved,
      children: children
    )
    // Reuse fast path: an unchanged reused subtree hands back exactly the nodes
    // already attached, in the same order (recordReusedSubtree resolves each child
    // via nodeForIdentity). The detach and re-parent loops below are then no-ops
    // and the identity Set is pure O(children) overhead, so refresh the committed
    // snapshot and bail. Structural changes (reorder/add/remove) fail the check and
    // take the full reconciliation path.
    if childrenReferToSameNodes(as: children) {
      committed = resolved
      isCommittedSnapshotFresh = true
      hasStaleIslandDescendant = false
      invalidateAncestorCachedSnapshots()
      return
    }

    let newChildrenByIdentity = Set(children.map(\.identity))
    for child in self.children
    where !newChildrenByIdentity.contains(child.identity) && child.parent === self {
      child.recordCheckpointMutation()
      child.parent = nil
    }

    committed = resolved
    isCommittedSnapshotFresh = true
    hasStaleIslandDescendant = false
    self.children = children
    for child in children {
      guard child !== self else {
        continue
      }
      child.recordCheckpointMutation()
      child.parent = self
    }
    invalidateAncestorCachedSnapshots()
  }

  package func applyRetainedSnapshot(
    _ snapshot: ResolvedNode
  ) {
    recordCheckpointMutation()
    var snapshot = snapshot
    snapshot.viewNodeID = viewNodeID
    snapshot.recomputeSubtreeRuntimeNodeIDsStamped()
    committed = snapshot
    isCommittedSnapshotFresh = true
    invalidateAncestorCachedSnapshots()
  }

  private func refreshChildResolvedMetadata(
    from resolvedChildren: [ResolvedNode],
    children: [ViewNode]
  ) {
    guard resolvedChildren.count == children.count else {
      return
    }

    for (resolvedChild, child) in zip(resolvedChildren, children) {
      child.refreshResolvedMetadata(from: resolvedChild)
    }
  }

  package func refreshResolvedMetadata(
    from resolved: ResolvedNode
  ) {
    recordCheckpointMutation()
    committed.structuralPath = resolved.structuralPath
    committed.structuralEdgeRole = resolved.structuralEdgeRole
    committed.entityIdentity = resolved.entityIdentity
    committed.entityStructuralPath = resolved.entityStructuralPath
    committed.declarationOwnerEdge = resolved.declarationOwnerEdge
    committed.typeDiscriminator = resolved.typeDiscriminator
  }

  private func childrenReferToSameNodes(
    as candidate: [ViewNode]
  ) -> Bool {
    guard candidate.count == children.count else {
      return false
    }
    for index in candidate.indices where candidate[index] !== children[index] {
      return false
    }
    return true
  }

  private func resolvedWithRuntimeNodeIDs(
    _ resolved: ResolvedNode,
    children: [ViewNode]
  ) -> ResolvedNode {
    // Fast path: a subtree value whose stamps are already complete and whose
    // root carries this node's ID was produced from committed snapshots
    // (retained reuse hands back `node.snapshot()`, child evaluations return
    // their freshly committed roots), so every descendant stamp is already
    // the one this walk would write.  Skipping the recursion keeps a fresh
    // ancestor's apply O(direct children) instead of O(subtree) struct
    // copies over large reused regions.  The flag is trustworthy because the
    // count-guard-unmet branch below withdraws it whenever child stamps were
    // spliced in unverified (Group splices, capture-host injections).  The
    // remaining seam where a stale interior could hide under a matching root
    // is the known divergent-resolvedIdentity capture-host orphaning bug
    // (reuse-host guard work tracks it); the debug assertion below trips
    // loudly if any such value reaches a skip.
    if resolved.subtreeRuntimeNodeIDsStamped, resolved.viewNodeID == viewNodeID {
      assertResolvedStampsCoherent(resolved, children: children)
      return resolved
    }
    var resolved = resolved
    resolved.viewNodeID = viewNodeID
    if resolved.children.count == children.count {
      let stampedChildren = zip(resolved.children, children).map { childResolved, childNode in
        childNode.resolvedWithRuntimeNodeIDs(
          childResolved,
          children: childNode.children
        )
      }
      resolved.setChildrenPreservingDerivedState(stampedChildren)
      resolved.recomputeSubtreeRuntimeNodeIDsStamped()
    } else {
      // Count guard unmet (Group splices, passthrough bodies, capture-host
      // injections like the toolbar reconcile): the walk could not pair this
      // value's children with this node's live children, so the child stamps
      // are unverified and may belong to other live nodes.  Claiming subtree
      // completeness here let a later apply fast-path over foreign stamps
      // (the gallery tab-switch stamp-coherence crash), so withdraw the
      // claim and leave this subtree to the slow restamping path.
      resolved.markSubtreeRuntimeNodeIDsUnstamped()
    }
    return resolved
  }

  /// Debug-only coherence check for the stamping fast path: every value
  /// stamp in the skipped subtree must equal the positionally paired live
  /// node's ID wherever the pairing is defined (count-aligned levels), i.e.
  /// exactly what the full walk would have written.
  private func assertResolvedStampsCoherent(
    _ resolved: ResolvedNode,
    children: [ViewNode]
  ) {
    #if DEBUG
      assert(
        resolved.viewNodeID == viewNodeID,
        "stamp skip: value stamp \(String(describing: resolved.viewNodeID)) "
          + "diverges from live node \(viewNodeID) at \(identity)"
      )
      guard resolved.children.count == children.count else {
        return
      }
      for (childResolved, childNode) in zip(resolved.children, children) {
        childNode.assertResolvedStampsCoherent(
          childResolved,
          children: childNode.children
        )
      }
    #endif
  }

  /// The view value this node was last resolved with, kept to compare against
  /// the next frame's value via ``MemoValueComparator`` for memoized-body reuse.
  /// Populated only when ``MemoReuseConfiguration`` is enabled (or, in DEBUG,
  /// the ``MemoSkipTrace`` diagnostics); `nil` otherwise, so it costs nothing
  /// when the feature is off. Checkpointed so an aborted frame does not leave a
  /// stale value that would mis-compare on the next frame.
  package var memoViewValue: Any?

  /// Whether this node would pass the retained-reuse guards *except* for the
  /// dirty / invalidation-intersection veto — the conjuncts that make a memoized
  /// skip safe (present, snapshot-fresh, island-fresh, reuse support, equal
  /// environment, reuse-equivalent transaction). ANDed with view-value equality
  /// and a deps-clean check by the memo gate.
  package func canMemoReuse(
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot
  ) -> Bool {
    wasPresentAtFrameStart
      && isCommittedSnapshotFresh
      && !hasStaleIslandDescendant
      && committed.supportsRetainedReuse
      && committed.environmentSnapshot == environment
      && committed.transactionSnapshot.isReuseEquivalent(to: transaction)
  }

  /// Whether the node recorded no `@State`/`@Observable`/`@Environment` reads
  /// when it was last resolved — the strictest memo-reuse subset whose output is
  /// a pure function of its view value and environment.
  ///
  /// This indexes only *explicitly attributed* reads. An `@Observable` model read
  /// directly (not via a `Bindable` projection) is tracked by
  /// `withObservationTracking`, not recorded here — so it can report `true` while
  /// still depending on observable state. That case is covered by the `!isDirty`
  /// conjunct the memo gate ANDs alongside this one (an observable mutation dirties
  /// the node before the next frame). Any future memo path MUST keep that `!isDirty`
  /// co-guard; this property alone is not a complete dependency oracle.
  package var hasNoRecordedDependencies: Bool {
    dependencies.stateSlotReads.isEmpty
      && dependencies.observableReads.isEmpty
      && dependencies.environmentReads.isEmpty
  }

  /// Whether the node's recorded dependencies are all *covered by the memo
  /// gate's other conjuncts* — i.e. it recorded no `@State` slot reads, no
  /// `@Observable` reads, and no `@Environment` read of an *uncovered* key.
  ///
  /// `@Environment` reads of keys carried by `environmentSnapshot` ARE allowed:
  /// the gate's `committed.environmentSnapshot == environment` conjunct (in
  /// ``canMemoReuse(environment:transaction:)``) already verifies the whole
  /// snapshot is unchanged, so those reads necessarily return the same value.
  /// This widens reuse to the layout containers (`VStack`/`HStack`/…) that read
  /// layout environment — exactly the boundaries where reusing a whole subtree
  /// pays.
  ///
  /// `uncoveredEnvironmentKeys` names the environment keys deliberately *excluded*
  /// from `environmentSnapshot` equality — the focus/press runtime side-fields
  /// (`focusedIdentity`/`pressedIdentity`), which change every focus move and
  /// would otherwise env-mismatch the whole tree. A read of one is NOT verified
  /// by the snapshot, so it disqualifies the node: focus/press correctness is
  /// enforced by the run loop's retained-reuse suppression scope, which the gate
  /// sits behind in the live path but which the one-shot renderer does not
  /// compute — so a focus reader must never be memo-reused on view-value +
  /// snapshot equality alone.
  ///
  /// `@State` slot reads and `@Observable` reads stay excluded outright: neither
  /// is covered by the environment snapshot. (`!isDirty` catches an observable
  /// mutation, but state-value equality is not yet checked — a further widening.)
  package func hasNoMemoUncoveredDependencies(
    uncoveredEnvironmentKeys: Set<ObjectIdentifier>
  ) -> Bool {
    dependencies.stateSlotReads.isEmpty
      && dependencies.observableReads.isEmpty
      && dependencies.environmentReads.isDisjoint(with: uncoveredEnvironmentKeys)
  }

  package func canReuse(
    frameID: UInt64,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot
  ) -> Bool {
    prepareForFrame(frameID)
    return wasPresentAtFrameStart
      && !wasVisitedThisFrame
      && !isDirty
      && isCommittedSnapshotFresh
      && !hasStaleIslandDescendant
      && committed.supportsRetainedReuse
      && committed.environmentSnapshot == environment
      // Compare resolve-time transaction *intent* (animation request + batch),
      // not the full snapshot: the per-frame `debugSignature` (the frame's cause
      // summary) otherwise changes every frame and defeats retained reuse for
      // subtrees disjoint from the invalidation. See `TransactionSnapshot.isReuseEquivalent`.
      && committed.transactionSnapshot.isReuseEquivalent(to: transaction)
  }

  /// Diagnostic mirror of ``canReuse(frameID:environment:transaction:)``:
  /// returns the first failing condition as a label, or `nil` if `canReuse`
  /// would succeed (so the caller can attribute the denial to invalidation
  /// intersection instead). For `env-mismatch` it records the specific differing
  /// environment keys into ``ReuseDenialTrace``. Used only when the trace is on.
  package func canReuseDenialReason(
    frameID: UInt64,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot
  ) -> String? {
    prepareForFrame(frameID)
    if !wasPresentAtFrameStart { return "not-present" }
    if wasVisitedThisFrame { return "visited" }
    if isDirty { return "dirty" }
    if !isCommittedSnapshotFresh { return "stale-snapshot" }
    if hasStaleIslandDescendant { return "stale-island-descendant" }
    if !committed.supportsRetainedReuse { return "no-retained-support" }
    if committed.environmentSnapshot != environment {
      recordEnvironmentSnapshotDiff(committed.environmentSnapshot, environment)
      return "env-mismatch"
    }
    if !committed.transactionSnapshot.isReuseEquivalent(to: transaction) {
      return "transaction"
    }
    return nil
  }

  private func recordEnvironmentSnapshotDiff(
    _ committed: EnvironmentSnapshot,
    _ current: EnvironmentSnapshot
  ) {
    guard ReuseDenialTrace.isEnabled else { return }
    if committed.debugSignature != current.debugSignature {
      ReuseDenialTrace.recordEnvironmentKeyDiff("debugSignature")
    }
    if committed.style != current.style {
      ReuseDenialTrace.recordEnvironmentKeyDiff("style")
    }
    let committedValues = committed.values
    let currentValues = current.values
    for key in Set(committedValues.keys).union(currentValues.keys)
    where committedValues[key] != currentValues[key] {
      ReuseDenialTrace.recordEnvironmentKeyDiff("val:\(key)")
    }
  }

  package var hasDirtyAncestor: Bool {
    var current = parent
    var visited: Set<ObjectIdentifier> = []

    while let node = current {
      let nodeID = ObjectIdentifier(node)
      guard visited.insert(nodeID).inserted else {
        return false
      }
      if node.isDirty {
        return true
      }
      current = node.parent
    }

    return false
  }

  package func beginRegistrationCapture() {
    recordCheckpointMutation()
    if registrationCaptureDepth == 0 {
      registeredHandlers.reset()
      recordRuntimeRegistrationMutation()
    }
    registrationCaptureDepth += 1
  }

  package func endRegistrationCapture() {
    recordCheckpointMutation()
    registrationCaptureDepth = max(0, registrationCaptureDepth - 1)
  }

  package func recordActionRegistration(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordAction(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
  }

  package func recordActionRegistration(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?,
    owner: RuntimeRegistrationOwnerKey
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordAction(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity,
      owner: owner
    )
  }

  package func recordKeyHandlerRegistration(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.Handler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordKeyHandler(
      identity: identity,
      handler: handler
    )
  }

  package func recordKeyPressHandlerRegistration(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.KeyPressHandler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordKeyPressHandler(
      identity: identity,
      handler: handler
    )
  }

  package func recordPasteHandlerRegistration(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.PasteHandler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordPasteHandler(
      identity: identity,
      handler: handler
    )
  }

  package func recordTerminationHandlerRegistration(
    identity: Identity,
    handler: @escaping LocalTerminationRegistry.Handler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordTerminationHandler(
      identity: identity,
      handler: handler
    )
  }

  package func recordPointerHandlerRegistration(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.Handler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordPointerHandler(
      routeID: routeID,
      handler: handler
    )
  }

  package func recordPointerHoverHandlerRegistration(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.HoverHandler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordPointerHoverHandler(
      routeID: routeID,
      handler: handler
    )
  }

  package func recordGestureRegistration(
    identity: Identity,
    recognizer: AnyGestureRecognizer
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordGesture(
      identity: identity,
      recognizer: recognizer
    )
  }

  package func gestureRegistration(
    for identity: Identity
  ) -> AnyGestureRecognizer? {
    registeredHandlers.gestureRegistrations[identity]
  }

  package func recordGestureStateBinding(
    identity: Identity,
    binding: AnyGestureStateBinding
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordGestureStateBinding(
      identity: identity,
      binding: binding
    )
  }

  package func recordDefaultFocus(
    _ registration: DefaultFocusScopeRegistrationSnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordDefaultFocus(registration)
  }

  package func recordDefaultFocus(
    _ registration: DefaultFocusCandidateRegistrationSnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordDefaultFocus(registration)
  }

  package func recordFocusBindingRegistration(
    _ registration: FocusBindingRegistrationSnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordFocusBinding(registration)
  }

  package func recordFocusedValuesRegistration(
    _ registration: FocusedValuesRegistrationSnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordFocusedValues(registration)
  }

  package func recordScrollPositionRegistration(
    _ registration: ScrollPositionRegistrationSnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordScrollPosition(registration)
  }

  package func recordLifecycleAppearRegistration(
    _ registration: LifecycleHandlerRegistration
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordLifecycleAppear(
      registration
    )
  }

  package func recordLifecycleDisappearRegistration(
    _ registration: LifecycleHandlerRegistration
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordLifecycleDisappear(
      registration
    )
  }

  package func recordLifecycleChangeRegistration(
    _ registration: LifecycleHandlerRegistration
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordLifecycleChange(
      registration
    )
  }

  package func recordTaskRegistration(
    identity: Identity,
    registration: TaskRegistration
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordTask(
      identity: identity,
      registration: registration
    )
  }

  package func recordPreferenceObservationRegistration(
    _ registration: PreferenceObservationRegistrationSnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordPreferenceObservation(registration)
  }

  package func recordCommandRegistration(
    _ registration: CommandRegistrySnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordCommand(registration)
  }

  package func recordDropDestinationRegistration(
    _ registration: DropDestinationRegistrySnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordDropDestination(registration)
  }

  private func recordRuntimeRegistrationMutation() {
    recordCheckpointMutation()
    runtimeRegistrationMutationGeneration &+= 1
  }

  package func runtimeRegistrationFingerprintEntry()
    -> RuntimeRegistrationNodeFingerprint?
  {
    guard registeredHandlers.hasRuntimeRegistrations else {
      return nil
    }
    return RuntimeRegistrationNodeFingerprint(
      viewNodeID: viewNodeID,
      subtreeRoot: identity,
      resolvedIdentity: resolvedIdentity,
      mutationGeneration: runtimeRegistrationMutationGeneration
    )
  }

  package func restoreRuntimeRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    var traversedNodes: Set<ObjectIdentifier> = []
    restoreRuntimeRegistrations(
      into: registrations,
      traversedNodes: &traversedNodes
    )
  }

  package func restoreOwnRuntimeRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    // Handler-less nodes (the bulk of a reused layout/text subtree) restore
    // nothing, so skip the per-registry `restore(from:)` work — which allocates
    // a Set + a filtered pointer-handler copy and touches ~18 registries — when
    // there is provably nothing to restore. `hasRuntimeRegistrations` is the
    // exact disjunction of the families `restore(from:)` reads, so this is a
    // behavior-preserving no-op skip (mirrors the guard at
    // `runtimeRegistrationFingerprintEntry()`).
    guard registeredHandlers.hasRuntimeRegistrations else {
      return
    }
    registrations.restore(from: registeredHandlers)
  }

  package func restoreOwnEffectRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    registrations.restoreEffectRegistrations(from: registeredHandlers)
  }

  private func restoreRuntimeRegistrations(
    into registrations: RuntimeRegistrationSet,
    traversedNodes: inout Set<ObjectIdentifier>
  ) {
    let nodeID = ObjectIdentifier(self)
    guard traversedNodes.insert(nodeID).inserted else {
      return
    }

    restoreOwnRuntimeRegistrations(
      into: registrations
    )

    for child in children {
      child.restoreRuntimeRegistrations(
        into: registrations,
        traversedNodes: &traversedNodes
      )
    }
  }

  package func rebuildRuntimeRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    registrations.resetAll()

    restoreRuntimeRegistrations(
      into: registrations
    )
  }

  /// Whether this node has a cached resolved snapshot available for reuse.
  package var hasCachedSnapshot: Bool {
    isCommittedSnapshotFresh
  }

  package func snapshot() -> ResolvedNode {
    if isCommittedSnapshotFresh {
      return committed
    }

    // Rebuild the whole-subtree snapshot by recursively pulling each
    // child ViewNode's current snapshot.  The `didSet` on
    // `ResolvedNode.children` then recomputes preferenceValues,
    // subtreeNodeCount, and supportsRetainedReuse from the new children.
    var rebuilt = committed
    rebuilt.children = children.map { $0.snapshot() }
    committed = rebuilt
    isCommittedSnapshotFresh = true
    return committed
  }

  private func invalidateCachedSnapshotUpward() {
    invalidateCachedSnapshots(startingAt: self)
  }

  private func invalidateAncestorCachedSnapshots() {
    if let parent {
      invalidateCachedSnapshots(startingAt: parent)
    } else if let evaluationHost {
      invalidateCachedSnapshots(startingAt: evaluationHost, crossedIslandSeam: true)
    }
  }

  /// Walks ancestors propagating "a descendant changed" with split signals.
  ///
  /// Along live `parent` links the walk clears `isCommittedSnapshotFresh`,
  /// whose `snapshot()` rebuild reconstructs the committed mirror from live
  /// children. The moment the walk crosses an island seam (a node reachable
  /// only via `evaluationHost` — capture-hosted content has no parent link to
  /// its host), it switches to setting `hasStaleIslandDescendant` instead and
  /// never touches freshness again: a host's live children do NOT mirror its
  /// committed value across the seam, so clearing its freshness would make
  /// `snapshot()`'s rebuild graft a structurally truncated tree (live
  /// children only) and launder it as fresh — erasing the island interior
  /// from the frame. `hasStaleIslandDescendant` is consumed only by
  /// `canReuse`, denying retained reuse until the host's body re-resolve
  /// re-captures the island by value; `apply` clears it.
  private func invalidateCachedSnapshots(
    startingAt start: ViewNode,
    crossedIslandSeam: Bool = false
  ) {
    var current: ViewNode? = start
    var crossedIslandSeam = crossedIslandSeam
    var visited: Set<ObjectIdentifier> = []

    while let node = current {
      let nodeID = ObjectIdentifier(node)
      guard visited.insert(nodeID).inserted else {
        return
      }
      node.recordCheckpointMutation()
      if crossedIslandSeam {
        node.hasStaleIslandDescendant = true
      } else {
        node.isCommittedSnapshotFresh = false
      }
      if let parent = node.parent {
        current = parent
      } else {
        current = node.evaluationHost
        crossedIslandSeam = crossedIslandSeam || current != nil
      }
    }
  }

  package var participatesInStructuralLifecycle: Bool {
    guard !suppressesStructuralLifecycle else {
      return false
    }
    var ancestor = parent
    while let current = ancestor {
      if current.committed.indexedChildSource != nil {
        return false
      }
      ancestor = current.parent
    }
    return true
  }

  package func isDescendant(
    of ancestor: ViewNode
  ) -> Bool {
    var current = parent
    var visited: Set<ObjectIdentifier> = []

    while let node = current {
      let nodeID = ObjectIdentifier(node)
      guard visited.insert(nodeID).inserted else {
        return false
      }
      if node === ancestor {
        return true
      }
      current = node.parent
    }

    return false
  }

  package func isPrepared(
    for frameID: UInt64
  ) -> Bool {
    preparedFrameID == frameID
  }

  package func visitedThisFrame(
    _ frameID: UInt64
  ) -> Bool {
    prepareForFrame(frameID)
    return visitedFrameID == frameID
  }

  package func setCommittedPresence(
    _ hasCommittedPresence: Bool
  ) {
    recordCheckpointMutation()
    self.hasCommittedPresence = hasCommittedPresence
  }

  package func setSuppressesStructuralLifecycle(
    _ suppressesStructuralLifecycle: Bool
  ) {
    recordCheckpointMutation()
    self.suppressesStructuralLifecycle = suppressesStructuralLifecycle
  }
}

extension ViewNode {
  package struct Checkpoint {
    package var viewNodeID: ViewNodeID
    package var invalidator: (any Invalidating)?
    package var ownerGraph: ViewGraph?
    package var parent: ViewNode?
    package var evaluationHost: ViewNode?
    package var committed: ResolvedNode
    package var isCommittedSnapshotFresh: Bool
    package var hasStaleIslandDescendant: Bool
    package var children: [ViewNode]
    package var stateSlots: [Int: AnyStateSlot]
    package var dependencies: DependencySet
    package var lifecycleState: NodeLifecycleState
    package var registeredHandlers: NodeHandlers
    package var isDirty: Bool
    package var wasPresentAtFrameStart: Bool
    package var wasVisitedThisFrame: Bool
    package var previousChildrenIdentities: [Identity]
    package var previousLifecycleMetadata: LifecycleMetadata
    package var bodyStateSlotCount: Int?
    package var currentBodyStateSlotCount: Int
    package var pendingChangeHandlerIDs: [String]
    package var dependencyTracker: DependencyTracker.Checkpoint
    package var registrationCaptureDepth: Int
    package var runtimeRegistrationMutationGeneration: UInt64
    package var checkpointMutationGeneration: UInt64
    package var evaluationDepth: Int
    package var hasCommittedPresence: Bool
    package var suppressesStructuralLifecycle: Bool
    package var nextChangeModifierOrdinal: Int
    package var nextNavigationDestinationModifierOrdinal: Int
    package var nextTaskModifierOrdinal: Int
    package var preparedFrameID: UInt64
    package var visitedFrameID: UInt64
    package var evaluator: (@MainActor () -> Void)?
    package var memoViewValue: Any?
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      viewNodeID: viewNodeID,
      invalidator: invalidator,
      ownerGraph: ownerGraph,
      parent: parent,
      evaluationHost: evaluationHost,
      committed: committed,
      isCommittedSnapshotFresh: isCommittedSnapshotFresh,
      hasStaleIslandDescendant: hasStaleIslandDescendant,
      children: children,
      stateSlots: stateSlots,
      dependencies: dependencies,
      lifecycleState: lifecycleState,
      registeredHandlers: registeredHandlers,
      isDirty: isDirty,
      wasPresentAtFrameStart: wasPresentAtFrameStart,
      wasVisitedThisFrame: wasVisitedThisFrame,
      previousChildrenIdentities: previousChildrenIdentities,
      previousLifecycleMetadata: previousLifecycleMetadata,
      bodyStateSlotCount: bodyStateSlotCount,
      currentBodyStateSlotCount: currentBodyStateSlotCount,
      pendingChangeHandlerIDs: pendingChangeHandlerIDs,
      dependencyTracker: dependencyTracker.makeCheckpoint(),
      registrationCaptureDepth: registrationCaptureDepth,
      runtimeRegistrationMutationGeneration: runtimeRegistrationMutationGeneration,
      checkpointMutationGeneration: checkpointMutationGeneration,
      evaluationDepth: evaluationDepth,
      hasCommittedPresence: hasCommittedPresence,
      suppressesStructuralLifecycle: suppressesStructuralLifecycle,
      nextChangeModifierOrdinal: nextChangeModifierOrdinal,
      nextNavigationDestinationModifierOrdinal: nextNavigationDestinationModifierOrdinal,
      nextTaskModifierOrdinal: nextTaskModifierOrdinal,
      preparedFrameID: preparedFrameID,
      visitedFrameID: visitedFrameID,
      evaluator: evaluator,
      memoViewValue: memoViewValue
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    precondition(
      checkpoint.viewNodeID == viewNodeID,
      "Cannot restore checkpoint for \(checkpoint.viewNodeID) onto \(viewNodeID)."
    )
    invalidator = checkpoint.invalidator
    ownerGraph = checkpoint.ownerGraph
    parent = checkpoint.parent
    evaluationHost = checkpoint.evaluationHost
    committed = checkpoint.committed
    isCommittedSnapshotFresh = checkpoint.isCommittedSnapshotFresh
    hasStaleIslandDescendant = checkpoint.hasStaleIslandDescendant
    children = checkpoint.children
    stateSlots = checkpoint.stateSlots
    dependencies = checkpoint.dependencies
    lifecycleState = checkpoint.lifecycleState
    registeredHandlers = checkpoint.registeredHandlers
    isDirty = checkpoint.isDirty
    wasPresentAtFrameStart = checkpoint.wasPresentAtFrameStart
    wasVisitedThisFrame = checkpoint.wasVisitedThisFrame
    previousChildrenIdentities = checkpoint.previousChildrenIdentities
    previousLifecycleMetadata = checkpoint.previousLifecycleMetadata
    bodyStateSlotCount = checkpoint.bodyStateSlotCount
    currentBodyStateSlotCount = checkpoint.currentBodyStateSlotCount
    pendingChangeHandlerIDs = checkpoint.pendingChangeHandlerIDs
    dependencyTracker.restoreCheckpoint(checkpoint.dependencyTracker)
    registrationCaptureDepth = checkpoint.registrationCaptureDepth
    runtimeRegistrationMutationGeneration = checkpoint.runtimeRegistrationMutationGeneration
    checkpointMutationGeneration = checkpoint.checkpointMutationGeneration
    evaluationDepth = checkpoint.evaluationDepth
    hasCommittedPresence = checkpoint.hasCommittedPresence
    suppressesStructuralLifecycle = checkpoint.suppressesStructuralLifecycle
    nextChangeModifierOrdinal = checkpoint.nextChangeModifierOrdinal
    nextNavigationDestinationModifierOrdinal =
      checkpoint.nextNavigationDestinationModifierOrdinal
    nextTaskModifierOrdinal = checkpoint.nextTaskModifierOrdinal
    preparedFrameID = checkpoint.preparedFrameID
    visitedFrameID = checkpoint.visitedFrameID
    evaluator = checkpoint.evaluator
    memoViewValue = checkpoint.memoViewValue
  }
}

extension ViewNode {
  package func debugTotalStateSnapshot() -> DebugTotalStateSnapshot {
    DebugTotalStateSnapshot(
      viewNodeID: viewNodeID,
      invalidatorInstalled: invalidator != nil,
      ownerGraphInstalled: ownerGraph != nil,
      parentIdentity: parent?.identity,
      committed: committed,
      isCommittedSnapshotFresh: isCommittedSnapshotFresh,
      hasStaleIslandDescendant: hasStaleIslandDescendant,
      children: children.map(\.identity),
      stateSlots: stateSlots.map { ordinal, slot in
        DebugTotalStateSnapshot.StateSlotSnapshot(
          ordinal: ordinal,
          storedTypeDescription: slot.storedTypeDescription
        )
      }.sorted { lhs, rhs in lhs.ordinal < rhs.ordinal },
      dependencies: dependencies,
      lifecycleState: lifecycleState,
      registeredHandlers: registeredHandlers.debugTotalStateSnapshot(),
      isDirty: isDirty,
      wasPresentAtFrameStart: wasPresentAtFrameStart,
      wasVisitedThisFrame: wasVisitedThisFrame,
      previousChildrenIdentities: previousChildrenIdentities,
      previousLifecycleMetadata: previousLifecycleMetadata,
      bodyStateSlotCount: bodyStateSlotCount,
      currentBodyStateSlotCount: currentBodyStateSlotCount,
      pendingChangeHandlerIDs: pendingChangeHandlerIDs,
      dependencyTracker: dependencyTracker.currentDependencies,
      registrationCaptureDepth: registrationCaptureDepth,
      runtimeRegistrationMutationGeneration: runtimeRegistrationMutationGeneration,
      checkpointMutationGeneration: checkpointMutationGeneration,
      evaluationDepth: evaluationDepth,
      hasCommittedPresence: hasCommittedPresence,
      suppressesStructuralLifecycle: suppressesStructuralLifecycle,
      nextChangeModifierOrdinal: nextChangeModifierOrdinal,
      nextNavigationDestinationModifierOrdinal: nextNavigationDestinationModifierOrdinal,
      preparedFrameID: preparedFrameID,
      visitedFrameID: visitedFrameID,
      evaluatorInstalled: evaluator != nil
    )
  }
}
