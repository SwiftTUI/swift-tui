@MainActor
package final class ViewNode {
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
  private var nextChangeModifierOrdinal: Int
  private var preparedFrameID: UInt64
  private var visitedFrameID: UInt64
  private var evaluator: (@MainActor () -> Void)?

  package init(
    identity: Identity
  ) {
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
    nextChangeModifierOrdinal = 0
    preparedFrameID = 0
    visitedFrameID = 0
    evaluator = nil
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
    preparedFrameID = frameID
  }

  package func beginEvaluation(
    frameID: UInt64,
    invalidator: (any Invalidating)?
  ) {
    prepareForFrame(frameID)
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

    dependencyTracker.recordStateRead(
      .init(identity: identity, ordinal: ordinal)
    )

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

  package func setStateSlot<Value>(
    ordinal: Int,
    value: Value
  ) {
    var slot = stateSlots[ordinal] ?? .init()
    let didChange = slot.set(value)
    stateSlots[ordinal] = slot
    if didChange {
      ownerGraph?.queueDirtyForStateChange(
        .init(identity: identity, ordinal: ordinal)
      )
      let animationRequest = AnimationContextStorage.currentRequest
      let batchID = AnimationContextStorage.currentBatchID
      if animationRequest != .inherit || batchID != nil,
        let animationAware = invalidator as? any AnimationAwareInvalidating
      {
        animationAware.requestInvalidation(
          of: [identity],
          animation: animationRequest,
          batchID: batchID
        )
      } else {
        invalidator?.requestInvalidation(of: [identity])
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
      && committed.transactionSnapshot == transaction
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

  package func recordGestureRegistration(
    identity: Identity,
    recognizer: AnyGestureRecognizer
  ) {
    registeredHandlers.recordGesture(
      identity: identity,
      recognizer: recognizer
    )
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
    handlerID: String,
    handler: @escaping LocalLifecycleRegistry.Handler
  ) {
    registeredHandlers.recordLifecycleAppear(
      handlerID: handlerID,
      handler: handler
    )
  }

  package func recordLifecycleDisappearRegistration(
    handlerID: String,
    handler: @escaping LocalLifecycleRegistry.Handler
  ) {
    registeredHandlers.recordLifecycleDisappear(
      handlerID: handlerID,
      handler: handler
    )
  }

  package func recordLifecycleChangeRegistration(
    handlerID: String,
    handler: @escaping LocalLifecycleRegistry.Handler
  ) {
    registeredHandlers.recordLifecycleChange(
      handlerID: handlerID,
      handler: handler
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
}

// MARK: - Committed-field forwarding accessors
//
// Prior to Item 6 of `docs/proposals/ARCHITECTURE_NOTES.md` these were ~14 stored mirror
// fields on ViewNode that were copied one-by-one out of each new
// ResolvedNode during `apply(resolved:children:)`.  The mirror had two
// problems:
//
// - drift risk: nothing enforced that the scattered fields stayed
//   consistent with the most-recently-applied ResolvedNode.
// - boilerplate: every new ResolvedNode field required touching
//   `apply()`, `snapshot()`, and both inits.
//
// Now they're derived from `committed: ResolvedNode`, which is a single
// stored field.  External readers see the same API they did before.
// There are no setters: all writes must go through
// `apply(resolved:children:)`.
extension ViewNode {
  package var resolvedIdentity: Identity { committed.identity }
  package var kind: NodeKind { committed.kind }
  package var environmentSnapshot: EnvironmentSnapshot { committed.environmentSnapshot }
  package var transactionSnapshot: TransactionSnapshot { committed.transactionSnapshot }
  package var layoutBehavior: LayoutBehavior { committed.layoutBehavior }
  package var layoutMetadata: LayoutMetadata { committed.layoutMetadata }
  package var drawMetadata: DrawMetadata { committed.drawMetadata }
  package var semanticMetadata: SemanticMetadata { committed.semanticMetadata }
  package var lifecycleMetadata: LifecycleMetadata { committed.lifecycleMetadata }
  package var drawPayload: DrawPayload { committed.drawPayload }
  package var intrinsicSize: CellSize? { committed.intrinsicSize }
  package var indexedChildSource: (any IndexedChildSource)? { committed.indexedChildSource }
  package var preferenceValues: PreferenceValues { committed.preferenceValues }
  package var supportsRetainedReuse: Bool { committed.supportsRetainedReuse }

  /// Derived on demand from `committed.children`.  Previously a stored
  /// field that was set in `apply()`; now computed so it can never drift
  /// from its source.
  package var childDescriptors: [ChildDescriptor] {
    committed.children.map(ChildDescriptor.init)
  }
}
