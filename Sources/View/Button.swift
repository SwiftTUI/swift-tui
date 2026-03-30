public import Core

// AnyView policy: retain heterogeneous child storage here for authored labels
// and local branch unification in button rendering.
/// A focusable control that triggers an action when activated.
public struct Button: View, ResolvableView {
  public var role: ButtonRole?
  private var action: (@MainActor @Sendable () -> Void)?
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
    labelViews = declaredBuilderChildren(from: label())
  }

  public init(
    _ title: String,
    role: ButtonRole? = nil,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.role = role
    self.action = action
    labelViews = [AnyView(Text(title))]
  }

  public init<Label: View>(
    role: ButtonRole? = nil,
    action: @escaping @MainActor @Sendable () -> Void,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    self.action = action
    labelViews = declaredBuilderChildren(from: label())
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

  private func buttonBody(
    buttonStyle: ButtonStyle,
    chrome: ControlChrome,
    chromePreset: ChromePreset,
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
      let usesDenseBorderlessChrome =
        chromePreset == .standard && buttonStyle != .bordered
      label = AnyView(
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
            Group {
              if !usesDenseBorderlessChrome {
                buttonBorder(
                  prominence: prominence,
                  borderShape: borderShape,
                  style: chrome.borderStyle,
                  backgroundStyle: chrome.borderBackgroundStyle
                )
              } else {
                EmptyView()
              }
            }
          }
      )
    }

    let protectedLabel =
      switch buttonStyle {
      case .automatic, .bordered, .borderedProminent:
        if chromePreset == .standard && buttonStyle != .bordered {
          label
        } else {
          AnyView(
            label.layoutMetadata(
              .init(minimumHeight: 3)
            )
          )
        }
      case .plain, .link:
        label
      }

    return protectedLabel
  }

  private func composedLabelView() -> AnyView {
    combinedView(from: labelViews, kindName: "ButtonLabel")
  }

  private func buttonBackground(
    usesDenseBorderlessChrome: Bool,
    prominence: ControlProminence,
    borderShape: ButtonBorderShape,
    style: AnyShapeStyle
  ) -> AnyView {
    if usesDenseBorderlessChrome {
      switch (borderShape, prominence) {
      case (.roundedRectangle, _), (.automatic, .increased):
        return AnyView(
          RoundedRectangle(cornerRadius: 1).fill(style)
        )
      default:
        return AnyView(
          Rectangle().fill(style)
        )
      }
    }

    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      return AnyView(
        RoundedRectangle(cornerRadius: 1).chromeFill(style)
      )
    default:
      return AnyView(
        Rectangle().chromeFill(style)
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
        RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
          style,
          backgroundStyle: backgroundStyle
        )
      )
    default:
      return AnyView(
        Rectangle().chromeStrokeBorder(
          style,
          backgroundStyle: backgroundStyle
        )
      )
    }
  }
}
