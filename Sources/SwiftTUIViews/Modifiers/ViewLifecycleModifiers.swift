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
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    let lifecycleAction = action
    let handlerID = context.localLifecycleRegistry?.registerAppear(
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
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    let lifecycleAction = action
    let handlerID = context.localLifecycleRegistry?.registerDisappear(
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
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    let node = content.resolve(in: context)
    let ownerNode = context.viewGraph?.nodeForIdentity(node.identity)
    let modifierOrdinal = ownerNode?.claimChangeModifierOrdinal() ?? 0
    let stateSlotOrdinal = StateSlotOrdinals.changeModifier(modifierOrdinal)
    let hadPreviousValue = ownerNode?.hasStateSlot(ordinal: stateSlotOrdinal) == true
    let previousValue = ownerNode.map { ownerNode in
      ownerNode.stateSlot(
        ordinal: stateSlotOrdinal,
        seed: value
      )
    }
    let shouldTrigger =
      if hadPreviousValue {
        previousValue.map { $0 != value } ?? false
      } else {
        initial
      }

    if let ownerNode {
      ownerNode.setStateSlotSilently(
        ordinal: stateSlotOrdinal,
        value: value
      )
    }

    guard shouldTrigger else {
      return [node]
    }

    let oldValue = previousValue ?? value
    let lifecycleAction = action

    let handlerID = context.localLifecycleRegistry?.registerChange(
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
  private let label: @MainActor (ResolveContext, Identity) -> String

  @MainActor
  init<ID: Equatable>(_ value: ID) {
    label = { context, identity in
      if let viewGraph = context.viewGraph {
        if let viewNodeID = ViewNodeContext.current?.viewNodeID {
          return viewGraph.taskDescriptorIdentityLabel(
            for: viewNodeID,
            value: value
          )
        }
        return viewGraph.taskDescriptorIdentityLabel(
          for: identity,
          value: value
        )
      }
      return "id:\(String(reflecting: ID.self))"
    }
  }

  @MainActor
  func descriptorLabel(
    in context: ResolveContext,
    identity: Identity
  ) -> String {
    label(context, identity)
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
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    let taskAction = action
    let lifecycleIdentity = node.identity
    recordLifecycleEvaluationOwner(
      for: lifecycleIdentity,
      in: context
    )
    let descriptorIdentityLabel = descriptorIdentity?.descriptorLabel(
      in: context,
      identity: lifecycleIdentity
    )
    let descriptor = TaskDescriptor(
      id: descriptorIdentityLabel.map {
        "\(lifecycleIdentity)#task[\($0)]"
      } ?? "\(lifecycleIdentity)#task",
      priority: priority
    )
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
      .init(task: descriptor)
    )
    return [node]
  }
}
