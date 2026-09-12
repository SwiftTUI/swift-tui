@_spi(Testing) import SwiftTUICore

/// Owns tab selection, strip focus and overflow slot policy. State stays on
/// the graph owner so ordinary checkpoint/rollback covers these operations.
@MainActor
enum TabSelectionState {
  static func resolvedFocusedTabIndex(
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

  static func moveStoredTabFocus(
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

  static func expandFocusedOverflowMenuIfNeeded(
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

  static func moveStoredOverflowMenuFocus(
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

  static func activateBoundTabSelection<SelectionValue: Hashable>(
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

  private static let tabFocusedIndexStateSlot = StateSlotOrdinals.tabFocusedIndex
  private static let tabOverflowMenuExpandedStateSlot = StateSlotOrdinals.tabOverflowMenuExpanded
  private static let tabOptionSignatureStateSlot = StateSlotOrdinals.tabOptionSignature
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

  static func storedFocusedTabIndex(
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

  static func setStoredFocusedTabIndex(
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
  static func certifiedStripFocusIdentities(
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
  static func stripFocusInvalidationIdentities(
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

  static func storedTabOverflowMenuExpanded(
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

  static func setStoredTabOverflowMenuExpanded(
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

  static func updateOptions(
    in ownerNode: SwiftTUICore.ViewNode?, tags: [SelectionTag], labels: [TabItemLabel]
  )
    -> Bool
  {
    let signature = TabOptionSignature(tags: tags, labels: labels)
    let previous =
      ownerNode?.stateSlot(ordinal: tabOptionSignatureStateSlot, seed: nil as TabOptionSignature?)
      ?? nil
    if previous != signature {
      ownerNode?.setStateSlotSilently(
        ordinal: tabOptionSignatureStateSlot, value: signature as TabOptionSignature?)
    }
    return previous != nil && previous != signature
  }

  static func resetOverflow(in ownerNode: SwiftTUICore.ViewNode?) {
    ownerNode?.setStateSlotSilently(ordinal: tabOverflowMenuExpandedStateSlot, value: false)
  }
}
