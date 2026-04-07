public import Core

/// Selects one child view from a tagged set and renders a terminal-native tab
/// strip above the active content.
public struct TabView<SelectionValue: Hashable, Content: View>: View, ResolvableView {
  public var selection: Binding<SelectionValue>
  private var content: Content

  public init(
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content
  ) {
    self.selection = selection
    self.content = content()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension TabView {
  private struct TabOption: Sendable {
    var tag: SelectionTag
    var label: TabItemLabel
    var node: ResolvedNode
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isEnabled = context.environmentValues.isEnabled
    let options = resolvedOptions(in: context.child(component: .named("TabOptions")))
    let selectedIndex =
      options.firstIndex { option in
        pickerSelectionMatches(option.tag, selection: selection.wrappedValue)
      }
      ?? options.indices.first

    if isEnabled {
      let binding = selection
      let dynamicPropertyScope = currentAuthoringContext()
      context.localKeyHandlerRegistry?.register(identity: context.identity) { event in
        let delta: Int?
        switch event {
        case .arrowLeft:
          delta = -1
        case .arrowRight:
          delta = 1
        default:
          delta = nil
        }

        guard let delta, !options.isEmpty else {
          return false
        }

        return withAuthoringContext(dynamicPropertyScope) {
          stepBoundSelection(
            binding,
            orderedTags: options.map(\.tag),
            delta: delta
          )
        }
      }

      for index in options.indices {
        let routeID = primaryRouteID(
          for: tabItemIdentity(
            for: context.identity,
            index: index
          )
        )
        context.localPointerHandlerRegistry?.register(routeID: routeID) { event in
          guard case .down(.primary) = event.kind else {
            return false
          }

          return withAuthoringContext(dynamicPropertyScope) {
            setBoundSelection(binding, to: options[index].tag)
          }
        }
      }
    }

    let tabStyle = context.environmentValues.tabViewStyle

    let child =
      tabBody(
        controlIdentity: context.identity,
        options: options,
        selectedIndex: selectedIndex,
        isFocused: isFocused,
        showsFocusEffect: showsFocusEffect,
        styleEnvironment: styleEnvironment,
        tabStyle: tabStyle
      ).resolve(
        in: context.child(component: .named("TabBody"))
      )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("TabView"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        isFocusable: true,
        focusInteractions: .edit,
        presentationRole: .tabView
      )
    )
  }

  private func resolvedOptions(
    in context: ResolveContext
  ) -> [TabOption] {
    resolveDeclaredChildren(
      content,
      in: context.child(component: .named("TabOptions")),
      kindName: "Tab"
    )
    .enumerated()
    .compactMap { index, node in
      guard let tag = tabSelectionTag(in: node) else {
        return nil
      }
      let fallbackTitle = resolvedNodeLabelText(from: node)
      let label =
        tabItemLabel(in: node)
        ?? TabItemLabel(fallbackTitle.isEmpty ? "Tab \(index + 1)" : fallbackTitle)
      return .init(tag: tag, label: label, node: node)
    }
  }

  @ViewBuilder
  private func tabBody(
    controlIdentity: Identity,
    options: [TabOption],
    selectedIndex: Int?,
    isFocused: Bool,
    showsFocusEffect: Bool,
    styleEnvironment: StyleEnvironmentSnapshot,
    tabStyle: TabViewStyle
  ) -> some View {
    let activeIndex = selectedIndex ?? 0
    let activeTone: TerminalTone = .accent
    let focusActive = isFocused && showsFocusEffect

    let hasRule = tabStyle != .powerline
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        ForEach(options.indices, id: \.self) { index in
          let option = options[index]
          let isSelected = index == activeIndex

          PointerRouteView(
            identity: tabItemIdentity(
              for: controlIdentity,
              index: index
            ),
            content: VStack(alignment: .leading, spacing: 0) {
              tabItemView(
                label: option.label.displayText,
                isSelected: isSelected,
                tone: activeTone,
                style: tabStyle,
                styleEnvironment: styleEnvironment
              )
              if hasRule {
                tabItemRuleSegment(
                  label: option.label.displayText,
                  isSelected: isSelected,
                  isFocused: focusActive,
                  style: tabStyle
                )
              }
            }
          )
        }
        Spacer(minLength: 0)
      }
      .frame(height: hasRule ? 2 : 1, alignment: .leading)
      .background {
        if focusActive {
          Rectangle()
            .fill(AnyShapeStyle(.terminalSurface(activeTone)))
        }
      }
      if options.indices.contains(activeIndex) {
        ResolvedContentView(node: options[activeIndex].node)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        EmptyView()
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func tabItemView(
    label: String,
    isSelected: Bool,
    tone: TerminalTone,
    style: TabViewStyle,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> some View {
    switch style == .automatic ? .underline : style {
    case .automatic, .underline:
      underlineTabItem(
        label: label,
        isSelected: isSelected,
        tone: tone
      )
    case .rounded:
      roundedTabItem(
        label: label,
        isSelected: isSelected,
        tone: tone
      )
    case .powerline:
      powerlineTabItem(
        label: label,
        isSelected: isSelected,
        tone: tone,
        styleEnvironment: styleEnvironment
      )
    }
  }

  // MARK: - Underline style (default)

  private func underlineTabItem(
    label: String,
    isSelected: Bool,
    tone: TerminalTone
  ) -> some View {
    let foreground: AnyShapeStyle =
      isSelected
      ? AnyShapeStyle(.terminalAccent(tone))
      : .semantic(.muted)
    return Text("\(label) ")
      .lineLimit(1)
      .foregroundStyle(foreground)
      .drawMetadata(.init(opacity: isSelected ? 1.0 : 0.4))
  }

  @ViewBuilder
  private func tabItemRuleSegment(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    style: TabViewStyle
  ) -> some View {
    let resolvedStyle = style == .automatic ? TabViewStyle.underline : style
    switch resolvedStyle {
    case .automatic, .underline:
      underlineRuleSegment(
        label: label,
        isSelected: isSelected,
        isFocused: isFocused
      )
    case .rounded:
      roundedRuleSegment(
        label: label,
        isSelected: isSelected,
        isFocused: isFocused
      )
    case .powerline:
      EmptyView()
    }
  }

  private func underlineRuleSegment(
    label: String,
    isSelected: Bool,
    isFocused: Bool
  ) -> some View {
    let width = tabLabelCellWidth(label)
    let glyph: Character =
      if isFocused { "▄" }
      else if isSelected { "━" }
      else { "─" }
    let text =
      "\(String(repeating: glyph, count: width)) "
    return Text(text)
      .lineLimit(1)
      .foregroundStyle(.separator)
      .frame(height: 1, alignment: .leading)
  }

  // MARK: - Rounded style (unicode tab shapes)

  private func roundedTabItem(
    label: String,
    isSelected: Bool,
    tone: TerminalTone
  ) -> some View {
    let prefix = isSelected ? "╭" : " "
    let suffix = isSelected ? "╮" : " "
    let foreground: AnyShapeStyle =
      isSelected
      ? AnyShapeStyle(.terminalAccent(tone))
      : .semantic(.muted)
    return Text("\(prefix)\(label)\(suffix)")
      .lineLimit(1)
      .foregroundStyle(foreground)
      .background {
        if isSelected {
          Rectangle().fill(AnyShapeStyle(.terminalTab(tone, isSelected: true)))
        }
      }
  }

  private func roundedRuleSegment(
    label: String,
    isSelected: Bool,
    isFocused: Bool
  ) -> some View {
    let width = tabLabelCellWidth(label)
    let text =
      if isFocused {
        (isSelected ? "╰" : " ") + String(repeating: "▄", count: width)
          + (isSelected ? "╯" : " ")
      } else if isSelected {
        "╰" + String(repeating: "─", count: width) + "╯"
      } else {
        " " + String(repeating: "─", count: width) + " "
      }
    return Text(text)
      .lineLimit(1)
      .foregroundStyle(.separator)
      .frame(height: 1, alignment: .leading)
  }

  // MARK: - Powerline style (p10k-inspired)

  private func powerlineTabItem(
    label: String,
    isSelected: Bool,
    tone: TerminalTone,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> some View {
    let foreground: AnyShapeStyle =
      isSelected
      ? styleEnvironment.resolvedStyle(for: .foreground)
      : .semantic(.muted)
    return Text("\(label) ")
      .lineLimit(1)
      .foregroundStyle(foreground)
      .background {
        if isSelected {
          Rectangle().fill(AnyShapeStyle(.terminalTab(tone, isSelected: true)))
        }
      }
      .drawMetadata(.init(opacity: isSelected ? 1.0 : 0.6))
  }
}

private func tabLabelCellWidth(
  _ label: String
) -> Int {
  layoutText(for: label, width: nil).size.width
}

extension View {
  public func tabItem(
    _ label: TabItemLabel
  ) -> some View {
    semanticMetadata(
      .init(tabItemLabel: label)
    )
  }

  public func tabItem<S: StringProtocol>(
    _ title: S
  ) -> some View {
    tabItem(TabItemLabel(title))
  }
}

private func tabItemIdentity(
  for controlIdentity: Identity,
  index: Int
) -> Identity {
  controlIdentity.child(.indexed("TabItem", index: index))
}

private func tabSelectionTag(
  in node: ResolvedNode
) -> SelectionTag? {
  if let tag = node.semanticMetadata.selectionTag {
    return tag
  }
  for child in node.children {
    if let match = tabSelectionTag(in: child) {
      return match
    }
  }
  return nil
}

private func tabItemLabel(
  in node: ResolvedNode
) -> TabItemLabel? {
  if let label = node.semanticMetadata.tabItemLabel {
    return label
  }
  for child in node.children {
    if let match = tabItemLabel(in: child) {
      return match
    }
  }
  return nil
}

private struct ResolvedContentView: View, ResolvableView {
  let node: ResolvedNode

  package func resolveElements(
    in _: ResolveContext
  ) -> [ResolvedNode] {
    [node]
  }
}
