public import SwiftTUICore

extension View {
  public func onAppear(
    perform action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    modifier(AppearLifecycleModifier(action: action))
  }

  public func onDisappear(
    perform action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    modifier(DisappearLifecycleModifier(action: action))
  }

  public func onChange<Value: Equatable>(
    of value: Value,
    initial: Bool = false,
    _ action: @escaping () -> Void
  ) -> some View {
    modifier(
      ChangeLifecycleModifier(
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

public struct AppearLifecycleModifier: PrimitiveViewModifier {
  let action: () -> Void

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    recordLifecycleEvaluationOwner(
      for: node.identity,
      in: context
    )
    let authoringContext = currentImperativeAuthoringContextSnapshot()?
      .withEnvironmentValues(context.environmentValues)
    let lifecycleAction = action
    let handlerID =
      context.localLifecycleRegistry?.registerAppear(
        identity: node.identity,
        ordinal: node.lifecycleMetadata.appearHandlerIDs.count,
        handler: {
          withImperativeAuthoringContext(authoringContext) {
            lifecycleAction()
          }
        }
      ) ?? "\(node.identity)#appear[\(node.lifecycleMetadata.appearHandlerIDs.count)]"
    node.lifecycleMetadata = node.lifecycleMetadata.merging(
      .init(appearHandlerIDs: [handlerID])
    )
    return [node]
  }
}

public struct DisappearLifecycleModifier: PrimitiveViewModifier {
  let action: () -> Void

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    recordLifecycleEvaluationOwner(
      for: node.identity,
      in: context
    )
    let authoringContext = currentImperativeAuthoringContextSnapshot()?
      .withEnvironmentValues(context.environmentValues)
    let lifecycleAction = action
    let handlerID =
      context.localLifecycleRegistry?.registerDisappear(
        identity: node.identity,
        ordinal: node.lifecycleMetadata.disappearHandlerIDs.count,
        handler: {
          withImperativeAuthoringContext(authoringContext) {
            lifecycleAction()
          }
        }
      ) ?? "\(node.identity)#disappear[\(node.lifecycleMetadata.disappearHandlerIDs.count)]"
    node.lifecycleMetadata = node.lifecycleMetadata.merging(
      .init(disappearHandlerIDs: [handlerID])
    )
    return [node]
  }
}

public struct ChangeLifecycleModifier<Value: Equatable>: PrimitiveViewModifier {
  var value: Value
  var initial: Bool
  let action: (Value, Value) -> Void

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let authoringContext = currentImperativeAuthoringContextSnapshot()?
      .withEnvironmentValues(context.environmentValues)
    let node = content.resolve(in: context)
    let viewGraph = context.viewGraph
    let ownerNode = viewGraph?.nodeForIdentity(node.identity)
    let modifierOrdinal = ownerNode?.claimChangeModifierOrdinal() ?? 0

    // `onChange`'s previous-value memory must survive `.id`-churn re-minting of
    // the observing node (a fresh `ViewNode` with empty state slots) and be
    // available on the node's very first resolve (before it lands in the graph's
    // identity index). A per-node state slot satisfies neither — the first
    // observation is swallowed and every post-churn change reads as "first". The
    // view graph is the persistent, cross-frame home; its change-observation
    // store keys by the *stable* identity, so it survives both. Fall back to the
    // per-node slot only when no graph is threaded (a resolve-only path where the
    // change handler could not be dispatched anyway).
    let hadPreviousValue: Bool
    let previousValue: Value?
    if let viewGraph {
      hadPreviousValue = viewGraph.hasChangeObservationValue(
        identity: node.identity,
        ordinal: modifierOrdinal
      )
      previousValue = viewGraph.changeObservationValue(
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
      context.localLifecycleRegistry?.registerChange(
        identity: node.identity,
        ordinal: modifierOrdinal,
        handler: {
          withImperativeAuthoringContext(authoringContext) {
            lifecycleAction(oldValue, value)
          }
        }
      ) ?? "\(node.identity)#change[\(modifierOrdinal)]"
    ownerNode?.queueChangeHandler(handlerID)
    return [node]
  }
}

private struct TaskLifecycleDescriptorIdentity {
  private let label: @MainActor (ResolveContext, Identity, Int) -> String

  @MainActor
  init<ID: Equatable>(_ value: ID) {
    label = { context, identity, ordinal in
      if let viewGraph = context.viewGraph {
        if let viewNodeID = ViewNodeContext.current?.viewNodeID {
          return viewGraph.taskDescriptorIdentityLabel(
            for: viewNodeID,
            ordinal: ordinal,
            value: value
          )
        }
        return viewGraph.taskDescriptorIdentityLabel(
          for: identity,
          ordinal: ordinal,
          value: value
        )
      }
      return "id:\(String(reflecting: ID.self))"
    }
  }

  @MainActor
  func descriptorLabel(
    in context: ResolveContext,
    identity: Identity,
    ordinal: Int
  ) -> String {
    label(context, identity, ordinal)
  }
}

public struct TaskLifecycleModifier: PrimitiveViewModifier {
  var priority: TaskPriority
  fileprivate var descriptorIdentity: TaskLifecycleDescriptorIdentity?
  let action: () async -> Void

  fileprivate init(
    priority: TaskPriority,
    descriptorIdentity: TaskLifecycleDescriptorIdentity?,
    action: @escaping () async -> Void
  ) {
    self.priority = priority
    self.descriptorIdentity = descriptorIdentity
    self.action = action
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let authoringContext = currentImperativeAuthoringContextSnapshot()?
      .withEnvironmentValues(context.environmentValues)
    let taskAction = action
    let lifecycleIdentity = node.identity
    recordLifecycleEvaluationOwner(
      for: lifecycleIdentity,
      in: context
    )
    let ownerNode = context.viewGraph?.nodeForIdentity(lifecycleIdentity)
    let taskOrdinal = ownerNode?.claimTaskModifierOrdinal() ?? 0
    let descriptorIdentityLabel = descriptorIdentity?.descriptorLabel(
      in: context,
      identity: lifecycleIdentity,
      ordinal: taskOrdinal
    )
    let descriptorID =
      if let label = descriptorIdentityLabel {
        taskOrdinal == 0
          ? "\(lifecycleIdentity)#task[\(label)]"
          : "\(lifecycleIdentity)#task[\(taskOrdinal):\(label)]"
      } else {
        taskOrdinal == 0
          ? "\(lifecycleIdentity)#task"
          : "\(lifecycleIdentity)#task[\(taskOrdinal)]"
      }
    let descriptor = TaskDescriptor(id: descriptorID, priority: priority)
    if let taskRegistry = context.localTaskRegistry {
      taskRegistry.register(
        identity: lifecycleIdentity,
        registration: .init(
          descriptor: descriptor,
          operation: {
            await withImperativeAuthoringContext(authoringContext) {
              await taskAction()
            }
          }
        )
      )
    }
    node.lifecycleMetadata = node.lifecycleMetadata.merging(
      .init(tasks: [descriptor])
    )
    return [node]
  }
}
