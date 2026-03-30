package import Core

/// A focusable multiline text editor that accepts terminal keyboard input.
public struct TextEditor: View, ResolvableView {
  public var text: Binding<String>
  @State private var scrollPosition = ScrollPosition.zero

  public init(text: Binding<String>) {
    self.text = text
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
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
    let fieldText = text.wrappedValue
    let chrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )

    registerMultilineTextEntryBinding(
      text,
      scrollPosition: $scrollPosition,
      in: context
    )

    let entryText = textEntryDisplayText(
      text: fieldText,
      promptText: nil,
      isActiveNavigation: isFocused,
      masked: false
    )

    let child = textEditorBody(
      displayText: entryText.displayText,
      chrome: chrome,
      scrollPosition: $scrollPosition
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
        presentationRole: .textEditor
      )
    )
  }
}
