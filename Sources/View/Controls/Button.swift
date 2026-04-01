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

    #if canImport(WASILibc)
      print("[button] style=\(buttonStyle)")
    #endif
    let childContext = context.child(component: .named("ButtonBody"))
    let child: ResolvedNode
    switch buttonStyle {
    case .plain:
      #if canImport(WASILibc)
        print("[button] resolving plain body")
      #endif
      child = ButtonPlainBody(
        label: label,
        chrome: chrome
      )
      .resolve(in: childContext)
    case .link:
      #if canImport(WASILibc)
        print("[button] resolving link body")
      #endif
      child = ButtonLinkBody(
        label: label,
        chrome: chrome
      )
      .resolve(in: childContext)
    case .automatic, .bordered, .borderedProminent:
      #if canImport(WASILibc)
        print("[button] resolving chrome body")
      #endif
      child = ButtonChromeBody(
        label: label,
        chrome: chrome,
        buttonStyle: buttonStyle,
        chromePreset: styleEnvironment.chromePreset,
        prominence: effectiveProminence,
        borderShape: context.environmentValues.buttonBorderShape
      )
      .resolve(in: childContext)
    }
    #if canImport(WASILibc)
      print("[button] child resolved")
    #endif

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

private struct ButtonPlainBody<Label: View>: View {
  var label: Label
  var chrome: ControlChrome

  var body: some View {
    label
      .foregroundStyle(chrome.foregroundStyle)
      .drawMetadata(.init(opacity: chrome.opacity))
  }
}

private struct ButtonLinkBody<Label: View>: View {
  var label: Label
  var chrome: ControlChrome

  var body: some View {
    ButtonPlainBody(
      label: label,
      chrome: chrome
    )
    .underline()
    .background {
      Rectangle().fill(chrome.backgroundStyle)
    }
  }
}

private struct ButtonChromeBody<Label: View>: View {
  var label: Label
  var chrome: ControlChrome
  var buttonStyle: ButtonStyle
  var chromePreset: ChromePreset
  var prominence: ControlProminence
  var borderShape: ButtonBorderShape

  private var usesDenseBorderlessChrome: Bool {
    chromePreset == .standard && buttonStyle != .bordered
  }

  private var verticalPadding: Int {
    chromePreset == .legacy || buttonStyle == .bordered ? 1 : 0
  }

  private var needsMinimumHeight: Bool {
    chromePreset != .standard || buttonStyle == .bordered
  }

  var body: some View {
    let styledLabel =
      ButtonPlainBody(
        label: label,
        chrome: chrome
      )
      .padding(
        .init(
          horizontal: 1,
          vertical: verticalPadding
        )
      )
      .background {
        ButtonChromeBackground(
          chrome: chrome,
          usesDenseBorderlessChrome: usesDenseBorderlessChrome,
          prominence: prominence,
          borderShape: borderShape
        )
      }
      .overlay {
        if !usesDenseBorderlessChrome {
          ButtonChromeBorder(
            chrome: chrome,
            prominence: prominence,
            borderShape: borderShape
          )
        }
      }

    if needsMinimumHeight {
      styledLabel.layoutMetadata(.init(minimumHeight: 3))
    } else {
      styledLabel
    }
  }
}

private struct ButtonChromeBackground: View {
  var chrome: ControlChrome
  var usesDenseBorderlessChrome: Bool
  var prominence: ControlProminence
  var borderShape: ButtonBorderShape

  @ViewBuilder
  var body: some View {
    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      if usesDenseBorderlessChrome {
        RoundedRectangle(cornerRadius: 1).fill(chrome.backgroundStyle)
      } else {
        RoundedRectangle(cornerRadius: 1).chromeFill(chrome.backgroundStyle)
      }
    default:
      if usesDenseBorderlessChrome {
        Rectangle().fill(chrome.backgroundStyle)
      } else {
        Rectangle().chromeFill(chrome.backgroundStyle)
      }
    }
  }
}

private struct ButtonChromeBorder: View {
  var chrome: ControlChrome
  var prominence: ControlProminence
  var borderShape: ButtonBorderShape

  @ViewBuilder
  var body: some View {
    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
        chrome.borderStyle,
        backgroundStyle: chrome.borderBackgroundStyle
      )
    default:
      Rectangle().chromeStrokeBorder(
        chrome.borderStyle,
        backgroundStyle: chrome.borderBackgroundStyle
      )
    }
  }
}
