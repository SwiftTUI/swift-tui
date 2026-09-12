import SwiftTUICore

/// Edits a string binding using keyboard input while masking the rendered value.
public struct SecureField<Label: View>: PrimitiveView, IterativeResolvableView {
  package var text: Binding<String>
  package var prompt: Text?
  @State private var textInputValue = TextInputValue()
  private var label: Label
  private var showsLabel: Bool
  private var titleAccessibilityLabel: String?
  private let authoringScope: AuthoringContext?

  public init<S: StringProtocol>(
    _ title: S,
    text: Binding<String>
  ) where Label == EmptyView {
    self.text = text
    let titleText = String(title)
    // SwiftUI treats the title as the field's label: it names the control
    // for accessibility and doubles as the placeholder while the field is
    // empty. Keep both roles.
    prompt = Text(titleText)
    titleAccessibilityLabel = titleText
    label = EmptyView()
    showsLabel = false
    authoringScope = currentAuthoringContext()
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
    authoringScope = currentAuthoringContext()
  }

  package func makeResolveWork(
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return withDynamicPropertyUpdateScope(self, for: context) {
      resolvedNode(in: context).map { [$0] }
    }
  }
}

extension SecureField {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused =
      context.environmentValues.focusedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isEnabled = context.environmentValues.isEnabled
    let textFieldStyle = context.environmentValues.textFieldStyle
    let cursorFollowsFocus = context.environmentValues.cursorFollowsFocus
    let chrome = textInputChrome(
      styleEnvironment: styleEnvironment,
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    let synchronizedValue = textInputValue.synchronized(with: text.wrappedValue)

    registerTextInputBinding(
      text,
      value: $textInputValue,
      traits: .secureField,
      authoringScope: authoringScope,
      in: context
    )
    let presentation = TextInputPresentation(
      value: synchronizedValue,
      traits: .secureField,
      prompt: prompt?.content,
      isFocused: isFocused,
      cursorFollowsFocus: cursorFollowsFocus,
      width: nil
    )
    let fallbackPresentation = TextInputPresentation(
      value: synchronizedValue,
      traits: .secureField,
      prompt: prompt?.content,
      isFocused: isFocused,
      cursorFollowsFocus: false,
      width: nil
    )
    let configuration = TextFieldStyleConfiguration(
      displayText: fallbackPresentation.displayText,
      fieldContent: .init(
        displayText: presentation.displayText,
        displayRuns: presentation.displayRuns,
        ownerIdentity: context.identity,
        caretAnchor: presentation.caretAnchor
      ),
      isShowingPrompt: presentation.isShowingPrompt,
      label: .init(authoringContext: authoringScope) { label.authoredAccessibilityLabel() },
      showsLabel: showsLabel,
      chrome: chrome,
      placeholderStyle: styleEnvironment.themeStyle(for: .placeholder),
      isEnabled: isEnabled,
      isFocused: isFocused,
      showsFocusEffect: showsFocusEffect,
      styleEnvironment: styleEnvironment
    )
    return textFieldStyle.resolveBody(
      configuration: configuration,
      in: context.child(component: .named("SecureFieldBody"))
    ).map { child in

      return ResolvedNode(
        identity: context.identity,
        kind: .view("SecureField"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        semanticMetadata: focusableControlMetadata(
          focusInteractions: .edit,
          accessibilityRole: .secureField
        ).namingControl(with: label).merging(
          SemanticMetadata(accessibilityLabel: titleAccessibilityLabel))
      )

    }
  }
}
