package import Core

/// A focusable command menu that expands inline when activated.
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
      let dynamicPropertyScope = currentDynamicPropertyScope()
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          withDynamicPropertyScope(dynamicPropertyScope) {
            binding.wrappedValue.toggle()
            return true
          }
        },
        followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
      )
    }

    let child = menuBody(
      isExpanded: isExpanded,
      isFocused: isFocused,
      isPressed: isPressed,
      chrome: chrome
    ).resolve(
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
