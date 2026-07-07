package import SwiftTUICore

/// A focusable multiline text editor that accepts terminal keyboard input.
public struct TextEditor: PrimitiveView, ResolvableView {
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
    let isFocused = context.environmentValues.focusedIdentity(comparedAgainst: [context.identity]) == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isEnabled = context.environmentValues.isEnabled
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
      traits: .multiline,
      layout: { value in
        TextInputPresentation(
          value: value,
          traits: .multiline,
          prompt: nil,
          isFocused: isFocused,
          cursorFollowsFocus: cursorFollowsFocus,
          width: nil
        ).layoutMap
      },
      authoringScope: authoringScope,
      in: context
    )

    let presentation = TextInputPresentation(
      value: synchronizedValue,
      traits: .multiline,
      prompt: nil,
      isFocused: isFocused,
      cursorFollowsFocus: cursorFollowsFocus,
      width: nil
    )

    let child = textEditorBody(
      displayText: presentation.displayText,
      displayRuns: presentation.displayRuns,
      ownerIdentity: context.identity,
      caretAnchor: presentation.caretAnchor,
      chrome: chrome,
      scrollPosition: $scrollPosition,
      focusActive: isFocused && showsFocusEffect
    ).resolve(
      in: context.child(component: .named("TextEditorBody"))
    )

    var metadata = focusableControlMetadata(
      focusInteractions: .edit,
      accessibilityRole: .textEditor
    )
    // The editor is ONE focus stop. Its body embeds a ScrollView, whose content
    // (and transient scroll indicator) would otherwise emit their own top-level
    // focus regions — putting the editor's internals on the Tab ring. Seal the
    // descendants: the editor's own region stays, wheel scrolling still routes
    // through the scroll role, and caret-driven scrolling uses the editor's own
    // scroll-position binding, none of which need descendant focus regions.
    metadata.sealsFocusDescendants = true
    return ResolvedNode(
      identity: context.identity,
      kind: .view("TextEditor"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: metadata
    )
  }
}
