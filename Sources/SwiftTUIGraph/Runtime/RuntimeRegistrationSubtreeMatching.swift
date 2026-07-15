// The two shared subtree-root matchers for registry teardown. Three matching
// families exist deliberately — collapsing their semantics is NOT safe:
//
// 1. Owner-key matching (`RuntimeRegistrationOwnerKey.matchesAnySubtreeRoot`)
//    follows the explicitly persisted owner identity. Pointer/hover may choose
//    an authored owner identity distinct from the registry key; other families
//    use their registration identity.
// 2. `focusRegistrationMatchesAnySubtreeRoot` below adds the recording node's
//    identity for focus snapshots published at detached identities — the
//    ordinary owner-key families do not adopt that publisher-lifetime rule
//    (the F04 stacking finding).
// 3. `identityMatchesAnySubtreeRoot` below is the bare identity-prefix match
//    for the families keyed only by their own registration identity
//    (scroll position, lifecycle, preference observation).

/// Matches a registered identity against subtree-removal roots by identity
/// prefix: the identity is the root itself or any descendant of it.
package func identityMatchesAnySubtreeRoot(
  _ identity: Identity,
  roots: [Identity]
) -> Bool {
  roots.contains { root in
    identity == root || identity.isDescendant(of: root)
  }
}

/// Matches a focus registration against subtree-removal roots by its
/// registered identity AND by the identity of the node that recorded it. The
/// owner match is what clears registrations published at detached identities
/// (an exact `.id(_:)`) when their publisher is re-evaluated — the scoped
/// restore re-appends the publisher's snapshots, so a removal that misses
/// them stacks one copy per scoped commit.
package func focusRegistrationMatchesAnySubtreeRoot(
  identity: Identity,
  ownerIdentity: Identity?,
  roots: [Identity]
) -> Bool {
  roots.contains { root in
    identity == root || identity.isDescendant(of: root)
      || ownerIdentity == root
      || ownerIdentity?.isDescendant(of: root) == true
  }
}
