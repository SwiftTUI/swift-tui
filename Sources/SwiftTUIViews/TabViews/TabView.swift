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
    let ownerNode = ViewNodeContext.current ?? context.viewGraph?.nodeForIdentity(context.identity)
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
    let styleItems = options.indices.map { index in
      TabViewStyleItemConfiguration(
        index: index,
        label: options[index].label,
        isSelected: selectedIndex == index,
        isFocused: (isFocused && showsFocusEffect) && focusedIndex == index,
        controlIdentity: context.identity
      )
    }
    let overflowTrigger = stylePresentation.overflowMenu.map { overflow in
      TabViewOverflowTriggerConfiguration(
        label: overflow.triggerLabel,
        isSelected: overflow.isTriggerSelected,
        isFocused: overflow.isTriggerFocused,
        isExpanded: overflow.isExpanded,
        overflowIndices: overflow.overflowIndices,
        leadingWidth: overflow.triggerLeadingWidth,
        controlIdentity: context.identity
      )
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
              setStoredTabOverflowMenuExpanded(
                false,
                in: ownerNode,
                invalidationIdentity: context.identity
              )
              moveStoredTabFocus(
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                optionCount: options.count,
                delta: -1,
                presentation: stylePresentation,
                invalidationIdentity: context.identity
              )
              return true
            case KeyPress(.arrowRight, modifiers: []):
              setStoredTabOverflowMenuExpanded(
                false,
                in: ownerNode,
                invalidationIdentity: context.identity
              )
              moveStoredTabFocus(
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                optionCount: options.count,
                delta: 1,
                presentation: stylePresentation,
                invalidationIdentity: context.identity
              )
              return true
            case KeyPress(.home, modifiers: []):
              setStoredTabOverflowMenuExpanded(
                false,
                in: ownerNode,
                invalidationIdentity: context.identity
              )
              setStoredFocusedTabIndex(
                0,
                in: ownerNode,
                invalidationIdentity: context.identity
              )
              return true
            case KeyPress(.end, modifiers: []):
              setStoredTabOverflowMenuExpanded(
                false,
                in: ownerNode,
                invalidationIdentity: context.identity
              )
              setStoredFocusedTabIndex(
                max(0, options.count - 1),
                in: ownerNode,
                invalidationIdentity: context.identity
              )
              return true
            case KeyPress(.escape, modifiers: [])
            where storedTabOverflowMenuExpanded(in: ownerNode):
              setStoredTabOverflowMenuExpanded(
                false,
                in: ownerNode,
                invalidationIdentity: context.identity
              )
              return true
            case KeyPress(.arrowDown, modifiers: []):
              if expandFocusedOverflowMenuIfNeeded(
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                optionCount: options.count,
                presentation: stylePresentation,
                invalidationIdentity: context.identity
              ) {
                return true
              }
              return moveStoredOverflowMenuFocus(
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                optionCount: options.count,
                delta: 1,
                presentation: stylePresentation,
                invalidationIdentity: context.identity
              )
            case KeyPress(.arrowUp, modifiers: []):
              if moveStoredOverflowMenuFocus(
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                optionCount: options.count,
                delta: -1,
                presentation: stylePresentation,
                invalidationIdentity: context.identity
              ) {
                return true
              }
              return true
            case KeyPress(.tab, modifiers: []), KeyPress(.tab, modifiers: .shift):
              setStoredTabOverflowMenuExpanded(
                false,
                in: ownerNode,
                invalidationIdentity: context.identity
              )
              setStoredFocusedTabIndex(
                nil,
                in: ownerNode,
                invalidationIdentity: context.identity
              )
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
            if expandFocusedOverflowMenuIfNeeded(
              ownerNode: ownerNode,
              selectedIndex: selectedIndex,
              optionCount: options.count,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            ) {
              return true
            }
            setStoredTabOverflowMenuExpanded(
              false,
              in: ownerNode,
              invalidationIdentity: context.identity
            )
            return activateBoundTabSelection(
              binding,
              focusedIndexOwnerNode: ownerNode,
              orderedTags: orderedTags,
              selectedIndex: selectedIndex,
              invalidationIdentity: context.identity
            )
          }
        },
        followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
      )

      registerPointerRoutes(
        in: context,
        presentation: stylePresentation,
        ownerNode: ownerNode,
        options: options,
        dynamicPropertyScope: dynamicPropertyScope
      )
    }

    let bodyConfiguration = TabViewStyleBodyConfiguration(
      styleConfiguration: styleConfiguration,
      presentation: stylePresentation,
      items: styleItems,
      overflowTrigger: overflowTrigger,
      content: .init(
        activeContentIndex: selectedIndex,
        payload: activeContentPayload
      )
    )
    let child = tabStyle.resolveBody(
      configuration: bodyConfiguration,
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

  @MainActor
  private func registerPointerRoutes(
    in context: ResolveContext,
    presentation: TabViewStylePresentation,
    ownerNode: SwiftTUICore.ViewNode?,
    options: [TabOption],
    dynamicPropertyScope: AuthoringContext?
  ) {
    guard let pointerRegistry = context.localPointerHandlerRegistry else {
      return
    }

    let binding = selection

    // Custom styles receive every item and can place any item in either the
    // primary strip or an overflow surface. Keep the registered route family
    // complete and let the style choose which wrappers it renders.
    for index in options.indices {
      let routeID = runtimePrimaryRouteID(
        for: tabItemIdentity(
          for: context.identity,
          index: index
        )
      )
      pointerRegistry.register(routeID: routeID) { event in
        guard case .down(.primary) = event.kind else {
          return false
        }

        return withAuthoringContext(dynamicPropertyScope) {
          setStoredTabOverflowMenuExpanded(
            false,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          setStoredFocusedTabIndex(
            index,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          return setBoundSelection(binding, to: options[index].tag)
        }
      }
    }

    guard let overflowPresentation = presentation.overflowMenu else {
      return
    }

    let triggerRouteID = runtimePrimaryRouteID(
      for: tabOverflowTriggerIdentity(for: context.identity)
    )
    pointerRegistry.register(routeID: triggerRouteID) { event in
      guard case .down(.primary) = event.kind else {
        return false
      }

      return withAuthoringContext(dynamicPropertyScope) {
        let nextExpanded = !storedTabOverflowMenuExpanded(in: ownerNode)
        setStoredTabOverflowMenuExpanded(
          nextExpanded,
          in: ownerNode,
          invalidationIdentity: context.identity
        )
        if nextExpanded, let focusIndex = overflowPresentation.preferredOverflowFocusIndex {
          setStoredFocusedTabIndex(
            focusIndex,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
        }
        return true
      }
    }

    for index in options.indices {
      let routeID = runtimePrimaryRouteID(
        for: tabOverflowItemIdentity(
          for: context.identity,
          index: index
        )
      )
      pointerRegistry.register(routeID: routeID) { event in
        guard case .down(.primary) = event.kind else {
          return false
        }

        return withAuthoringContext(dynamicPropertyScope) {
          setStoredFocusedTabIndex(
            index,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          setStoredTabOverflowMenuExpanded(
            false,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          return setBoundSelection(binding, to: options[index].tag)
        }
      }
    }
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
  delta: Int,
  presentation: TabViewStylePresentation,
  invalidationIdentity: Identity? = nil
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

  if let overflow = presentation.overflowMenu, !overflow.isExpanded {
    let overflowIndices = Set(overflow.overflowIndices)
    if overflowIndices.contains(currentIndex) {
      let nextIndex =
        if direction < 0, let lastVisible = presentation.visibleOptionIndices.last {
          lastVisible
        } else {
          overflow.preferredOverflowFocusIndex ?? overflow.overflowIndices.first ?? currentIndex
        }
      setStoredFocusedTabIndex(
        nextIndex,
        in: ownerNode,
        invalidationIdentity: invalidationIdentity
      )
      return
    }

    let nextIndex = min(
      max(currentIndex + direction, 0),
      optionCount - 1
    )
    if overflowIndices.contains(nextIndex),
      let overflowFocusIndex =
        overflow.preferredOverflowFocusIndex ?? overflow.overflowIndices.first
    {
      setStoredFocusedTabIndex(
        overflowFocusIndex,
        in: ownerNode,
        invalidationIdentity: invalidationIdentity
      )
    } else {
      setStoredFocusedTabIndex(
        nextIndex,
        in: ownerNode,
        invalidationIdentity: invalidationIdentity
      )
    }
    return
  }

  let nextIndex = min(
    max(currentIndex + direction, 0),
    optionCount - 1
  )
  setStoredFocusedTabIndex(
    nextIndex,
    in: ownerNode,
    invalidationIdentity: invalidationIdentity
  )
}

@MainActor
private func expandFocusedOverflowMenuIfNeeded(
  ownerNode: SwiftTUICore.ViewNode?,
  selectedIndex: Int?,
  optionCount: Int,
  presentation: TabViewStylePresentation,
  invalidationIdentity: Identity? = nil
) -> Bool {
  guard let overflow = presentation.overflowMenu, !overflow.isExpanded else {
    return false
  }
  guard
    let index = resolvedFocusedTabIndex(
      storedIndex: storedFocusedTabIndex(in: ownerNode),
      selectedIndex: selectedIndex,
      optionCount: optionCount
    ),
    overflow.overflowIndices.contains(index)
  else {
    return false
  }

  setStoredTabOverflowMenuExpanded(
    true,
    in: ownerNode,
    invalidationIdentity: invalidationIdentity
  )
  setStoredFocusedTabIndex(
    index,
    in: ownerNode,
    invalidationIdentity: invalidationIdentity
  )
  return true
}

@MainActor
private func moveStoredOverflowMenuFocus(
  ownerNode: SwiftTUICore.ViewNode?,
  selectedIndex: Int?,
  optionCount: Int,
  delta: Int,
  presentation: TabViewStylePresentation,
  invalidationIdentity: Identity? = nil
) -> Bool {
  guard let direction = delta == 0 ? nil : delta.signum(),
    let overflow = presentation.overflowMenu,
    overflow.isExpanded,
    !overflow.overflowIndices.isEmpty
  else {
    return false
  }

  let currentIndex =
    resolvedFocusedTabIndex(
      storedIndex: storedFocusedTabIndex(in: ownerNode),
      selectedIndex: selectedIndex,
      optionCount: optionCount
    )
    ?? overflow.preferredOverflowFocusIndex
    ?? overflow.overflowIndices[0]
  let currentOverflowPosition =
    overflow.overflowIndices.firstIndex(of: currentIndex)
    ?? (direction > 0 ? -1 : overflow.overflowIndices.count)
  let nextOverflowPosition = min(
    max(currentOverflowPosition + direction, 0),
    overflow.overflowIndices.count - 1
  )
  setStoredFocusedTabIndex(
    overflow.overflowIndices[nextOverflowPosition],
    in: ownerNode,
    invalidationIdentity: invalidationIdentity
  )
  return true
}

@MainActor
private func activateBoundTabSelection<SelectionValue: Hashable>(
  _ selectionBinding: Binding<SelectionValue>,
  focusedIndexOwnerNode: SwiftTUICore.ViewNode?,
  orderedTags: [SelectionTag],
  selectedIndex: Int?,
  invalidationIdentity: Identity? = nil
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
  setStoredFocusedTabIndex(
    index,
    in: focusedIndexOwnerNode,
    invalidationIdentity: invalidationIdentity
  )
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
  in ownerNode: SwiftTUICore.ViewNode?,
  invalidationIdentity: Identity? = nil
) {
  ownerNode?.setStateSlot(
    ordinal: tabFocusedIndexStateSlot,
    value: index,
    invalidationIdentity: invalidationIdentity
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
  in ownerNode: SwiftTUICore.ViewNode?,
  invalidationIdentity: Identity? = nil
) {
  ownerNode?.setStateSlot(
    ordinal: tabOverflowMenuExpandedStateSlot,
    value: isExpanded,
    invalidationIdentity: invalidationIdentity
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

// Tab metadata peeking — `PeekedTabChildMetadata`, the `TabMetadataPeekingView`
// / `TabDeclarationView` protocols, and `peekTabChildMetadata` — lives in
// `TabMetadataPeeking.swift`.

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
    if case .finite(let width) = context.effectiveProposal.width {
      max(0, width)
    } else {
      nil
    }

  return proposalWidth.map { min($0, environmentWidth) } ?? environmentWidth
}

// The tab metadata-peeking protocols and conformances live in
// `TabMetadataPeeking.swift`.
