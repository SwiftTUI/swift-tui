package import SwiftTUICore

/// Toggles a boolean binding on or off.
public struct Toggle<Label: View>: View, ResolvableView {
  public var isOn: Binding<Bool>
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
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.pressedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let isSelected = isOn.wrappedValue
    let chrome = styleEnvironment.rowChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed,
      isSelected: false
    )

    if isEnabled {
      let binding = isOn
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          [
            authoringContext =
              currentImperativeAuthoringContextSnapshot()
              ?? ImperativeAuthoringContextSnapshot(authoringScope)
          ] in
          withImperativeAuthoringContext(authoringContext) {
            binding.wrappedValue.toggle()
            return true
          }
        },
        followUpInvalidationIdentity: (currentImperativeAuthoringContextSnapshot()
          ?? ImperativeAuthoringContextSnapshot(authoringScope))?.viewIdentity
      )
    }

    let child = toggleBody(
      isOn: isSelected,
      isFocused: isFocused,
      isPressed: isPressed,
      chrome: chrome
    ).resolve(
      in: context.child(component: .named("ToggleBody"))
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

  @ViewBuilder
  private func toggleBody(
    isOn: Bool,
    isFocused: Bool,
    isPressed: Bool,
    chrome: ControlChrome
  ) -> some View {
    let indicatorStyle =
      isOn
      ? chrome.borderStyle
      : AnyShapeStyle(.separator)
    let rowContent = controlFocusRow(
      showsRail: isFocused,
      railStyle: chrome.borderStyle,
      isHighlighted: isFocused || isPressed,
      backgroundStyle: chrome.backgroundStyle,
      reservesRailSpaceWhenHidden: true
    ) {
      Text(isOn ? "◉" : "○")
        .foregroundStyle(indicatorStyle)
      label
    }
    .foregroundStyle(chrome.foregroundStyle)
    .drawMetadata(.init(opacity: chrome.opacity))
    rowContent
  }
}

public struct TextField<Label: View>: View, ResolvableView {
  public var text: Binding<String>
  public var prompt: Text?
  @State private var textInputValue = TextInputValue()
  private var label: Label
  private var showsLabel: Bool
  private let authoringScope: AuthoringContext?

  public init<S: StringProtocol>(
    _ title: S,
    text: Binding<String>
  ) where Label == EmptyView {
    self.text = text
    prompt = Text(String(title))
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
    let dynamicPropertyScope = dynamicPropertyAuthoringContext(for: context)
    return withAuthoringContext(dynamicPropertyScope) {
      [resolvedNode(in: context)]
    }
  }
}

extension TextField {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
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
      authoringContext: currentImperativeAuthoringContextSnapshot()
        ?? ImperativeAuthoringContextSnapshot(authoringScope),
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
      )
    )
  }
}

/// Reveals or hides nested content behind an expansion control.
public struct DisclosureGroup<Label: View, Content: View>: View, ResolvableView {
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
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.pressedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let expanded = isExpanded.wrappedValue
    let chrome = styleEnvironment.rowChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed
    )

    if isEnabled {
      let binding = isExpanded
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          [
            authoringContext =
              currentImperativeAuthoringContextSnapshot()
              ?? ImperativeAuthoringContextSnapshot(authoringScope)
          ] in
          withImperativeAuthoringContext(authoringContext) {
            binding.wrappedValue.toggle()
            return true
          }
        },
        followUpInvalidationIdentity: (currentImperativeAuthoringContextSnapshot()
          ?? ImperativeAuthoringContextSnapshot(authoringScope))?.viewIdentity
      )
    }

    let child = disclosureBody(
      isExpanded: expanded,
      isFocused: isFocused,
      isPressed: isPressed,
      chrome: chrome
    ).resolve(
      in: context.child(component: .named("DisclosureBody"))
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

  @ViewBuilder
  private func disclosureBody(
    isExpanded: Bool,
    isFocused: Bool,
    isPressed: Bool,
    chrome: ControlChrome
  ) -> some View {
    let indicatorStyle =
      isExpanded
      ? AnyShapeStyle(.tint)
      : AnyShapeStyle(.separator)
    let labelRow = controlFocusRow(
      showsRail: isFocused,
      railStyle: chrome.borderStyle,
      isHighlighted: isFocused || isPressed,
      backgroundStyle: chrome.backgroundStyle,
      reservesRailSpaceWhenHidden: true
    ) {
      Text(isExpanded ? "▾" : "▸")
        .foregroundStyle(indicatorStyle)
      label
    }
    .foregroundStyle(chrome.foregroundStyle)
    .drawMetadata(.init(opacity: chrome.opacity))
    VStack(alignment: .leading, spacing: 0) {
      labelRow
      if isExpanded {
        content
          .padding(.init(top: 0, leading: 1, bottom: 0, trailing: 0))
      }
    }
  }
}
