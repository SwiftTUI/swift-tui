import SwiftTUICore

@MainActor
private func menuIsExpanded(in ownerNode: SwiftTUICore.ViewNode?) -> Bool {
  guard let ownerNode else { return false }
  return ownerNode.stateSlot(ordinal: StateSlotOrdinals.menuExpansion, seed: false)
}

/// A focusable command menu.
/// Its automatic style floats expanded content above the surrounding layout.
/// Opening and closing a floating menu does not reflow sibling views.
///
/// The automatic trigger row (`Label ▾` / `Label ▴`) renders inline at
/// the menu's site in the layout, taking exactly one cell of height.
/// When active, a nonmodal portal entry hosts the user-supplied `content`.
/// The automatic entry is a compact bordered box with intrinsic width at the
/// top-leading of the portal root; a ``MenuStyle`` supplies its own
/// ``AnchoredSurfaceStylePresentation`` (insets, bounds, border, paint) or
/// composes the content inline instead.
///
/// **Current presentation behavior:**
/// - Anchoring is at the presentation host's top-leading rather than
///   at the menu's source frame.
/// - The menu stays non-modal: opening it does not freeze surrounding
///   controls, although Escape still dismisses the topmost open menu.
/// Use ``MenuStyle`` to compose a different trigger or inline content.
public struct Menu<Label: View, Content: View>: PrimitiveView, IterativeResolvableView {
  package var label: Label
  package var content: Content
  private let authoringScope: AuthoringContext?

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    authoringScope = currentAuthoringContext()
    label = Text(String(title))
    self.content = content()
  }

  public init(
    @ViewBuilder label: () -> Label,
    @ViewBuilder content: () -> Content
  ) {
    authoringScope = currentAuthoringContext()
    self.label = label()
    self.content = content()
  }

  package func makeResolveWork(
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return resolveViewWork(
      MenuStateHost(menu: self, controlIdentity: context.identity),
      in: context.child(component: .named("MenuState"))
    ).map { child in
      var metadata = focusableControlMetadata(
        focusInteractions: .activate, accessibilityRole: .menu
      )
      .namingControl(with: label)
      // The open menu remains a keyboard dismissal target after disablement.
      // Its commands and pointer routes still obey the disabled environment.
      metadata.allowsFocusWhenDisabled = menuIsExpanded(
        in: context.viewGraph?.nodeForIdentity(context.identity.child(.named("MenuState"))))
      // Keep geometric evidence that the keyboard action has no pointer area.
      // Merely omitting its region permits the runtime's ancestor-action fallback.
      metadata.explicitInteractionRect = CellRect(origin: .zero, size: .zero)
      return [
        ResolvedNode(
          identity: context.identity,
          kind: .view("Menu"),
          children: [child],
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction,
          semanticMetadata: metadata)
      ]
    }
  }
}

/// A menu may occupy the same style-body position as a different container.
/// Its expansion lifetime belongs to this dedicated child, which departs when
/// the menu leaves, rather than the surviving style-body node.
extension Menu {
  private struct MenuStateHost: PrimitiveView, IterativeResolvableView {
    let menu: Menu<Label, Content>
    let controlIdentity: Identity

    func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
      let owner = ViewNodeContext.current?.stateOwnerHandle
      return menu.resolvedBody(
        in: context.replacingIdentity(with: controlIdentity), ownerNode: ViewNodeContext.current
      ).map { body in
        var node = ResolvedNode(
          identity: context.identity, kind: .view("MenuState"), children: [body],
          environmentSnapshot: context.environment, transactionSnapshot: context.transaction)
        if let owner {
          node.preferenceValues[CapturedSubviewOwnersPreferenceKey.self].insert(owner)
        }
        return [node]
      }
    }
  }

  private func resolvedBody(
    in context: ResolveContext, ownerNode: SwiftTUICore.ViewNode?
  ) -> ResolveWork<ResolvedNode> {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused =
      context.environmentValues.focusedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed =
      context.environmentValues.pressedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let isEnabled = context.environmentValues.isEnabled
    // A disabled menu keeps its expansion: disabling one while it is
    // presented leaves the content visible with its actions disabled (pinned
    // by the presentation-semantics stress suite). Dismissal remains available
    // while disabled, just as it does for a floating portal.
    let isExpanded = menuIsExpanded(in: ownerNode)
    let owner = ownerNode?.stateOwnerHandle
    let controlIdentity = context.identity
    let expansionBinding = Binding<Bool>(
      get: { menuIsExpanded(in: owner.flatMap(LiveViewGraphRegistry.node(for:))) },
      set: { value in
        owner.flatMap(LiveViewGraphRegistry.node(for:))?.setStateSlot(
          ordinal: StateSlotOrdinals.menuExpansion, value: value,
          invalidationIdentity: controlIdentity)
      })

    let binding = expansionBinding
    let intake = HandlerDescriptorIntake(
      context: context,
      fallbackAuthoringScope: authoringScope
    )
    if isEnabled {
      intake.registerAction(identity: context.identity) {
        binding.wrappedValue.toggle()
        return true
      }
      intake.registerPointerHandler(
        routeID: runtimePrimaryRouteID(for: menuTriggerIdentity(for: context.identity))
      ) { event in
        switch event.kind {
        case .down(.primary):
          binding.wrappedValue.toggle()
          return .claimed
        case .up(.primary): return .claimed
        default: return .ignored
        }
      }
    }
    if isExpanded {
      let dismissOnEscape: @MainActor (KeyPress) -> Bool = { key in
        guard key.modifiers.isEmpty, key.key == .escape, binding.wrappedValue else { return false }
        binding.wrappedValue = false
        return true
      }
      intake.registerKeyPressHandler(identity: context.identity, handler: dismissOnEscape)
      // Inline descendants bubble through the dedicated host; the trigger
      // itself focuses the public control identity above that host.
      if let ownerNode, ownerNode.identity != context.identity {
        intake.registerKeyPressHandler(identity: ownerNode.identity, handler: dismissOnEscape)
      }
    }

    var configuration = MenuStyleConfiguration(
      label: .init(authoringContext: authoringScope) { label.authoredAccessibilityLabel() },
      content: .init(authoringContext: authoringScope) { content },
      isPresented: enabledStyleBinding(expansionBinding, isEnabled: isEnabled),
      isEnabled: isEnabled, isFocused: isFocused, showsFocusEffect: showsFocusEffect,
      isPressed: isPressed, styleEnvironment: styleEnvironment)
    configuration.bindRoutes(to: context.identity, presentation: expansionBinding)
    if let owner {
      configuration.content.retention = CapturedSubviewRetention(
        owner: owner, identity: context.identity.child(.named("MenuContent")))
    }
    let style = context.environmentValues.menuStyle
    let bodyContext = context.child(component: .named("MenuBody"))
    return style.resolveBody(configuration: configuration, in: bodyContext).flatMap { child in
      guard isExpanded,
        !child.preferenceValues[MenuStyleUsagePreferenceKey.self].contains(context.identity)
      else { return .value(child) }
      ImperativeRuntimeIssueQueue.record(
        StyleMisuse.missingRequiredRouteIssue(
          family: "MenuStyle", role: "portal wrapper and inline content",
          styleLabel: style.snapshotLabel, identity: context.identity))
      return AnyMenuStyle.automatic.resolveBody(configuration: configuration, in: bodyContext)

    }
  }
}
