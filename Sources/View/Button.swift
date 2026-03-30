public import Core

/// A focusable control that triggers an action when activated.
public struct Button<Label: View>: View, ResolvableView {
  public var role: ButtonRole?
  private var action: (@MainActor @Sendable () -> Void)?
  private var label: Label

  public init(
    _ title: String,
    role: ButtonRole? = nil
  ) where Label == Text {
    self.role = role
    action = nil
    label = Text(title)
  }

  public init(
    role: ButtonRole? = nil,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    action = nil
    self.label = label()
  }

  public init(
    _ title: String,
    role: ButtonRole? = nil,
    action: @escaping @MainActor @Sendable () -> Void
  ) where Label == Text {
    self.role = role
    self.action = action
    label = Text(title)
  }

  public init(
    role: ButtonRole? = nil,
    action: @escaping @MainActor @Sendable () -> Void,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    self.action = action
    self.label = label()
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
    let effectiveProminence =
      buttonStyle == .borderedProminent
      ? ControlProminence.increased : context.environmentValues.controlProminence
    let chrome = styleEnvironment.buttonChrome(
      buttonStyle: buttonStyle,
      isEnabled: context.environmentValues.isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed,
      prominence: effectiveProminence,
      role: role
    )

    if context.environmentValues.isEnabled, let action {
      let dynamicPropertyScope = currentDynamicPropertyScope()
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          withDynamicPropertyScope(dynamicPropertyScope) {
            action()
            return true
          }
        },
        followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
      )
    }

    let body = buttonBody(
      buttonStyle: buttonStyle,
      chrome: chrome,
      chromePreset: styleEnvironment.chromePreset,
      prominence: effectiveProminence,
      borderShape: context.environmentValues.buttonBorderShape
    )
    let child = body.resolve(
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

  @ViewBuilder
  private func buttonBody(
    buttonStyle: ButtonStyle,
    chrome: ControlChrome,
    chromePreset: ChromePreset,
    prominence: ControlProminence,
    borderShape: ButtonBorderShape
  ) -> some View {
    let baseLabel =
      label
      .foregroundStyle(chrome.foregroundStyle)
      .drawMetadata(.init(opacity: chrome.opacity))

    switch buttonStyle {
    case .plain:
      baseLabel
    case .link:
      baseLabel
        .underline()
        .background {
          Rectangle().fill(chrome.backgroundStyle)
        }
    case .automatic, .bordered, .borderedProminent:
      let usesDenseBorderlessChrome =
        chromePreset == .standard && buttonStyle != .bordered
      let styledLabel =
        baseLabel
        .padding(
          .init(
            horizontal: 1,
            vertical: chromePreset == .legacy || buttonStyle == .bordered ? 1 : 0
          )
        )
        .background {
          buttonBackground(
            usesDenseBorderlessChrome: usesDenseBorderlessChrome,
            prominence: prominence,
            borderShape: borderShape,
            style: chrome.backgroundStyle
          )
        }
        .overlay {
          if !usesDenseBorderlessChrome {
            buttonBorder(
              prominence: prominence,
              borderShape: borderShape,
              style: chrome.borderStyle,
              backgroundStyle: chrome.borderBackgroundStyle
            )
          }
        }

      if chromePreset == .standard && buttonStyle != .bordered {
        styledLabel
      } else {
        styledLabel.layoutMetadata(.init(minimumHeight: 3))
      }
    }
  }

  @ViewBuilder
  private func buttonBackground(
    usesDenseBorderlessChrome: Bool,
    prominence: ControlProminence,
    borderShape: ButtonBorderShape,
    style: AnyShapeStyle
  ) -> some View {
    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      if usesDenseBorderlessChrome {
        RoundedRectangle(cornerRadius: 1).fill(style)
      } else {
        RoundedRectangle(cornerRadius: 1).chromeFill(style)
      }
    default:
      if usesDenseBorderlessChrome {
        Rectangle().fill(style)
      } else {
        Rectangle().chromeFill(style)
      }
    }
  }

  @ViewBuilder
  private func buttonBorder(
    prominence: ControlProminence,
    borderShape: ButtonBorderShape,
    style: AnyShapeStyle,
    backgroundStyle: AnyShapeStyle?
  ) -> some View {
    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
        style,
        backgroundStyle: backgroundStyle
      )
    default:
      Rectangle().chromeStrokeBorder(
        style,
        backgroundStyle: backgroundStyle
      )
    }
  }
}
