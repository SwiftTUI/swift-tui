package import SwiftTUICore

/// A focusable multiline text editor that accepts terminal keyboard input.
public struct TextEditor: View, ResolvableView {
  public var text: Binding<String>
  @State private var scrollPosition = ScrollPosition.zero
  @State private var textInputValue = TextInputValue()
  private let authoringScope: AuthoringContext?

  public init(text: Binding<String>) {
    self.text = text
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let dynamicPropertyScope = dynamicPropertyAuthoringContext(for: context)
    return withAuthoringContext(dynamicPropertyScope) {
      [resolvedNode(in: context)]
    }
  }
}

extension TextEditor {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isEnabled = context.environmentValues.isEnabled
    let chrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    let synchronizedValue = textInputValue.synchronized(with: text.wrappedValue)

    registerTextInputBinding(
      text,
      value: $textInputValue,
      traits: .multiline,
      layout: { value in
        TextInputPresentation(
          value: value,
          traits: .multiline,
          prompt: nil,
          isFocused: isFocused,
          cursorFollowsFocus: false,
          width: nil
        ).layoutMap
      },
      authoringContext: currentImperativeAuthoringContextSnapshot()
        ?? ImperativeAuthoringContextSnapshot(authoringScope),
      in: context
    )

    let presentation = TextInputPresentation(
      value: synchronizedValue,
      traits: .multiline,
      prompt: nil,
      isFocused: isFocused,
      cursorFollowsFocus: false,
      width: nil
    )

    let child = textEditorBody(
      displayText: presentation.displayText,
      chrome: chrome,
      scrollPosition: $scrollPosition,
      focusActive: isFocused && showsFocusEffect
    ).resolve(
      in: context.child(component: .named("TextEditorBody"))
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("TextEditor"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .edit,
        accessibilityRole: .textEditor
      )
    )
  }
}
