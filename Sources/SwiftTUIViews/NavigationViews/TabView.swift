package import SwiftTUICore

/// Selects one declared tab and renders a terminal-native tab strip above the
/// active content.
public struct TabView<SelectionValue: Hashable, Content: View>: PrimitiveView, ResolvableView {
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
    var contentPayload: DeferredViewPayload?
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
    let tabStyle = context.environmentValues.tabViewStyle
    let styleConfiguration = TabViewStyleConfiguration(
      options: options.map { .init(label: $0.label) },
      selectedIndex: selectedIndex,
      focusedIndex: focusedIndex,
      isFocused: isFocused,
      showsFocusEffect: showsFocusEffect,
      styleEnvironment: styleEnvironment,
      availableWidth: tabViewAvailableWidth(in: context),
      isOverflowMenuExpanded: storedTabOverflowMenuExpanded(in: ownerNode)
    )
    let stylePresentation = tabStyle.presentation(for: styleConfiguration)
    let activeContentPayload =
      selectedIndex.flatMap { index in
        options.indices.contains(index) ? options[index].contentPayload : nil
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
              setStoredTabOverflowMenuExpanded(false, in: ownerNode)
              moveStoredTabFocus(
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                optionCount: options.count,
                delta: -1
              )
              return true
            case KeyPress(.arrowRight, modifiers: []):
              setStoredTabOverflowMenuExpanded(false, in: ownerNode)
              moveStoredTabFocus(
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                optionCount: options.count,
                delta: 1
              )
              return true
            case KeyPress(.home, modifiers: []):
              setStoredTabOverflowMenuExpanded(false, in: ownerNode)
              setStoredFocusedTabIndex(0, in: ownerNode)
              return true
            case KeyPress(.end, modifiers: []):
              setStoredTabOverflowMenuExpanded(false, in: ownerNode)
              setStoredFocusedTabIndex(max(0, options.count - 1), in: ownerNode)
              return true
            case KeyPress(.escape, modifiers: [])
            where storedTabOverflowMenuExpanded(in: ownerNode):
              setStoredTabOverflowMenuExpanded(false, in: ownerNode)
              return true
            case KeyPress(.arrowUp, modifiers: []), KeyPress(.arrowDown, modifiers: []):
              return true
            case KeyPress(.tab, modifiers: []), KeyPress(.tab, modifiers: .shift):
              setStoredTabOverflowMenuExpanded(false, in: ownerNode)
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
            setStoredTabOverflowMenuExpanded(false, in: ownerNode)
            return activateBoundTabSelection(
              binding,
              focusedIndexOwnerNode: ownerNode,
              orderedTags: orderedTags,
              selectedIndex: selectedIndex
            )
          }
        },
        followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
      )

      for index in stylePresentation.visibleOptionIndices {
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
            setStoredTabOverflowMenuExpanded(false, in: ownerNode)
            setStoredFocusedTabIndex(index, in: ownerNode)
            return setBoundSelection(binding, to: options[index].tag)
          }
        }
      }

      if let overflowPresentation = stylePresentation.overflowMenu {
        let triggerRouteID = primaryRouteID(
          for: tabOverflowTriggerIdentity(for: context.identity)
        )
        context.localPointerHandlerRegistry?.register(routeID: triggerRouteID) { event in
          guard case .down(.primary) = event.kind else {
            return false
          }

          return withAuthoringContext(dynamicPropertyScope) {
            let nextExpanded = !storedTabOverflowMenuExpanded(in: ownerNode)
            setStoredTabOverflowMenuExpanded(nextExpanded, in: ownerNode)
            if nextExpanded, let focusIndex = overflowPresentation.preferredOverflowFocusIndex {
              setStoredFocusedTabIndex(focusIndex, in: ownerNode)
            }
            return true
          }
        }

        for index in overflowPresentation.overflowIndices {
          let routeID = primaryRouteID(
            for: tabOverflowItemIdentity(
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
              setStoredTabOverflowMenuExpanded(false, in: ownerNode)
              return setBoundSelection(binding, to: options[index].tag)
            }
          }
        }
      }
    }

    let child = tabStyle.resolveBody(
      configuration: styleConfiguration,
      presentation: stylePresentation,
      controlIdentity: context.identity,
      activeContentIndex: selectedIndex,
      activeContent: activeContentPayload,
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
        accessibilityRole: .tabView
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
    let declaredContentPayloads = deferredDeclaredBuilderChildren(from: content)
    var contentPayloads: [DeferredViewPayload?] = []
    var nextIndex = 0
    let childContext = context.child(component: .named("TabOptions"))
    enumerateDeclaredChildViews(
      content,
      in: childContext,
      kindName: "Tab",
      nextIndex: &nextIndex
    ) { child, childContext, resolveOne in
      peekedEntries.append(peekTabChildMetadata(from: child))
      let payloadIndex = contentPayloads.count
      let contentPayload =
        declaredContentPayloads.indices.contains(payloadIndex)
        ? declaredContentPayloads[payloadIndex]
        : nil
      contentPayloads.append(contentPayload)
      if let declaration = child as? any TabDeclarationView {
        resolveClosures.append {
          declaration.resolveTabDeclarationContent(in: childContext)
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

      let label: TabItemLabel
      if let peekedLabel = entry.label {
        label = peekedLabel
      } else if isActive {
        let resolved = resolveClosures[index]()
        if let derived = tabItemLabel(in: resolved) {
          label = derived
        } else {
          let fallbackTitle = resolvedNodeLabelText(from: resolved)
          label = TabItemLabel(
            fallbackTitle.isEmpty ? "Tab \(index + 1)" : fallbackTitle
          )
        }
      } else {
        label = TabItemLabel("Tab \(index + 1)")
      }

      return TabOption(
        tag: tag,
        label: label,
        contentPayload: contentPayloads[index]
      )
    }
  }

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
  ownerNode: SwiftTUICore.ViewNode?,
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
  focusedIndexOwnerNode: SwiftTUICore.ViewNode?,
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
private let tabOverflowMenuExpandedStateSlot = -4_000_002

@MainActor
private func storedFocusedTabIndex(
  in ownerNode: SwiftTUICore.ViewNode?
) -> Int? {
  ownerNode?.stateSlot(
    ordinal: tabFocusedIndexStateSlot,
    seed: nil as Int?
  ) ?? nil
}

@MainActor
private func setStoredFocusedTabIndex(
  _ index: Int?,
  in ownerNode: SwiftTUICore.ViewNode?
) {
  ownerNode?.setStateSlot(
    ordinal: tabFocusedIndexStateSlot,
    value: index
  )
}

@MainActor
private func storedTabOverflowMenuExpanded(
  in ownerNode: SwiftTUICore.ViewNode?
) -> Bool {
  guard let ownerNode else {
    return false
  }
  return ownerNode.stateSlot(
    ordinal: tabOverflowMenuExpandedStateSlot,
    seed: false
  )
}

@MainActor
private func setStoredTabOverflowMenuExpanded(
  _ isExpanded: Bool,
  in ownerNode: SwiftTUICore.ViewNode?
) {
  ownerNode?.setStateSlot(
    ordinal: tabOverflowMenuExpandedStateSlot,
    value: isExpanded
  )
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

  package mutating func merge(_ other: PeekedTabChildMetadata) {
    if let label = other.label, label != self.label {
      self.label = self.label ?? label
    }
    if let tag = other.tag, tag != self.tag {
      self.tag = self.tag ?? tag
    }
  }
}

@MainActor
private func tabViewAvailableWidth(
  in context: ResolveContext
) -> Int {
  let environmentWidth = max(
    0,
    context.environmentValues.terminalSize.width
      - context.environmentValues.safeAreaInsets.horizontal
  )
  let proposalWidth: Int? =
    if let frameState = context.frameState,
      case .finite(let width) = frameState.proposal.width
    {
      max(0, width)
    } else {
      nil
    }

  return proposalWidth.map { min($0, environmentWidth) } ?? environmentWidth
}

/// Modifier-side tab metadata semantic hook.
///
/// Built-in modifiers should report label/tag semantics here instead
/// of attaching them to concrete wrapper views.
@MainActor
package protocol TabItemMetadataProvidingModifier: ViewModifier {
  var tabItemMetadataContribution: PeekedTabChildMetadata { get }
}

/// Structured metadata-peeking hook for authored tab child trees.
@MainActor
package protocol TabMetadataPeekingView {
  var peekedTabChildMetadata: PeekedTabChildMetadata { get }
}

/// Declaration-level hook for `Tab`-style child declarations.
///
/// Future `ModifiedContent` chains that wrap a `Tab` declaration may
/// also conform so the selected child can still resolve directly
/// without a declaration wrapper node.
@MainActor
package protocol TabDeclarationView {
  var tabDeclarationMetadata: PeekedTabChildMetadata { get }
  func resolveTabDeclarationContent(in context: ResolveContext) -> ResolvedNode
}

extension ModifiedContent: TabMetadataPeekingView
where Content: View, Modifier: ViewModifier {
  package var peekedTabChildMetadata: PeekedTabChildMetadata {
    if let provider = modifier as? any TabItemMetadataProvidingModifier {
      var result = provider.tabItemMetadataContribution
      result.merge(peekTabChildMetadata(from: content))
      return result
    }
    return peekTabChildMetadata(from: content)
  }
}

extension ModifiedContent: TabDeclarationView
where Content: TabDeclarationView & View, Modifier: ViewModifier {
  package var tabDeclarationMetadata: PeekedTabChildMetadata {
    if let provider = modifier as? any TabItemMetadataProvidingModifier {
      var result = provider.tabItemMetadataContribution
      result.merge(content.tabDeclarationMetadata)
      return result
    }
    return content.tabDeclarationMetadata
  }

  package func resolveTabDeclarationContent(in context: ResolveContext) -> ResolvedNode {
    resolveView(self, in: context)
  }
}

@MainActor
package func peekTabChildMetadata(from view: Any) -> PeekedTabChildMetadata {
  if let declaration = view as? any TabDeclarationView {
    return declaration.tabDeclarationMetadata
  }
  if let peekable = view as? any TabMetadataPeekingView {
    return peekable.peekedTabChildMetadata
  }
  return PeekedTabChildMetadata()
}
