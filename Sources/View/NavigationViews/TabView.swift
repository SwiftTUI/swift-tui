package import Core

/// Selects one declared tab and renders a terminal-native tab strip above the
/// active content.
public struct TabView<SelectionValue: Hashable, Content: View>: View, ResolvableView {
  public var selection: Binding<SelectionValue>
  private var content: Content
  private let authoringScope: AuthoringContext?

  public init(
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content
  ) {
    self.selection = selection
    self.content = content()
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

extension TabView {
  private struct TabOption: Sendable {
    var tag: SelectionTag
    var label: TabItemLabel
    var node: ResolvedNode?
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isEnabled = context.environmentValues.isEnabled
    let ownerNode = context.viewGraph?.nodeForIdentity(context.identity)
    let options = resolvedOptions(in: context.child(component: .named("TabOptions")))
    let selectedIndex =
      options.firstIndex { option in
        pickerSelectionMatches(option.tag, selection: selection.wrappedValue)
      }
      ?? options.indices.first
    let focusedIndex: Int? =
      if isFocused {
        resolvedFocusedTabIndex(
          storedIndex: storedFocusedTabIndex(in: ownerNode),
          selectedIndex: selectedIndex,
          optionCount: options.count
        )
      } else {
        nil
      }

    if isEnabled {
      let binding = selection
      let orderedTags = options.map(\.tag)
      let dynamicPropertyScope = currentAuthoringContext() ?? authoringScope
      context.localKeyHandlerRegistry?.register(
        identity: context.identity,
        keyPressHandler: {
          keyPress in
          guard !options.isEmpty else {
            return false
          }

          return withAuthoringContext(dynamicPropertyScope) {
            switch keyPress {
            case KeyPress(.arrowLeft, modifiers: []):
              moveStoredTabFocus(
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                optionCount: options.count,
                delta: -1
              )
              return true
            case KeyPress(.arrowRight, modifiers: []):
              moveStoredTabFocus(
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                optionCount: options.count,
                delta: 1
              )
              return true
            case KeyPress(.home, modifiers: []):
              setStoredFocusedTabIndex(0, in: ownerNode)
              return true
            case KeyPress(.end, modifiers: []):
              setStoredFocusedTabIndex(max(0, options.count - 1), in: ownerNode)
              return true
            case KeyPress(.arrowUp, modifiers: []), KeyPress(.arrowDown, modifiers: []):
              return true
            case KeyPress(.tab, modifiers: []), KeyPress(.tab, modifiers: .shift):
              setStoredFocusedTabIndex(nil, in: ownerNode)
              return false
            default:
              return false
            }
          }
        })
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          withAuthoringContext(dynamicPropertyScope) {
            activateBoundTabSelection(
              binding,
              focusedIndexOwnerNode: ownerNode,
              orderedTags: orderedTags,
              selectedIndex: selectedIndex
            )
          }
        },
        followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
      )

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
            setStoredFocusedTabIndex(index, in: ownerNode)
            return setBoundSelection(binding, to: options[index].tag)
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
        focusedIndex: focusedIndex,
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
        focusInteractions: .activate,
        presentationRole: .tabView
      )
    )
  }

  private func resolvedOptions(
    in context: ResolveContext
  ) -> [TabOption] {
    // Phase 1: walk declared children and peek metadata (tab label + tag)
    // off each without resolving. We capture a lazy `resolveOne` closure
    // per child so that only the active tab actually enters the resolve
    // pipeline — inactive tabs never call `beginEvaluation`, so their
    // `.onAppear` / `.task` handlers do not fire until the user first
    // selects them.
    var peekedEntries: [PeekedTabChildMetadata] = []
    var resolveClosures: [() -> ResolvedNode] = []
    var nextIndex = 0
    let childContext = context.child(component: .named("TabOptions"))
    enumerateDeclaredChildViews(
      content,
      in: childContext,
      kindName: "Tab",
      nextIndex: &nextIndex
    ) { child, childContext, resolveOne in
      peekedEntries.append(peekTabChildMetadata(from: child))
      if let declaration = child as? any TabChildDirectResolving {
        resolveClosures.append {
          declaration.resolveTabChild(in: childContext)
        }
      } else {
        resolveClosures.append(resolveOne)
      }
    }

    let selectedIndex =
      peekedEntries.firstIndex { entry in
        guard let tag = entry.tag else { return false }
        return pickerSelectionMatches(tag, selection: selection.wrappedValue)
      }
      ?? peekedEntries.indices.first { peekedEntries[$0].tag != nil }

    return peekedEntries.enumerated().compactMap { index, entry in
      guard let tag = entry.tag else {
        return nil
      }
      let isActive = (index == selectedIndex)
      let resolvedNodeIfActive = isActive ? resolveClosures[index]() : nil

      let label: TabItemLabel
      if let peekedLabel = entry.label {
        label = peekedLabel
      } else if let resolved = resolvedNodeIfActive,
        let derived = tabItemLabel(in: resolved)
      {
        label = derived
      } else if let resolved = resolvedNodeIfActive {
        let fallbackTitle = resolvedNodeLabelText(from: resolved)
        label = TabItemLabel(
          fallbackTitle.isEmpty ? "Tab \(index + 1)" : fallbackTitle
        )
      } else {
        label = TabItemLabel("Tab \(index + 1)")
      }

      return TabOption(
        tag: tag,
        label: label,
        node: resolvedNodeIfActive
      )
    }
  }

  @ViewBuilder
  private func tabBody(
    controlIdentity: Identity,
    options: [TabOption],
    selectedIndex: Int?,
    focusedIndex: Int?,
    isFocused: Bool,
    showsFocusEffect: Bool,
    styleEnvironment: StyleEnvironmentSnapshot,
    tabStyle: TabViewStyle
  ) -> some View {
    let activeIndex = selectedIndex ?? 0
    let activeTone: TerminalTone = .accent
    let focusActive = isFocused && showsFocusEffect

    let hasRule = tabStyle != .powerline
    let hasLiteralTabEdgeRow = tabStyle == .literalTabs
    let stripHeight =
      if hasLiteralTabEdgeRow {
        3
      } else if hasRule {
        2
      } else {
        1
      }
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        ForEach(options.indices, id: \.self) { index in
          let option = options[index]
          let isSelected = index == activeIndex
          let isTabFocused = focusActive && index == focusedIndex

          PointerRouteView(
            identity: tabItemIdentity(
              for: controlIdentity,
              index: index
            ),
            content: VStack(alignment: .leading, spacing: 0) {
              let trailingSeparatorStyle: PowerlineSeparatorStyle =
                if index == activeIndex {
                  .selectedTrailing
                } else if index + 1 == activeIndex {
                  .selectedLeading
                } else {
                  .plain
                }
              tabItemView(
                label: option.label.displayText,
                isSelected: isSelected,
                isFocused: isTabFocused,
                showsTrailingSeparator: index < options.count - 1,
                trailingSeparatorStyle: trailingSeparatorStyle,
                tone: activeTone,
                style: tabStyle,
                styleEnvironment: styleEnvironment
              )
              if hasRule {
                tabItemRuleSegment(
                  label: option.label.displayText,
                  isSelected: isSelected,
                  isFocused: isTabFocused,
                  tone: activeTone,
                  style: tabStyle,
                  styleEnvironment: styleEnvironment
                )
              }
              if hasLiteralTabEdgeRow {
                literalTabBottomSegment(
                  index: index,
                  label: option.label.displayText,
                  isSelected: isSelected,
                  tone: activeTone
                )
              }
            }
            .background {
              if isTabFocused {
                Rectangle()
                  .fill(AnyShapeStyle(.terminalSurface(activeTone)))
              }
            }
          )
        }
        Spacer(minLength: 0)
      }
      .frame(height: stripHeight, alignment: .leading)
      .background {
        if hasLiteralTabEdgeRow {
          VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
              .frame(height: stripHeight - 1)
            Divider(
              drawMetadata: .init(
                foregroundStyle: .semantic(.foreground)
              )
            )
            .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1, alignment: .leading)
          }
        }
      }
      if options.indices.contains(activeIndex), let activeNode = options[activeIndex].node {
        ResolvedContentView(node: activeNode)
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
    isFocused: Bool,
    showsTrailingSeparator: Bool,
    trailingSeparatorStyle: PowerlineSeparatorStyle,
    tone: TerminalTone,
    style: TabViewStyle,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> some View {
    switch style == .automatic ? .underline : style {
    case .automatic, .underline:
      underlineTabItem(
        label: label,
        isSelected: isSelected,
        isFocused: isFocused,
        tone: tone
      )
    case .literalTabs:
      literalTabItem(
        label: label,
        isSelected: isSelected,
        isFocused: isFocused,
        tone: tone
      )
    case .powerline:
      powerlineTabItem(
        label: label,
        isSelected: isSelected,
        isFocused: isFocused,
        showsTrailingSeparator: showsTrailingSeparator,
        trailingSeparatorStyle: trailingSeparatorStyle,
        tone: tone,
        styleEnvironment: styleEnvironment
      )
    }
  }

  // MARK: - Underline style (default)

  private func underlineTabItem(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    tone: TerminalTone
  ) -> some View {
    let foreground: AnyShapeStyle =
      if isSelected {
        AnyShapeStyle(.terminalAccent(tone))
      } else {
        .semantic(.foreground)
      }
    return Text("\(label) ")
      .lineLimit(1)
      .foregroundStyle(foreground)
      .drawMetadata(.init(opacity: 1.0))
  }

  @ViewBuilder
  private func tabItemRuleSegment(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    tone: TerminalTone,
    style: TabViewStyle,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> some View {
    let resolvedStyle = style == .automatic ? TabViewStyle.underline : style
    switch resolvedStyle {
    case .automatic, .underline:
      underlineRuleSegment(
        label: label,
        isSelected: isSelected,
        isFocused: isFocused,
        tone: tone
      )
    case .literalTabs:
      roundedRuleSegment(
        label: label,
        isSelected: isSelected,
        isFocused: isFocused,
        tone: tone
      )
    case .powerline:
      EmptyView()
    }
  }

  private func underlineRuleSegment(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    tone: TerminalTone
  ) -> some View {
    let width = tabLabelCellWidth(label)
    let glyph: Character =
      if isSelected && isFocused { "▄" } else if isSelected || isFocused { "▂" } else { "▁" }
    let foreground: AnyShapeStyle =
      if isSelected {
        AnyShapeStyle(.terminalAccent(tone))
      } else if isFocused {
        .semantic(.foreground)
      } else {
        .semantic(.separator)
      }
    let text =
      "\(String(repeating: glyph, count: width)) "
    return Text(text)
      .lineLimit(1)
      .foregroundStyle(foreground)
      .frame(height: 1, alignment: .leading)
  }

  // MARK: - Rounded style (unicode tab shapes)

  private func literalTabItem(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    tone: TerminalTone
  ) -> some View {
    let interiorWidth = tabLabelCellWidth(label) + 2
    let topText = "╭" + String(repeating: "─", count: interiorWidth) + "╮"
    let chromeForeground = AnyShapeStyle(.foreground)
    return Text(topText)
      .lineLimit(1)
      .foregroundStyle(chromeForeground)
      .drawMetadata(.init(opacity: 1.0))
  }

  private func roundedRuleSegment(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    tone: TerminalTone
  ) -> some View {
    let chromeForeground = AnyShapeStyle(.foreground)
    let labelForeground: AnyShapeStyle =
      if isSelected {
        AnyShapeStyle(.terminalAccent(tone))
      } else {
        .semantic(.foreground)
      }
    return HStack(alignment: .top, spacing: 0) {
      Text("│ ")
        .lineLimit(1)
        .foregroundStyle(chromeForeground)
        .drawMetadata(.init(opacity: 1.0))
      Text(label)
        .lineLimit(1)
        .foregroundStyle(labelForeground)
        .drawMetadata(.init(opacity: 1.0))
      Text(" │")
        .lineLimit(1)
        .foregroundStyle(chromeForeground)
        .drawMetadata(.init(opacity: 1.0))
    }
    .frame(height: 1, alignment: .leading)
  }

  private func literalTabBottomSegment(
    index: Int,
    label: String,
    isSelected: Bool,
    tone: TerminalTone
  ) -> some View {
    let interiorWidth = tabLabelCellWidth(label) + 2
    let inactiveLeadingGlyph = "┴"
    let chromeForeground = AnyShapeStyle(.foreground)
    let text =
      if isSelected {
        "┘" + String(repeating: " ", count: interiorWidth) + "└"
      } else {
        inactiveLeadingGlyph + String(repeating: "─", count: interiorWidth) + "┴"
      }
    return Text(text)
      .lineLimit(1)
      .foregroundStyle(chromeForeground)
      .drawMetadata(.init(opacity: 1.0))
      .frame(height: 1, alignment: .leading)
  }

  // MARK: - Powerline style (p10k-inspired)

  private func powerlineTabItem(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    showsTrailingSeparator: Bool,
    trailingSeparatorStyle: PowerlineSeparatorStyle,
    tone: TerminalTone,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> some View {
    let selectedBackgroundColor = powerlineSelectedBackgroundColor(
      tone: tone,
      styleEnvironment: styleEnvironment
    )
    let selectedBackgroundStyle = AnyShapeStyle(selectedBackgroundColor)
    let selectedForegroundStyle = AnyShapeStyle(
      contrastingForegroundColor(on: selectedBackgroundColor)
    )
    let foreground: AnyShapeStyle =
      if isSelected {
        selectedForegroundStyle
      } else {
        .semantic(.foreground)
      }
    let separatorGlyph = trailingSeparatorStyle.glyph
    let separatorForeground: AnyShapeStyle =
      trailingSeparatorStyle == .plain
      ? .semantic(.separator)
      : selectedBackgroundStyle
    return HStack(alignment: .top, spacing: 0) {
      Text("\(label) ")
        .lineLimit(1)
        .foregroundStyle(foreground)
        .background {
          if isSelected {
            Rectangle().fill(selectedBackgroundStyle)
          }
        }
        .drawMetadata(.init(opacity: 1.0))
      if showsTrailingSeparator {
        Text(separatorGlyph)
          .lineLimit(1)
          .foregroundStyle(separatorForeground)
          .drawMetadata(.init(opacity: trailingSeparatorStyle.opacity))
      }
    }
  }
}

private enum PowerlineSeparatorStyle {
  case plain
  case selectedLeading
  case selectedTrailing

  var glyph: String {
    switch self {
    case .plain:
      "╱"
    case .selectedLeading:
      "◢"
    case .selectedTrailing:
      "◤"
    }
  }

  var opacity: Double {
    switch self {
    case .plain:
      0.6
    case .selectedLeading, .selectedTrailing:
      1.0
    }
  }
}

private func powerlineSelectedBackgroundColor(
  tone: TerminalTone,
  styleEnvironment: StyleEnvironmentSnapshot
) -> Color {
  switch tone {
  case .accent:
    styleEnvironment.appearance.tintColor
  case .info:
    styleEnvironment.theme.color(for: .info)
  case .success:
    styleEnvironment.theme.color(for: .success)
  case .warning:
    styleEnvironment.theme.color(for: .warning)
  case .danger:
    styleEnvironment.theme.color(for: .danger)
  case .neutral:
    styleEnvironment.theme.color(for: .selection)
  }
}

private func contrastingForegroundColor(
  on backgroundColor: Color
) -> Color {
  let whiteContrast = Color.white.contrastRatio(to: backgroundColor)
  let blackContrast = Color.black.contrastRatio(to: backgroundColor)
  return whiteContrast >= blackContrast ? .white : .black
}

private func tabLabelCellWidth(
  _ label: String
) -> Int {
  layoutText(for: label, width: nil).size.width
}

@MainActor
private func resolvedFocusedTabIndex(
  storedIndex: Int?,
  selectedIndex: Int?,
  optionCount: Int
) -> Int? {
  guard optionCount > 0 else {
    return nil
  }
  if let storedIndex, (0..<optionCount).contains(storedIndex) {
    return storedIndex
  }
  if let selectedIndex, (0..<optionCount).contains(selectedIndex) {
    return selectedIndex
  }
  return 0
}

@MainActor
private func moveStoredTabFocus(
  ownerNode: Core.ViewNode?,
  selectedIndex: Int?,
  optionCount: Int,
  delta: Int
) {
  guard let direction = delta == 0 ? nil : delta.signum(), optionCount > 0 else {
    return
  }

  let currentIndex =
    resolvedFocusedTabIndex(
      storedIndex: storedFocusedTabIndex(in: ownerNode),
      selectedIndex: selectedIndex,
      optionCount: optionCount
    )
    ?? (direction > 0 ? -1 : optionCount)
  let nextIndex = min(
    max(currentIndex + direction, 0),
    optionCount - 1
  )
  setStoredFocusedTabIndex(nextIndex, in: ownerNode)
}

@MainActor
private func activateBoundTabSelection<SelectionValue: Hashable>(
  _ selectionBinding: Binding<SelectionValue>,
  focusedIndexOwnerNode: Core.ViewNode?,
  orderedTags: [SelectionTag],
  selectedIndex: Int?
) -> Bool {
  guard
    let index = resolvedFocusedTabIndex(
      storedIndex: storedFocusedTabIndex(in: focusedIndexOwnerNode),
      selectedIndex: selectedIndex,
      optionCount: orderedTags.count
    ),
    orderedTags.indices.contains(index)
  else {
    return false
  }
  setStoredFocusedTabIndex(index, in: focusedIndexOwnerNode)
  return setBoundSelection(selectionBinding, to: orderedTags[index])
}

private let tabFocusedIndexStateSlot = -4_000_001

@MainActor
private func storedFocusedTabIndex(
  in ownerNode: Core.ViewNode?
) -> Int? {
  ownerNode?.stateSlot(
    ordinal: tabFocusedIndexStateSlot,
    seed: nil as Int?
  ) ?? nil
}

@MainActor
private func setStoredFocusedTabIndex(
  _ index: Int?,
  in ownerNode: Core.ViewNode?
) {
  ownerNode?.setStateSlot(
    ordinal: tabFocusedIndexStateSlot,
    value: index
  )
}

private func tabItemIdentity(
  for controlIdentity: Identity,
  index: Int
) -> Identity {
  controlIdentity.child(.indexed("TabItem", index: index))
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

// MARK: - Metadata peeking

package struct PeekedTabChildMetadata {
  package var label: TabItemLabel?
  package var tag: SelectionTag?

  package init(label: TabItemLabel? = nil, tag: SelectionTag? = nil) {
    self.label = label
    self.tag = tag
  }
}

@MainActor
package protocol TabChildMetadataContributing {
  var tabChildMetadataContribution: PeekedTabChildMetadata { get }
  func withTabChildInnerContent<R>(_ body: (Any) -> R) -> R
}

@MainActor
package protocol TabChildDirectResolving: TabChildMetadataContributing {
  func resolveTabChild(in context: ResolveContext) -> ResolvedNode
}

@MainActor
package func peekTabChildMetadata(from view: Any) -> PeekedTabChildMetadata {
  var result = PeekedTabChildMetadata()
  var current: Any = view
  while let provider = current as? any TabChildMetadataContributing {
    let contribution = provider.tabChildMetadataContribution
    if let label = contribution.label, result.label == nil {
      result.label = label
    }
    if let tag = contribution.tag, result.tag == nil {
      result.tag = tag
    }
    current = provider.withTabChildInnerContent { $0 }
  }
  return result
}

/// Hosts a pre-resolved tab content subtree inside the `tabBody` view
/// hierarchy without collapsing its own identity into the captured
/// node.
///
/// If this view returned `[node]` directly, `normalizeResolvedElements`
/// would unwrap the single-element array and hand the captured
/// `ResolvedNode` straight back to the outer resolver.  That causes
/// `finishEvaluation` to set this view's ViewNode's `committed` to the
/// captured subtree's root (e.g. the ScrollView's resolved tree),
/// *including its stale per-node fields and identity*.  The
/// ScrollView's own ViewNode then becomes orphaned from the snapshot
/// walk: when a scroll event re-evaluates just the ScrollView via the
/// selective dirty plan, its updated `committed` never reaches the
/// root snapshot — `ResolvedContentView`'s stale `committed` copy is
/// used instead.  The visible symptom is a ScrollView whose scroll
/// offset stays frozen until some unrelated interaction forces a full
/// re-resolve of the tab body.
///
/// Wrapping the captured node as a **child** of an outer
/// `ResolvedContentView`-identity node keeps this view's identity and
/// committed snapshot distinct from the captured subtree's, so
/// `finishEvaluation` installs the captured subtree's root as a
/// child ViewNode under us.  The normal `snapshot()` walk then
/// recurses into that child ViewNode and picks up its current
/// committed state — including any per-frame re-evaluation.
private struct ResolvedContentView: View, ResolvableView {
  let node: ResolvedNode

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ResolvedContent"),
        children: [node],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}
