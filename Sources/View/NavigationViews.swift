public import Core

/// Selects one child view from a tagged set and renders a terminal-native tab
/// strip above the active content.
public struct TabView<SelectionValue: Hashable>: View, ResolvableView {
  public var selection: Binding<SelectionValue>
  private var contentViews: [AnyView]

  public init<Content: View>(
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content
  ) {
    self.selection = selection
    contentViews = declaredBuilderChildren(from: content())
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
      let dynamicPropertyScope = currentDynamicPropertyScope()
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

        return withDynamicPropertyScope(dynamicPropertyScope) {
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

          return withDynamicPropertyScope(dynamicPropertyScope) {
            setBoundSelection(binding, to: options[index].tag)
          }
        }
      }
    }

    let child =
      tabBody(
        controlIdentity: context.identity,
        options: options,
        selectedIndex: selectedIndex,
        isFocused: isFocused,
        showsFocusEffect: showsFocusEffect,
        styleEnvironment: styleEnvironment
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
    contentViews.enumerated().compactMap { index, view in
      let node = view.resolve(
        in: context.child(component: .indexed("Tab", index: index))
      )
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

  private func tabBody(
    controlIdentity: Identity,
    options: [TabOption],
    selectedIndex: Int?,
    isFocused: Bool,
    showsFocusEffect: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> AnyView {
    let activeIndex = selectedIndex ?? 0
    let activeTone: TerminalTone = .accent

    let tabStrip = AnyView(
      HStack(alignment: .center, spacing: 1) {
        ForEach(options.indices, id: \.self) { index in
          let option = options[index]
          let isSelected = index == activeIndex
          let isActiveNavigation = isFocused && showsFocusEffect && isSelected
          let tabChrome = styleEnvironment.rowChrome(
            isEnabled: true,
            isFocused: isActiveNavigation,
            isSelected: isSelected
          )
          let tabLabel = Text(
            isSelected ? "[\(option.label.displayText)]" : option.label.displayText
          )
          .lineLimit(1)
          .foregroundStyle(
            isSelected
              ? tabChrome.foregroundStyle
              : styleEnvironment.theme.foreground
          )
          .padding(.init(horizontal: 1, vertical: 0))
          .background {
            if isSelected || isActiveNavigation {
              Rectangle().fill(
                isSelected
                  ? AnyShapeStyle(.terminalTab(activeTone, isSelected: true))
                  : tabChrome.backgroundStyle
              )
            }
          }
          .drawMetadata(.init(opacity: tabChrome.opacity))

          PointerRouteView(
            identity: tabItemIdentity(
              for: controlIdentity,
              index: index
            ),
            content: AnyView(tabLabel)
          )
        }
        Spacer(minLength: 0)
      }
      .frame(height: 1, alignment: .leading)
    )

    let content =
      if options.indices.contains(activeIndex) {
        AnyView(
          options[activeIndex].node.erasedToAnyView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
      } else {
        AnyView(
          EmptyView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
      }

    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        tabStrip
        Divider()
        content
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    )
  }
}

/// Composes a sidebar, optional content pane, and detail pane using a
/// terminal-native split layout.
public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View,
  ResolvableView
{
  private var sidebarView: AnyView
  private var contentView: AnyView?
  private var detailView: AnyView

  public init(
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder detail: () -> Detail
  ) where Content == EmptyView {
    sidebarView = AnyView(sidebar())
    contentView = nil
    detailView = AnyView(detail())
  }

  public init(
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder content: () -> Content,
    @ViewBuilder detail: () -> Detail
  ) {
    sidebarView = AnyView(sidebar())
    contentView = AnyView(content())
    detailView = AnyView(detail())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    composedView().resolveElements(in: context)
  }

  private func composedView() -> AnyView {
    AnyView(
      HStack(alignment: .top, spacing: 0) {
        sidebarView
          .frame(maxHeight: .infinity, alignment: .topLeading)
          .clipped()
        Divider()

        if let contentView {
          contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
          Divider()
        }

        detailView
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .clipped()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    )
  }
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

extension ResolvedNode {
  @MainActor
  fileprivate func erasedToAnyView() -> AnyView {
    AnyView(ResolvedContentView(node: self))
  }
}

private struct ResolvedContentView: View, ResolvableView {
  let node: ResolvedNode

  package func resolveElements(
    in _: ResolveContext
  ) -> [ResolvedNode] {
    [node]
  }
}
