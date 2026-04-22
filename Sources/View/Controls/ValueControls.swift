package import Core

/// Toggles a boolean binding on or off.
public struct Toggle<Label: View>: View, ResolvableView {
  public var isOn: Binding<Bool>
  private var label: Label

  public init(
    isOn: Binding<Bool>,
    @ViewBuilder label: () -> Label
  ) {
    self.isOn = isOn
    self.label = label()
  }

  public init<S: StringProtocol>(
    _ title: S,
    isOn: Binding<Bool>
  ) where Label == Text {
    self.isOn = isOn
    label = Text(String(title))
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
      let dynamicPropertyScope = currentAuthoringContext()
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          withAuthoringContext(dynamicPropertyScope) {
            binding.wrappedValue.toggle()
            return true
          }
        },
        followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
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
        presentationRole: .toggle
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

/// Edits a string binding using keyboard input.
@MainActor
package func registerTextEntryBinding(
  _ binding: Binding<String>,
  in context: ResolveContext
) {
  guard context.environmentValues.isEnabled else {
    return
  }

  let dynamicPropertyScope = currentAuthoringContext()
  context.localKeyHandlerRegistry?.register(identity: context.identity) { event in
    withAuthoringContext(dynamicPropertyScope) {
      mutateTextEntryBinding(
        binding,
        event: event,
        allowsNewlines: false,
        scrollPosition: nil
      )
    }
  }
}

package func textEntryDisplayText(
  text: String,
  promptText: String?,
  isActiveNavigation: Bool,
  masked: Bool = false
) -> (displayText: String, isShowingPrompt: Bool) {
  let visibleText =
    masked
    ? String(repeating: "•", count: text.count)
    : text

  let displayText =
    if text.isEmpty {
      isActiveNavigation ? "_" : (promptText ?? "")
    } else if isActiveNavigation {
      "\(visibleText)_"
    } else {
      visibleText
    }

  return (
    displayText: displayText,
    isShowingPrompt: text.isEmpty && !isActiveNavigation && promptText != nil
  )
}

public struct TextField<Label: View>: View, ResolvableView {
  public var text: Binding<String>
  public var prompt: Text?
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
    [resolvedNode(in: context)]
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
    let fieldText = text.wrappedValue
    let textFieldStyle = context.environmentValues.textFieldStyle
    let chrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )

    registerTextEntryBinding(text, in: context)
    let entryText = textEntryDisplayText(
      text: fieldText,
      promptText: prompt?.content,
      isActiveNavigation: isFocused,
      masked: false
    )
    let configuration = TextFieldStyleConfiguration(
      displayText: entryText.displayText,
      isShowingPrompt: entryText.isShowingPrompt,
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
        presentationRole: .textField
      )
    )
  }
}

/// Reveals or hides nested content behind an expansion control.
public struct DisclosureGroup<Label: View, Content: View>: View, ResolvableView {
  public var isExpanded: Binding<Bool>
  private var label: Label
  private var content: Content

  public init(
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    self.isExpanded = isExpanded
    self.label = label()
    self.content = content()
  }

  public init<S: StringProtocol>(
    _ title: S,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) where Label == Text {
    self.isExpanded = isExpanded
    label = Text(String(title))
    self.content = content()
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
      let dynamicPropertyScope = currentAuthoringContext()
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          withAuthoringContext(dynamicPropertyScope) {
            binding.wrappedValue.toggle()
            return true
          }
        },
        followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
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
        presentationRole: .disclosureGroup
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
