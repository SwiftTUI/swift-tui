/// Stable identity for content declared in one subtree and hosted by a portal root.
package struct PortalEntryID: Hashable, Sendable, CustomStringConvertible {
  package var sourceIdentity: Identity
  package var token: String

  package init(
    sourceIdentity: Identity,
    token: String
  ) {
    self.sourceIdentity = sourceIdentity
    self.token = token
  }

  package var description: String {
    "\(sourceIdentity.path)#\(token)"
  }
}

/// Whether an overlay should leave base interaction available.
package enum PortalModalPolicy: Equatable, Sendable {
  case nonModal
  case disablesBaseInteraction
}

/// Deterministic ordering key shared by drawing and Escape dismissal.
package struct PortalOrdering: Equatable, Sendable {
  package var zIndex: Int
  package var activationOrdinal: Int
  package var stableTieBreaker: String

  package init(
    zIndex: Int,
    activationOrdinal: Int,
    stableTieBreaker: String
  ) {
    self.zIndex = zIndex
    self.activationOrdinal = activationOrdinal
    self.stableTieBreaker = stableTieBreaker
  }
}

package func portalOrderingPrecedes(
  _ lhs: PortalOrdering,
  _ rhs: PortalOrdering
) -> Bool {
  if lhs.zIndex != rhs.zIndex {
    return lhs.zIndex < rhs.zIndex
  }
  if lhs.activationOrdinal != rhs.activationOrdinal {
    return lhs.activationOrdinal < rhs.activationOrdinal
  }
  return lhs.stableTieBreaker < rhs.stableTieBreaker
}

package func portalOrderingIsAbove(
  _ lhs: PortalOrdering,
  _ rhs: PortalOrdering
) -> Bool {
  portalOrderingPrecedes(rhs, lhs)
}

/// Dismiss route for an overlay entry.
package struct DismissStackEntry<ID: Hashable & Sendable>: Sendable {
  package var id: ID
  package var ordering: PortalOrdering
  package var acceptsEscape: Bool
  package var dismiss: @MainActor @Sendable () -> Void

  package init(
    id: ID,
    ordering: PortalOrdering,
    acceptsEscape: Bool,
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    self.id = id
    self.ordering = ordering
    self.acceptsEscape = acceptsEscape
    self.dismiss = dismiss
  }
}
