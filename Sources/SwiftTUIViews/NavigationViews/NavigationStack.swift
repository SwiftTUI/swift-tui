public import SwiftTUICore

/// A data-driven destination host for terminal-native surface replacement.
///
/// `NavigationStack` has no built-in chrome. It renders the root content when
/// its path and destination bindings are inactive, and renders the topmost
/// destination declared by that data otherwise.
public struct NavigationStack<Root: View>: PrimitiveView, ActionScope, ResolvableView {
  /// The framework-derived identity used by the stack's `ActionScope`
  /// conformance.
  ///
  /// Stack lifetime and navigation identity follow structural view identity;
  /// callers do not supply an identifier to the initializer.
  public let id: AnyID
  private let pathBinding: NavigationPathBinding?
  private let root: Root

  public init(
    @ViewBuilder root: () -> Root
  ) {
    id = implicitNavigationStackID()
    pathBinding = nil
    self.root = root()
  }

  /// Creates a stack whose pushed destinations are derived from `path`.
  ///
  /// Append values to push, remove the last value to pop, and remove every
  /// value to return to the root. Register the matching view builder with
  /// ``View/navigationDestination(for:destination:)`` inside the stack.
  public init<Element: Hashable & Sendable>(
    path: Binding<[Element]>,
    @ViewBuilder root: () -> Root
  ) {
    id = implicitNavigationStackID()
    pathBinding = NavigationPathBinding(path)
    self.root = root()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let dynamicPropertyScope = dynamicPropertyAuthoringContext(for: context)
    return withAuthoringContext(dynamicPropertyScope) {
      [resolvedNode(in: context)]
    }
  }

  private func resolvedNode(in context: ResolveContext) -> ResolvedNode {
    // Publish this stack's identity as the declaration scope for the
    // `navigationDestination(...)` modifiers resolving in its subtree. The
    // stack's identity is structural (position-based) and sits outside any
    // branch its root toggles, so it is stable
    // per stack and unique across sibling stacks — the branch-independent,
    // per-stack-unique root a stable-`.id` source needs for its pushed surface
    // (see `navigationDestinationDeclarationRoot`).
    let rootContext =
      context
      .child(component: .named("Root"))
      .settingEnvironment(\.navigationDestinationDeclarationScope, to: context.identity)
    let rootNode = root.resolve(in: rootContext)
    let pathResolution = resolveValuePath(
      from: rootNode,
      pathBinding: pathBinding,
      in: context
    )
    let resolution = resolveActiveDestinationChain(
      from: pathResolution.visibleNode,
      in: context,
      initial: pathResolution
    )

    // While a destination is presented, the root subtree stays resolved every
    // frame (its state must survive the push) but is absent from this stack's
    // committed children — reachable through neither committed values nor
    // parent links. Resolve-lifetime scope owns the detached value at the
    // nearest declaring host so owner churn/removal tears it down.
    if resolution.visibleNode.identity != rootNode.identity {
      context.viewGraph?.reportDetachedResolvedLifetimeResult(rootNode)
    }

    // Record the pushed-destination surface content nodes this stack resolved
    // so the finalize barrier can retire a surface the stack minted last frame
    // but reminted this frame (a `.id("…-\(gen)")` folded onto this stack node
    // bumps its declaration root each generation). Such a surface's content is
    // orphaned by the fold's chain collapse — parented by neither a committed
    // child nor a detached-hosted edge — so only this diff finds it. Keyed by
    // the host node's stable ViewNodeID across the churn.
    if let hostNodeID = ViewNodeContext.current?.viewNodeID {
      context.viewGraph?.recordActiveNavigationSurfaces(
        hostNodeID: hostNodeID,
        contentNodeIDs: Set(resolution.activeSurfaceContentNodeIDs)
      )
    }

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
    preferences[NavigationValueDestinationPreferenceKey.self] = .init()

    let navigationTitle = preferences[NavigationTitlePreferenceKey.self]
    preferences[NavigationTitlePreferenceKey.self] = nil
    if let navigationTitle {
      var toolbarItems = preferences[ToolbarItemsPreferenceKey.self]
      toolbarItems.insert(
        ToolbarItemConfig(
          title: navigationTitle,
          position: .top,
          isEnabled: false,
          action: {}
        ),
        at: 0
      )
      preferences[ToolbarItemsPreferenceKey.self] = toolbarItems
    }

    var runtimeIssues = preferences[RuntimeIssuePreferenceKey.self]
    for issue in resolution.runtimeIssues where !runtimeIssues.contains(issue) {
      runtimeIssues.append(issue)
    }
    preferences[RuntimeIssuePreferenceKey.self] = runtimeIssues

    var popPreferences = preferences[NavigationDestinationPopPreferenceKey.self]
    popPreferences.entries.append(contentsOf: resolution.popEntries)
    preferences[NavigationDestinationPopPreferenceKey.self] = popPreferences
    stackNode.preferenceValues = preferences

    return stackNode
  }
}

@MainActor
private func implicitNavigationStackID() -> AnyID {
  if let scope = currentAuthoringContext() {
    return AnyID(scope.structuralPath)
  }
  return AnyID("NavigationStack")
}

@MainActor
private struct NavigationPathBinding {
  var valueTypeID: ObjectIdentifier
  var valueTypeName: String
  var values: @MainActor @Sendable () -> [AnyHashableSendable]
  var removeSuffix: @MainActor @Sendable (Int) -> Void

  init<Element: Hashable & Sendable>(_ binding: Binding<[Element]>) {
    let authoringContext = makeLazySubviewAuthoringContext()
    valueTypeID = ObjectIdentifier(Element.self)
    valueTypeName = String(reflecting: Element.self)
    values = {
      binding.wrappedValue.map(AnyHashableSendable.init)
    }
    removeSuffix = { firstRemovedIndex in
      withAuthoringContext(authoringContext) {
        var path = binding.wrappedValue
        guard firstRemovedIndex >= 0, firstRemovedIndex < path.count else {
          return
        }
        path.removeSubrange(firstRemovedIndex...)
        binding.wrappedValue = path
      }
    }
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

  /// Registers a destination builder for values stored in the nearest
  /// navigation stack's typed path.
  public func navigationDestination<Data: Hashable & Sendable, Destination: View>(
    for data: Data.Type,
    @ViewBuilder destination: @escaping @MainActor @Sendable (Data) -> Destination
  ) -> some View {
    modifier(
      ValueNavigationDestinationModifier(
        data: data,
        destination: destination,
        destinationAuthoringContext: makeLazySubviewAuthoringContext()
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
      sourceEntity: node.entityIdentity,
      modifierOrdinal: modifierOrdinal,
      scope: context.environmentValues.navigationDestinationDeclarationScope
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
      sourceEntity: node.entityIdentity,
      modifierOrdinal: modifierOrdinal,
      scope: context.environmentValues.navigationDestinationDeclarationScope
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

/// The modifier value produced by
/// ``View/navigationDestination(for:destination:)``.
public struct ValueNavigationDestinationModifier<Data: Hashable & Sendable, Destination: View>:
  PrimitiveViewModifier
{
  var data: Data.Type
  var destination: @MainActor @Sendable (Data) -> Destination
  var destinationAuthoringContext: AuthoringContext?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let sourceIdentity = node.identity
    let modifierOrdinal = navigationDestinationModifierOrdinal(for: sourceIdentity, in: context)
    let declarationIdentity = navigationDestinationDeclarationIdentity(
      sourceIdentity: sourceIdentity,
      sourceEntity: node.entityIdentity,
      modifierOrdinal: modifierOrdinal,
      scope: context.environmentValues.navigationDestinationDeclarationScope
    )

    node.preferenceValues.merge(
      NavigationValueDestinationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(
            sourceIdentity: sourceIdentity,
            declarationIdentity: declarationIdentity,
            valueTypeID: ObjectIdentifier(data),
            valueTypeName: String(reflecting: data),
            makePayload: { [destination, destinationAuthoringContext] value in
              guard let value = value.unwrap(as: Data.self) else {
                return nil
              }
              return NavigationDestinationPayload(
                navigationDestinationAuthoringContext: destinationAuthoringContext,
                declarationIdentity: declarationIdentity
              ) {
                destination(value)
              }
            }
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
  var runtimeIssues: [RuntimeIssue]
  var depth: Int
  // The out-of-band pushed-destination surface CONTENT-node IDs minted this
  // resolve (one per active `NavigationDestinationInstance`). The resolving
  // host node records these so a per-generation declaration-root churn — which
  // mints a fresh surface while orphaning the previous one's content node — is
  // torn down at the frame barrier (see
  // `ViewGraph.recordActiveNavigationSurfaces`).
  var activeSurfaceContentNodeIDs: [ViewNodeID]
}

private let navigationDestinationDepthLimit = 32

@MainActor
private func resolveValuePath(
  from rootNode: ResolvedNode,
  pathBinding: NavigationPathBinding?,
  in context: ResolveContext
) -> NavigationChainResolution {
  var visibleNode = rootNode
  var accumulatedPreferences = PreferenceValues()
  var popEntries: [NavigationDestinationPopEntry] = []
  var runtimeIssues: [RuntimeIssue] = []
  var activeSurfaceContentNodeIDs: [ViewNodeID] = []

  guard let pathBinding else {
    return NavigationChainResolution(
      visibleNode: visibleNode,
      accumulatedPreferences: accumulatedPreferences,
      popEntries: popEntries,
      runtimeIssues: runtimeIssues,
      depth: 0,
      activeSurfaceContentNodeIDs: activeSurfaceContentNodeIDs
    )
  }

  let values = pathBinding.values()
  guard !values.isEmpty else {
    return NavigationChainResolution(
      visibleNode: visibleNode,
      accumulatedPreferences: accumulatedPreferences,
      popEntries: popEntries,
      runtimeIssues: runtimeIssues,
      depth: 0,
      activeSurfaceContentNodeIDs: activeSurfaceContentNodeIDs
    )
  }

  var declarations = visibleNode.preferenceValues[
    NavigationValueDestinationPreferenceKey.self
  ].declarations
  visibleNode.preferenceValues[NavigationValueDestinationPreferenceKey.self] = .init()

  for (index, value) in values.prefix(navigationDestinationDepthLimit).enumerated() {
    guard
      let declaration = declarations.last(where: {
        $0.valueTypeID == pathBinding.valueTypeID
      }),
      let payload = declaration.makePayload(value)
    else {
      runtimeIssues.append(
        RuntimeIssue(
          severity: .warning,
          code: "navigation.missingValueDestination",
          message:
            "No navigation destination is registered for path value type \(pathBinding.valueTypeName); the path stopped at index \(index).",
          identity: context.identity,
          source: ".navigationDestination(for:destination:)"
        )
      )
      return NavigationChainResolution(
        visibleNode: visibleNode,
        accumulatedPreferences: accumulatedPreferences,
        popEntries: popEntries,
        runtimeIssues: runtimeIssues,
        depth: index,
        activeSurfaceContentNodeIDs: activeSurfaceContentNodeIDs
      )
    }

    accumulatedPreferences.merge(visibleNode.preferenceValues)
    let instanceIdentity =
      declaration.declarationIdentity
      .child("Path[\(index)]")
      .explicitID(value)
    let instance = NavigationDestinationInstance(
      identity: instanceIdentity,
      payload: payload,
      dismiss: { [pathBinding] in
        pathBinding.removeSuffix(index)
      }
    )
    popEntries.append(
      NavigationDestinationPopEntry(
        scopeIdentity: instanceIdentity,
        dismiss: instance.dismiss
      )
    )

    visibleNode = NavigationDestinationSurface(instance: instance)
      .resolve(in: context.replacingIdentity(with: instanceIdentity))
    if let contentNodeID = visibleNode.children.first?.viewNodeID {
      activeSurfaceContentNodeIDs.append(contentNodeID)
    }

    let nestedDeclarations = visibleNode.preferenceValues[
      NavigationValueDestinationPreferenceKey.self
    ].declarations
    declarations.append(contentsOf: nestedDeclarations)
    visibleNode.preferenceValues[NavigationValueDestinationPreferenceKey.self] = .init()
  }

  if values.count > navigationDestinationDepthLimit {
    runtimeIssues.append(navigationDepthLimitIssue(identity: context.identity))
  }

  return NavigationChainResolution(
    visibleNode: visibleNode,
    accumulatedPreferences: accumulatedPreferences,
    popEntries: popEntries,
    runtimeIssues: runtimeIssues,
    depth: min(values.count, navigationDestinationDepthLimit),
    activeSurfaceContentNodeIDs: activeSurfaceContentNodeIDs
  )
}

@MainActor
private func resolveActiveDestinationChain(
  from rootNode: ResolvedNode,
  in context: ResolveContext,
  initial: NavigationChainResolution
) -> NavigationChainResolution {
  var visibleNode = rootNode
  var accumulatedPreferences = initial.accumulatedPreferences
  var popEntries = initial.popEntries
  var runtimeIssues = initial.runtimeIssues
  var depth = initial.depth
  var activeSurfaceContentNodeIDs = initial.activeSurfaceContentNodeIDs

  while depth < navigationDestinationDepthLimit {
    let declarations = visibleNode.preferenceValues[
      NavigationDestinationDeclarationPreferenceKey.self
    ].declarations
    let activeInstances = declarations.compactMap(\.instance)

    visibleNode.preferenceValues[NavigationDestinationDeclarationPreferenceKey.self] = .init()
    visibleNode.preferenceValues[NavigationValueDestinationPreferenceKey.self] = .init()

    guard let instance = activeInstances.last else {
      return NavigationChainResolution(
        visibleNode: visibleNode,
        accumulatedPreferences: accumulatedPreferences,
        popEntries: popEntries,
        runtimeIssues: runtimeIssues,
        depth: depth,
        activeSurfaceContentNodeIDs: activeSurfaceContentNodeIDs
      )
    }

    if activeInstances.count > 1 {
      for losingInstance in activeInstances.dropLast() {
        losingInstance.dismiss()
      }
      runtimeIssues.append(
        RuntimeIssue(
          severity: .warning,
          code: "navigation.multipleActiveDestinations",
          message:
            "\(activeInstances.count) binding-driven navigation destinations were active in the same surface; the last declaration won and every earlier binding was reset.",
          identity: context.identity,
          source: ".navigationDestination(...)"
        )
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
    // The surface's own node collapses onto the reused stack node under a
    // folded `.id`; its payload content node stays distinct per generation and
    // is the leak-bearing subtree, so track that. `NavigationDestinationSurface`
    // resolves its payload as the single child of the surface node.
    if let contentNodeID = visibleNode.children.first?.viewNodeID {
      activeSurfaceContentNodeIDs.append(contentNodeID)
    }
    depth += 1
  }

  let hasOverflow = visibleNode.preferenceValues[
    NavigationDestinationDeclarationPreferenceKey.self
  ].declarations.contains { $0.instance != nil }
  visibleNode.preferenceValues[NavigationDestinationDeclarationPreferenceKey.self] = .init()
  visibleNode.preferenceValues[NavigationValueDestinationPreferenceKey.self] = .init()
  if hasOverflow,
    !runtimeIssues.contains(where: { $0.code == "navigation.depthLimitExceeded" })
  {
    runtimeIssues.append(navigationDepthLimitIssue(identity: context.identity))
  }
  return NavigationChainResolution(
    visibleNode: visibleNode,
    accumulatedPreferences: accumulatedPreferences,
    popEntries: popEntries,
    runtimeIssues: runtimeIssues,
    depth: depth,
    activeSurfaceContentNodeIDs: activeSurfaceContentNodeIDs
  )
}

private func navigationDepthLimitIssue(identity: Identity) -> RuntimeIssue {
  RuntimeIssue(
    severity: .warning,
    code: "navigation.depthLimitExceeded",
    message:
      "Navigation exceeded the \(navigationDestinationDepthLimit)-destination safety limit; deeper destinations were not resolved.",
    identity: identity,
    source: "NavigationStack"
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
  sourceEntity: EntityIdentity?,
  modifierOrdinal: Int,
  scope: Identity?
) -> Identity {
  navigationDestinationDeclarationRoot(
    sourceIdentity: sourceIdentity,
    sourceEntity: sourceEntity,
    scope: scope
  )
  .child("NavigationDestination[\(modifierOrdinal)]")
}

/// The branch-independent root the pushed destination surface's identity is
/// built on.
///
/// The declaration, activation, and pushed-surface identities are all derived
/// from this root, so it decides whether the surface's `@State` survives a
/// change in the *source*'s structural identity. A source whose structural
/// `node.identity` flips every frame while its activation stays live — a
/// sibling reorder (a `ConditionalContent` branch swap) or a child-cardinality
/// toggle (a single resolved child vs a synthesized `Group` node) — would
/// otherwise re-mint the surface node and reset its `@State`.
///
/// When the source carries a stable entity (`.id(...)`) *and* resolves inside a
/// `NavigationStack`, root on the enclosing stack's identity plus the source
/// entity: the stack identity is outside the toggled branch (stable and
/// per-stack-unique) and the entity value is branch-independent, so the surface
/// identity is stable across the flip yet cannot collide with another stack's
/// same-`.id` source (their stack scopes differ). Without a stable entity or an
/// enclosing scope there is no branch-independent key, so fall back to the
/// source's structural identity — matching a source that legitimately loses
/// state when its identity changes.
private func navigationDestinationDeclarationRoot(
  sourceIdentity: Identity,
  sourceEntity: EntityIdentity?,
  scope: Identity?
) -> Identity {
  guard let sourceEntity, let scope else {
    return sourceIdentity
  }
  return
    scope
    .child("NavigationDestinationSource")
    .explicitID(sourceEntity.description)
}

private enum NavigationDestinationDeclarationScopeKey: EnvironmentKey {
  static let defaultValue: Identity? = nil
}

extension EnvironmentValues {
  /// The identity of the nearest enclosing `NavigationStack`, published so a
  /// `navigationDestination(...)` modifier can root a stable-`.id` source's
  /// pushed surface on a branch-independent, per-stack-unique key. See
  /// ``navigationDestinationDeclarationRoot``.
  package var navigationDestinationDeclarationScope: Identity? {
    get { self[NavigationDestinationDeclarationScopeKey.self] }
    set { self[NavigationDestinationDeclarationScopeKey.self] = newValue }
  }
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
