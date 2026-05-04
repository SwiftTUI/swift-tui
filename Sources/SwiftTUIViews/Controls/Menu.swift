package import SwiftTUICore

/// A focusable command menu whose expanded content floats above the
/// surrounding layout as an overlay — opening and closing the menu
/// does NOT reflow sibling views.
///
/// The trigger row (`Label ▾` / `Label ▴`) always renders inline at
/// the menu's site in the layout, taking exactly one cell of height.
/// When activated, the user-supplied `content` is hosted by a non-modal
/// portal entry with `.menu` chrome (a compact, intrinsic-width bordered
/// box anchored at the portal root's top-leading).
///
/// **v1 caveats** (tracked as future work):
/// - Anchoring is at the presentation host's top-leading rather than
///   at the menu's source frame. A future enhancement will plumb
///   source frames through the presentation system.
/// - The menu stays non-modal: opening it does not freeze surrounding
///   controls, although Escape still dismisses the topmost open menu.
public struct Menu<Label: View, Content: View>: View, ResolvableView {
  @State private var isExpanded = false
  package var label: Label
  package var content: Content

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    label = Text(String(title))
    self.content = content()
  }

  public init(
    @ViewBuilder label: () -> Label,
    @ViewBuilder content: () -> Content
  ) {
    self.label = label()
    self.content = content()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let dynamicPropertyScope = dynamicPropertyAuthoringContext(for: context)
    return withAuthoringContext(dynamicPropertyScope) {
      [resolvedNode(in: context)]
    }
  }
}

extension Menu {
  private var expansionBinding: Binding<Bool> {
    $isExpanded
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.pressedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let chrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed
    )

    if isEnabled {
      let binding = expansionBinding
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: { [authoringContext = currentImperativeAuthoringContextSnapshot()] in
          withImperativeAuthoringContext(authoringContext) {
            binding.wrappedValue.toggle()
            return true
          }
        },
        followUpInvalidationIdentity: currentImperativeAuthoringContextSnapshot()?.viewIdentity
      )
    }

    // Wrap the trigger row with the prompt presentation modifier so the
    // menu's expanded content rides the portal overlay infrastructure.
    // Routing the modifier through the view tree (rather
    // than imperatively attaching the preference inside this function)
    // is critical: `ResolvedNode.children`'s setter recomputes
    // `preferenceValues` from its children, so an imperative attach on
    // the parent gets overwritten when `ViewNode.snapshot()` rebuilds.
    // A modifier in the view tree re-applies on every resolve, so the
    // preference is always present in the rebuilt snapshot.
    let triggerView = menuTriggerRow(
      isExpanded: isExpanded,
      isFocused: isFocused,
      isPressed: isPressed,
      chrome: chrome
    )
    let menuPresentation = triggerView.modifier(
      BuiltinSheetPresentationModifier(
        title: "",
        isPresented: expansionBinding,
        spec: menuPromptPresentationSpec(),
        sheetContent: content,
        sheetContentAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )

    let child = menuPresentation.resolve(
      in: context.child(component: .named("MenuBody"))
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Menu"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .activate,
        presentationRole: .menu
      )
    )
  }
}
