@MainActor
package final class ViewNode {
  package let identity: Identity
  package weak var invalidator: (any Invalidating)?

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

  package init(identity: Identity) {
    self.identity = identity
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
  }

  package func prepareForFrame() {
    wasPresentAtFrameStart = true
    wasVisitedThisFrame = false
    previousChildrenIdentities = children.map(\.identity)
    previousLifecycleMetadata = lifecycleMetadata
    currentBodyStateSlotCount = 0
  }

  package func beginEvaluation(
    invalidator: (any Invalidating)?
  ) {
    self.invalidator = invalidator
    wasVisitedThisFrame = true
    isDirty = false
    currentBodyStateSlotCount = 0
    _ = dependencyTracker.reset()
  }

  package func finishEvaluation(
    accessedStateSlots: Int
  ) {
    bodyStateSlotCount = max(bodyStateSlotCount ?? 0, accessedStateSlots)

    dependencies = dependencyTracker.reset()
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
      requestInvalidation()
    }
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
    cachedResolvedNode = resolved
    registeredHandlers = .init(
      lifecycleHandlerIDs:
        resolved.lifecycleMetadata.appearHandlerIDs
        + resolved.lifecycleMetadata.disappearHandlerIDs,
      task: resolved.lifecycleMetadata.task
    )
  }

  package func snapshot() -> ResolvedNode {
    if let cachedResolvedNode {
      return cachedResolvedNode
    }

    var snapshot = ResolvedNode(
      identity: identity,
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
    snapshot.preferenceValues = preferenceValues
    snapshot.supportsRetainedReuse = supportsRetainedReuse
    return snapshot
  }
}
