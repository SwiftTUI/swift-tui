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
    var node: ResolvedNode?
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
    // Phase 1: walk declared children and peek metadata (tabItem + tag)
    // off each without resolving. We capture a lazy `resolveOne` closure
    // per child so that only the active tab actually enters the resolve
    // pipeline — inactive tabs never call `beginEvaluation`, so their
    // `.onAppear` / `.task` handlers do not fire until the user first
    // selects them (which is the moment a new ViewNode is created for
    // that child and `finishEvaluation` emits the structural appear).
    var peekedEntries: [PeekedTabChildMetadata] = []
    var resolveClosures: [() -> ResolvedNode] = []
    var nextIndex = 0
    // Match the old resolveDeclaredChildren(...) double-scoping so
    // per-tab ViewNode identities are preserved across this refactor.
    let childContext = context.child(component: .named("TabOptions"))
    enumerateDeclaredChildViews(
      content,
      in: childContext,
      kindName: "Tab",
      nextIndex: &nextIndex
    ) { child, _, resolveOne in
      peekedEntries.append(peekTabChildMetadata(from: child))
      resolveClosures.append(resolveOne)
    }

    // Phase 2: determine the active tab by matching tags.
    let selectedIndex =
      peekedEntries.firstIndex { entry in
        guard let tag = entry.tag else { return false }
        return pickerSelectionMatches(tag, selection: selection.wrappedValue)
      }
      ?? peekedEntries.indices.first { peekedEntries[$0].tag != nil }

    // Phase 3: resolve ONLY the active tab. Inactive tabs return a
    // TabOption with `node: nil` — they contribute only a label +
    // selection tag to the tab strip, and nothing to the committed
    // ViewNode tree.
    return peekedEntries.enumerated().compactMap { index, entry in
      guard let tag = entry.tag else {
        return nil
      }
      let isActive = (index == selectedIndex)
      let resolvedNodeIfActive = isActive ? resolveClosures[index]() : nil

      // Prefer the statically peeked label; fall back to introspecting
      // the active resolved tree (for composed content that exposes its
      // label lazily); otherwise default to "Tab N".
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
                  tone: activeTone,
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
    tone: TerminalTone,
    style: TabViewStyle
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
    case .rounded:
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
      isSelected
      ? AnyShapeStyle(.terminalAccent(tone))
      : .semantic(.separator)
    let text =
      "\(String(repeating: glyph, count: width)) "
    return Text(text)
      .lineLimit(1)
      .foregroundStyle(foreground)
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
    isFocused: Bool,
    tone: TerminalTone
  ) -> some View {
    let width = tabLabelCellWidth(label)
    let glyph: Character =
      if isSelected && isFocused { "▄" } else if isSelected || isFocused { "▂" } else { "▁" }
    let text =
      if isSelected {
        "╰" + String(repeating: glyph, count: width) + "╯"
      } else {
        " " + String(repeating: glyph, count: width) + " "
      }
    let foreground: AnyShapeStyle =
      isSelected
      ? AnyShapeStyle(.terminalAccent(tone))
      : .semantic(.separator)
    return Text(text)
      .lineLimit(1)
      .foregroundStyle(foreground)
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

// MARK: - Metadata peeking

/// Metadata peeled statically off a declared TabView child without
/// triggering a resolve pass. Tab children typically wrap their body in
/// `.tabItem(...)` and `.tag(...)` modifiers — both of which are
/// metadata-only wrappers that can be inspected structurally.
package struct PeekedTabChildMetadata {
  package var label: TabItemLabel?
  package var tag: SelectionTag?

  package init(label: TabItemLabel? = nil, tag: SelectionTag? = nil) {
    self.label = label
    self.tag = tag
  }
}

/// A view wrapper whose body does not need to be resolved in order to
/// extract its tab metadata contribution. Conforming types carry their
/// metadata on the wrapper struct itself and expose their inner content
/// so the walker can continue peeling modifier layers.
@MainActor
package protocol TabChildMetadataContributing {
  /// The metadata contributed by this single wrapper layer.
  var tabChildMetadataContribution: PeekedTabChildMetadata { get }
  /// Forwards the inner content to `body` so the walker can continue
  /// peeling subsequent metadata wrappers without resolving them.
  func withTabChildInnerContent<R>(_ body: (Any) -> R) -> R
}

/// Recursively peels metadata-only modifier layers off `view`, returning
/// the accumulated `TabItemLabel` + `SelectionTag`. Stops at the first
/// view that does not conform to `TabChildMetadataContributing`, which
/// means any non-metadata wrapper (state, gestures, layout) on an
/// inactive tab is NEVER touched — its body is never read.
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
