public import Core

/// A focusable control that triggers an action when activated.
public struct Button<Label: View>: View, ResolvableView {
  public var role: ButtonRole?
  private var action: (@MainActor @Sendable () -> Void)?
  private var label: Label
  private let authoringScope: AuthoringContext?

  public init(
    _ title: String,
    role: ButtonRole? = nil
  ) where Label == Text {
    self.role = role
    action = nil
    label = Text(title)
    authoringScope = currentAuthoringContext()
  }

  public init(
    role: ButtonRole? = nil,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    action = nil
    self.label = label()
    authoringScope = currentAuthoringContext()
  }

  public init(
    _ title: String,
    role: ButtonRole? = nil,
    action: @escaping @MainActor @Sendable () -> Void
  ) where Label == Text {
    self.role = role
    self.action = action
    label = Text(title)
    authoringScope = currentAuthoringContext()
  }

  public init(
    role: ButtonRole? = nil,
    action: @escaping @MainActor @Sendable () -> Void,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    self.action = action
    self.label = label()
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }

  package func resolve(
    in context: ResolveContext
  ) -> ResolvedNode {
    resolvedNode(in: context)
  }
}

extension Button {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.pressedIdentity == context.identity
    let buttonStyle = context.environmentValues.buttonStyle

    if context.environmentValues.isEnabled, let action {
      let dynamicPropertyScope = currentAuthoringContext() ?? authoringScope
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          return withAuthoringContext(dynamicPropertyScope) {
            action()
            return true
          }
        },
        followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
      )
    }

    let effectiveProminence = buttonStyle.resolvedProminence(
      base: context.environmentValues.controlProminence
    )
    let configuration = ButtonStyleConfiguration(
      label: .init(authoringContext: authoringScope) { label },
      role: role,
      isEnabled: context.environmentValues.isEnabled,
      isFocused: isFocused,
      showsFocusEffect: showsFocusEffect,
      isPressed: isPressed,
      controlProminence: effectiveProminence,
      buttonBorderShape: context.environmentValues.buttonBorderShape,
      styleEnvironment: styleEnvironment
    )
    let child = buttonStyle.resolveBody(
      configuration: configuration,
      in: context.child(component: .named("ButtonBody"))
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Button"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .activate,
        presentationRole: .button
      )
    )
  }
}
