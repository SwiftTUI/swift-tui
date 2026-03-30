package import Core

/// Toggles a boolean binding on or off.
public struct Toggle: View, ResolvableView {
  public var isOn: Binding<Bool>
  private var labelViews: [AnyView]

  public init<Label: View>(
    isOn: Binding<Bool>,
    @ViewBuilder label: () -> Label
  ) {
    self.isOn = isOn
    labelViews = parallelBuilderChildren(from: label())
  }

  public init<S: StringProtocol>(
    _ title: S,
    isOn: Binding<Bool>
  ) {
    self.isOn = isOn
    labelViews = [AnyView(Text(String(title)))]
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
    let styleEnvironment = context.environmentValues.parallelStyleEnvironmentSnapshot
    let isFocused = context.environmentValues.parallelFocusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.parallelPressedIdentity == context.identity
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
      let dynamicPropertyScope = currentDynamicPropertyScope()
      context.localActionRegistry?.register(identity: context.identity) {
        withDynamicPropertyScope(dynamicPropertyScope) {
          binding.wrappedValue.toggle()
          return true
        }
      }
    }

    let child = toggleBody(
      isOn: isSelected,
      isFocused: isFocused,
      isPressed: isPressed,
      chrome: chrome
    ).resolve(
      in: context.child(component: "ToggleBody")
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Toggle"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: parallelFocusableControlMetadata(
        focusInteractions: .activate,
        presentationRole: .toggle
      )
    )
  }

  private func toggleBody(
    isOn: Bool,
    isFocused: Bool,
    isPressed: Bool,
    chrome: ControlChrome
  ) -> AnyView {
    let indicatorStyle =
      isOn
      ? chrome.borderStyle
      : AnyShapeStyle(.separator)
    let markerStyle =
      isFocused
      ? chrome.borderStyle
      : AnyShapeStyle(.background)

    let rowContent = AnyView(
      HStack(alignment: .center, spacing: 1) {
        if isFocused {
          Text("▌ ")
            .foregroundStyle(markerStyle)
        }
        Text(isOn ? "◉" : "○")
          .foregroundStyle(indicatorStyle)
        combinedView(from: labelViews, kindName: "ToggleLabel")
      }
      .foregroundStyle(chrome.foregroundStyle)
      .drawMetadata(.init(opacity: chrome.opacity))
    )

    let body =
      if isFocused || isPressed {
        AnyView(
          rowContent
            .background {
              Rectangle().fill(chrome.backgroundStyle)
            }
        )
      } else {
        rowContent
      }

    return body
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

  let dynamicPropertyScope = currentDynamicPropertyScope()
  context.localKeyHandlerRegistry?.register(identity: context.identity) { event in
    withDynamicPropertyScope(dynamicPropertyScope) {
      switch event {
      case .character(let character):
        var candidate = binding.wrappedValue
        candidate.append(character)
        binding.wrappedValue = candidate
        return true
      case .space:
        var candidate = binding.wrappedValue
        candidate.append(" ")
        binding.wrappedValue = candidate
        return true
      case .backspace:
        var candidate = binding.wrappedValue
        guard !candidate.isEmpty else {
          return false
        }
        candidate.removeLast()
        binding.wrappedValue = candidate
        return true
      default:
        return false
      }
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

@MainActor
package func textEntryFieldBody(
  displayText: String,
  isShowingPrompt: Bool,
  labelViews: [AnyView],
  style: TextFieldStyle,
  chrome: ControlChrome,
  placeholderStyle: AnyShapeStyle,
  chromePreset: ChromePreset
) -> AnyView {
  let textStyle =
    isShowingPrompt ? placeholderStyle : chrome.foregroundStyle
  let baseField = AnyView(
    Text(displayText)
      .fixedSize(horizontal: true, vertical: false)
      .foregroundStyle(textStyle)
      .drawMetadata(.init(opacity: chrome.opacity))
  )
  let stretchedField = AnyView(
    HStack(alignment: .center, spacing: 0) {
      baseField
      Spacer(minLength: 0)
    }
  )

  let fieldContent =
    switch style {
    case .plain:
      AnyView(baseField)
    case .roundedBorder, .automatic:
      AnyView(
        stretchedField
          .padding(.init(horizontal: 1, vertical: 1))
          .background {
            RoundedRectangle(cornerRadius: 1).parallelInteriorFill(chrome.backgroundStyle)
          }
          .overlay {
            RoundedRectangle(cornerRadius: 1).parallelStrokeBorder(
              chrome.borderStyle,
              backgroundStyle: chrome.borderBackgroundStyle
            )
          }
      )
    }

  let body =
    if labelViews.isEmpty {
      fieldContent
    } else {
      AnyView(
        VStack(alignment: .leading, spacing: 0) {
          combinedView(from: labelViews, kindName: "TextFieldLabel")
            .foregroundStyle(.terminalBorder(.accent))
          fieldContent
        }
      )
    }

  let protectedBody =
    switch style {
    case .roundedBorder, .automatic:
      AnyView(
        body.layoutMetadata(
          .init(
            minimumHeight: (labelViews.isEmpty ? 0 : 1) + 3
          )
        )
      )
    default:
      body
    }

  return protectedBody
}

public struct TextField: View, ResolvableView {
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

extension TextField {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.parallelStyleEnvironmentSnapshot
    let isFocused = context.environmentValues.parallelFocusedIdentity == context.identity
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
      masked: false
    )
    let child = textEntryFieldBody(
      displayText: entryText.displayText,
      isShowingPrompt: entryText.isShowingPrompt,
      labelViews: labelViews,
      style: effectiveStyle,
      chrome: chrome,
      placeholderStyle: styleEnvironment.theme.placeholder,
      chromePreset: styleEnvironment.chromePreset
    ).resolve(
      in: context.child(component: "TextFieldBody")
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("TextField"),
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

/// Reveals or hides nested content behind an expansion control.
public struct DisclosureGroup: View, ResolvableView {
  public var isExpanded: Binding<Bool>
  private var labelViews: [AnyView]
  private var contentViews: [AnyView]

  public init<Content: View, Label: View>(
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    self.isExpanded = isExpanded
    labelViews = parallelBuilderChildren(from: label())
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<S: StringProtocol, Content: View>(
    _ title: S,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.isExpanded = isExpanded
    labelViews = [AnyView(Text(String(title)))]
    contentViews = parallelBuilderChildren(from: content())
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
    let styleEnvironment = context.environmentValues.parallelStyleEnvironmentSnapshot
    let isFocused = context.environmentValues.parallelFocusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.parallelPressedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let expanded = isExpanded.wrappedValue
    let chrome = styleEnvironment.rowChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isPressed: isPressed
    )

    if isEnabled {
      let binding = isExpanded
      let dynamicPropertyScope = currentDynamicPropertyScope()
      context.localActionRegistry?.register(identity: context.identity) {
        withDynamicPropertyScope(dynamicPropertyScope) {
          binding.wrappedValue.toggle()
          return true
        }
      }
    }

    let child = disclosureBody(
      isExpanded: expanded,
      isFocused: isFocused,
      isPressed: isPressed,
      chrome: chrome
    ).resolve(
      in: context.child(component: "DisclosureBody")
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("DisclosureGroup"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: parallelFocusableControlMetadata(
        focusInteractions: .activate,
        presentationRole: .disclosureGroup
      )
    )
  }

  private func disclosureBody(
    isExpanded: Bool,
    isFocused: Bool,
    isPressed: Bool,
    chrome: ControlChrome
  ) -> AnyView {
    let indicatorStyle =
      isExpanded
      ? AnyShapeStyle(.tint)
      : AnyShapeStyle(.separator)
    let labelRow = AnyView(
      HStack(alignment: .center, spacing: 1) {
        if isFocused {
          Text("| ")
            .foregroundStyle(chrome.borderStyle)
        }
        Text(isExpanded ? "▾" : "▸")
          .foregroundStyle(indicatorStyle)
        combinedView(from: labelViews, kindName: "DisclosureLabel")
      }
      .foregroundStyle(chrome.foregroundStyle)
      .drawMetadata(.init(opacity: chrome.opacity))
    )
    let highlightedLabel =
      if isFocused || isPressed {
        AnyView(
          labelRow
            .background {
              Rectangle().fill(chrome.backgroundStyle)
            }
        )
      } else {
        labelRow
      }

    let body = AnyView(
      VStack(alignment: .leading, spacing: 0) {
        highlightedLabel
        if isExpanded {
          combinedView(from: contentViews, kindName: "DisclosureContent")
            .padding(.init(top: 0, leading: 1, bottom: 0, trailing: 0))
        }
      }
    )

    return body
  }
}
