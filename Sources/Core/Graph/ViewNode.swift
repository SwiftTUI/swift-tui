@MainActor
package final class ViewNode {
  package let identity: Identity
  package weak var invalidator: (any Invalidating)?
  package weak var ownerGraph: ViewGraph?
  package weak var parent: ViewNode?
  package private(set) var resolvedIdentity: Identity

  package private(set) var children: [ViewNode]
  package private(set) var stateSlots: [AnyStateSlot]
  package private(set) var dependencies: DependencySet
  package private(set) var lifecycleState: NodeLifecycleState
  package private(set) var registeredHandlers: NodeHandlers

  package var kind: NodeKind
  package var environmentSnapshot: EnvironmentSnapshot
  package var transactionSnapshot: TransactionSnapshot
  package var layoutBehavior: LayoutBehavior
  package var layoutMetadata: LayoutMetadata
  package var drawMetadata: DrawMetadata
  package var semanticMetadata: SemanticMetadata
  package var lifecycleMetadata: LifecycleMetadata
  package var drawPayload: DrawPayload
  package var intrinsicSize: Size?
  package var indexedChildSource: (any IndexedChildSource)?
  package var preferenceValues: PreferenceValues
  package var supportsRetainedReuse: Bool
  package var childDescriptors: [ChildDescriptor]
  package var isDirty: Bool

  package var wasPresentAtFrameStart: Bool
  package var wasVisitedThisFrame: Bool
  package var previousChildrenIdentities: [Identity]
  package var previousLifecycleMetadata: LifecycleMetadata
  package var bodyStateSlotCount: Int?
  package var currentBodyStateSlotCount: Int

  private let dependencyTracker: DependencyTracker
  private var cachedResolvedNode: ResolvedNode?
  private var registrationCaptureDepth: Int
  private var evaluationDepth: Int
  private var hasCommittedPresence: Bool
  private var preparedFrameID: UInt64
  private var visitedFrameID: UInt64
  private var evaluator: (@MainActor () -> Void)?

  package init(
    identity: Identity
  ) {
    self.identity = identity
    resolvedIdentity = identity
    children = []
    stateSlots = []
    dependencies = .init()
    lifecycleState = .alive
    registeredHandlers = .init()
    kind = .view("EmptyView")
    environmentSnapshot = .init()
    transactionSnapshot = .init()
    layoutBehavior = .intrinsic
    layoutMetadata = .init()
    drawMetadata = .init()
    semanticMetadata = .init()
    lifecycleMetadata = .init()
    drawPayload = .none
    intrinsicSize = nil
    indexedChildSource = nil
    preferenceValues = .init()
    supportsRetainedReuse = true
    childDescriptors = []
    isDirty = true
    wasPresentAtFrameStart = false
    wasVisitedThisFrame = false
    previousChildrenIdentities = []
    previousLifecycleMetadata = .init()
    bodyStateSlotCount = nil
    currentBodyStateSlotCount = 0
    dependencyTracker = .init()
    registrationCaptureDepth = 0
    evaluationDepth = 0
    hasCommittedPresence = false
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

  package func stateSlot<Value>(
    ordinal: Int,
    seed: @autoclosure () -> Value
  ) -> Value {
    if ordinal >= stateSlots.count {
      while stateSlots.count <= ordinal {
        stateSlots.append(.init())
      }
    }

    stateSlots[ordinal].initializeIfNeeded(with: seed())

    dependencyTracker.recordStateRead(
      .init(identity: identity, ordinal: ordinal)
    )
    return stateSlots[ordinal].value(as: Value.self)
  }

  package func setStateSlot<Value>(
    ordinal: Int,
    value: Value
  ) {
    if ordinal >= stateSlots.count {
      while stateSlots.count <= ordinal {
        stateSlots.append(.init())
      }
    }

    let didChange = stateSlots[ordinal].set(value)
    if didChange {
      ownerGraph?.queueDirtyForStateChange(
        .init(identity: identity, ordinal: ordinal)
      )
      invalidator?.requestInvalidation(of: [identity])
    }
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

  package func apply(
    resolved: ResolvedNode,
    children: [ViewNode]
  ) {
    let newChildrenByIdentity = Set(children.map(\.identity))
    for child in self.children
    where !newChildrenByIdentity.contains(child.identity) && child.parent === self {
      child.parent = nil
    }

    resolvedIdentity = resolved.identity
    kind = resolved.kind
    environmentSnapshot = resolved.environmentSnapshot
    transactionSnapshot = resolved.transactionSnapshot
    layoutBehavior = resolved.layoutBehavior
    layoutMetadata = resolved.layoutMetadata
    drawMetadata = resolved.drawMetadata
    semanticMetadata = resolved.semanticMetadata
    lifecycleMetadata = resolved.lifecycleMetadata
    drawPayload = resolved.drawPayload
    intrinsicSize = resolved.intrinsicSize
    indexedChildSource = resolved.indexedChildSource
    preferenceValues = resolved.preferenceValues
    supportsRetainedReuse = resolved.supportsRetainedReuse
    childDescriptors = resolved.children.map(ChildDescriptor.init)
    self.children = children
    for child in children {
      guard child !== self else {
        continue
      }
      child.parent = self
    }
    cachedResolvedNode = resolved
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
      && supportsRetainedReuse
      && cachedResolvedNode != nil
      && environmentSnapshot == environment
      && transactionSnapshot == transaction
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

  package func recordPointerHandlerRegistration(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.Handler
  ) {
    registeredHandlers.recordPointerHandler(
      routeID: routeID,
      handler: handler
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

  package func recordHotkeyRegistration(
    _ registration: HotkeyRegistrationSnapshot
  ) {
    registeredHandlers.recordHotkey(registration)
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

  package func snapshot() -> ResolvedNode {
    if let cachedResolvedNode {
      return cachedResolvedNode
    }

    return ResolvedNode(
      identity: resolvedIdentity,
      kind: kind,
      children: children.map { $0.snapshot() },
      environmentSnapshot: environmentSnapshot,
      transactionSnapshot: transactionSnapshot,
      layoutBehavior: layoutBehavior,
      layoutMetadata: layoutMetadata,
      drawMetadata: drawMetadata,
      semanticMetadata: semanticMetadata,
      lifecycleMetadata: lifecycleMetadata,
      drawPayload: drawPayload,
      intrinsicSize: intrinsicSize,
      indexedChildSource: indexedChildSource
    )
  }

  private func invalidateCachedSnapshotUpward() {
    var current: ViewNode? = self
    var visited: Set<ObjectIdentifier> = []

    while let node = current {
      let nodeID = ObjectIdentifier(node)
      guard visited.insert(nodeID).inserted else {
        return
      }
      node.cachedResolvedNode = nil
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
      node.cachedResolvedNode = nil
      current = node.parent
    }
  }

  package var participatesInStructuralLifecycle: Bool {
    var ancestor = parent
    while let current = ancestor {
      if current.indexedChildSource != nil {
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
