package struct ScrollOffset: Equatable, Sendable {
  package var x: Int
  package var y: Int

  package init(
    x: Int = 0,
    y: Int = 0
  ) {
    self.x = x
    self.y = y
  }

  package static let zero = Self()
}

package struct ScrollPositionRegistrationSnapshot {
  package var identity: Identity
  package var currentOffset: @MainActor () -> ScrollOffset
  package var applyOffset: @MainActor (ScrollOffset) -> Void

  package init(
    identity: Identity,
    currentOffset: @escaping @MainActor () -> ScrollOffset,
    applyOffset: @escaping @MainActor (ScrollOffset) -> Void
  ) {
    self.identity = identity
    self.currentOffset = currentOffset
    self.applyOffset = applyOffset
  }
}

@MainActor
package final class LocalScrollPositionRegistry: Equatable {
  private var registrations: [Identity: ScrollPositionRegistrationSnapshot] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalScrollPositionRegistry,
    rhs: LocalScrollPositionRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    currentOffset: @escaping @MainActor () -> ScrollOffset,
    applyOffset: @escaping @MainActor (ScrollOffset) -> Void
  ) {
    let registration = ScrollPositionRegistrationSnapshot(
      identity: identity,
      currentOffset: currentOffset,
      applyOffset: applyOffset
    )
    registrations[identity] = registration
    ViewNodeContext.current?.recordScrollPositionRegistration(registration)
  }

  @discardableResult
  package func sync(
    focusedIdentity: Identity?,
    focusRegions: [FocusRegion],
    scrollRoutes: [ScrollRoute]
  ) -> Bool {
    guard let focusedIdentity,
      let focusedRegion = focusRegions.first(where: { $0.identity == focusedIdentity })
    else {
      return false
    }

    for route in scrollRoutes.reversed()
    where route.identity.isAncestor(of: focusedIdentity) {
      guard let registration = registrations[route.identity] else {
        continue
      }

      let currentOffset = registration.currentOffset()
      let adjustedOffset = adjustedOffset(
        currentOffset,
        revealing: focusedRegion.rect,
        in: route
      )
      guard adjustedOffset != currentOffset else {
        continue
      }

      registration.applyOffset(adjustedOffset)
      return true
    }

    return false
  }

  package func reset() {
    registrations.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    for identity in registrations.keys.filter({
      identityMatchesAnySubtreeRoot($0, roots: roots)
    }) {
      registrations.removeValue(forKey: identity)
    }
  }

  package func snapshot() -> [ScrollPositionRegistrationSnapshot] {
    Array(registrations.values)
  }

  package func restore(_ snapshot: [ScrollPositionRegistrationSnapshot]) {
    guard !snapshot.isEmpty else {
      return
    }

    for registration in snapshot {
      registrations[registration.identity] = registration
    }
  }

  private func adjustedOffset(
    _ currentOffset: ScrollOffset,
    revealing focusRect: Rect,
    in route: ScrollRoute
  ) -> ScrollOffset {
    var next = currentOffset

    if focusRect.origin.x < route.viewportRect.origin.x {
      next.x += focusRect.origin.x - route.viewportRect.origin.x
    } else if focusRect.maxX > route.viewportRect.maxX {
      next.x += focusRect.maxX - route.viewportRect.maxX
    }

    if focusRect.origin.y < route.viewportRect.origin.y {
      next.y += focusRect.origin.y - route.viewportRect.origin.y
    } else if focusRect.maxY > route.viewportRect.maxY {
      next.y += focusRect.maxY - route.viewportRect.maxY
    }

    next.x = clampedOffset(
      next.x,
      contentLength: route.contentBounds.size.width,
      viewportLength: route.viewportRect.size.width
    )
    next.y = clampedOffset(
      next.y,
      contentLength: route.contentBounds.size.height,
      viewportLength: route.viewportRect.size.height
    )
    return next
  }

  private func clampedOffset(
    _ offset: Int,
    contentLength: Int,
    viewportLength: Int
  ) -> Int {
    min(max(0, offset), max(0, contentLength - viewportLength))
  }
}

private func identityMatchesAnySubtreeRoot(
  _ identity: Identity,
  roots: [Identity]
) -> Bool {
  roots.contains { root in
    identity == root || identity.isDescendant(of: root)
  }
}
