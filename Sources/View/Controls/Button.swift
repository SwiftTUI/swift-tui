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

    let childContext = context.child(component: .named("ButtonBody"))
    let child: ResolvedNode
    switch buttonStyle {
    case .plain:
      child = ButtonPlainBody(
        label: label,
        chrome: chrome,
        focusActive: isFocused && showsFocusEffect
      )
      .resolve(in: childContext)
    case .link:
      child = ButtonLinkBody(
        label: label,
        chrome: chrome,
        focusActive: isFocused && showsFocusEffect
      )
      .resolve(in: childContext)
    case .automatic, .bordered, .borderedProminent:
      child = ButtonChromeBody(
        label: label,
        chrome: chrome,
        buttonStyle: buttonStyle,
        prominence: effectiveProminence,
        borderShape: context.environmentValues.buttonBorderShape,
        focusActive: isFocused && showsFocusEffect
      )
      .resolve(in: childContext)
    }

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
  var focusActive: Bool

  var body: some View {
    // The focus rail is drawn as an overlay rather than an HStack
    // sibling. If it lived inside `controlFocusRow` the button's
    // bounds would grow by the rail width the moment focus arrives,
    // shifting the row's layout out from under a pressed pointer and
    // making mouseDown-followed-by-mouseUp miss the armed route so
    // the action never dispatches. With the overlay, the button's
    // bounds are stable across focus state changes.
    highlightedControlRow(
      label,
      isHighlighted: focusActive,
      backgroundStyle: chrome.backgroundStyle
    )
    .foregroundStyle(chrome.foregroundStyle)
    .drawMetadata(.init(opacity: chrome.opacity))
    .overlay(alignment: .leading) {
      if focusActive {
        Text(controlFocusRailGlyph)
          .foregroundStyle(chrome.borderStyle)
      }
    }
  }
}

private struct ButtonLinkBody<Label: View>: View {
  var label: Label
  var chrome: ControlChrome
  var focusActive: Bool

  var body: some View {
    ButtonPlainBody(
      label: label.underline(),
      chrome: chrome,
      focusActive: focusActive
    )
    .background {
      Rectangle().fill(chrome.backgroundStyle)
    }
  }
}

private struct ButtonChromeBody<Label: View>: View {
  var label: Label
  var chrome: ControlChrome
  var buttonStyle: ButtonStyle
  var prominence: ControlProminence
  var borderShape: ButtonBorderShape
  var focusActive: Bool

  private var usesDenseBorderlessChrome: Bool {
    buttonStyle != .bordered
  }

  private var verticalPadding: Int {
    buttonStyle == .bordered ? 1 : 0
  }

  private var needsMinimumHeight: Bool {
    buttonStyle == .bordered
  }

  var body: some View {
    let styledLabel =
      ButtonPlainBody(
        label: label,
        chrome: chrome,
        focusActive: false
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
            borderShape: borderShape,
            focusActive: focusActive
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
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(chrome.backgroundStyle)
      }
    default:
      if usesDenseBorderlessChrome {
        Rectangle().fill(chrome.backgroundStyle)
      } else {
        Rectangle().inset(by: 1).fill(chrome.backgroundStyle)
      }
    }
  }
}

private struct ButtonChromeBorder: View {
  var chrome: ControlChrome
  var prominence: ControlProminence
  var borderShape: ButtonBorderShape
  var focusActive: Bool

  @ViewBuilder
  var body: some View {
    let strokeStyle: StrokeStyle = focusActive ? .thick : .init()
    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
        chrome.borderStyle,
        style: strokeStyle,
        backgroundStyle: chrome.borderBackgroundStyle
      )
    default:
      Rectangle().chromeStrokeBorder(
        chrome.borderStyle,
        style: strokeStyle,
        backgroundStyle: chrome.borderBackgroundStyle
      )
    }
  }
}
