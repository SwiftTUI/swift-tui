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

  public init(
    focusRegions: [FocusRegion] = [],
    invalidationIdentities: Set<Identity> = [
      Identity(components: [] as [IdentityComponent])
    ]
  ) {
    self.focusRegions = focusRegions
    self.invalidationIdentities = invalidationIdentities
    self.currentIndex = focusRegions.isEmpty ? nil : 0
  }

  public var currentFocusIdentity: Identity? {
    guard let currentIndex, focusRegions.indices.contains(currentIndex) else {
      return nil
    }
    return focusRegions[currentIndex].identity
  }

  @discardableResult
  public func updateRegions(_ regions: [FocusRegion]) -> Bool {
    let previousFocus = currentFocusIdentity
    let previousFocusRegion = currentFocusRegion()
    let wasPreservingNoFocus = prefersNoFocus
    recordModalRestorationIfNeeded(
      previousFocusRegion: previousFocusRegion,
      nextRegions: regions
    )
    let modalRestoration = modalRestorationCandidate(
      previousFocusRegion: previousFocusRegion,
      nextRegions: regions
    )
    focusRegions = regions

    if let previousFocus,
      let preservedIndex = regions.firstIndex(where: { $0.identity == previousFocus })
    {
      currentIndex = preservedIndex
      prefersNoFocus = false
    } else if let modalRestoration {
      currentIndex = modalRestoration.regionIndex
      prefersNoFocus = false
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
      currentIndex = regions.isEmpty ? nil : 0
    }
    pruneModalRestorationStack(
      previousFocusRegion: previousFocusRegion,
      nextRegions: regions,
      consumedIndex: modalRestoration?.stackIndex
    )

    // Keep the initial automatic focus adoption as runtime state without forcing an
    // immediate second frame before the user has interacted.
    if previousFocus == nil,
      !wasPreservingNoFocus,
      currentFocusIdentity != nil
    {
      return false
    }

    return notifyIfFocusChanged(from: previousFocus)
  }

  @discardableResult
  public func focusNext() -> Identity? {
    guard !focusRegions.isEmpty else {
      return nil
    }

    let previousFocus = currentFocusIdentity
    currentIndex = indexEscapingCurrentSection(step: 1)
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
    currentIndex = indexEscapingCurrentSection(step: -1)
    prefersNoFocus = false

    _ = notifyIfFocusChanged(from: previousFocus)
    return currentFocusIdentity
  }

  /// Computes the next (or previous) focus index for linear traversal,
  /// skipping past every region that shares the current focus region's
  /// `sectionIdentity`.
  ///
  /// When the current focus has a non-nil `sectionIdentity`, linear
  /// traversal walks past every region belonging to that section before
  /// landing, so one `Tab` press escapes the entire section instead of
  /// stepping through each member. Regions outside a section, or
  /// degenerate cases where every region shares the same section,
  /// continue to advance one step at a time.
  ///
  /// - Parameter step: `+1` for `focusNext`, `-1` for `focusPrevious`.
  private func indexEscapingCurrentSection(step: Int) -> Int {
    let count = focusRegions.count
    precondition(count > 0, "indexEscapingCurrentSection called with no regions")
    guard let startIndex = currentIndex else {
      return step > 0 ? 0 : count - 1
    }

    let linearNext = (startIndex + step + count) % count
    guard let section = focusRegions[startIndex].sectionIdentity else {
      return linearNext
    }

    // Walk forward (or backward) past every region that shares the
    // current section. Cap the walk at `count` iterations so a tree
    // where every region happens to sit in the same section still
    // advances — in that degenerate case we fall back to a single
    // linear step so focus at least cycles within the section.
    var candidate = linearNext
    var steps = 0
    while steps < count, focusRegions[candidate].sectionIdentity == section {
      candidate = (candidate + step + count) % count
      steps += 1
    }

    if focusRegions[candidate].sectionIdentity == section {
      return linearNext
    }
    return candidate
  }

  @discardableResult
  package func moveFocus(
    _ direction: FocusDirection
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
        direction: direction
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
    var focusRegion: FocusRegion
  }

  private struct ModalRestorationCandidate {
    var stackIndex: Int
    var regionIndex: Int
  }

  private struct DirectionalCandidate {
    var index: Int
    var sharesSection: Bool
    var sharedScopeDepth: Int
    var overlapsOrthogonalAxis: Bool
    var primaryDistance: Int
    var orthogonalDistance: Int
    var documentDistance: Int
  }

  private struct DirectionalMetrics {
    var primaryDistance: Int
    var orthogonalDistance: Int
    var overlapsOrthogonalAxis: Bool
  }

  private func currentFocusRegion() -> FocusRegion? {
    guard let currentIndex, focusRegions.indices.contains(currentIndex) else {
      return nil
    }
    return focusRegions[currentIndex]
  }

  private func recordModalRestorationIfNeeded(
    previousFocusRegion: FocusRegion?,
    nextRegions: [FocusRegion]
  ) {
    guard
      let previousFocusRegion,
      let nextModalScopePath = activeModalScopePath(in: nextRegions),
      previousFocusRegion.modalFocusScopePath != nextModalScopePath,
      !nextRegions.contains(where: { $0.identity == previousFocusRegion.identity })
    else {
      return
    }

    if modalRestorationStack.last?.modalScopePath == nextModalScopePath {
      modalRestorationStack.removeLast()
    }
    modalRestorationStack.append(
      ModalRestoration(
        modalScopePath: nextModalScopePath,
        focusRegion: previousFocusRegion
      )
    )
  }

  private func modalRestorationCandidate(
    previousFocusRegion: FocusRegion?,
    nextRegions: [FocusRegion]
  ) -> ModalRestorationCandidate? {
    guard
      let previousModalScopePath = previousFocusRegion?.modalFocusScopePath,
      activeModalScopePath(in: nextRegions) != previousModalScopePath,
      let stackIndex = modalRestorationStack.lastIndex(where: { restoration in
        restoration.modalScopePath == previousModalScopePath
          && nextRegions.contains { $0.identity == restoration.focusRegion.identity }
      })
    else {
      return nil
    }

    guard
      let regionIndex = nextRegions.firstIndex(
        where: { $0.identity == modalRestorationStack[stackIndex].focusRegion.identity }
      )
    else {
      return nil
    }

    return ModalRestorationCandidate(stackIndex: stackIndex, regionIndex: regionIndex)
  }

  private func pruneModalRestorationStack(
    previousFocusRegion: FocusRegion?,
    nextRegions: [FocusRegion],
    consumedIndex: Int?
  ) {
    if let consumedIndex {
      modalRestorationStack.remove(at: consumedIndex)
    }

    guard
      let previousModalScopePath = previousFocusRegion?.modalFocusScopePath,
      activeModalScopePath(in: nextRegions) != previousModalScopePath
    else {
      return
    }

    modalRestorationStack.removeAll { $0.modalScopePath == previousModalScopePath }
  }

  private func activeModalScopePath(
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
    direction: FocusDirection
  ) -> Int? {
    let candidates = focusRegions.enumerated().compactMap {
      index,
      candidateRegion -> DirectionalCandidate? in
      guard index != currentIndex else {
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
    let currentCenterX = current.origin.x * 2 + current.size.width
    let currentCenterY = current.origin.y * 2 + current.size.height
    let candidateCenterX = candidate.origin.x * 2 + candidate.size.width
    let candidateCenterY = candidate.origin.y * 2 + candidate.size.height

    switch direction {
    case .left:
      guard candidateCenterX < currentCenterX else {
        return nil
      }
      let orthogonalDistance = verticalGap(between: current, and: candidate)
      return DirectionalMetrics(
        primaryDistance: max(
          0,
          current.origin.x - (candidate.origin.x + candidate.size.width)
        ),
        orthogonalDistance: orthogonalDistance,
        overlapsOrthogonalAxis: orthogonalDistance == 0
      )
    case .right:
      guard candidateCenterX > currentCenterX else {
        return nil
      }
      let orthogonalDistance = verticalGap(between: current, and: candidate)
      return DirectionalMetrics(
        primaryDistance: max(
          0,
          candidate.origin.x - (current.origin.x + current.size.width)
        ),
        orthogonalDistance: orthogonalDistance,
        overlapsOrthogonalAxis: orthogonalDistance == 0
      )
    case .up:
      guard candidateCenterY < currentCenterY else {
        return nil
      }
      let orthogonalDistance = horizontalGap(between: current, and: candidate)
      return DirectionalMetrics(
        primaryDistance: max(
          0,
          current.origin.y - (candidate.origin.y + candidate.size.height)
        ),
        orthogonalDistance: orthogonalDistance,
        overlapsOrthogonalAxis: orthogonalDistance == 0
      )
    case .down:
      guard candidateCenterY > currentCenterY else {
        return nil
      }
      let orthogonalDistance = horizontalGap(between: current, and: candidate)
      return DirectionalMetrics(
        primaryDistance: max(
          0,
          candidate.origin.y - (current.origin.y + current.size.height)
        ),
        orthogonalDistance: orthogonalDistance,
        overlapsOrthogonalAxis: orthogonalDistance == 0
      )
    }
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
    between lhs: CellRect,
    and rhs: CellRect
  ) -> Int {
    let lhsMaxX = lhs.origin.x + lhs.size.width
    let rhsMaxX = rhs.origin.x + rhs.size.width
    if lhsMaxX <= rhs.origin.x {
      return rhs.origin.x - lhsMaxX
    }
    if rhsMaxX <= lhs.origin.x {
      return lhs.origin.x - rhsMaxX
    }
    return 0
  }

  private func verticalGap(
    between lhs: CellRect,
    and rhs: CellRect
  ) -> Int {
    let lhsMaxY = lhs.origin.y + lhs.size.height
    let rhsMaxY = rhs.origin.y + rhs.size.height
    if lhsMaxY <= rhs.origin.y {
      return rhs.origin.y - lhsMaxY
    }
    if rhsMaxY <= lhs.origin.y {
      return lhs.origin.y - rhsMaxY
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
