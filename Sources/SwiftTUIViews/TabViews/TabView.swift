import SwiftTUICore

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
    return withDynamicPropertyUpdateScope(self, for: context) {
      [resolvedNode(in: context)]
    }
  }
}

extension TabView {
  private struct TabOption: Sendable {
    var tag: SelectionTag
    var label: TabItemLabel
    var contentPayload: LazySubviewPayload?
    var tagOccurrence: Int

    var dormantKey: TabDormantKey {
      TabDormantKey(
        value: tag.identityValue,
        includeOptional: tag.includeOptional,
        occurrence: tagOccurrence
      )
    }
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused =
      context.environmentValues.focusedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isEnabled = context.environmentValues.isEnabled
    let ownerNode = ViewNodeContext.current ?? context.viewGraph?.nodeForIdentity(context.identity)
    var optionTraversalDivergence: DeclaredChildTraversalDivergence?
    let options = resolvedOptions(
      in: context.child(component: .named("TabOptions")),
      divergence: &optionTraversalDivergence
    )
    let optionSignature = TabOptionSignature(
      tags: options.map(\.tag),
      labels: options.map(\.label)
    )
    let previousOptionSignature =
      ownerNode?.stateSlot(
        ordinal: tabOptionSignatureStateSlot,
        seed: nil as TabOptionSignature?
      ) ?? nil
    let optionsChurned =
      previousOptionSignature != nil && previousOptionSignature != optionSignature
    if previousOptionSignature != optionSignature {
      ownerNode?.setStateSlotSilently(
        ordinal: tabOptionSignatureStateSlot,
        value: optionSignature as TabOptionSignature?
      )
    }
    let orderedTags = options.map(\.tag)
    let selectedIndex =
      options.firstIndex { option in
        pickerSelectionMatches(option.tag, selection: selection.wrappedValue)
      }
      ?? options.indices.first
    let selectedDormantKey = selectedIndex.map { options[$0].dormantKey }
    var selectedContentEntityIdentity: EntityIdentity?
    var selectedContentStructuralIdentity: TabDormantPayloadStructuralIdentity?
    var dormantArchiveRefreshRequest: DormantTabArchiveRefreshRequest?

    if let ownerNode {
      let enclosingEntity = ResolveEntityRouteStorage.current?.identity
      let dormantOwnerScope = TabDormantOwnerScope(
        enclosingEntity: enclosingEntity,
        rootOwner: enclosingEntity == nil ? ownerNode.stateOwnerHandle : nil,
        authoredIdentity: context.identity
      )
      var dormantRegistry = loadTabDormantRegistry(from: ownerNode)
      var locatorState = loadTabDormantLocatorState(from: ownerNode)
      let declaredDormantKeys = options.map(\.dormantKey)
      dormantRegistry.updateDeclaredKeys(declaredDormantKeys)
      if let selectedDormantKey,
        let selectedIndex,
        let generation = dormantRegistry.lifetimeGeneration(for: selectedDormantKey)
      {
        selectedContentEntityIdentity = EntityIdentity(
          TabDormantEntityKey(
            owner: dormantOwnerScope,
            value: selectedDormantKey.value,
            includeOptional: selectedDormantKey.includeOptional,
            generation: generation
          ),
          occurrence: selectedDormantKey.occurrence
        )
        selectedContentStructuralIdentity = TabDormantPayloadStructuralIdentity(
          typedTagComponent: options[selectedIndex].tag.identityComponent,
          includeOptional: selectedDormantKey.includeOptional,
          occurrence: selectedDormantKey.occurrence,
          generation: generation
        )
      }

      if dormantRegistry.activeKey != selectedDormantKey {
        if let departingKey = dormantRegistry.activeKey,
          declaredDormantKeys.contains(departingKey),
          locatorState.activeKey == departingKey,
          let activeLocator = locatorState.activeLocator,
          let viewGraph = context.viewGraph
        {
          let refreshToken = dormantRegistry.archive(
            viewGraph.captureDormantStateArchive(using: activeLocator),
            for: departingKey
          )
          if let owner = ownerNode.stateOwnerHandle {
            dormantArchiveRefreshRequest = .init(
              owner: owner,
              key: departingKey,
              refreshToken: refreshToken,
              locator: activeLocator
            )
          }
        }

        if let selectedDormantKey,
          let archive = dormantRegistry.archive(for: selectedDormantKey)
        {
          context.viewGraph?.restoreDormantStateArchive(archive)
          dormantRegistry.removeArchive(for: selectedDormantKey)
        }

        dormantRegistry.activeKey = selectedDormantKey
        locatorState = TabDormantLocatorState()
      }

      storeTabDormantRegistry(dormantRegistry, in: ownerNode)
      storeTabDormantLocatorState(locatorState, in: ownerNode)
    }
    let focusedIndex: Int? =
      if isFocused {
        resolvedFocusedTabIndex(
          storedIndex: storedFocusedTabIndex(in: ownerNode, tags: orderedTags),
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
    if stylePresentation.overflowMenu == nil,
      storedTabOverflowMenuExpanded(in: ownerNode)
    {
      // The overflow surface departed (the options now fit, or were
      // removed): clear the expanded flag silently so a future overflow
      // surface starts collapsed instead of resurrecting this one. Nothing
      // rendered this frame reads the flag while no surface exists, so no
      // invalidation is owed.
      ownerNode?.setStateSlotSilently(
        ordinal: tabOverflowMenuExpandedStateSlot,
        value: false
      )
    }
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

    // The strip item routes are focus-presentation *value-verified* slots:
    // their configurations carry every focus-derived input (`isFocused`), so
    // on a focus/press move onto/off this control an item whose value
    // compares `Equatable`-equal is provably unchanged and may memo-reuse
    // instead of recomputing — while the flipped item's compare fails and
    // recomputes. Mirrors the certified state-write cone
    // (`stripFocusInvalidationIdentities`): visible items, the overflow
    // trigger, and the expanded overflow items.
    if let viewGraph = context.viewGraph {
      for index in stylePresentation.visibleOptionIndices
      where options.indices.contains(index) {
        viewGraph.declareFocusPresentationValueVerifiedSlot(
          tabItemIdentity(for: context.identity, index: index),
          forControl: context.identity
        )
      }
      if let overflow = stylePresentation.overflowMenu {
        viewGraph.declareFocusPresentationValueVerifiedSlot(
          tabOverflowTriggerIdentity(for: context.identity),
          forControl: context.identity
        )
        if overflow.isExpanded {
          for index in overflow.overflowIndices
          where options.indices.contains(index) {
            viewGraph.declareFocusPresentationValueVerifiedSlot(
              tabOverflowItemIdentity(for: context.identity, index: index),
              forControl: context.identity
            )
          }
        }
      }
    }

    if isEnabled {
      let binding = selection
      let intake = HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: authoringScope
      )
      intake.registerKeyPressHandler(
        identity: context.identity,
        handler: {
          keyPress in
          guard !options.isEmpty else {
            return false
          }

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
              orderedTags: orderedTags,
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
              orderedTags: orderedTags,
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
              tags: orderedTags,
              in: ownerNode,
              invalidationIdentity: context.identity,
              certifiedInvalidationIdentities: certifiedStripFocusIdentities(
                controlIdentity: context.identity,
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                orderedTags: orderedTags,
                presentation: stylePresentation,
                nextStoredIndex: 0
              )
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
              tags: orderedTags,
              in: ownerNode,
              invalidationIdentity: context.identity,
              certifiedInvalidationIdentities: certifiedStripFocusIdentities(
                controlIdentity: context.identity,
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                orderedTags: orderedTags,
                presentation: stylePresentation,
                nextStoredIndex: max(0, options.count - 1)
              )
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
              orderedTags: orderedTags,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            ) {
              return true
            }
            return moveStoredOverflowMenuFocus(
              ownerNode: ownerNode,
              selectedIndex: selectedIndex,
              orderedTags: orderedTags,
              delta: 1,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            )
          case KeyPress(.arrowUp, modifiers: []):
            if expandFocusedOverflowMenuIfNeeded(
              ownerNode: ownerNode,
              selectedIndex: selectedIndex,
              orderedTags: orderedTags,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            ) {
              return true
            }
            return moveStoredOverflowMenuFocus(
              ownerNode: ownerNode,
              selectedIndex: selectedIndex,
              orderedTags: orderedTags,
              delta: -1,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            )
          case KeyPress(.tab, modifiers: []), KeyPress(.tab, modifiers: .shift):
            setStoredTabOverflowMenuExpanded(
              false,
              in: ownerNode,
              invalidationIdentity: context.identity
            )
            setStoredFocusedTabIndex(
              nil,
              tags: orderedTags,
              in: ownerNode,
              invalidationIdentity: context.identity,
              certifiedInvalidationIdentities: certifiedStripFocusIdentities(
                controlIdentity: context.identity,
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                orderedTags: orderedTags,
                presentation: stylePresentation,
                nextStoredIndex: nil
              )
            )
            return false
          default:
            return false
          }
        })
      intake.registerAction(identity: context.identity) {
        if expandFocusedOverflowMenuIfNeeded(
          ownerNode: ownerNode,
          selectedIndex: selectedIndex,
          orderedTags: orderedTags,
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
          presentation: stylePresentation,
          invalidationIdentity: context.identity
        )
      }

      registerPointerRoutes(
        in: context,
        presentation: stylePresentation,
        ownerNode: ownerNode,
        options: options,
        intake: intake
      )
    }

    let bodyConfiguration = TabViewStyleBodyConfiguration(
      styleConfiguration: styleConfiguration,
      presentation: stylePresentation,
      items: styleItems,
      overflowTrigger: overflowTrigger,
      content: .init(
        payload: activeContentPayload,
        controlIdentity: context.identity,
        payloadEntityIdentity: selectedContentEntityIdentity,
        payloadStructuralIdentity: selectedContentStructuralIdentity,
        dormantArchiveLocatorSink: makeDormantArchiveLocatorSink(
          ownerNode: ownerNode,
          key: selectedDormantKey
        )
      )
    )
    var tabBodyContext = context.child(component: .named("TabBody"))
    if optionsChurned {
      // The options changed value across a re-resolve. Force the style body to
      // recompute even if the TabView node reused across an `.id`-island seam,
      // so the rendered chrome (route/label bindings) follows the new options
      // instead of being served stale by value-blind Layer-A reuse.
      tabBodyContext.withinChurnedSubtree = true
    }
    let child = tabStyle.resolveBody(
      configuration: bodyConfiguration,
      in: tabBodyContext
    )

    var node = ResolvedNode(
      identity: context.identity,
      kind: .view("TabView"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: tabViewSemanticMetadata()
    )
    if let dormantArchiveRefreshRequest {
      node.preferenceValues[DormantTabArchiveRefreshPreferenceKey.self] = [
        dormantArchiveRefreshRequest
      ]
    }
    if let optionTraversalDivergence {
      // Observability-first, like the F166 placement mismatch: a tab showing a
      // sibling's body is better reported than crashed, and the report names
      // the shape that produced it.
      var preferences = node.preferenceValues
      var runtimeIssues = preferences[RuntimeIssuePreferenceKey.self]
      let issue = optionTraversalDivergence.runtimeIssue(
        container: "TabView",
        identity: context.identity
      )
      if !runtimeIssues.contains(issue) {
        runtimeIssues.append(issue)
      }
      preferences[RuntimeIssuePreferenceKey.self] = runtimeIssues
      node.preferenceValues = preferences
    }
    let duplicateTagIssues = options.compactMap { option -> RuntimeIssue? in
      guard option.tagOccurrence > 0 else {
        return nil
      }
      return RuntimeIssue(
        severity: .warning,
        code: "tab.duplicateTag",
        message:
          "TabView declared duplicate selection tag \(option.tag.identityComponent) "
          + "at occurrence \(option.tagOccurrence); dormant state is isolated by occurrence, "
          + "but unique stable tags are required for supported selection semantics.",
        identity: context.identity,
        source: "TabView"
      )
    }
    if !duplicateTagIssues.isEmpty {
      var preferences = node.preferenceValues
      var runtimeIssues = preferences[RuntimeIssuePreferenceKey.self]
      for issue in duplicateTagIssues where !runtimeIssues.contains(issue) {
        runtimeIssues.append(issue)
      }
      preferences[RuntimeIssuePreferenceKey.self] = runtimeIssues
      node.preferenceValues = preferences
    }
    return node
  }

  @MainActor
  private func registerPointerRoutes(
    in context: ResolveContext,
    presentation: TabViewStylePresentation,
    ownerNode: SwiftTUICore.ViewNode?,
    options: [TabOption],
    intake: HandlerDescriptorIntake
  ) {
    guard context.localPointerHandlerRegistry != nil else {
      return
    }

    let binding = selection
    let orderedTags = options.map(\.tag)

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
      intake.registerPointerHandler(routeID: routeID) { event in
        switch event.kind {
        case .down(.primary):
          setStoredTabOverflowMenuExpanded(
            false,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          setStoredFocusedTabIndex(
            index,
            tags: orderedTags,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          _ = setBoundSelection(binding, to: options[index].tag)
          return .claimed
        case .up(.primary):
          return .claimed
        default:
          return .ignored
        }
      }
    }

    guard let overflowPresentation = presentation.overflowMenu else {
      return
    }

    let triggerRouteID = runtimePrimaryRouteID(
      for: tabOverflowTriggerIdentity(for: context.identity)
    )
    intake.registerPointerHandler(routeID: triggerRouteID) { event in
      switch event.kind {
      case .down(.primary):
        let nextExpanded = !storedTabOverflowMenuExpanded(in: ownerNode)
        setStoredTabOverflowMenuExpanded(
          nextExpanded,
          in: ownerNode,
          invalidationIdentity: context.identity
        )
        if nextExpanded, let focusIndex = overflowPresentation.preferredOverflowFocusIndex {
          setStoredFocusedTabIndex(
            focusIndex,
            tags: orderedTags,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
        }
        return .claimed
      case .up(.primary):
        return .claimed
      default:
        return .ignored
      }
    }

    for index in options.indices {
      let routeID = runtimePrimaryRouteID(
        for: tabOverflowItemIdentity(
          for: context.identity,
          index: index
        )
      )
      intake.registerPointerHandler(routeID: routeID) { event in
        switch event.kind {
        case .down(.primary):
          setStoredFocusedTabIndex(
            index,
            tags: orderedTags,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          setStoredTabOverflowMenuExpanded(
            false,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          _ = setBoundSelection(binding, to: options[index].tag)
          return .claimed
        case .up(.primary):
          return .claimed
        default:
          return .ignored
        }
      }
    }
  }

  private func resolvedOptions(
    in context: ResolveContext,
    divergence: inout DeclaredChildTraversalDivergence?
  ) -> [TabOption] {
    // Peek each declared child's metadata (tab label + tag) without resolving
    // it, and carry the deferred payload that will resolve it if selected.
    // Only the active tab's payload enters the resolve pipeline — inactive
    // tabs never call `beginEvaluation`, so their `.onAppear` / `.task`
    // handlers do not fire until selected.
    let declared = pairedLazyDeclaredChildren(
      from: content,
      in: context.child(component: .named("TabOptions")),
      kindName: "Tab",
      debugName: "TabBody",
      lifecyclePolicy: .dormantStatePreserving
    )
    divergence = declared.divergence

    // Untagged children are dropped, but their declared position is not: the
    // payload was already paired by declared index, so a tagless child cannot
    // shift its siblings' content.
    var resolved: [TabOption] = []
    for (index, child) in declared.children.enumerated() {
      let entry = peekTabChildMetadata(from: child.view)
      guard let tag = entry.tag else {
        continue
      }

      let occurrence = resolved.lazy.filter { $0.tag == tag }.count
      resolved.append(
        TabOption(
          tag: tag,
          label: entry.label ?? TabItemLabel("Tab \(index + 1)"),
          contentPayload: child.payload,
          tagOccurrence: occurrence
        )
      )
    }
    return resolved
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
  orderedTags: [SelectionTag],
  delta: Int,
  presentation: TabViewStylePresentation,
  invalidationIdentity: Identity? = nil
) {
  let optionCount = orderedTags.count
  guard let direction = delta == 0 ? nil : delta.signum(), optionCount > 0 else {
    return
  }

  let currentIndex =
    resolvedFocusedTabIndex(
      storedIndex: storedFocusedTabIndex(in: ownerNode, tags: orderedTags),
      selectedIndex: selectedIndex,
      optionCount: optionCount
    )
    ?? (direction > 0 ? -1 : optionCount)
  // The synthetic off-strip anchors (-1 / optionCount) fall out of the
  // certified set naturally: no visible or overflow index matches them.
  let certifiedIdentities = { (nextIndex: Int) -> Set<Identity>? in
    invalidationIdentity.map { controlIdentity in
      stripFocusInvalidationIdentities(
        controlIdentity: controlIdentity,
        presentation: presentation,
        flippedIndices: [currentIndex, nextIndex]
      )
    }
  }

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
        tags: orderedTags,
        in: ownerNode,
        invalidationIdentity: invalidationIdentity,
        certifiedInvalidationIdentities: certifiedIdentities(nextIndex)
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
        tags: orderedTags,
        in: ownerNode,
        invalidationIdentity: invalidationIdentity,
        certifiedInvalidationIdentities: certifiedIdentities(overflowFocusIndex)
      )
    } else {
      setStoredFocusedTabIndex(
        nextIndex,
        tags: orderedTags,
        in: ownerNode,
        invalidationIdentity: invalidationIdentity,
        certifiedInvalidationIdentities: certifiedIdentities(nextIndex)
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
    tags: orderedTags,
    in: ownerNode,
    invalidationIdentity: invalidationIdentity,
    certifiedInvalidationIdentities: certifiedIdentities(nextIndex)
  )
}

@MainActor
private func expandFocusedOverflowMenuIfNeeded(
  ownerNode: SwiftTUICore.ViewNode?,
  selectedIndex: Int?,
  orderedTags: [SelectionTag],
  presentation: TabViewStylePresentation,
  invalidationIdentity: Identity? = nil
) -> Bool {
  guard let overflow = presentation.overflowMenu, !overflow.isExpanded else {
    return false
  }
  guard
    let index = resolvedFocusedTabIndex(
      storedIndex: storedFocusedTabIndex(in: ownerNode, tags: orderedTags),
      selectedIndex: selectedIndex,
      optionCount: orderedTags.count
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
    tags: orderedTags,
    in: ownerNode,
    invalidationIdentity: invalidationIdentity
  )
  return true
}

@MainActor
private func moveStoredOverflowMenuFocus(
  ownerNode: SwiftTUICore.ViewNode?,
  selectedIndex: Int?,
  orderedTags: [SelectionTag],
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
      storedIndex: storedFocusedTabIndex(in: ownerNode, tags: orderedTags),
      selectedIndex: selectedIndex,
      optionCount: orderedTags.count
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
  let nextIndex = overflow.overflowIndices[nextOverflowPosition]
  setStoredFocusedTabIndex(
    nextIndex,
    tags: orderedTags,
    in: ownerNode,
    invalidationIdentity: invalidationIdentity,
    certifiedInvalidationIdentities: invalidationIdentity.map { controlIdentity in
      stripFocusInvalidationIdentities(
        controlIdentity: controlIdentity,
        presentation: presentation,
        flippedIndices: [currentIndex, nextIndex]
      )
    }
  )
  return true
}

@MainActor
private func activateBoundTabSelection<SelectionValue: Hashable>(
  _ selectionBinding: Binding<SelectionValue>,
  focusedIndexOwnerNode: SwiftTUICore.ViewNode?,
  orderedTags: [SelectionTag],
  selectedIndex: Int?,
  presentation: TabViewStylePresentation,
  invalidationIdentity: Identity? = nil
) -> Bool {
  guard
    let index = resolvedFocusedTabIndex(
      storedIndex: storedFocusedTabIndex(in: focusedIndexOwnerNode, tags: orderedTags),
      selectedIndex: selectedIndex,
      optionCount: orderedTags.count
    ),
    orderedTags.indices.contains(index)
  else {
    return false
  }
  // Normalizes storage onto the already-displayed index (old == new), so the
  // certified cone is the single resolved item plus the trigger; the
  // selection write below carries its own (broad) invalidation.
  setStoredFocusedTabIndex(
    index,
    tags: orderedTags,
    in: focusedIndexOwnerNode,
    invalidationIdentity: invalidationIdentity,
    certifiedInvalidationIdentities: invalidationIdentity.map { controlIdentity in
      stripFocusInvalidationIdentities(
        controlIdentity: controlIdentity,
        presentation: presentation,
        flippedIndices: [index]
      )
    }
  )
  return setBoundSelection(selectionBinding, to: orderedTags[index])
}

private let tabFocusedIndexStateSlot = StateSlotOrdinals.tabFocusedIndex
private let tabOverflowMenuExpandedStateSlot = StateSlotOrdinals.tabOverflowMenuExpanded
private let tabOptionSignatureStateSlot = StateSlotOrdinals.tabOptionSignature
private let tabDormantArchiveStateSlot = StateSlotOrdinals.tabDormantArchive
private let tabDormantLocatorStateSlot = tabDormantArchiveStateSlot - 1

package struct TabDormantKey: Hashable, Sendable {
  var value: AnyID
  var includeOptional: Bool
  var occurrence: Int

  package init(
    value: AnyID,
    includeOptional: Bool,
    occurrence: Int
  ) {
    self.value = value
    self.includeOptional = includeOptional
    self.occurrence = occurrence
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.value == rhs.value
      && lhs.includeOptional == rhs.includeOptional
      && lhs.occurrence == rhs.occurrence
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(value)
    hasher.combine(includeOptional)
    hasher.combine(occurrence)
  }
}

private struct TabDormantEntityKey: Hashable, Sendable {
  var owner: TabDormantOwnerScope
  var value: AnyID
  var includeOptional: Bool
  var generation: UInt64
}

/// Authored, value-only identity for the active payload's structural child.
/// The enclosing TabView/content path supplies owner scope; the fields here
/// distinguish typed tags, optional matching, duplicates, and replacement
/// generations within that owner without depending on a graph-node lifetime.
package struct TabDormantPayloadStructuralIdentity: Hashable, Sendable {
  package var typedTagComponent: String
  package var includeOptional: Bool
  package var occurrence: Int
  package var generation: UInt64
}

/// Stable authored ownership for a TabView's lazy payload entities. Nested
/// TabViews inherit the nearest routed payload entity, so an enclosing dormant
/// archive can preseed the same inner payload routes without depending on a
/// raw graph-node allocation. The authored identity separates sibling owners
/// within that entity scope and changes with explicit owner replacement.
private struct TabDormantOwnerScope: Hashable, Sendable {
  var enclosingEntity: EntityIdentity?
  var rootOwner: StateOwnerHandle?
  var authoredIdentity: Identity
}

package struct DormantTabArchiveRefreshRequest: Sendable {
  package var owner: StateOwnerHandle
  package var key: TabDormantKey
  package var refreshToken: UInt64
  package var locator: DormantStateArchiveLocator

  package init(
    owner: StateOwnerHandle,
    key: TabDormantKey,
    refreshToken: UInt64,
    locator: DormantStateArchiveLocator
  ) {
    self.owner = owner
    self.key = key
    self.refreshToken = refreshToken
    self.locator = locator
  }
}

@MainActor
package struct DormantTabArchiveCommitRefresh {
  package var owner: StateOwnerHandle
  package var key: TabDormantKey
  package var refreshToken: UInt64
  package var archive: DormantStateArchive

  package init(
    owner: StateOwnerHandle,
    key: TabDormantKey,
    refreshToken: UInt64,
    archive: DormantStateArchive
  ) {
    self.owner = owner
    self.key = key
    self.refreshToken = refreshToken
    self.archive = archive
  }
}

package enum DormantTabArchiveRefreshPreferenceKey: PreferenceKey {
  package static let defaultValue: [DormantTabArchiveRefreshRequest] = []

  package static func reduce(
    value: inout [DormantTabArchiveRefreshRequest],
    nextValue: () -> [DormantTabArchiveRefreshRequest]
  ) {
    value.append(contentsOf: nextValue())
  }
}

@MainActor
private struct TabDormantRegistry {
  struct Entry {
    var key: TabDormantKey
    var archive: DormantStateArchive
    var pendingRefreshToken: UInt64?
  }

  struct Lifetime {
    var key: TabDormantKey
    var generation: UInt64
  }

  var activeKey: TabDormantKey?
  var entries: [Entry] = []
  var lifetimes: [Lifetime] = []
  var nextLifetimeGeneration: UInt64 = 0
  var nextRefreshToken: UInt64 = 0

  @discardableResult
  mutating func archive(
    _ archive: DormantStateArchive,
    for key: TabDormantKey
  ) -> UInt64 {
    let refreshToken = nextRefreshToken
    nextRefreshToken &+= 1
    if let index = entries.firstIndex(where: { $0.key == key }) {
      entries[index].archive = archive
      entries[index].pendingRefreshToken = refreshToken
    } else {
      entries.append(
        Entry(
          key: key,
          archive: archive,
          pendingRefreshToken: refreshToken
        )
      )
    }
    return refreshToken
  }

  func archive(for key: TabDormantKey) -> DormantStateArchive? {
    entries.first(where: { $0.key == key })?.archive
  }

  mutating func removeArchive(for key: TabDormantKey) {
    entries.removeAll { $0.key == key }
  }

  mutating func updateDeclaredKeys(_ newDeclaredKeys: [TabDormantKey]) {
    entries.removeAll { entry in
      !newDeclaredKeys.contains(entry.key)
    }
    lifetimes.removeAll { lifetime in
      !newDeclaredKeys.contains(lifetime.key)
    }
    for key in newDeclaredKeys where !lifetimes.contains(where: { $0.key == key }) {
      lifetimes.append(
        Lifetime(key: key, generation: nextLifetimeGeneration)
      )
      nextLifetimeGeneration &+= 1
    }
  }

  func lifetimeGeneration(for key: TabDormantKey) -> UInt64? {
    lifetimes.first(where: { $0.key == key })?.generation
  }
}

/// Locator recipes are live-graph currency and must never enter a dormant
/// archive. Keeping them in a distinct transient slot lets the value-only tab
/// registry itself nest safely inside an enclosing tab's archive.
private struct TabDormantLocatorState {
  var activeKey: TabDormantKey?
  var activeLocator: DormantStateArchiveLocator?
}

/// Reads value-only archive snapshots for the tab owners that emitted a
/// departure request in this candidate. The completed-frame path calls this
/// while the suspended committed graph is still materialized, before the
/// prepared checkpoint replaces outgoing owners. Nothing is written here, so
/// a subsequently aborted candidate cannot mutate the committed registry.
@MainActor
package func captureDormantTabArchiveCommitRefreshes(
  in viewGraph: ViewGraph,
  requests: [DormantTabArchiveRefreshRequest]
) -> [DormantTabArchiveCommitRefresh] {
  var refreshedOwners: Set<StateOwnerHandle> = []
  var refreshes: [DormantTabArchiveCommitRefresh] = []
  for request in requests where refreshedOwners.insert(request.owner).inserted {
    refreshes.append(
      DormantTabArchiveCommitRefresh(
        owner: request.owner,
        key: request.key,
        refreshToken: request.refreshToken,
        archive: viewGraph.captureDormantStateArchive(using: request.locator)
      )
    )
  }
  return refreshes
}

/// Applies commit-authoritative value snapshots after the prepared graph is
/// materialized and immediately before frame finalization tears down outgoing
/// payload nodes. The archive contains no task, registration, observation, or
/// node references.
@MainActor
package func applyDormantTabArchiveCommitRefreshes(
  _ refreshes: [DormantTabArchiveCommitRefresh],
  in viewGraph: ViewGraph
) {
  for refresh in refreshes {
    guard
      refresh.owner.graphScope == viewGraph.stateGraphScopeID,
      let ownerNode = viewGraph.nodeForOwnerLifetimeID(refresh.owner.ownerLifetime)
    else {
      continue
    }
    var registry = loadTabDormantRegistry(from: ownerNode)
    guard
      let index = registry.entries.firstIndex(where: {
        $0.key == refresh.key && $0.pendingRefreshToken == refresh.refreshToken
      })
    else {
      continue
    }
    registry.entries[index].archive = refresh.archive
    registry.entries[index].pendingRefreshToken = nil
    storeTabDormantRegistry(registry, in: ownerNode)
  }
}

@MainActor
private func makeDormantArchiveLocatorSink(
  ownerNode: SwiftTUICore.ViewNode?,
  key: TabDormantKey?
) -> (@MainActor @Sendable (DormantStateArchiveLocator) -> Void)? {
  guard let ownerNode, let key else {
    return nil
  }
  return { [weak ownerNode] locator in
    guard let ownerNode else {
      return
    }
    let registry = loadTabDormantRegistry(from: ownerNode)
    guard registry.activeKey == key else {
      return
    }
    storeTabDormantLocatorState(
      TabDormantLocatorState(activeKey: key, activeLocator: locator),
      in: ownerNode
    )
  }
}

@MainActor
private func loadTabDormantRegistry(
  from ownerNode: SwiftTUICore.ViewNode
) -> TabDormantRegistry {
  withPersistentDormantStateSlot {
    ownerNode.stateSlot(
      ordinal: tabDormantArchiveStateSlot,
      seed: TabDormantRegistry()
    )
  }
}

@MainActor
private func storeTabDormantRegistry(
  _ registry: TabDormantRegistry,
  in ownerNode: SwiftTUICore.ViewNode
) {
  withPersistentDormantStateSlot {
    ownerNode.setStateSlotSilently(
      ordinal: tabDormantArchiveStateSlot,
      value: registry
    )
  }
}

@MainActor
private func loadTabDormantLocatorState(
  from ownerNode: SwiftTUICore.ViewNode
) -> TabDormantLocatorState {
  withTransientDormantStateSlot {
    ownerNode.stateSlot(
      ordinal: tabDormantLocatorStateSlot,
      seed: TabDormantLocatorState()
    )
  }
}

@MainActor
private func storeTabDormantLocatorState(
  _ locatorState: TabDormantLocatorState,
  in ownerNode: SwiftTUICore.ViewNode
) {
  withTransientDormantStateSlot {
    ownerNode.setStateSlotSilently(
      ordinal: tabDormantLocatorStateSlot,
      value: locatorState
    )
  }
}

@MainActor
package struct TabDormantRegistrySnapshot: Equatable, Sendable {
  package var archivedTabCount: Int
  package var archivedNodeCount: Int
  package var persistentSlotCount: Int
}

@MainActor
package func tabDormantRegistrySnapshot(
  in ownerNode: SwiftTUICore.ViewNode?
) -> TabDormantRegistrySnapshot {
  guard let ownerNode else {
    return .init(archivedTabCount: 0, archivedNodeCount: 0, persistentSlotCount: 0)
  }
  let registry = loadTabDormantRegistry(from: ownerNode)
  return TabDormantRegistrySnapshot(
    archivedTabCount: registry.entries.count,
    archivedNodeCount: registry.entries.reduce(into: 0) { $0 += $1.archive.records.count },
    persistentSlotCount: registry.entries.reduce(into: 0) {
      $0 += $1.archive.persistentSlotCount
    }
  )
}

/// The value-identity of a TabView's resolved options (selection tags + item
/// labels). When it changes across a re-resolve, the style body must recompute
/// even though the TabView node reused across an `.id`-island seam — otherwise
/// value-blind Layer-A reuse serves stale tab chrome (index-keyed route/label
/// skew) while the handlers refresh underneath it.
private struct TabOptionSignature: Equatable, Sendable {
  var tags: [SelectionTag]
  var labels: [TabItemLabel]
}

/// What the strip focus remembers: the focused option's strip position plus
/// its selection tag. The tag is authoritative when the option order changes
/// — logical focus follows the *tab*, not the strip position — and the
/// recorded index is the fallback when the tag has departed.
private struct StoredTabFocus: Equatable, Sendable {
  var index: Int
  var tag: SelectionTag?
}

@MainActor
private func storedFocusedTabIndex(
  in ownerNode: SwiftTUICore.ViewNode?,
  tags: [SelectionTag]
) -> Int? {
  guard
    let stored =
      ownerNode?.stateSlot(
        ordinal: tabFocusedIndexStateSlot,
        seed: nil as StoredTabFocus?
      ) ?? nil
  else {
    return nil
  }
  if let tag = stored.tag, let currentIndex = tags.firstIndex(of: tag) {
    return currentIndex
  }
  return stored.index
}

@MainActor
private func setStoredFocusedTabIndex(
  _ index: Int?,
  tags: [SelectionTag],
  in ownerNode: SwiftTUICore.ViewNode?,
  invalidationIdentity: Identity? = nil,
  certifiedInvalidationIdentities: Set<Identity>? = nil
) {
  let stored = index.map { index in
    StoredTabFocus(
      index: index,
      tag: tags.indices.contains(index) ? tags[index] : nil
    )
  }
  ownerNode?.setStateSlot(
    ordinal: tabFocusedIndexStateSlot,
    value: stored,
    invalidationIdentity: invalidationIdentity,
    certifiedInvalidationIdentities: certifiedInvalidationIdentities
  )
}

/// Resolves the old and new *display* indices for a stored-index write (the
/// display index falls back to the selection when storage is nil) and returns
/// the certified strip cone between them.
@MainActor
private func certifiedStripFocusIdentities(
  controlIdentity: Identity,
  ownerNode: SwiftTUICore.ViewNode?,
  selectedIndex: Int?,
  orderedTags: [SelectionTag],
  presentation: TabViewStylePresentation,
  nextStoredIndex: Int?
) -> Set<Identity> {
  let optionCount = orderedTags.count
  let currentIndex = resolvedFocusedTabIndex(
    storedIndex: storedFocusedTabIndex(in: ownerNode, tags: orderedTags),
    selectedIndex: selectedIndex,
    optionCount: optionCount
  )
  let nextIndex = resolvedFocusedTabIndex(
    storedIndex: nextStoredIndex,
    selectedIndex: selectedIndex,
    optionCount: optionCount
  )
  return stripFocusInvalidationIdentities(
    controlIdentity: controlIdentity,
    presentation: presentation,
    flippedIndices: [currentIndex, nextIndex]
  )
}

/// The strip-chrome subtrees whose resolved output can differ when the stored
/// strip-focus index moves between `flippedIndices` (the resolved old/new
/// display indices): the flipped visible bar items, the flipped overflow-menu
/// items while the menu is expanded, and the overflow trigger (whose
/// focused/expanded presentation tracks the focused domain) whenever an
/// overflow surface exists. The stored index is read only by the declaring
/// `TabView`'s own body — its re-run rides the state-dirty queue — and the
/// content slot is `f(authored, selection)`, which a pure strip-focus move
/// cannot change (the same promise the focus-presentation-inert slot
/// declaration certifies for tracker moves). Styles that do not stamp these
/// route identities fail the certified write's liveness check and keep the
/// reader-attributed broad cone.
private func stripFocusInvalidationIdentities(
  controlIdentity: Identity,
  presentation: TabViewStylePresentation,
  flippedIndices: [Int?]
) -> Set<Identity> {
  var identities: Set<Identity> = []
  let visibleIndices = Set(presentation.visibleOptionIndices)
  for case let index? in flippedIndices {
    if visibleIndices.contains(index) {
      identities.insert(tabItemIdentity(for: controlIdentity, index: index))
    }
    if let overflow = presentation.overflowMenu,
      overflow.isExpanded,
      overflow.overflowIndices.contains(index)
    {
      identities.insert(
        tabOverflowItemIdentity(for: controlIdentity, index: index)
      )
    }
  }
  if presentation.overflowMenu != nil {
    identities.insert(tabOverflowTriggerIdentity(for: controlIdentity))
  }
  return identities
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

private func tabViewSemanticMetadata() -> SemanticMetadata {
  // The root action is keyboard-only. Built-in and custom tab styles expose
  // pointer routes for tab labels and overflow controls; the root must not
  // turn active-tab background clicks into tab activations.
  .init(
    isFocusable: true,
    focusInteractions: .activate,
    participatesInPointerHitTesting: true,
    accessibilityRole: .tabView,
    explicitInteractionRect: CellRect(origin: .zero, size: .zero)
  )
}

// The tab metadata-peeking protocols and conformances live in
// `TabMetadataPeeking.swift`.
