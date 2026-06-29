public import SwiftTUICore

/// A binding-driven destination host for terminal-native surface replacement.
///
/// `NavigationStack` has no built-in chrome. It renders the root content when
/// no destination binding is active and renders the topmost active destination
/// when one or more `navigationDestination(...)` declarations are active.
public struct NavigationStack<ID: Hashable & Sendable, Root: View>: PrimitiveView, ActionScope,
  ResolvableView
{
  public let id: ID
  private let root: Root

  public init(
    id: ID,
    @ViewBuilder root: () -> Root
  ) {
    self.id = id
    self.root = root()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let dynamicPropertyScope = dynamicPropertyAuthoringContext(for: context)
    return withAuthoringContext(dynamicPropertyScope) {
      [resolvedNode(in: context)]
    }
  }

  private func resolvedNode(in context: ResolveContext) -> ResolvedNode {
    let rootNode = root.resolve(in: context.child(component: .named("Root")))
    let resolution = resolveActiveDestinationChain(
      from: rootNode,
      in: context
    )

    // A NavigationStack is a command host (Role A): a focus scope, not a focus
    // target. Tab passes through to the focusable item leaves of the visible
    // destination; the stack itself is never a Tab stop.
    var metadata = focusStructureMetadata(scopeBoundary: true)
    metadata.isCommandHost = true

    var stackNode = ResolvedNode(
      identity: context.identity,
      kind: .view("NavigationStack"),
      children: [resolution.visibleNode],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: metadata
    )

    var preferences = resolution.accumulatedPreferences
    preferences.merge(resolution.visibleNode.preferenceValues)
    preferences[NavigationDestinationDeclarationPreferenceKey.self] = .init()
    var popPreferences = preferences[NavigationDestinationPopPreferenceKey.self]
    popPreferences.entries.append(contentsOf: resolution.popEntries)
    preferences[NavigationDestinationPopPreferenceKey.self] = popPreferences
    stackNode.preferenceValues = preferences

    return stackNode
  }
}

extension NavigationStack where ID == AnyID {
  public init(
    @ViewBuilder root: () -> Root
  ) {
    guard let scope = currentAuthoringContext() else {
      preconditionFailure(
        "NavigationStack() requires an authoring context -- call it inside a View's body, or use NavigationStack(id:) with an explicit identity."
      )
    }
    self.init(id: AnyID(scope.structuralPath), root: root)
  }
}

extension View {
  /// Registers a Boolean-driven destination for the nearest navigation stack.
  public func navigationDestination<Destination: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder destination: () -> Destination
  ) -> some View {
    modifier(
      BooleanNavigationDestinationModifier(
        isPresented: isPresented,
        destination: destination(),
        destinationAuthoringContext: makeLazySubviewAuthoringContext(),
        dismissAuthoringContext: makeLazySubviewAuthoringContext()
      )
    )
  }

  /// Registers an item-driven destination for the nearest navigation stack.
  public func navigationDestination<Item: Identifiable & Sendable, Destination: View>(
    item: Binding<Item?>,
    @ViewBuilder destination: @escaping @MainActor (Item) -> Destination
  ) -> some View where Item.ID: Sendable {
    modifier(
      ItemNavigationDestinationModifier(
        item: item,
        destination: destination,
        destinationAuthoringContext: makeLazySubviewAuthoringContext(),
        dismissAuthoringContext: makeLazySubviewAuthoringContext()
      )
    )
  }
}

public struct BooleanNavigationDestinationModifier<Destination: View>: PrimitiveViewModifier {
  var isPresented: Binding<Bool>
  var destination: Destination
  var destinationAuthoringContext: AuthoringContext?
  var dismissAuthoringContext: AuthoringContext?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let sourceIdentity = node.identity
    let modifierOrdinal = navigationDestinationModifierOrdinal(for: sourceIdentity, in: context)
    let declarationIdentity = navigationDestinationDeclarationIdentity(
      sourceIdentity: sourceIdentity,
      modifierOrdinal: modifierOrdinal
    )
    let activationOrdinal = updateNavigationDestinationActivation(
      sourceIdentity: sourceIdentity,
      modifierOrdinal: modifierOrdinal,
      activeKey: isPresented.wrappedValue ? .boolean : nil,
      in: context
    )
    let dismissInvalidator = context.invalidationProxy?.invalidator

    let instance = activationOrdinal.map { ordinal in
      NavigationDestinationInstance(
        identity: declarationIdentity.child("Activation[\(ordinal)]"),
        payload: NavigationDestinationPayload(
          navigationDestinationAuthoringContext: destinationAuthoringContext,
          declarationIdentity: declarationIdentity
        ) {
          destination
        },
        dismiss: { [isPresented, dismissAuthoringContext, dismissInvalidator, sourceIdentity] in
          withAuthoringContext(dismissAuthoringContext) {
            isPresented.wrappedValue = false
          }
          dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
        }
      )
    }

    node.preferenceValues.merge(
      NavigationDestinationDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(
            sourceIdentity: sourceIdentity,
            declarationIdentity: declarationIdentity,
            instance: instance
          )
        ]
      )
    )
    return [node]
  }
}

public struct ItemNavigationDestinationModifier<Item: Identifiable & Sendable, Destination: View>:
  PrimitiveViewModifier
where Item.ID: Sendable {
  var item: Binding<Item?>
  var destination: @MainActor (Item) -> Destination
  var destinationAuthoringContext: AuthoringContext?
  var dismissAuthoringContext: AuthoringContext?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let sourceIdentity = node.identity
    let modifierOrdinal = navigationDestinationModifierOrdinal(for: sourceIdentity, in: context)
    let declarationIdentity = navigationDestinationDeclarationIdentity(
      sourceIdentity: sourceIdentity,
      modifierOrdinal: modifierOrdinal
    )
    let currentItem = item.wrappedValue
    let activeKey = currentItem.map { NavigationDestinationActivationKey($0.id) }
    let activationOrdinal = updateNavigationDestinationActivation(
      sourceIdentity: sourceIdentity,
      modifierOrdinal: modifierOrdinal,
      activeKey: activeKey,
      in: context
    )
    let dismissInvalidator = context.invalidationProxy?.invalidator

    let instance: NavigationDestinationInstance? =
      if let currentItem, let activationOrdinal {
        NavigationDestinationInstance(
          identity:
            declarationIdentity
            .child("Item")
            .explicitID(currentItem.id)
            .child("Activation[\(activationOrdinal)]"),
          payload: NavigationDestinationPayload(
            navigationDestinationAuthoringContext: destinationAuthoringContext,
            declarationIdentity: declarationIdentity
          ) {
            destination(currentItem)
          },
          dismiss: { [item, dismissAuthoringContext, dismissInvalidator, sourceIdentity] in
            withAuthoringContext(dismissAuthoringContext) {
              item.wrappedValue = nil
            }
            dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
          }
        )
      } else {
        nil
      }

    node.preferenceValues.merge(
      NavigationDestinationDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(
            sourceIdentity: sourceIdentity,
            declarationIdentity: declarationIdentity,
            instance: instance
          )
        ]
      )
    )
    return [node]
  }
}

@MainActor
package func navigationDestinationPopAction(
  in node: ResolvedNode,
  along scopePath: [Identity]
) -> (@MainActor @Sendable () -> Void)? {
  let entries = node.preferenceValues[NavigationDestinationPopPreferenceKey.self].entries
  guard !entries.isEmpty else {
    return nil
  }
  guard !scopePath.isEmpty else {
    return entries.last?.dismiss
  }

  return entries.max { lhs, rhs in
    scopeDepth(of: lhs.scopeIdentity, in: scopePath)
      < scopeDepth(of: rhs.scopeIdentity, in: scopePath)
  }?.dismiss
}

private struct NavigationChainResolution {
  var visibleNode: ResolvedNode
  var accumulatedPreferences: PreferenceValues
  var popEntries: [NavigationDestinationPopEntry]
}

@MainActor
private func resolveActiveDestinationChain(
  from rootNode: ResolvedNode,
  in context: ResolveContext
) -> NavigationChainResolution {
  var visibleNode = rootNode
  var accumulatedPreferences = PreferenceValues()
  var popEntries: [NavigationDestinationPopEntry] = []

  for _ in 0..<32 {
    let declarations = visibleNode.preferenceValues[
      NavigationDestinationDeclarationPreferenceKey.self
    ].declarations
    let activeInstances = declarations.compactMap(\.instance)

    visibleNode.preferenceValues[NavigationDestinationDeclarationPreferenceKey.self] = .init()

    guard let instance = activeInstances.last else {
      return NavigationChainResolution(
        visibleNode: visibleNode,
        accumulatedPreferences: accumulatedPreferences,
        popEntries: popEntries
      )
    }

    accumulatedPreferences.merge(visibleNode.preferenceValues)
    popEntries.append(
      NavigationDestinationPopEntry(
        scopeIdentity: instance.identity,
        dismiss: instance.dismiss
      )
    )

    visibleNode = NavigationDestinationSurface(instance: instance)
      .resolve(in: context.replacingIdentity(with: instance.identity))
  }

  visibleNode.preferenceValues[NavigationDestinationDeclarationPreferenceKey.self] = .init()
  return NavigationChainResolution(
    visibleNode: visibleNode,
    accumulatedPreferences: accumulatedPreferences,
    popEntries: popEntries
  )
}

private struct NavigationDestinationSurface: PrimitiveView, ActionScope, ResolvableView {
  typealias ID = Identity

  var instance: NavigationDestinationInstance

  nonisolated var id: Identity {
    instance.identity
  }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let payloadNode = instance.payload.resolve(in: context.child(component: .named("Content")))
    // A pushed navigation destination is a command host (Role A): a focus scope,
    // not a focus target. Tab passes through to the destination's item leaves.
    var metadata = focusStructureMetadata(scopeBoundary: true)
    metadata.isCommandHost = true

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("NavigationDestination"),
        children: [payloadNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        semanticMetadata: metadata
      )
    ]
  }
}

private enum NavigationDestinationActivationKey: Equatable, Hashable, Sendable {
  case boolean
  case item(AnyHashableSendable)

  init<ID: Hashable & Sendable>(_ itemID: ID) {
    self = .item(AnyHashableSendable(itemID))
  }
}

private struct NavigationDestinationActivationState: Equatable, Sendable {
  var activeKey: NavigationDestinationActivationKey?
  var activeOrdinal: Int
  var nextOrdinal: Int

  static let inactive = Self(
    activeKey: nil,
    activeOrdinal: -1,
    nextOrdinal: 0
  )
}

@MainActor
private func navigationDestinationModifierOrdinal(
  for sourceIdentity: Identity,
  in context: ResolveContext
) -> Int {
  context.viewGraph?
    .nodeForIdentity(sourceIdentity)?
    .claimNavigationDestinationModifierOrdinal() ?? 0
}

private func navigationDestinationDeclarationIdentity(
  sourceIdentity: Identity,
  modifierOrdinal: Int
) -> Identity {
  sourceIdentity.child("NavigationDestination[\(modifierOrdinal)]")
}

@MainActor
private func updateNavigationDestinationActivation(
  sourceIdentity: Identity,
  modifierOrdinal: Int,
  activeKey: NavigationDestinationActivationKey?,
  in context: ResolveContext
) -> Int? {
  guard let ownerNode = context.viewGraph?.nodeForIdentity(sourceIdentity) else {
    return activeKey == nil ? nil : 0
  }

  let slotOrdinal = navigationDestinationActivationStateSlot(modifierOrdinal)
  var state = ownerNode.stateSlot(
    ordinal: slotOrdinal,
    seed: NavigationDestinationActivationState.inactive
  )

  guard let activeKey else {
    state.activeKey = nil
    state.activeOrdinal = -1
    ownerNode.setStateSlotSilently(
      ordinal: slotOrdinal,
      value: state
    )
    return nil
  }

  if state.activeKey == activeKey {
    return state.activeOrdinal
  }

  state.activeKey = activeKey
  state.activeOrdinal = state.nextOrdinal
  state.nextOrdinal += 1
  ownerNode.setStateSlotSilently(
    ordinal: slotOrdinal,
    value: state
  )
  return state.activeOrdinal
}

private func navigationDestinationActivationStateSlot(_ modifierOrdinal: Int) -> Int {
  StateSlotOrdinals.navigationDestinationActivation(modifierOrdinal)
}

private func scopeDepth(
  of identity: Identity,
  in scopePath: [Identity]
) -> Int {
  scopePath.firstIndex(of: identity) ?? -1
}
