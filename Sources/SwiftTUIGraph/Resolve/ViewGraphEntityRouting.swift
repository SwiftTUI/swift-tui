// Entity routing and identity adoption, extracted from ViewGraph.swift
// (F115): the five identity/entity-adoption policies of
// `nodeForIdentity(for:entityIdentity:)` (entity re-route, same-entity
// re-bind, duplicate-occurrence minting, flattened-state-owner tiebreak,
// fresh mint), the flattened-state-owner lookup, entity binding/collection,
// and the frame-barrier release/prune of entity routes (the Stage 6
// deferred-removal contract). Consumes ViewGraph's module-internal state
// accessors; the guard order inside `nodeForIdentity` is load-bearing.

extension ViewGraph {
  /// The sole production fresh-node minting door. Raw node IDs may repeat
  /// after checkpoint rollback; owner lifetimes never do.
  private func mintFreshNode(
    identity: Identity,
    installIdentityIndex: Bool
  ) -> ViewNode {
    // 64-bit raw-ID wraparound remains practically unreachable. Lifetime
    // safety does not depend on this allocator because the separate owner
    // sequencer below is checked and never checkpointed.
    nextViewNodeIDRawValue &+= 1
    let viewNodeID = ViewNodeID(rawValue: nextViewNodeIDRawValue)
    let node = ViewNode(
      viewNodeID: viewNodeID,
      identity: identity,
      ownerLifetimeID: issueNodeOwnerLifetimeID()
    )
    node.ownerGraph = self
    nodesByNodeID[viewNodeID] = node
    nodesByOwnerLifetimeID[node.ownerLifetimeID] = node
    identityByNodeID[viewNodeID] = identity
    if installIdentityIndex {
      nodeIDByIdentity[identity] = viewNodeID
    }
    return node
  }

  func nodeForIdentity(
    for identity: Identity,
    entityIdentity: EntityIdentity? = nil
  ) -> ViewNode {



    if let entityIdentity,
      let routedNodeID = entityRoutingTable.route(entityIdentity)
    {
      if let routedNode = nodeIfExists(for: routedNodeID) {
        // A route-prepared owner is provisional until authored resolution
        // claims it. Reaching it through the ordinary entity-routing door is
        // that claim: withdraw its end-of-frame scratch debt before the
        // teardown barrier runs. Ordinary routed nodes have no such debt, so
        // this is a no-op for every non-staged adoption.
        consumeTeardownWork(.resolveScopeScratch, for: [routedNodeID])
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
        // Single-child flattening, entity-routed: the identity index resolves
        // to the ABSORBER (the container whose committed value is this lone
        // `ForEach` element, so `reindexIdentity` handed it the entry) and the
        // absorber's committed value carries the element's stamp — so the
        // occupant comparison below would adopt the container as the element's
        // node. Mirror the no-entity tiebreak: authoring lands on the authored
        // element node when it survived, and on a fresh node otherwise; the
        // container keeps the index entry for planning and value stitching.
        if entityIdentity.isForEachScoped, existing.identity != identity {
          if let stateOwner = flattenedStateOwnerNode(for: identity),
            stateOwner !== existing,
            stateOwner.committed.entityIdentity
              ?? entityRoutingTable.entityByNodeID[stateOwner.viewNodeID]
              ?? stateOwner.lastHomedEntityIdentity == entityIdentity
          {
            bindEntityRoute(entityIdentity, to: stateOwner.viewNodeID)
            return stateOwner
          }
          let element = mintFreshNode(identity: identity, installIdentityIndex: false)
          bindEntityRoute(entityIdentity, to: element.viewNodeID)
          return element
        }
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
            // and hosted-detached edges. The arriving entity mints a distinct
            // runtime lifetime below.
            removeSubtree(rootedAt: existing)
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

    let node = mintFreshNode(identity: identity, installIdentityIndex: true)
    if let entityIdentity {
      bindEntityRoute(entityIdentity, to: node.viewNodeID)
    }
    return node
  }

  /// Prepares an entity-routed owner without displacing a co-resident owner
  /// that has the same authored structural identity.
  ///
  /// Entity routing, rather than the identity index, is authoritative for
  /// these owners. This matters when two authored lifetimes deliberately
  /// share one immutable structural identity (for example, a value host and a
  /// top-level explicit-identity child). Normal first-allocation routing may
  /// evict the occurrence-zero occupant so an authored replacement converges;
  /// restore preparation must keep both records alive until their respective
  /// authored entity claims arrive. A fresh co-resident node therefore keeps
  /// the authored identity on the node and route, but leaves the existing
  /// identity-index occupant untouched.
  ///
  /// Every prepared owner carries resolve-scope scratch debt. Ordinary
  /// `nodeForIdentity(for:entityIdentity:)` route adoption clears that debt;
  /// an unclaimed owner is reclaimed at the frame teardown barrier. The
  /// checkpointed graph index and teardown work make candidate-frame rollback
  /// restore both membership and route ownership atomically.
  package func prepareEntityRoutedOwnerPreservingCoResidentIdentity(
    identity: Identity,
    entityIdentity: EntityIdentity
  ) -> ViewNode {
    let node: ViewNode
    if let routedNodeID = entityRoutingTable.route(entityIdentity),
      let routedNode = nodeIfExists(for: routedNodeID)
    {
      // This is another preparation of the same provisional route, not its
      // authored adoption. Keep the scratch debt below.
      node = routedNode
    } else if let occupant = nodeIfExists(for: identity) {
      let occupantEntityIdentity =
        occupant.committed.entityIdentity
        ?? entityRoutingTable.entityByNodeID[occupant.viewNodeID]
        ?? occupant.lastHomedEntityIdentity
      if occupantEntityIdentity == entityIdentity {
        bindEntityRoute(entityIdentity, to: occupant.viewNodeID)
        node = occupant
      } else {
        // Do not write `nodeIDByIdentity[identity]`: the existing occupant is
        // still the structural lookup result until normal authored adoption
        // selects one of the co-resident entity routes.
        let coResident = mintFreshNode(identity: identity, installIdentityIndex: false)
        bindEntityRoute(entityIdentity, to: coResident.viewNodeID)
        node = coResident
      }
    } else {
      node = nodeForIdentity(for: identity, entityIdentity: entityIdentity)
    }

    enqueueTeardownWork(.resolveScopeScratch, for: node.viewNodeID)
    node.prepareForFrame(currentFrameID)
    node.beginDynamicPropertyUpdate()
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
    // A `ForEach` element's entity-carrying value can also bubble ACROSS an
    // identity boundary: a lone element is spliced up as its container's own
    // resolved value (`normalizeResolvedElements` unwraps a single element
    // instead of minting a `Group`), so the container at `…/background`
    // applies a value whose identity is the element's `…/background/ID[x]`.
    // Element entities never fold into an enclosing node — `ForEachIteration`
    // routes them without preparing the enclosing node as their owner — so a
    // claimant at another identity is always that flattening container, and
    // letting it take the route re-homes the element onto the container next
    // frame: its `@State` re-seeds there, writes made through body-created
    // closures land on the orphaned element node, and once the data grows the
    // hijacked element resolves ON the container mid-evaluation, where reuse
    // serves the container's whole committed `Group` as that element (the
    // counter-demo ripple wedge, 2026-09-01). The entity stays with the node
    // that resolved the value's identity (see also `nodeForIdentity`'s absorber
    // tiebreak and `lifetimeReachabilityContext`'s flattened-home fact).
    //
    // Exact and `.id()` entities are deliberately NOT covered: their hosts
    // (`ExactIdentityModifier`'s `ExplicitIdentityHost`, `AnyView`'s payload
    // content host) prepare the route on the enclosing node and fold the
    // content in — a cross-identity claim by design. Refusing it leaves the
    // content's node orphaned for a frame with its registrations live (the
    // `anyView*KeyRebinds` stress cases count two key handlers).
    if entityIdentity.isForEachScoped,
      let claimant = nodeIfExists(for: viewNodeID),
      claimant.identity != resolved.identity
    {
      return
    }
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
    while !teardownBarrierWork.nodeIDs(for: .entityRoutedRemoval).isEmpty {
      let pendingNodeIDs = teardownBarrierWork.nodeIDs(for: .entityRoutedRemoval)
      consumeTeardownWork(.entityRoutedRemoval, for: pendingNodeIDs)
      for viewNodeID in pendingNodeIDs {
        guard let node = nodeIfExists(for: viewNodeID),
          node.committed.entityIdentity != nil,
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
        let relationKeeps =
          lifetimeReachabilityContext(
            activeEntities: activeEntities
          ).flatMap { context in
            lifetimeAnchors.qualifiedEntityHome(
              for: node.viewNodeID,
              context: context
            )
          } != nil
        if relationKeeps {
          continue
        }
        removeSubtree(rootedAt: node, policy: .sparingVisitedDescendants)
      }
    }
  }
}
