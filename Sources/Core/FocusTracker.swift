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

  public init(
    focusRegions: [FocusRegion] = [],
    invalidationIdentities: Set<Identity> = [Identity(components: [])]
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
    focusRegions = regions

    if let previousFocus,
      let preservedIndex = regions.firstIndex(where: { $0.identity == previousFocus })
    {
      currentIndex = preservedIndex
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
    if let currentIndex {
      self.currentIndex = (currentIndex + 1) % focusRegions.count
    } else {
      currentIndex = 0
    }
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
    if let currentIndex {
      self.currentIndex = (currentIndex - 1 + focusRegions.count) % focusRegions.count
    } else {
      currentIndex = focusRegions.count - 1
    }
    prefersNoFocus = false

    _ = notifyIfFocusChanged(from: previousFocus)
    return currentFocusIdentity
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
    from current: Rect,
    to candidate: Rect,
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
    between lhs: Rect,
    and rhs: Rect
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
    between lhs: Rect,
    and rhs: Rect
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
