import SwiftTUICore

/// Toggles a boolean binding on or off.
public struct Toggle<Label: View>: PrimitiveView, ResolvableView {
  package var isOn: Binding<Bool>
  private var label: Label
  private let authoringScope: AuthoringContext?

  public init(
    isOn: Binding<Bool>,
    @ViewBuilder label: () -> Label
  ) {
    self.isOn = isOn
    self.label = label()
    authoringScope = currentAuthoringContext()
  }

  public init<S: StringProtocol>(
    _ title: S,
    isOn: Binding<Bool>
  ) where Label == Text {
    self.isOn = isOn
    label = Text(String(title))
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension Toggle {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused =
      context.environmentValues.focusedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed =
      context.environmentValues.pressedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let binding = isOn

    if isEnabled {
      let binding = isOn
      let intake = HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: authoringScope
      )
      intake.registerAction(identity: context.identity) {
        binding.wrappedValue.toggle()
        return true
      }
    }

    let configuration = ToggleStyleConfiguration(
      label: .init(authoringContext: authoringScope) { label },
      isOn: enabledStyleBinding(binding, isEnabled: isEnabled),
      isMixed: false,
      isEnabled: isEnabled,
      isFocused: isFocused,
      showsFocusEffect: showsFocusEffect,
      isPressed: isPressed,
      styleEnvironment: styleEnvironment
    )
    let child = context.environmentValues.toggleStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("ToggleBody"))
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Toggle"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .activate,
        accessibilityRole: .toggle
      )
    )
  }

}

/// Edits a single-line string binding using terminal keyboard input.
public struct TextField<Label: View>: PrimitiveView, ResolvableView {
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

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    return withDynamicPropertyUpdateScope(self, for: context) {
      [resolvedNode(in: context)]
    }
  }
}

extension TextField {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
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
      traits: .singleLine,
      authoringScope: authoringScope,
      in: context
    )
    let presentation = TextInputPresentation(
      value: synchronizedValue,
      traits: .singleLine,
      prompt: prompt?.content,
      isFocused: isFocused,
      cursorFollowsFocus: cursorFollowsFocus,
      width: nil
    )
    let fallbackPresentation = TextInputPresentation(
      value: synchronizedValue,
      traits: .singleLine,
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
      label: .init(authoringContext: authoringScope) { label },
      showsLabel: showsLabel,
      chrome: chrome,
      placeholderStyle: styleEnvironment.themeStyle(for: .placeholder),
      focusActive: isFocused && showsFocusEffect,
      styleEnvironment: styleEnvironment
    )
    let child = textFieldStyle.resolveBody(
      configuration: configuration,
      in: context.child(component: .named("TextFieldBody"))
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("TextField"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .edit,
        accessibilityRole: .textField
      ).merging(SemanticMetadata(accessibilityLabel: titleAccessibilityLabel))
    )
  }
}

/// Reveals or hides nested content behind an expansion control.
public struct DisclosureGroup<Label: View, Content: View>: PrimitiveView, ResolvableView {
  public var isExpanded: Binding<Bool>
  private var label: Label
  private var content: Content
  private let authoringScope: AuthoringContext?

  public init(
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    self.isExpanded = isExpanded
    self.label = label()
    self.content = content()
    authoringScope = currentAuthoringContext()
  }

  public init<S: StringProtocol>(
    _ title: S,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) where Label == Text {
    self.isExpanded = isExpanded
    label = Text(String(title))
    self.content = content()
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension DisclosureGroup {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused =
      context.environmentValues.focusedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed =
      context.environmentValues.pressedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let expanded = isExpanded.wrappedValue
    let binding = isExpanded

    if isEnabled {
      let binding = isExpanded
      let intake = HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: authoringScope
      )
      intake.registerAction(identity: context.identity) {
        binding.wrappedValue.toggle()
        return true
      }
    }

    let configuration = DisclosureGroupStyleConfiguration(
      label: .init(authoringContext: authoringScope) { label },
      content: .init(authoringContext: authoringScope) {
        if expanded { content }
      },
      isExpanded: enabledStyleBinding(binding, isEnabled: isEnabled),
      isEnabled: isEnabled,
      isFocused: isFocused,
      showsFocusEffect: showsFocusEffect,
      isPressed: isPressed,
      styleEnvironment: styleEnvironment
    )
    let child = context.environmentValues.disclosureGroupStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("DisclosureBody"))
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("DisclosureGroup"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .activate,
        accessibilityRole: .disclosureGroup
      )
    )
  }

}
