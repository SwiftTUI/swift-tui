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
  package static let hostComponent = "PortalHost"
  package static let overlaysComponent = "overlays"
  package static let entryPrefix = "entry:"

  /// The identity component naming one overlay entry.
  package static func entryComponent(id: String) -> String {
    entryPrefix + id
  }

  /// The overlays host identity under a portal root.
  package static func hostIdentity(portalRootIdentity: Identity) -> Identity {
    portalRootIdentity
      .child(hostComponent)
      .child(overlaysComponent)
  }

  /// The full identity of one overlay entry under a portal root.
  package static func entryIdentity(
    portalRootIdentity: Identity,
    entryID: String
  ) -> Identity {
    hostIdentity(portalRootIdentity: portalRootIdentity)
      .child(entryComponent(id: entryID))
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
      identity.components.dropFirst(portalRootIdentity.components.count)
    )
    guard entryRootOnly ? suffix.count == 3 : suffix.count >= 3 else {
      return false
    }
    return suffix[0] == hostComponent
      && suffix[1] == overlaysComponent
      && suffix[2].hasPrefix(entryPrefix)
  }
}
