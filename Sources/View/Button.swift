import Core

/// A focusable control that triggers an action when activated.
public struct Button: View, ResolvableView {
  public var role: ButtonRole?
  private var action: (() -> Void)?
  private var labelViews: [AnyView]

  public init(
    _ title: String,
    role: ButtonRole? = nil
  ) {
    self.role = role
    action = nil
    labelViews = [AnyView(Text(title))]
  }

  public init<Label: View>(
    role: ButtonRole? = nil,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    action = nil
    labelViews = parallelBuilderChildren(from: label())
  }

  public init(
    _ title: String,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) {
    self.role = role
    self.action = action
    labelViews = [AnyView(Text(title))]
  }

  public init<Label: View>(
    role: ButtonRole? = nil,
    action: @escaping () -> Void,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    self.action = action
    labelViews = parallelBuilderChildren(from: label())
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
    let isFocused = context.environmentValues.parallelFocusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.parallelPressedIdentity == context.identity
    let buttonStyle = context.environmentValues.buttonStyle
    let effectiveProminence =
      buttonStyle == .borderedProminent
      ? ControlProminence.increased : context.environmentValues.controlProminence
    let chrome = context.environmentValues.terminalAppearance.buttonChrome(
      buttonStyle: buttonStyle,
      isEnabled: context.environmentValues.isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed,
      prominence: effectiveProminence,
      role: role
    )

    if context.environmentValues.isEnabled, let action {
      let dynamicPropertyScope = currentDynamicPropertyScope()
      context.localActionRegistry?.register(identity: context.identity) {
        withDynamicPropertyScope(dynamicPropertyScope) {
          action()
          return true
        }
      }
    }

    let body = buttonBody(
      buttonStyle: buttonStyle,
      chrome: chrome,
      prominence: effectiveProminence,
      borderShape: context.environmentValues.buttonBorderShape
    )
    let child = body.resolve(
      in: context.child(component: "ButtonBody")
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Button"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: parallelFocusableControlMetadata(
        focusInteractions: .activate,
        presentationRole: .button
      )
    )
  }

  private func buttonBody(
    buttonStyle: ButtonStyle,
    chrome: ControlChrome,
    prominence: ControlProminence,
    borderShape: ButtonBorderShape
  ) -> AnyView {
    let baseLabel = AnyView(
      composedLabelView()
        .foregroundStyle(chrome.foregroundStyle)
        .drawMetadata(.init(opacity: chrome.opacity))
    )

    let label: AnyView
    switch buttonStyle {
    case .plain:
      label = baseLabel
    case .link:
      label = AnyView(
        baseLabel
          .underline()
          .background {
            Rectangle().fill(chrome.backgroundStyle)
          }
      )
    case .automatic, .bordered, .borderedProminent:
      label = AnyView(
        baseLabel
          .padding(.init(all: 1))
          .background {
            buttonBackground(
              prominence: prominence,
              borderShape: borderShape,
              style: chrome.backgroundStyle
            )
          }
          .overlay {
            buttonBorder(
              prominence: prominence,
              borderShape: borderShape,
              style: chrome.borderStyle,
              backgroundStyle: chrome.borderBackgroundStyle
            )
          }
      )
    }

    let protectedLabel =
      switch buttonStyle {
      case .automatic, .bordered, .borderedProminent:
        AnyView(
          label.layoutMetadata(
            .init(minimumHeight: 3)
          )
        )
      case .plain, .link:
        label
      }

    return protectedLabel
  }

  private func composedLabelView() -> AnyView {
    combinedView(from: labelViews, kindName: "ButtonLabel")
  }

  private func buttonBackground(
    prominence: ControlProminence,
    borderShape: ButtonBorderShape,
    style: AnyShapeStyle
  ) -> AnyView {
    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      return AnyView(
        RoundedRectangle(cornerRadius: 1).parallelInteriorFill(style)
      )
    default:
      return AnyView(
        Rectangle().parallelInteriorFill(style)
      )
    }
  }

  private func buttonBorder(
    prominence: ControlProminence,
    borderShape: ButtonBorderShape,
    style: AnyShapeStyle,
    backgroundStyle: AnyShapeStyle?
  ) -> AnyView {
    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      return AnyView(
        RoundedRectangle(cornerRadius: 1).parallelStrokeBorder(
          style,
          backgroundStyle: backgroundStyle
        )
      )
    default:
      return AnyView(
        Rectangle().parallelStrokeBorder(
          style,
          backgroundStyle: backgroundStyle
        )
      )
    }
  }
}
