import Core

/// A focusable command menu that expands inline when activated.
public struct Menu: View, ResolvableView {
  @State private var isExpanded = false
  package var labelViews: [AnyView]
  package var contentViews: [AnyView]

  public init<S: StringProtocol, Content: View>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) {
    labelViews = [AnyView(Text(String(title)))]
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<Label: View, Content: View>(
    @ViewBuilder label: () -> Label,
    @ViewBuilder content: () -> Content
  ) {
    labelViews = parallelBuilderChildren(from: label())
    contentViews = parallelBuilderChildren(from: content())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension Menu {
  private var expansionBinding: Binding<Bool> {
    $isExpanded
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let isFocused = context.environmentValues.parallelFocusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.parallelPressedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let chrome = context.environmentValues.terminalAppearance.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed
    )

    if isEnabled {
      let binding = expansionBinding
      let dynamicPropertyScope = currentDynamicPropertyScope()
      context.localActionRegistry?.register(identity: context.identity) {
        withDynamicPropertyScope(dynamicPropertyScope) {
          binding.wrappedValue.toggle()
          return true
        }
      }
    }

    let child = menuBody(
      isExpanded: isExpanded,
      isFocused: isFocused,
      isPressed: isPressed,
      chrome: chrome
    ).resolve(
      in: context.child(component: "MenuBody")
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Menu"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: parallelFocusableControlMetadata(
        focusInteractions: .activate,
        presentationRole: .menu
      )
    )
  }
}
