import Core

/// Edits a string binding using keyboard input while masking the rendered value.
public struct SecureField: View, ResolvableView {
  public var text: Binding<String>
  public var prompt: Text?
  private var labelViews: [AnyView]

  public init<S: StringProtocol>(
    _ title: S,
    text: Binding<String>
  ) {
    self.text = text
    prompt = Text(String(title))
    labelViews = []
  }

  public init<Label: View>(
    text: Binding<String>,
    prompt: Text? = nil,
    @ViewBuilder label: () -> Label
  ) {
    self.text = text
    self.prompt = prompt
    labelViews = parallelBuilderChildren(from: label())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension SecureField {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let isFocused = context.environmentValues.parallelFocusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isEnabled = context.environmentValues.isEnabled
    let fieldText = text.wrappedValue
    let effectiveStyle =
      context.environmentValues.textFieldStyle == .automatic
      ? TextFieldStyle.roundedBorder
      : context.environmentValues.textFieldStyle
    let chrome = context.environmentValues.terminalAppearance.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )

    registerTextEntryBinding(text, in: context)
    let entryText = textEntryDisplayText(
      text: fieldText,
      promptText: prompt?.content,
      isActiveNavigation: isFocused,
      masked: true
    )
    let child = textEntryFieldBody(
      displayText: entryText.displayText,
      isShowingPrompt: entryText.isShowingPrompt,
      labelViews: labelViews,
      style: effectiveStyle,
      chrome: chrome,
      appearance: context.environmentValues.terminalAppearance
    ).resolve(
      in: context.child(component: "SecureFieldBody")
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("SecureField"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: parallelFocusableControlMetadata(
        focusInteractions: .edit,
        presentationRole: .textField
      )
    )
  }
}
