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
/// The entry uses `.menu` chrome.
/// This chrome is a compact bordered box with intrinsic width at the top-leading of the portal root.
///
/// **Current presentation behavior:**
/// - Anchoring is at the presentation host's top-leading rather than
///   at the menu's source frame.
/// - The menu stays non-modal: opening it does not freeze surrounding
///   controls, although Escape still dismisses the topmost open menu.
/// Use ``MenuStyle`` to compose a different trigger or inline content.
public struct Menu<Label: View, Content: View>: PrimitiveView, ResolvableView {
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

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let child = resolveView(
      MenuStateHost(menu: self, controlIdentity: context.identity),
      in: context.child(component: .named("MenuState")))
    var metadata = focusableControlMetadata(focusInteractions: .activate, accessibilityRole: .menu)
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

/// A menu may occupy the same style-body position as a different container.
/// Its expansion lifetime belongs to this dedicated child, which departs when
/// the menu leaves, rather than the surviving style-body node.
extension Menu {
  private struct MenuStateHost: PrimitiveView, ResolvableView {
    let menu: Menu<Label, Content>
    let controlIdentity: Identity

    func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
      let body = menu.resolvedBody(
        in: context.replacingIdentity(with: controlIdentity), ownerNode: ViewNodeContext.current)
      return [
        ResolvedNode(
          identity: context.identity, kind: .view("MenuState"), children: [body],
          environmentSnapshot: context.environment, transactionSnapshot: context.transaction)
      ]
    }
  }

  private func resolvedBody(
    in context: ResolveContext, ownerNode: SwiftTUICore.ViewNode?
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused =
      context.environmentValues.focusedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed =
      context.environmentValues.pressedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let isEnabled = context.environmentValues.isEnabled
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

    if isEnabled {
      let binding = expansionBinding
      let intake = HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: authoringScope
      )
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
      label: .init(authoringContext: authoringScope) { label },
      content: .init(authoringContext: authoringScope) { content },
      isPresented: enabledStyleBinding(expansionBinding, isEnabled: isEnabled),
      isEnabled: isEnabled, isFocused: isFocused, showsFocusEffect: showsFocusEffect,
      isPressed: isPressed, styleEnvironment: styleEnvironment)
    configuration.bindRoutes(to: context.identity, presentation: expansionBinding)
    let style = context.environmentValues.menuStyle
    let bodyContext = context.child(component: .named("MenuBody"))
    let child = style.resolveBody(configuration: configuration, in: bodyContext)
    guard isExpanded,
      !child.preferenceValues[MenuStyleUsagePreferenceKey.self].contains(context.identity)
    else { return child }
    ImperativeRuntimeIssueQueue.record(
      RuntimeIssue(
        severity: .warning, code: "style.missingRequiredRoute",
        message:
          "MenuStyle \(style.snapshotLabel) omitted its portal wrapper and inline content while presented. "
          + "The automatic style body was rendered for this resolve.",
        identity: context.identity, source: "MenuStyle"))
    return AnyMenuStyle.automatic.resolveBody(configuration: configuration, in: bodyContext)
  }
}
