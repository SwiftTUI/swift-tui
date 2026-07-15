// Entity routing and identity adoption, extracted from ViewGraph.swift
// (F115): the five identity/entity-adoption policies of
// `nodeForIdentity(for:entityIdentity:)` (entity re-route, same-entity
// re-bind, duplicate-occurrence minting, flattened-state-owner tiebreak,
// fresh mint), the flattened-state-owner lookup, entity binding/collection,
// and the frame-barrier release/prune of entity routes (the Stage 6
// deferred-removal contract). Consumes ViewGraph's module-internal state
// accessors; the guard order inside `nodeForIdentity` is load-bearing.

extension ViewGraph {
  func nodeForIdentity(
    for identity: Identity,
    entityIdentity: EntityIdentity? = nil
  ) -> ViewNode {
    var displacedOccupant = false
    if let entityIdentity,
      let routedNodeID = entityRoutingTable.route(entityIdentity)
    {
      if let routedNode = nodeIfExists(for: routedNodeID) {
        // Re-routing moves the node to a new `Identity`. Clear the old
        // identity's index entry so nothing else resolving at the old
        // (possibly aliased) identity this frame adopts the moved node — that
        // would wire it as a child inside its own subtree (a children-graph
        // cycle). The node's own resolved identity is spared, mirroring
        // `reindexIdentity`: it is position-independent (an explicit-id
        // re-root resolves the same stable identity at every position), stays
        // correct across the move, and identity-keyed lookups (`onChange`'s
        // previous-value owner) read it mid-resolve, before the apply would
        // restore it.
        if let previousIdentity = identityByNodeID[routedNodeID],
          previousIdentity != identity,
          previousIdentity != routedNode.resolvedIdentity,
          nodeIDByIdentity[previousIdentity] == routedNodeID
        {
          nodeIDByIdentity.removeValue(forKey: previousIdentity)
        }
        nodeIDByIdentity[identity] = routedNodeID
        identityByNodeID[routedNodeID] = identity
        bindEntityRoute(entityIdentity, to: routedNodeID)
        if identity != routedNode.identity {
          // Adopted across identities: the committed value's positional stamp
          // pairing is unverified against whatever children this position
          // resolves next — withdraw the fast-path claim.
          routedNode.withdrawCommittedStampClaim()
        }
        return routedNode
      }
      releaseEntityRoute(for: routedNodeID)
    }

    if let existing = nodeIfExists(for: identity) {
      if let entityIdentity {
        let existingEntityIdentity =
          existing.committed.entityIdentity
          ?? entityRoutingTable.entityByNodeID[existing.viewNodeID]
        if existingEntityIdentity == entityIdentity {
          bindEntityRoute(entityIdentity, to: existing.viewNodeID)
          return existing
        }
        // A different entity (or none) occupies this `Identity` slot. A
        // duplicate-occurrence sibling (`occurrence > 0`, e.g. the second `7`
        // in `ForEach([7, 7])`) shares an `Identity` with the primary
        // (`occurrence == 0`) sibling but is a *distinct* runtime lifetime: it
        // must not adopt or evict the primary's node. Fall through to mint a
        // fresh `ViewNodeID` so duplicate-id siblings get independent
        // `@State`/lifecycle (G13). Cross-frame reuse of each occurrence is
        // handled above by the entity route; this fallback only runs on first
        // allocation, so the `nodeIDByIdentity` index landing on the
        // last-resolved occurrence is acceptable — the node store
        // (`nodesByNodeID`), entity routing, and parent→child teardown all
        // track both siblings.
        if entityIdentity.occurrence == 0 {
          if existingEntityIdentity != nil {
            // The displaced occupant's resolved subtree departs right here.
            // The eviction's descent covers committed values, live children,
            // and hosted-detached edges; the fresh node minted below carries
            // the displacement mark so `ExactIdentityModifier`'s churn
            // predicate (reuse suppression) fires even though the fresh node
            // was never present at frame start.
            removeSubtree(rootedAt: existing)
            displacedOccupant = true
          } else {
            bindEntityRoute(entityIdentity, to: existing.viewNodeID)
            return existing
          }
        }
      } else {
        // Single-child flattening tiebreak: the occupant is the absorber
        // whose committed root identity is this identity, but the authored
        // child node registered here holds the live state slots. Authoring
        // must land on the authored node — hosting the child's body on the
        // absorber re-seeds `@State`/`@FocusState` from authored defaults
        // (one spurious focus flip per presentation open; writes through a
        // superseded pass's host silently orphaned). Planning and value
        // stitching keep resolving the identity index to the absorber.
        if existing.identity != identity,
          let stateOwner = flattenedStateOwnerNode(for: identity),
          stateOwner !== existing
        {
          return stateOwner
        }
        return existing
      }
    }

    // The identity index entry can vanish while the authored state owner
    // lives on (the absorber stopped flattening, and its reindex removed the
    // entry it claimed). Re-adopt the live owner rather than minting a fresh
    // node over its state.
    if entityIdentity == nil,
      let stateOwner = flattenedStateOwnerNode(for: identity)
    {
      nodeIDByIdentity[identity] = stateOwner.viewNodeID
      return stateOwner
    }

    // 64-bit wraparound is deliberately unguarded (F122): unreachable in practice, and the generation-equality oracles assume no value reuse — do not narrow the width.
    nextViewNodeIDRawValue &+= 1
    let viewNodeID = ViewNodeID(rawValue: nextViewNodeIDRawValue)
    let node = ViewNode(
      viewNodeID: viewNodeID,
      identity: identity
    )
    node.ownerGraph = self
    nodesByNodeID[viewNodeID] = node
    nodeIDByIdentity[identity] = viewNodeID
    identityByNodeID[viewNodeID] = identity
    if let entityIdentity {
      bindEntityRoute(entityIdentity, to: viewNodeID)
    }
    if displacedOccupant {
      node.entityDisplacedOccupantFrameID = currentFrameID
    }
    return node
  }

  /// The live authored node registered as the state owner for `identity`
  /// while a single-child flattening absorber claims its identity index
  /// entry — see `GraphIndex.flattenedStateOwnerNodeIDByIdentity`.
  func flattenedStateOwnerNode(
    for identity: Identity
  ) -> ViewNode? {
    guard !flattenedStateOwnerNodeIDByIdentity.isEmpty,
      let nodeID = flattenedStateOwnerNodeIDByIdentity[identity]
    else {
      return nil
    }
    return nodeIfExists(for: nodeID)
  }

  func bindEntityIdentity(
    from resolved: ResolvedNode,
    to viewNodeID: ViewNodeID
  ) {
    guard let entityIdentity = resolved.entityIdentity else {
      return
    }
    // The outermost same-frame claim owns the entity (see
    // `prepareEntityRoutedOwner`). The entity-carrying resolved value bubbles
    // through every wrapper level of its chain, and each level's apply lands
    // here — an inner level must not re-bind the entity away from the
    // enclosing claimer still on the evaluation stack, or next frame's
    // forwarded claim adopts the inner node cross-identity and aliases the
    // parent's committed child pairing.
    if let boundNodeID = entityRoutingTable.route(entityIdentity),
      boundNodeID != viewNodeID,
      let bound = nodeIfExists(for: boundNodeID),
      bound.isEvaluating
    {
      return
    }
    bindEntityRoute(entityIdentity, to: viewNodeID)
  }

  func entityIdentities(
    in resolved: ResolvedNode
  ) -> Set<EntityIdentity> {
    var entities: Set<EntityIdentity> = []
    func visit(_ node: ResolvedNode) {
      if let entityIdentity = node.entityIdentity {
        entities.insert(entityIdentity)
      }
      for child in node.children {
        visit(child)
      }
    }
    visit(resolved)
    return entities
  }

  func releaseInactiveEntityRoutes(
    activeEntities: Set<EntityIdentity>
  ) {
    let releasedNodeIDs = entityRoutingTable.nodeIDByEntity.compactMap { entity, nodeID in
      activeEntities.contains(entity) && liveNodeIDs.contains(nodeID) ? nil : nodeID
    }
    entityRoutingTable.releaseEntities(notIn: activeEntities)
    entityRoutingTable.releaseNodes(notIn: liveNodeIDs)
    for nodeID in releasedNodeIDs {
      lifetimeAnchors.removeEntityHome(for: nodeID)
    }
  }

  func shouldDeferEntityRoutedRemoval(
    of node: ViewNode
  ) -> Bool {
    guard let entityIdentity = node.committed.entityIdentity else {
      return false
    }
    return entityRoutingTable.route(entityIdentity) == node.viewNodeID
  }

  func prunePendingEntityRoutedRemovals(
    activeEntities: Set<EntityIdentity>
  ) {
    // Fixed-point: removing a pending subtree can itself defer deeper
    // entity-routed descendants back into the pending set. Each pass consumes
    // a disjoint snapshot and either keeps or removes every node in it, so
    // the loop strictly shrinks into the finite node store.
    while !pendingEntityRoutedRemovalNodeIDs.isEmpty {
      let pendingNodeIDs = pendingEntityRoutedRemovalNodeIDs
      pendingEntityRoutedRemovalNodeIDs.removeAll(keepingCapacity: true)
      consumeTeardownWork(.entityRoutedRemoval, for: pendingNodeIDs)
      for viewNodeID in pendingNodeIDs {
        guard let node = nodeIfExists(for: viewNodeID),
          let entityIdentity = node.committed.entityIdentity,
          // Use the frame-stamped `visitedThisFrame` signal, not the stored
          // `wasVisitedThisFrame` bool: a genuinely-gone node is never
          // re-prepared in the frame it disappears, so the stored bool stays
          // stale-`true` from its last live frame and would wrongly skip the
          // teardown — leaking the node (and, for duplicate-id siblings, the
          // occurrence-`>0` lifetime) in `nodesByNodeID` forever (G13).
          !node.visitedThisFrame(currentFrameID)
        else {
          continue
        }
        // Keep the node only while it is still the entity's live home: the
        // entity must be active in the new tree AND still route here. An
        // active entity that re-homed to another node this frame (an owner
        // churn re-attached it to the arriving generation) leaves this node a
        // displaced stale copy — tear it down, sparing any descendants the
        // arriving tree already re-adopted (they are visited).
        //
        // Routing alone cannot prove liveness when the entity's claims are
        // suppressed inside a hosting boundary (`entityHosting`): the arriving
        // generation re-resolves the same re-rooted identity onto a fresh
        // structural node without ever re-binding the route, and the stale
        // copy would be kept as "the home" forever. The resolved-identity
        // index is the tiebreaker — the live home's apply owns that entry; a
        // stale copy lost it to the arriving node's reindex. Duplicate-id
        // occurrences (> 0) are exempt: siblings share the identity entry by
        // design, so only the entity route is authoritative for them (G13).
        let keepFacts = LegacyEntityHomeKeepFacts(
          entityIsActive: activeEntities.contains(entityIdentity),
          routeOwnsNode: entityRoutingTable.route(entityIdentity) == node.viewNodeID,
          occurrence: entityIdentity.occurrence,
          resolvedIdentityIndexOwnsNode:
            nodeIDByIdentity[node.resolvedIdentity] == node.viewNodeID
        )
        if legacyEntityHomeKeepsNode(keepFacts) {
          continue
        }
        removeSubtree(rootedAt: node, sparingVisitedNodes: true)
      }
    }
  }
}
