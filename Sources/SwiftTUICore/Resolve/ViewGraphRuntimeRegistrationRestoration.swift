@MainActor
package enum ViewGraphRuntimeRegistrationRestorer {
  package static func restoreLiveIdentities(
    _ identities: Set<Identity>,
    into registrations: RuntimeRegistrationSet,
    nodesByIdentity: [Identity: ViewNode]
  ) {
    for identity in identities.sorted() {
      nodesByIdentity[identity]?.restoreOwnRuntimeRegistrations(into: registrations)
    }
  }

  package static func restoreResolvedSubtree(
    _ resolved: ResolvedNode,
    into registrations: RuntimeRegistrationSet,
    nodesByIdentity: [Identity: ViewNode],
    registrationAliasesByIdentity: [Identity: Set<Identity>]
  ) {
    guard let node = nodesByIdentity[resolved.identity] else {
      return
    }

    node.restoreOwnRuntimeRegistrations(
      into: registrations
    )
    for aliasIdentity in registrationAliasesByIdentity[resolved.identity] ?? [] {
      nodesByIdentity[aliasIdentity]?.restoreOwnRuntimeRegistrations(
        into: registrations
      )
    }

    for child in resolved.children {
      restoreResolvedSubtree(
        child,
        into: registrations,
        nodesByIdentity: nodesByIdentity,
        registrationAliasesByIdentity: registrationAliasesByIdentity
      )
    }
  }
}
