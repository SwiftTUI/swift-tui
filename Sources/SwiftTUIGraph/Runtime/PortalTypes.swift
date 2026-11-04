/// The modifier or item that owns a portal attachment.
package enum PresentationToken: Hashable, Sendable, CustomStringConvertible {
  package enum Family: String, Sendable {
    case alert, confirmationDialog, menu, sheet, fullScreenCover, popover, popoverTip
  }
  case family(Family)
  case item(Family, AnyID)
  case toast(ordinal: Int)
  case imperative(String)

  package var description: String {
    switch self {
    case .family(let family): family.rawValue
    case .item(let family, let value): "\(family.rawValue):\(value.reflectedValue)"
    case .toast(let ordinal): ordinal == 0 ? "toast" : "toast[\(ordinal)]"
    case .imperative(let name): name
    }
  }
}

/// Stable identity for content declared in one subtree and hosted by a portal root.
package struct PortalEntryID: Hashable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible, ExpressibleByStringLiteral
{
  package init(stringLiteral value: String) { self = .imperative(value) }

  package static func imperative(_ id: String) -> Self {
    Self(
      sourceIdentity: Identity(components: ["__ImperativePresentation", id]), token: .imperative(id)
    )
  }

  /// Structural IDs historically reflected the caller's string when minting ForEach paths.
  package var debugDescription: String {
    if case .imperative(let name) = token { return String(reflecting: name) }
    return String(reflecting: description)
  }

  package var sourceIdentity: Identity
  package var sourceStructuralPath: StructuralPath
  package var sourceEntityIdentity: EntityIdentity?
  package var token: PresentationToken

  package init(
    sourceIdentity: Identity,
    sourceStructuralPath: StructuralPath? = nil,
    sourceEntityIdentity: EntityIdentity? = nil,
    token: PresentationToken
  ) {
    self.sourceIdentity = sourceIdentity
    self.sourceStructuralPath = sourceStructuralPath ?? StructuralPath(identity: sourceIdentity)
    self.sourceEntityIdentity = sourceEntityIdentity
    self.token = token
  }

  /// A declaration keeps its activation when its entity moves to another slot.
  /// Without an entity, the declaring node's identity is the lifetime boundary.
  package static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs.token == rhs.token, lhs.sourceEntityIdentity == rhs.sourceEntityIdentity else {
      return false
    }
    return lhs.sourceEntityIdentity != nil || lhs.sourceIdentity == rhs.sourceIdentity
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(token)
    hasher.combine(sourceEntityIdentity)
    if sourceEntityIdentity == nil { hasher.combine(sourceIdentity) }
  }

  package func hasSameAttachment(as other: Self) -> Bool {
    self == other && sourceIdentity == other.sourceIdentity
      && sourceStructuralPath == other.sourceStructuralPath
  }

  package var description: String {
    if let sourceEntityIdentity {
      return "entity:\(sourceEntityIdentity.scopedDescription)#\(token)"
    }
    return "\(sourceIdentity.path)#\(token)"
  }

  package enum OwnerKey: Hashable, Sendable, CustomStringConvertible {
    case entity(EntityIdentity, token: PresentationToken)
    case source(StructuralPath, token: PresentationToken)

    package var description: String {
      switch self {
      case .entity(let entity, let token): "entity:\(entity.scopedDescription)#\(token)"
      case .source(let path, let token): "source:\(path)#\(token)"
      }
    }
  }

  package var ownerStableKey: OwnerKey {
    if let sourceEntityIdentity { return .entity(sourceEntityIdentity, token: token) }
    return .source(sourceStructuralPath, token: token)
  }

  package var placementStableKey: String {
    "entry:\(sourceStructuralPath.description)#\(token)"
  }

  package func declarationOwnerEdge(
    placementRoot: StructuralPath
  ) -> DeclarationOwnerEdge {
    DeclarationOwnerEdge(
      sourceIdentity: sourceIdentity,
      sourceStructuralPath: sourceStructuralPath,
      sourceEntityIdentity: sourceEntityIdentity,
      placementRoot: placementRoot,
      token: token
    )
  }
}

/// Typed back-edge from a placed portal entry to the node that declared it.
package struct DeclarationOwnerEdge: Hashable, Sendable {
  package var sourceIdentity: Identity
  package var sourceStructuralPath: StructuralPath
  package var sourceEntityIdentity: EntityIdentity?
  package var placementRoot: StructuralPath
  package var token: PresentationToken

  package init(
    sourceIdentity: Identity,
    sourceStructuralPath: StructuralPath,
    sourceEntityIdentity: EntityIdentity?,
    placementRoot: StructuralPath,
    token: PresentationToken
  ) {
    self.sourceIdentity = sourceIdentity
    self.sourceStructuralPath = sourceStructuralPath
    self.sourceEntityIdentity = sourceEntityIdentity
    self.placementRoot = placementRoot
    self.token = token
  }
}

/// Whether an overlay should leave base interaction available.
package enum PortalModalPolicy: Equatable, Sendable {
  case nonModal
  case disablesBaseInteraction
}

/// Shared ordering key for painting, hit testing, and Escape dismissal.
/// Activation recency crosses family boundaries so a nested presentation
/// appears above its presenter. Family priority breaks activation ties.
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
  if lhs.activationOrdinal != rhs.activationOrdinal {
    return lhs.activationOrdinal < rhs.activationOrdinal
  }
  if lhs.zIndex != rhs.zIndex {
    return lhs.zIndex < rhs.zIndex
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
