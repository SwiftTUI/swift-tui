public import SwiftTUICore

extension View {
  public func onAppear(
    perform action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    modifier(
      AppearLifecycleModifier(
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }

  public func onDisappear(
    perform action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    modifier(
      DisappearLifecycleModifier(
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }

  public func onChange<Value: Equatable>(
    of value: Value,
    initial: Bool = false,
    _ action: @escaping () -> Void
  ) -> some View {
    modifier(
      ChangeLifecycleModifier(
        callbackScope: currentImperativeAuthoringContextSnapshot(),
        value: value,
        initial: initial,
        action: { _, _ in action() }
      )
    )
  }

  public func onChange<Value: Equatable>(
    of value: Value,
    initial: Bool = false,
    _ action: @escaping (Value, Value) -> Void
  ) -> some View {
    modifier(
      ChangeLifecycleModifier(
        callbackScope: currentImperativeAuthoringContextSnapshot(),
        value: value,
        initial: initial,
        action: action
      )
    )
  }

  public func task(
    priority: TaskPriority = .userInitiated,
    @_inheritActorContext
    _ action: sending @escaping @isolated(any) () async -> Void
  ) -> some View {
    modifier(
      TaskLifecycleModifier(
        priority: priority,
        descriptorIdentity: nil,
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }

  public func task<ID: Equatable>(
    id value: ID,
    priority: TaskPriority = .userInitiated,
    @_inheritActorContext
    _ action: sending @escaping @isolated(any) () async -> Void
  ) -> some View {
    modifier(
      TaskLifecycleModifier(
        priority: priority,
        descriptorIdentity: TaskLifecycleDescriptorIdentity(value),
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }
}

@MainActor
private func recordLifecycleEvaluationOwner(
  for lifecycleIdentity: Identity,
  in context: ResolveContext
) {
  context.viewGraph?.recordLifecycleEvaluationOwner(
    target: lifecycleIdentity,
    owner: context.identity
  )
}

public struct AppearLifecycleModifier: IterativePrimitiveViewModifier {
  let authoringContext: ImperativeAuthoringContextSnapshot?
  let action: () -> Void

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return content.resolveWork(in: context).map { completed in
      var node = completed
      recordLifecycleEvaluationOwner(
        for: node.identity,
        in: context
      )
      let intake = HandlerDescriptorIntake(
        context: context,
        preferringSnapshot: authoringContext
      )
      let lifecycleAction = action
      let handlerID =
        intake.registerAppearHandler(
          identity: node.identity,
          ordinal: node.lifecycleMetadata.appearIDs.count,
          handler: {
            lifecycleAction()
          }
        ) ?? .current(node.identity, .appear(ordinal: node.lifecycleMetadata.appearIDs.count))
      node.lifecycleMetadata = node.lifecycleMetadata.merging(
        .init(appearIDs: [handlerID], disappearIDs: [])
      )
      return [node]

    }
  }
}

public struct DisappearLifecycleModifier: IterativePrimitiveViewModifier {
  let authoringContext: ImperativeAuthoringContextSnapshot?
  let action: () -> Void

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return content.resolveWork(in: context).map { completed in
      var node = completed
      recordLifecycleEvaluationOwner(
        for: node.identity,
        in: context
      )
      let intake = HandlerDescriptorIntake(
        context: context,
        preferringSnapshot: authoringContext
      )
      let lifecycleAction = action
      let handlerID =
        intake.registerDisappearHandler(
          identity: node.identity,
          ordinal: node.lifecycleMetadata.disappearIDs.count,
          handler: {
            lifecycleAction()
          }
        ) ?? .current(node.identity, .disappear(ordinal: node.lifecycleMetadata.disappearIDs.count))
      node.lifecycleMetadata = node.lifecycleMetadata.merging(
        .init(appearIDs: [], disappearIDs: [handlerID])
      )
      return [node]

    }
  }
}

public struct ChangeLifecycleModifier<Value: Equatable>: IterativePrimitiveViewModifier {
  let callbackScope: ImperativeAuthoringContextSnapshot?
  var value: Value
  var initial: Bool
  let action: (Value, Value) -> Void

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    let intake = HandlerDescriptorIntake(
      context: context,
      preferringSnapshot: callbackScope
    )
    return content.resolveWork(in: context).map { completed in
      var node = completed
      let viewGraph = context.viewGraph
      // The package-only exact `.id(Identity)` replaces the resolved path
      // wholesale. Its scoped entity is therefore the lifecycle owner: it stays
      // stable inside one enclosing identity lifetime and is reminted when that
      // ancestor changes. Public generic IDs and structural paths retain the
      // established resolved-identity ownership used by modifier-chain churn.
      let routedEntityIdentity =
        node.entityIdentity ?? ResolveEntityRouteStorage.current?.identity
      let exactEntityIdentity = routedEntityIdentity.flatMap { entityIdentity in
        entityIdentity.isScopedExactIdentity ? entityIdentity : nil
      }
      let ownerNode =
        exactEntityIdentity.flatMap { viewGraph?.nodeForEntityIdentity($0) }
        ?? viewGraph?.nodeForIdentity(node.identity)
      // A content-first `.id(...).onChange(...)` can expose a freshly routed
      // node before its resolved identity has entered the graph index. Keep the
      // established identity for observation baselines, but queue the event on
      // the concrete resolved node (or its route) so `initial: true` is
      // not swallowed on that first lifetime pass.
      let eventOwnerNode =
        ownerNode
        ?? node.viewNodeID.flatMap { viewGraph?.nodeForViewNodeID($0) }
        ?? routedEntityIdentity.flatMap { viewGraph?.nodeForEntityIdentity($0) }
      // Flattened wrappers can index different graph nodes at this same resolved
      // identity as content completes. Count the observers on the element itself
      // so every modifier shares one inner-first baseline sequence.
      let modifierOrdinal = node.lifecycleMetadata.changeObservationCount
      node.lifecycleMetadata.changeObservationCount += 1

      // The graph store can read the owner's prior value before commit. Exact-ID
      // entries follow the scoped entity above; ordinary entries keep their
      // resolved-identity key. Fall back to a per-node slot only when no graph is
      // threaded (a resolve-only path where the handler cannot dispatch).
      let hadPreviousValue: Bool
      let previousValue: Value?
      if let viewGraph {
        hadPreviousValue = viewGraph.hasChangeObservationValue(
          entityIdentity: exactEntityIdentity,
          identity: node.identity,
          ordinal: modifierOrdinal
        )
        previousValue = viewGraph.changeObservationValue(
          entityIdentity: exactEntityIdentity,
          identity: node.identity,
          ordinal: modifierOrdinal,
          as: Value.self
        )
      } else {
        let stateSlotOrdinal = StateSlotOrdinals.changeModifier(modifierOrdinal)
        hadPreviousValue = ownerNode?.hasStateSlot(ordinal: stateSlotOrdinal) == true
        previousValue = ownerNode.map { ownerNode in
          ownerNode.stateSlot(
            ordinal: stateSlotOrdinal,
            seed: value
          )
        }
      }

      let shouldTrigger =
        if hadPreviousValue {
          previousValue.map { $0 != value } ?? false
        } else {
          initial
        }

      if let viewGraph {
        viewGraph.recordChangeObservationValue(
          value,
          entityIdentity: exactEntityIdentity,
          identity: node.identity,
          ordinal: modifierOrdinal
        )
      } else if let ownerNode {
        ownerNode.setStateSlotSilently(
          ordinal: StateSlotOrdinals.changeModifier(modifierOrdinal),
          value: value
        )
      }

      guard shouldTrigger else {
        return [node]
      }

      let oldValue = previousValue ?? value
      let lifecycleAction = action

      let handlerID =
        intake.registerChangeHandler(
          identity: node.identity,
          ordinal: modifierOrdinal,
          handler: {
            lifecycleAction(oldValue, value)
          }
        ) ?? .current(node.identity, .change(ordinal: modifierOrdinal))
      eventOwnerNode?.queueChangeHandler(handlerID)
      return [node]

    }
  }
}

private struct TaskLifecycleDescriptorIdentity {
  let valueType: Any.Type
  let token: @MainActor (ViewGraph, Identity, Int) -> UInt64

  @MainActor
  init<ID: Equatable>(_ value: ID) {
    valueType = ID.self
    token = { graph, identity, ordinal in
      if let node = ViewNodeContext.current?.viewNodeID {
        return graph.taskDescriptorIdentityToken(for: node, ordinal: ordinal, value: value)
      }
      return graph.taskDescriptorIdentityToken(for: identity, ordinal: ordinal, value: value)
    }
  }
}

public struct TaskLifecycleModifier: IterativePrimitiveViewModifier {
  var priority: TaskPriority
  fileprivate var descriptorIdentity: TaskLifecycleDescriptorIdentity?
  fileprivate var authoringContext: ImperativeAuthoringContextSnapshot?
  let action: () async -> Void

  fileprivate init(
    priority: TaskPriority,
    descriptorIdentity: TaskLifecycleDescriptorIdentity?,
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping () async -> Void
  ) {
    self.priority = priority
    self.descriptorIdentity = descriptorIdentity
    self.authoringContext = authoringContext
    self.action = action
  }

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return content.resolveWork(in: context).map { completed in
      var node = completed
      let intake = HandlerDescriptorIntake(
        context: context,
        preferringSnapshot: authoringContext
      )
      let taskAction = action
      let lifecycleIdentity = node.identity
      recordLifecycleEvaluationOwner(
        for: lifecycleIdentity,
        in: context
      )
      let ownerNode = context.viewGraph?.nodeForIdentity(lifecycleIdentity)
      let taskOrdinal = ownerNode?.claimTaskModifierOrdinal() ?? 0
      let token = context.viewGraph.flatMap { graph in
        descriptorIdentity?.token(graph, lifecycleIdentity, taskOrdinal)
      }
      let descriptor = TaskDescriptor(
        owner: lifecycleIdentity, ordinal: taskOrdinal, token: token,
        detachedType: context.viewGraph == nil ? descriptorIdentity?.valueType : nil,
        priority: priority)
      intake.registerTask(
        identity: lifecycleIdentity,
        descriptor: descriptor,
        operation: {
          await taskAction()
        }
      )
      node.lifecycleMetadata = node.lifecycleMetadata.merging(
        .init(tasks: [descriptor])
      )
      return [node]

    }
  }
}
