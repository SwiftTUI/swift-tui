package enum FocusDirection: Sendable {
  case left
  case right
  case up
  case down
}

/// Maintains the currently focused region and focus traversal order.
public final class FocusTracker {
  public private(set) var focusRegions: [FocusRegion]
  public weak var invalidator: (any Invalidating)?
  public let invalidationIdentities: Set<Identity>

  private var currentIndex: Int?
  private var prefersNoFocus = false
  private var modalRestorationStack: [ModalRestoration] = []
  private var activeModalScopePath: [Identity]?

  public init(
    focusRegions: [FocusRegion] = [],
    invalidationIdentities: Set<Identity> = [
      Identity(components: [] as [IdentityComponent])
    ]
  ) {
    self.focusRegions = focusRegions
    self.invalidationIdentities = invalidationIdentities
    self.currentIndex = focusRegions.isEmpty ? nil : 0
    activeModalScopePath = Self.inferredModalScopePath(in: focusRegions)
  }

  public var currentFocusIdentity: Identity? {
    guard let currentIndex, focusRegions.indices.contains(currentIndex) else {
      return nil
    }
    return focusRegions[currentIndex].identity
  }

  package var isPreservingNoFocus: Bool {
    prefersNoFocus
  }

  package var currentFocusOwnerNodeID: ViewNodeID? {
    currentFocusRegion()?.ownerNodeID
  }

  package var currentFocusOwnerIdentity: Identity? {
    currentFocusRegion()?.ownerIdentity
  }

  /// How many modal focus restorations are currently pending.
  ///
  /// Exposed for stress harnesses that assert the restoration stack drains when
  /// modal owners are recreated. Reading the depth through a declared member
  /// keeps a rename of the underlying storage a compile error.
  package var modalRestorationDepth: Int {
    modalRestorationStack.count
  }

  @discardableResult
  public func updateRegions(_ regions: [FocusRegion]) -> Bool {
    updateRegions(regions, activeModalScopePath: Self.inferredModalScopePath(in: regions))
  }

  @discardableResult
  package func updateRegions(
    _ regions: [FocusRegion], activeModalScopePath nextModal: [Identity]?,
    mountedModalScopePaths: Set<[Identity]>? = nil
  ) -> Bool {
    let previousFocus = currentFocusIdentity
    let previousFocusRegion = currentFocusRegion()
    let restoration = transitionModalScope(
      to: nextModal, mountedScopes: mountedModalScopePaths, previousFocus: previousFocusRegion)
    let restoredIndex = restoration?.focusRegion.flatMap { target in
      regions.firstIndex { $0.identity == target.identity }
    }
    focusRegions = regions

    if let previousFocusRegion,
      let target = previousFocusRegion.collectionFocusTarget,
      let entityIndex = regions.firstIndex(where: {
        $0.ownerIdentity == previousFocusRegion.ownerIdentity
          && $0.collectionFocusTarget?.itemIdentity == target.itemIdentity
      })
    {
      currentIndex = entityIndex
      prefersNoFocus = false
    } else if let previousFocus,
      let preservedIndex = regions.firstIndex(where: { $0.identity == previousFocus })
    {
      currentIndex = preservedIndex
      prefersNoFocus = false
    } else if let restoredIndex {
      currentIndex = restoredIndex
      prefersNoFocus = false
    } else if restoration?.preservesNoFocus == true {
      currentIndex = nil
      prefersNoFocus = true
    } else if let previousFocusRegion,
      let replacementIndex = preferredReplacementIndex(
        for: previousFocusRegion,
        in: regions
      )
    {
      currentIndex = replacementIndex
      prefersNoFocus = false
    } else if prefersNoFocus {
      currentIndex = nil
    } else {
      currentIndex = regions.isEmpty ? nil : collectionEntryIndex(landingAt: 0, in: regions)
    }

    // Initial adoption belongs to the caller's region-resolution pass. Report
    // it so focus-dependent content can settle in that pass, without queuing
    // an additional frame as if an input event had moved established focus.
    if previousFocus == nil {
      return currentFocusIdentity != nil
    }
    return notifyIfFocusChanged(from: previousFocus)
  }

  @discardableResult
  public func focusNext() -> Identity? {
    guard !focusRegions.isEmpty else {
      return nil
    }

    let previousFocus = currentFocusIdentity
    currentIndex = sequentialTraversalIndex(step: 1)
    prefersNoFocus = false

    _ = notifyIfFocusChanged(from: previousFocus)
    return currentFocusIdentity
  }

  @discardableResult
  public func focusPrevious() -> Identity? {
    guard !focusRegions.isEmpty else {
      return nil
    }

    let previousFocus = currentFocusIdentity
    currentIndex = sequentialTraversalIndex(step: -1)
    prefersNoFocus = false

    _ = notifyIfFocusChanged(from: previousFocus)
    return currentFocusIdentity
  }

  /// Authored focus sections visit every descendant. Only a composite
  /// control's own row targets share a sequential stop (STUI-1523).
  private func sequentialTraversalIndex(step: Int) -> Int {
    let count = focusRegions.count
    precondition(count > 0, "sequentialTraversalIndex called with no regions")
    guard let startIndex = currentIndex else {
      return collectionEntryIndex(landingAt: step > 0 ? 0 : count - 1, in: focusRegions)
    }

    var candidate = (startIndex + step + count) % count
    if let owner = focusRegions[startIndex].compositeTraversalOwner {
      while candidate != startIndex, focusRegions[candidate].compositeTraversalOwner == owner {
        candidate = (candidate + step + count) % count
      }
      // A scene containing only this composite keeps its current row. Tab
      // cannot manufacture row navigation or change its active selection.
      if candidate == startIndex { return startIndex }
    }
    return collectionEntryIndex(landingAt: candidate, in: focusRegions)
  }

  /// Where a traversal or initial adoption that lands on `index` takes focus.
  /// Landing on a row of a collection that publishes its active row (the
  /// selection) enters at that row, so the keyboard cursor, the selected-row
  /// chrome and a selection-centred window stay on the selection
  /// (STUI-1290). Otherwise, and when the active row is outside the window,
  /// focus stays where it landed.
  private func collectionEntryIndex(landingAt index: Int, in regions: [FocusRegion]) -> Int {
    let landing = regions[index]
    guard landing.collectionFocusTarget != nil, !landing.isCollectionEntry,
      let owner = landing.ownerIdentity
    else { return index }
    return regions.firstIndex {
      $0.isCollectionEntry && $0.ownerIdentity == owner && $0.ownerNodeID == landing.ownerNodeID
    } ?? index
  }

  @discardableResult
  package func moveFocus(
    _ direction: FocusDirection,
    excluding excludedIdentities: Set<Identity> = []
  ) -> Identity? {
    guard !focusRegions.isEmpty else {
      return nil
    }

    guard
      let currentIndex,
      let currentRegion = currentFocusRegion()
    else {
      switch direction {
      case .left, .up:
        return focusPrevious()
      case .right, .down:
        return focusNext()
      }
    }

    guard
      let nextIndex = directionalCandidateIndex(
        from: currentRegion,
        currentIndex: currentIndex,
        direction: direction,
        excluding: excludedIdentities
      )
    else {
      return currentFocusIdentity
    }

    let previousFocus = currentFocusIdentity
    self.currentIndex = nextIndex
    prefersNoFocus = false

    _ = notifyIfFocusChanged(from: previousFocus)
    return currentFocusIdentity
  }

  @discardableResult
  public func setFocus(
    to identity: Identity?
  ) -> Bool {
    guard let identity else {
      return clearFocus()
    }
    guard let index = focusRegions.firstIndex(where: { $0.identity == identity }) else {
      return false
    }

    let previousFocus = currentFocusIdentity
    currentIndex = index
    prefersNoFocus = false
    return notifyIfFocusChanged(from: previousFocus)
  }

  @discardableResult
  public func clearFocus() -> Bool {
    guard currentFocusIdentity != nil || !prefersNoFocus else {
      return false
    }

    let previousFocus = currentFocusIdentity
    currentIndex = nil
    prefersNoFocus = true
    return notifyIfFocusChanged(from: previousFocus)
  }
}

extension FocusTracker {
  private struct ModalRestoration {
    var modalScopePath: [Identity]
    var focusRegion: FocusRegion?
    var preservesNoFocus: Bool
  }

  private struct DirectionalCandidate {
    var index: Int
    var sharesSection: Bool
    var sharedScopeDepth: Int
    var overlapsOrthogonalAxis: Bool
    var primaryDistance: Int128
    var orthogonalDistance: Int128
    var documentDistance: Int
  }

  /// Distances between focus regions, exact in 128 bits: a region placed by an
  /// extreme offset or frame keeps far geometry (STUI-777), and its doubled
  /// centre or gap overflows `Int` (STUI-1333). In-range distances are the
  /// same values as before.
  private struct DirectionalMetrics {
    var primaryDistance: Int128
    var orthogonalDistance: Int128
    var overlapsOrthogonalAxis: Bool
  }

  private func currentFocusRegion() -> FocusRegion? {
    guard let currentIndex, focusRegions.indices.contains(currentIndex) else {
      return nil
    }
    return focusRegions[currentIndex]
  }

  /// Reconcile the modal lifetime separately from the focused control. Closing
  /// or replacing a surface unwinds its record even if it never had a target.
  /// A replacement inherits the original invoker; a nested modal records the
  /// current target in its still-live parent.
  private func transitionModalScope(
    to next: [Identity]?, mountedScopes: Set<[Identity]>?, previousFocus: FocusRegion?
  ) -> ModalRestoration? {
    guard next != activeModalScopePath else { return nil }
    activeModalScopePath = next
    let retainedCount: Int
    if let next,
      let returningIndex = modalRestorationStack.firstIndex(where: {
        $0.modalScopePath == next
      })
    {
      retainedCount = returningIndex + 1
    } else {
      // Portal entries are siblings in the placed tree even when one was
      // presented from another. The committed census distinguishes suspension
      // from replacement; scope-path prefixes only serve legacy direct callers.
      retainedCount =
        modalRestorationStack.prefix { entry in
          next != nil
            && (mountedScopes?.contains(entry.modalScopePath)
              ?? (next?.starts(with: entry.modalScopePath) == true))
        }.count
    }
    let departing = modalRestorationStack.dropFirst(retainedCount).first
    modalRestorationStack.removeSubrange(retainedCount...)
    if let next, modalRestorationStack.last?.modalScopePath != next {
      let invoker: FocusRegion?
      if let departing { invoker = departing.focusRegion } else { invoker = previousFocus }
      modalRestorationStack.append(
        .init(
          modalScopePath: next,
          focusRegion: invoker,
          preservesNoFocus: departing?.preservesNoFocus ?? prefersNoFocus))
    }
    return departing
  }

  private static func inferredModalScopePath(
    in regions: [FocusRegion]
  ) -> [Identity]? {
    guard
      let firstRegion = regions.first,
      let firstModalScopePath = firstRegion.modalFocusScopePath
    else {
      return nil
    }

    return regions.allSatisfy { $0.modalFocusScopePath == firstModalScopePath }
      ? firstModalScopePath
      : nil
  }

  private func directionalCandidateIndex(
    from currentRegion: FocusRegion,
    currentIndex: Int,
    direction: FocusDirection,
    excluding excludedIdentities: Set<Identity>
  ) -> Int? {
    let candidates = focusRegions.enumerated().compactMap {
      index,
      candidateRegion -> DirectionalCandidate? in
      guard index != currentIndex, !excludedIdentities.contains(candidateRegion.identity) else {
        return nil
      }
      guard
        let metrics = directionalMetrics(
          from: currentRegion.rect,
          to: candidateRegion.rect,
          direction: direction
        )
      else {
        return nil
      }

      return DirectionalCandidate(
        index: index,
        sharesSection: currentRegion.sectionIdentity != nil
          && candidateRegion.sectionIdentity == currentRegion.sectionIdentity,
        sharedScopeDepth: sharedScopePrefixLength(
          between: currentRegion.scopePath,
          and: candidateRegion.scopePath
        ),
        overlapsOrthogonalAxis: metrics.overlapsOrthogonalAxis,
        primaryDistance: metrics.primaryDistance,
        orthogonalDistance: metrics.orthogonalDistance,
        documentDistance: abs(index - currentIndex)
      )
    }

    return candidates.min { lhs, rhs in
      if lhs.sharesSection != rhs.sharesSection {
        return lhs.sharesSection && !rhs.sharesSection
      }
      if lhs.sharedScopeDepth != rhs.sharedScopeDepth {
        return lhs.sharedScopeDepth > rhs.sharedScopeDepth
      }
      if lhs.overlapsOrthogonalAxis != rhs.overlapsOrthogonalAxis {
        return lhs.overlapsOrthogonalAxis && !rhs.overlapsOrthogonalAxis
      }
      if lhs.primaryDistance != rhs.primaryDistance {
        return lhs.primaryDistance < rhs.primaryDistance
      }
      if lhs.orthogonalDistance != rhs.orthogonalDistance {
        return lhs.orthogonalDistance < rhs.orthogonalDistance
      }
      if lhs.documentDistance != rhs.documentDistance {
        return lhs.documentDistance < rhs.documentDistance
      }
      return lhs.index < rhs.index
    }?.index
  }

  private func preferredReplacementIndex(
    for previousRegion: FocusRegion,
    in regions: [FocusRegion]
  ) -> Int? {
    if let sectionIdentity = previousRegion.sectionIdentity,
      let sectionIndex = regions.firstIndex(where: { $0.sectionIdentity == sectionIdentity })
    {
      return sectionIndex
    }

    // A hosted row may leave the viewport while its collection remains. Keep
    // focus with that owner when it is explicitly focusable.
    if let ownerIdentity = previousRegion.ownerIdentity,
      let ownerIndex = regions.firstIndex(where: { $0.identity == ownerIdentity })
    {
      return ownerIndex
    }

    guard !previousRegion.scopePath.isEmpty else {
      return nil
    }

    for prefixLength in stride(from: previousRegion.scopePath.count, through: 1, by: -1) {
      let scopePrefix = Array(previousRegion.scopePath.prefix(prefixLength))
      if let scopeIndex = regions.firstIndex(where: { $0.scopePath.starts(with: scopePrefix) }) {
        return scopeIndex
      }
    }

    return nil
  }

  private func directionalMetrics(
    from current: CellRect,
    to candidate: CellRect,
    direction: FocusDirection
  ) -> DirectionalMetrics? {
    let current = Rect128(current)
    let candidate = Rect128(candidate)
    let currentCenterX = current.x * 2 + current.width
    let currentCenterY = current.y * 2 + current.height
    let candidateCenterX = candidate.x * 2 + candidate.width
    let candidateCenterY = candidate.y * 2 + candidate.height

    switch direction {
    case .left:
      guard candidateCenterX < currentCenterX else {
        return nil
      }
      let orthogonalDistance = verticalGap(between: current, and: candidate)
      return DirectionalMetrics(
        primaryDistance: max(0, current.x - candidate.maxX),
        orthogonalDistance: orthogonalDistance,
        overlapsOrthogonalAxis: orthogonalDistance == 0
      )
    case .right:
      guard candidateCenterX > currentCenterX else {
        return nil
      }
      let orthogonalDistance = verticalGap(between: current, and: candidate)
      return DirectionalMetrics(
        primaryDistance: max(0, candidate.x - current.maxX),
        orthogonalDistance: orthogonalDistance,
        overlapsOrthogonalAxis: orthogonalDistance == 0
      )
    case .up:
      guard candidateCenterY < currentCenterY else {
        return nil
      }
      let orthogonalDistance = horizontalGap(between: current, and: candidate)
      return DirectionalMetrics(
        primaryDistance: max(0, current.y - candidate.maxY),
        orthogonalDistance: orthogonalDistance,
        overlapsOrthogonalAxis: orthogonalDistance == 0
      )
    case .down:
      guard candidateCenterY > currentCenterY else {
        return nil
      }
      let orthogonalDistance = horizontalGap(between: current, and: candidate)
      return DirectionalMetrics(
        primaryDistance: max(0, candidate.y - current.maxY),
        orthogonalDistance: orthogonalDistance,
        overlapsOrthogonalAxis: orthogonalDistance == 0
      )
    }
  }

  /// A focus region's rect widened to 128 bits, where no sum or doubling of
  /// its coordinates can overflow.
  private struct Rect128 {
    let x: Int128
    let y: Int128
    let width: Int128
    let height: Int128

    init(_ rect: CellRect) {
      x = Int128(rect.origin.x)
      y = Int128(rect.origin.y)
      width = Int128(rect.size.width)
      height = Int128(rect.size.height)
    }

    var maxX: Int128 { x + width }
    var maxY: Int128 { y + height }
  }

  private func sharedScopePrefixLength(
    between lhs: [Identity],
    and rhs: [Identity]
  ) -> Int {
    zip(lhs, rhs).prefix { left, right in
      left == right
    }.count
  }

  private func horizontalGap(
    between lhs: Rect128,
    and rhs: Rect128
  ) -> Int128 {
    if lhs.maxX <= rhs.x {
      return rhs.x - lhs.maxX
    }
    if rhs.maxX <= lhs.x {
      return lhs.x - rhs.maxX
    }
    return 0
  }

  private func verticalGap(
    between lhs: Rect128,
    and rhs: Rect128
  ) -> Int128 {
    if lhs.maxY <= rhs.y {
      return rhs.y - lhs.maxY
    }
    if rhs.maxY <= lhs.y {
      return lhs.y - rhs.maxY
    }
    return 0
  }

  @discardableResult
  private func notifyIfFocusChanged(
    from previousFocus: Identity?
  ) -> Bool {
    let currentFocusIdentity = currentFocusIdentity
    guard previousFocus != currentFocusIdentity else {
      return false
    }
    let affectedIdentities = Set(
      [previousFocus, currentFocusIdentity]
        .compactMap { $0 }
    )
    invalidator?.requestInvalidation(
      of: affectedIdentities.isEmpty ? invalidationIdentities : affectedIdentities
    )
    return true
  }
}
