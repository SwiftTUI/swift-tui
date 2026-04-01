package import Core

/// Edits a string binding using keyboard input while masking the rendered value.
public struct SecureField<Label: View>: View, ResolvableView {
  public var text: Binding<String>
  public var prompt: Text?
  private var label: Label
  private var showsLabel: Bool

  public init<S: StringProtocol>(
    _ title: S,
    text: Binding<String>
  ) where Label == EmptyView {
    self.text = text
    prompt = Text(String(title))
    label = EmptyView()
    showsLabel = false
  }

  public init(
    text: Binding<String>,
    prompt: Text? = nil,
    @ViewBuilder label: () -> Label
  ) {
    self.text = text
    self.prompt = prompt
    self.label = label()
    showsLabel = true
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
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isEnabled = context.environmentValues.isEnabled
    let fieldText = text.wrappedValue
    let effectiveStyle =
      context.environmentValues.textFieldStyle == .automatic
      ? TextFieldStyle.roundedBorder
      : context.environmentValues.textFieldStyle
    let chrome = styleEnvironment.controlChrome(
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
      label: label,
      showsLabel: showsLabel,
      style: effectiveStyle,
      chrome: chrome,
      placeholderStyle: styleEnvironment.theme.placeholder
    ).resolve(
      in: context.child(component: .named("SecureFieldBody"))
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("SecureField"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .edit,
        presentationRole: .textField
      )
    )
  }
}
