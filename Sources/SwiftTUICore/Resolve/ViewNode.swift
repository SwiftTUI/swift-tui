@MainActor
package final class ViewNode {
  package let viewNodeID: ViewNodeID
  package let identity: Identity
  package weak var invalidator: (any Invalidating)?
  package weak var ownerGraph: ViewGraph?
  package weak var parent: ViewNode?

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
  private var evaluationDepth: Int
  private var hasCommittedPresence: Bool
  private var suppressesStructuralLifecycle: Bool
  private var nextChangeModifierOrdinal: Int
  private var nextNavigationDestinationModifierOrdinal: Int
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
    evaluationDepth = 0
    hasCommittedPresence = false
    suppressesStructuralLifecycle = false
    nextChangeModifierOrdinal = 0
    nextNavigationDestinationModifierOrdinal = 0
    preparedFrameID = 0
    visitedFrameID = 0
    evaluator = nil
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

    wasPresentAtFrameStart = hasCommittedPresence
    wasVisitedThisFrame = false
    previousChildrenIdentities = children.map(\.identity)
    previousLifecycleMetadata = lifecycleMetadata
    currentBodyStateSlotCount = 0
    pendingChangeHandlerIDs.removeAll(keepingCapacity: true)
    nextChangeModifierOrdinal = 0
    nextNavigationDestinationModifierOrdinal = 0
    preparedFrameID = frameID
  }

  package func beginEvaluation(
    frameID: UInt64,
    invalidator: (any Invalidating)?,
    suppressesStructuralLifecycle: Bool = false
  ) {
    prepareForFrame(frameID)
    self.suppressesStructuralLifecycle = suppressesStructuralLifecycle
    if evaluationDepth == 0 {
      self.invalidator = invalidator
      wasVisitedThisFrame = true
      visitedFrameID = frameID
      isDirty = false
      currentBodyStateSlotCount = 0
      _ = dependencyTracker.reset()
    }
    evaluationDepth += 1
  }

  package func beginReuse(
    frameID: UInt64,
    invalidator: (any Invalidating)?
  ) {
    prepareForFrame(frameID)
    self.invalidator = invalidator
    wasVisitedThisFrame = true
    visitedFrameID = frameID
    isDirty = false
  }

  package func finishEvaluation(
    accessedStateSlots: Int
  ) -> Bool {
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
    dependencyTracker.recordStateRead(key)
  }

  package func setStateSlot<Value>(
    ordinal: Int,
    value: Value,
    invalidationIdentity: Identity? = nil
  ) {
    var slot = stateSlots[ordinal] ?? .init()
    let didChange = slot.set(value)
    stateSlots[ordinal] = slot
    if didChange {
      ownerGraph?.queueDirtyForStateChange(
        .init(owner: viewNodeID, ordinal: ordinal)
      )
      let invalidationIdentity = invalidationIdentity ?? identity
      let animationRequest = AnimationContextStorage.currentRequest
      let batchID = AnimationContextStorage.currentBatchID
      if animationRequest != .inherit || batchID != nil,
        let animationAware = invalidator as? any AnimationAwareInvalidating
      {
        animationAware.requestInvalidation(
          of: [invalidationIdentity],
          animation: animationRequest,
          batchID: batchID
        )
      } else {
        invalidator?.requestInvalidation(of: [invalidationIdentity])
      }
    }
  }

  /// Stores a value in a state slot without triggering invalidation or
  /// dirtying the graph.  Used by ``ValueAnimationModifier`` to remember
  /// the previous watched value during resolve without causing a
  /// re-resolve cycle.
  package func setStateSlotSilently<Value>(
    ordinal: Int,
    value: Value
  ) {
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
    stateSlots[ordinal] = slot
  }

  package func resetStateSlots() {
    stateSlots.removeAll(keepingCapacity: false)
  }

  package func markDirty() {
    let wasDirty = isDirty
    isDirty = true
    if !wasDirty {
      invalidateCachedSnapshotUpward()
    }
  }

  package func setEvaluator(
    _ evaluator: @escaping @MainActor () -> Void
  ) {
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
    dependencyTracker.recordEnvironmentRead(key)
  }

  package func recordObservableRead(
    _ key: ObjectIdentifier
  ) {
    dependencyTracker.recordObservableRead(key)
  }

  package func requestInvalidation() {
    ownerGraph?.queueDirty([identity])
    invalidator?.requestInvalidation(of: [identity])
  }

  package func setLifecycleState(
    _ lifecycleState: NodeLifecycleState
  ) {
    self.lifecycleState = lifecycleState
  }

  package func claimChangeModifierOrdinal() -> Int {
    defer {
      nextChangeModifierOrdinal += 1
    }
    return nextChangeModifierOrdinal
  }

  package func claimNavigationDestinationModifierOrdinal() -> Int {
    defer {
      nextNavigationDestinationModifierOrdinal += 1
    }
    return nextNavigationDestinationModifierOrdinal
  }

  package func queueChangeHandler(
    _ handlerID: String
  ) {
    guard !pendingChangeHandlerIDs.contains(handlerID) else {
      return
    }
    pendingChangeHandlerIDs.append(handlerID)
  }

  package func apply(
    resolved: ResolvedNode,
    children: [ViewNode]
  ) {
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
      invalidateAncestorCachedSnapshots()
      return
    }

    let newChildrenByIdentity = Set(children.map(\.identity))
    for child in self.children
    where !newChildrenByIdentity.contains(child.identity) && child.parent === self {
      child.parent = nil
    }

    committed = resolved
    isCommittedSnapshotFresh = true
    self.children = children
    for child in children {
      guard child !== self else {
        continue
      }
      child.parent = self
    }
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
    }
    return resolved
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
      && committed.supportsRetainedReuse
      && committed.environmentSnapshot == environment
      // Compare resolve-time transaction *intent* (animation request + batch),
      // not the full snapshot: the per-frame `debugSignature` (the frame's cause
      // summary) otherwise changes every frame and defeats retained reuse for
      // subtrees disjoint from the invalidation. See `TransactionSnapshot.isReuseEquivalent`.
      && committed.transactionSnapshot.isReuseEquivalent(to: transaction)
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
    if registrationCaptureDepth == 0 {
      registeredHandlers.reset()
    }
    registrationCaptureDepth += 1
  }

  package func endRegistrationCapture() {
    registrationCaptureDepth = max(0, registrationCaptureDepth - 1)
  }

  package func recordActionRegistration(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?
  ) {
    registeredHandlers.recordAction(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
  }

  package func recordKeyHandlerRegistration(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.Handler
  ) {
    registeredHandlers.recordKeyHandler(
      identity: identity,
      handler: handler
    )
  }

  package func recordKeyPressHandlerRegistration(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.KeyPressHandler
  ) {
    registeredHandlers.recordKeyPressHandler(
      identity: identity,
      handler: handler
    )
  }

  package func recordPasteHandlerRegistration(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.PasteHandler
  ) {
    registeredHandlers.recordPasteHandler(
      identity: identity,
      handler: handler
    )
  }

  package func recordTerminationHandlerRegistration(
    identity: Identity,
    handler: @escaping LocalTerminationRegistry.Handler
  ) {
    registeredHandlers.recordTerminationHandler(
      identity: identity,
      handler: handler
    )
  }

  package func recordPointerHandlerRegistration(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.Handler
  ) {
    registeredHandlers.recordPointerHandler(
      routeID: routeID,
      handler: handler
    )
  }

  package func recordPointerHoverHandlerRegistration(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.HoverHandler
  ) {
    registeredHandlers.recordPointerHoverHandler(
      routeID: routeID,
      handler: handler
    )
  }

  package func recordGestureRegistration(
    identity: Identity,
    recognizer: AnyGestureRecognizer
  ) {
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
    registeredHandlers.recordGestureStateBinding(
      identity: identity,
      binding: binding
    )
  }

  package func recordDefaultFocus(
    _ registration: DefaultFocusScopeRegistrationSnapshot
  ) {
    registeredHandlers.recordDefaultFocus(registration)
  }

  package func recordDefaultFocus(
    _ registration: DefaultFocusCandidateRegistrationSnapshot
  ) {
    registeredHandlers.recordDefaultFocus(registration)
  }

  package func recordFocusBindingRegistration(
    _ registration: FocusBindingRegistrationSnapshot
  ) {
    registeredHandlers.recordFocusBinding(registration)
  }

  package func recordFocusedValuesRegistration(
    _ registration: FocusedValuesRegistrationSnapshot
  ) {
    registeredHandlers.recordFocusedValues(registration)
  }

  package func recordScrollPositionRegistration(
    _ registration: ScrollPositionRegistrationSnapshot
  ) {
    registeredHandlers.recordScrollPosition(registration)
  }

  package func recordLifecycleAppearRegistration(
    _ registration: LifecycleHandlerRegistration
  ) {
    registeredHandlers.recordLifecycleAppear(
      registration
    )
  }

  package func recordLifecycleDisappearRegistration(
    _ registration: LifecycleHandlerRegistration
  ) {
    registeredHandlers.recordLifecycleDisappear(
      registration
    )
  }

  package func recordLifecycleChangeRegistration(
    _ registration: LifecycleHandlerRegistration
  ) {
    registeredHandlers.recordLifecycleChange(
      registration
    )
  }

  package func recordTaskRegistration(
    identity: Identity,
    registration: TaskRegistration
  ) {
    registeredHandlers.recordTask(
      identity: identity,
      registration: registration
    )
  }

  package func recordPreferenceObservationRegistration(
    _ registration: PreferenceObservationRegistrationSnapshot
  ) {
    registeredHandlers.recordPreferenceObservation(registration)
  }

  package func recordCommandRegistration(
    _ registration: CommandRegistrySnapshot
  ) {
    registeredHandlers.recordCommand(registration)
  }

  package func recordDropDestinationRegistration(
    _ registration: DropDestinationRegistrySnapshot
  ) {
    registeredHandlers.recordDropDestination(registration)
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
    registrations.restore(from: registeredHandlers)
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
    var current: ViewNode? = self
    var visited: Set<ObjectIdentifier> = []

    while let node = current {
      let nodeID = ObjectIdentifier(node)
      guard visited.insert(nodeID).inserted else {
        return
      }
      node.isCommittedSnapshotFresh = false
      current = node.parent
    }
  }

  private func invalidateAncestorCachedSnapshots() {
    var current = parent
    var visited: Set<ObjectIdentifier> = []

    while let node = current {
      let nodeID = ObjectIdentifier(node)
      guard visited.insert(nodeID).inserted else {
        return
      }
      node.isCommittedSnapshotFresh = false
      current = node.parent
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
    self.hasCommittedPresence = hasCommittedPresence
  }

  package func setSuppressesStructuralLifecycle(
    _ suppressesStructuralLifecycle: Bool
  ) {
    self.suppressesStructuralLifecycle = suppressesStructuralLifecycle
  }
}

extension ViewNode {
  package struct Checkpoint {
    package var viewNodeID: ViewNodeID
    package var invalidator: (any Invalidating)?
    package var ownerGraph: ViewGraph?
    package var parent: ViewNode?
    package var committed: ResolvedNode
    package var isCommittedSnapshotFresh: Bool
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
    package var evaluationDepth: Int
    package var hasCommittedPresence: Bool
    package var suppressesStructuralLifecycle: Bool
    package var nextChangeModifierOrdinal: Int
    package var nextNavigationDestinationModifierOrdinal: Int
    package var preparedFrameID: UInt64
    package var visitedFrameID: UInt64
    package var evaluator: (@MainActor () -> Void)?
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      viewNodeID: viewNodeID,
      invalidator: invalidator,
      ownerGraph: ownerGraph,
      parent: parent,
      committed: committed,
      isCommittedSnapshotFresh: isCommittedSnapshotFresh,
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
      evaluationDepth: evaluationDepth,
      hasCommittedPresence: hasCommittedPresence,
      suppressesStructuralLifecycle: suppressesStructuralLifecycle,
      nextChangeModifierOrdinal: nextChangeModifierOrdinal,
      nextNavigationDestinationModifierOrdinal: nextNavigationDestinationModifierOrdinal,
      preparedFrameID: preparedFrameID,
      visitedFrameID: visitedFrameID,
      evaluator: evaluator
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
    committed = checkpoint.committed
    isCommittedSnapshotFresh = checkpoint.isCommittedSnapshotFresh
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
    evaluationDepth = checkpoint.evaluationDepth
    hasCommittedPresence = checkpoint.hasCommittedPresence
    suppressesStructuralLifecycle = checkpoint.suppressesStructuralLifecycle
    nextChangeModifierOrdinal = checkpoint.nextChangeModifierOrdinal
    nextNavigationDestinationModifierOrdinal =
      checkpoint.nextNavigationDestinationModifierOrdinal
    preparedFrameID = checkpoint.preparedFrameID
    visitedFrameID = checkpoint.visitedFrameID
    evaluator = checkpoint.evaluator
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
