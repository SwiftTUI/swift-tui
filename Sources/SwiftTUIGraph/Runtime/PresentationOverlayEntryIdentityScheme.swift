package enum PresentationOverlayKind: String, Hashable, Sendable {
  case alert = "AlertPresentation"
  case confirmationDialog = "ConfirmationDialogPresentation"
  case sheet = "SheetPresentation"
  case popover = "PopoverPresentation"
  case menu = "MenuPresentation"
  case toast = "ToastPresentation"
}

package enum OverlayEntryKey: Hashable, Sendable, CustomStringConvertible {
  case presentation(PresentationOverlayKind, PortalEntryID.OwnerKey)
  case unowned(String)

  package var description: String {
    switch self {
    case .presentation(let kind, let owner): "\(kind.rawValue):\(owner)"
    case .unowned(let name): name
    }
  }

  package var component: IdentityComponent { .overlayEntry(description) }
}

/// The single source of the presentation overlay-entry identity scheme
/// (F168). Three subsystems must agree byte-for-byte on how an overlay
/// entry's identity is spelled under a portal root — the Views-side mint
/// (`OverlayStack`), the runtime re-derivation
/// (`DefaultRendererFrameHeadCoordinator`), and the graph-side matchers
/// (`ViewGraph`'s portal invalidation translation). They were hand-mirrored
/// copies; a drift in any one silently broke portal invalidation targeting.
///
/// The scheme: `<portalRoot>/PortalHost/overlays/entry:<id>`.
package enum PresentationOverlayEntryIdentityScheme {
  package static let hostComponent = IdentityComponent.named("PortalHost")
  package static let overlaysComponent = IdentityComponent.named("overlays")

  /// The overlays host identity under a portal root.
  package static func hostIdentity(portalRootIdentity: Identity) -> Identity {
    portalRootIdentity
      .child(hostComponent)
      .child(overlaysComponent)
  }

  /// The full identity of one overlay entry under a portal root.
  package static func entryIdentity(
    portalRootIdentity: Identity,
    entryID: OverlayEntryKey
  ) -> Identity {
    hostIdentity(portalRootIdentity: portalRootIdentity)
      .child(entryID.component)
  }

  /// Whether `identity` names an overlay entry — or, with
  /// `entryRootOnly: false`, any descendant of one — under `portalRootIdentity`.
  package static func isEntryIdentity(
    _ identity: Identity,
    portalRootIdentity: Identity,
    entryRootOnly: Bool
  ) -> Bool {
    guard identity.isDescendant(of: portalRootIdentity) else {
      return false
    }
    let suffix = Array(
      identity.typedComponents.dropFirst(portalRootIdentity.typedComponents.count)
    )
    guard entryRootOnly ? suffix.count == 3 : suffix.count >= 3 else {
      return false
    }
    return suffix[0] == hostComponent
      && suffix[1] == overlaysComponent
      && suffix[2].isOverlayEntry
  }
}
