import SwiftTUICore

/// Selects one declared tab and renders a terminal-native tab strip above the
/// active content.
public struct TabView<SelectionValue: Hashable, Content: View>: PrimitiveView,
  IterativeResolvableView
{
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

  package func makeResolveWork(
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return withDynamicPropertyUpdateScope(self, for: context) {
      resolvedNode(in: context).map { [$0] }
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
  ) -> ResolveWork<ResolvedNode> {
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
    let optionsChurned = TabSelectionState.updateOptions(
      in: ownerNode, tags: options.map(\.tag), labels: options.map(\.label))
    // Input handlers capture tags only. Capturing the option array also owns
    // every deferred payload's authored State seeds through retained chrome.
    let orderedTags = options.map(\.tag)
    let selectedIndex =
      options.firstIndex { option in
        pickerSelectionMatches(option.tag, selection: selection.wrappedValue)
      }
      ?? options.indices.first
    let selectedDormantKey = selectedIndex.map { options[$0].dormantKey }
    let dormantSelection = TabDormancy.prepare(
      in: context, ownerNode: ownerNode,
      declaredDormantKeys: options.map(\.dormantKey), selectedDormantKey: selectedDormantKey,
      selectedTagComponent: selectedIndex.map { options[$0].tag.identityComponent })
    let selectedContentEntityIdentity = dormantSelection.entityIdentity
    let selectedContentStructuralIdentity = dormantSelection.structuralIdentity
    let dormantArchiveRefreshRequest = dormantSelection.refreshRequest
    let focusedIndex: Int? =
      if isFocused {
        TabSelectionState.resolvedFocusedTabIndex(
          storedIndex: TabSelectionState.storedFocusedTabIndex(in: ownerNode, tags: orderedTags),
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
      isOverflowMenuExpanded: TabSelectionState.storedTabOverflowMenuExpanded(in: ownerNode)
    )
    let stylePresentation = tabStyle.validatedPresentation(
      for: styleConfiguration,
      identity: context.identity
    )
    if stylePresentation.overflowMenu == nil,
      TabSelectionState.storedTabOverflowMenuExpanded(in: ownerNode)
    {
      // The overflow surface departed (the options now fit, or were
      // removed): clear the expanded flag silently so a future overflow
      // surface starts collapsed instead of resurrecting this one. Nothing
      // rendered this frame reads the flag while no surface exists, so no
      // invalidation is owed.
      TabSelectionState.resetOverflow(in: ownerNode)
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
          guard !orderedTags.isEmpty else {
            return false
          }

          switch keyPress {
          case KeyPress(.arrowLeft, modifiers: []):
            TabSelectionState.setStoredTabOverflowMenuExpanded(
              false,
              in: ownerNode,
              invalidationIdentity: context.identity
            )
            TabSelectionState.moveStoredTabFocus(
              ownerNode: ownerNode,
              selectedIndex: selectedIndex,
              orderedTags: orderedTags,
              delta: -1,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            )
            return true
          case KeyPress(.arrowRight, modifiers: []):
            TabSelectionState.setStoredTabOverflowMenuExpanded(
              false,
              in: ownerNode,
              invalidationIdentity: context.identity
            )
            TabSelectionState.moveStoredTabFocus(
              ownerNode: ownerNode,
              selectedIndex: selectedIndex,
              orderedTags: orderedTags,
              delta: 1,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            )
            return true
          case KeyPress(.home, modifiers: []):
            TabSelectionState.setStoredTabOverflowMenuExpanded(
              false,
              in: ownerNode,
              invalidationIdentity: context.identity
            )
            TabSelectionState.setStoredFocusedTabIndex(
              0,
              tags: orderedTags,
              in: ownerNode,
              invalidationIdentity: context.identity,
              certifiedInvalidationIdentities: TabSelectionState.certifiedStripFocusIdentities(
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
            TabSelectionState.setStoredTabOverflowMenuExpanded(
              false,
              in: ownerNode,
              invalidationIdentity: context.identity
            )
            TabSelectionState.setStoredFocusedTabIndex(
              max(0, orderedTags.count - 1),
              tags: orderedTags,
              in: ownerNode,
              invalidationIdentity: context.identity,
              certifiedInvalidationIdentities: TabSelectionState.certifiedStripFocusIdentities(
                controlIdentity: context.identity,
                ownerNode: ownerNode,
                selectedIndex: selectedIndex,
                orderedTags: orderedTags,
                presentation: stylePresentation,
                nextStoredIndex: max(0, orderedTags.count - 1)
              )
            )
            return true
          case KeyPress(.escape, modifiers: [])
          where TabSelectionState.storedTabOverflowMenuExpanded(in: ownerNode):
            TabSelectionState.setStoredTabOverflowMenuExpanded(
              false,
              in: ownerNode,
              invalidationIdentity: context.identity
            )
            return true
          case KeyPress(.arrowDown, modifiers: []):
            if TabSelectionState.expandFocusedOverflowMenuIfNeeded(
              ownerNode: ownerNode,
              selectedIndex: selectedIndex,
              orderedTags: orderedTags,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            ) {
              return true
            }
            return TabSelectionState.moveStoredOverflowMenuFocus(
              ownerNode: ownerNode,
              selectedIndex: selectedIndex,
              orderedTags: orderedTags,
              delta: 1,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            )
          case KeyPress(.arrowUp, modifiers: []):
            if TabSelectionState.expandFocusedOverflowMenuIfNeeded(
              ownerNode: ownerNode,
              selectedIndex: selectedIndex,
              orderedTags: orderedTags,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            ) {
              return true
            }
            return TabSelectionState.moveStoredOverflowMenuFocus(
              ownerNode: ownerNode,
              selectedIndex: selectedIndex,
              orderedTags: orderedTags,
              delta: -1,
              presentation: stylePresentation,
              invalidationIdentity: context.identity
            )
          case KeyPress(.tab, modifiers: []), KeyPress(.tab, modifiers: .shift):
            TabSelectionState.setStoredTabOverflowMenuExpanded(
              false,
              in: ownerNode,
              invalidationIdentity: context.identity
            )
            TabSelectionState.setStoredFocusedTabIndex(
              nil,
              tags: orderedTags,
              in: ownerNode,
              invalidationIdentity: context.identity,
              certifiedInvalidationIdentities: TabSelectionState.certifiedStripFocusIdentities(
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
        if TabSelectionState.expandFocusedOverflowMenuIfNeeded(
          ownerNode: ownerNode,
          selectedIndex: selectedIndex,
          orderedTags: orderedTags,
          presentation: stylePresentation,
          invalidationIdentity: context.identity
        ) {
          return true
        }
        TabSelectionState.setStoredTabOverflowMenuExpanded(
          false,
          in: ownerNode,
          invalidationIdentity: context.identity
        )
        return TabSelectionState.activateBoundTabSelection(
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
        dormantArchiveLocatorSink: TabDormancy.makeLocatorSink(
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
    return tabStyle.resolveBody(
      configuration: bodyConfiguration,
      in: tabBodyContext
    ).map { child in

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
          TabSelectionState.setStoredTabOverflowMenuExpanded(
            false,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          TabSelectionState.setStoredFocusedTabIndex(
            index,
            tags: orderedTags,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          _ = setBoundSelection(binding, to: orderedTags[index])
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
        let nextExpanded = !TabSelectionState.storedTabOverflowMenuExpanded(in: ownerNode)
        TabSelectionState.setStoredTabOverflowMenuExpanded(
          nextExpanded,
          in: ownerNode,
          invalidationIdentity: context.identity
        )
        if nextExpanded, let focusIndex = overflowPresentation.preferredOverflowFocusIndex {
          TabSelectionState.setStoredFocusedTabIndex(
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
          TabSelectionState.setStoredFocusedTabIndex(
            index,
            tags: orderedTags,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          TabSelectionState.setStoredTabOverflowMenuExpanded(
            false,
            in: ownerNode,
            invalidationIdentity: context.identity
          )
          _ = setBoundSelection(binding, to: orderedTags[index])
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
