// The subtree-removal cascade, extracted from ViewGraph.swift (F115): the
// teardown walk that retires a departing node tree — committed-snapshot
// descent with per-cascade re-entrancy guarding, visited-node sparing,
// entity-routed deferral to the frame barrier, hosted-detached descent, and
// the index/lifecycle cleanup fan-out. Consumes ViewGraph's module-internal
// state accessors; the comment-justified special cases inside are
// load-bearing and ordered — see each guard's rationale before reordering.

extension ViewGraph {
  /// Per-cascade re-entrancy guard for subtree removal. One walk instance is
  /// created at each removal root and threaded through the descent, so aliased
  /// identity/structural-path lookups cannot re-enter a node the cascade is
  /// already removing.
  final class SubtreeRemovalWalk {
    var enteredNodeIDs: Set<ViewNodeID> = []
  }

  func removeSubtree(
    rootedAt node: ViewNode,
    committedSnapshot: ResolvedNode? = nil,
    sparingVisitedNodes: Bool = false,
    isSubtreeDescent: Bool = false,
    walk: SubtreeRemovalWalk? = nil
  ) {
    guard let current = nodesByNodeID[node.viewNodeID],
      current === node
    else {
      return
    }
    // The descent below walks committed snapshots whose identity and
    // structural-path lookups can alias a node already being removed higher in
    // this same cascade (an absolute-`.id` re-root shares structural paths with
    // its wrapper). Re-entering it re-runs the whole body with no progress —
    // track entered nodes per removal cascade and run the node-local teardown
    // once. A re-entry still descends its own snapshot's children: an aliased
    // snapshot can cover departed descendants the first entry's snapshot does
    // not, and the descent strictly shrinks into the finite resolved tree.
    let walk = walk ?? SubtreeRemovalWalk()
    guard walk.enteredNodeIDs.insert(node.viewNodeID).inserted else {
      guard let committedSnapshot else {
        return
      }
      // The re-entry snapshot can name an interior node DISTINCT from the
      // re-entered absorber: a chain collapse leaves the interior's value
      // stamped with the absorber, but the interior still owns its re-rooted
      // identity index entry (a `.id` slot node under a hosting boundary).
      // Enter any not-yet-entered node the snapshot maps to — the walk's
      // entered-set makes this cycle-proof and strictly shrinking. When
      // nothing new maps, fall back to the children-only descent.
      var interiorNodes = nodeIDsForResolvedNode(committedSnapshot)
        .subtracting(walk.enteredNodeIDs)
        .compactMap { nodeIfExists(for: $0) }
      if interiorNodes.isEmpty,
        let interior = nodeIfExists(for: committedSnapshot.identity),
        !walk.enteredNodeIDs.contains(interior.viewNodeID)
      {
        interiorNodes = [interior]
      }
      guard !interiorNodes.isEmpty else {
        for child in committedSnapshot.children {
          removeResolvedSubtree(child, sparingVisitedNodes: sparingVisitedNodes, walk: walk)
        }
        return
      }
      interiorNodes.sort { lhs, rhs in
        if lhs.identity == rhs.identity {
          return lhs.viewNodeID < rhs.viewNodeID
        }
        return lhs.identity < rhs.identity
      }
      for interior in interiorNodes {
        removeSubtree(
          rootedAt: interior,
          committedSnapshot: committedSnapshot,
          sparingVisitedNodes: sparingVisitedNodes,
          isSubtreeDescent: true,
          walk: walk
        )
      }
      return
    }

    // A departed-subtree teardown (an explicitly diffed-out child, a churn
    // orphan) removes a root the caller has already judged gone, but the walk
    // DOWN from that root goes through committed snapshots and identity/node
    // lookups that can land on nodes the arriving tree re-adopted this frame
    // (a stable-`.id` control re-rooted out of the departing generation, a
    // reused chrome node). A visited node reached by DESCENT therefore belongs
    // to the live tree — leave it, and its subtree, alone. The explicit root
    // is still removed unconditionally, and callers that do not opt in keep
    // the narrower parent-detached keep-guard below (some removals — e.g. a
    // pruned navigation destination — legitimately tear down visited roots).
    if sparingVisitedNodes,
      isSubtreeDescent,
      node.visitedThisFrame(currentFrameID)
    {
      return
    }

    // A node reached while tearing down a *departing* subtree (e.g. an owner
    // whose `.id` churned) may itself be a re-rooted stable-`.id` descendant
    // (a control under an `AnyView`/captured-subview scope) that the *arriving*
    // subtree already re-resolved this frame at its re-rooted identity. Because
    // its identity is re-rooted, it has no live parent link (`parent == nil`) —
    // the same property the retained-reuse decision observes — so it only appears
    // here through the departing owner's committed children, yet its runtime node
    // is genuinely live now. Dropping it would mint a fresh node next frame,
    // churning its route/registration identity and breaking same-node
    // interactions (a click whose press/release straddle the churn stops
    // dispatching). Keep it when it was visited this frame and is parent-detached;
    // a genuinely departing node either was not visited (pruned normally) or is
    // still parented under the surviving tree (e.g. an entity-routed owner being
    // replaced), so its lifecycle/registrations are retired as before.
    // …unless nothing can reach the node anymore: a live re-rooted node owns
    // its identity index entry (its apply reindexed it) or is an entity's
    // routed home, and the arriving tree finds it through one of those. A
    // visited, parent-detached node with neither is a stranded same-frame
    // mint whose output a chain collapse absorbed (`pruneAbsorbedShadowedNodes`)
    // — keeping it would leak it beyond every teardown path's reach.
    if node.parent == nil,
      node.viewNodeID != root?.viewNodeID,
      node.visitedThisFrame(currentFrameID),
      nodeIDByIdentity[node.identity] == node.viewNodeID
        || nodeIDByIdentity[node.resolvedIdentity] == node.viewNodeID
        || entityRoutingTable.entityByNodeID[node.viewNodeID].map({ entity in
          entityRoutingTable.route(entity) == node.viewNodeID
        }) ?? false
    {
      return
    }

    // An entity-routed node reached by DESCENT is not necessarily departing
    // with the subtree being torn down: its entity may reappear elsewhere this
    // frame (a stable explicit-id control inside a churned owner, an `AnyView`
    // payload whose entity is re-attached by the arriving generation). Defer
    // the decision to the frame barrier (`prunePendingEntityRoutedRemovals`),
    // where the full old-vs-new entity set is known — the Stage 6 release
    // contract. An explicitly removed root (`isSubtreeDescent == false`, e.g.
    // the mid-resolve different-entity eviction) is still torn down
    // unconditionally; that eviction is load-bearing for same-frame
    // convergence of fixed-slot explicit-id churn.
    if isSubtreeDescent,
      shouldDeferEntityRoutedRemoval(of: node)
    {
      pendingEntityRoutedRemovalNodeIDs.insert(node.viewNodeID)
      return
    }

    node.prepareForFrame(currentFrameID)
    let snapshot = committedSnapshot ?? node.committed
    removeResolvedNodeReuseCaches(rootedAt: node.identity)
    if node.resolvedIdentity != node.identity {
      removeResolvedNodeReuseCaches(rootedAt: node.resolvedIdentity)
    }
    if snapshot.identity != node.identity,
      snapshot.identity != node.resolvedIdentity
    {
      removeResolvedNodeReuseCaches(rootedAt: snapshot.identity)
    }
    if snapshot.children.isEmpty {
      for child in node.children {
        removeSubtree(
          rootedAt: child,
          sparingVisitedNodes: sparingVisitedNodes,
          isSubtreeDescent: true,
          walk: walk
        )
      }
    } else {
      for child in snapshot.children {
        removeResolvedSubtree(child, sparingVisitedNodes: sparingVisitedNodes, walk: walk)
      }
      // A chain collapse can absorb an interior node's output as the
      // absorber's own resolved value: the committed value tree then names
      // the interior's identity with the absorber's stamp, so the value
      // descent above re-enters the absorber and never reaches the interior
      // node itself (its structural-path and identity index entries were
      // rewritten by the same collapse). The interior stays reachable only
      // as a live child — descend whatever is still parented here that the
      // value descent did not cover. A child the arriving tree re-adopted
      // was re-parented by its apply and is skipped; a child already reached
      // through the values is a no-op via the walk's entered-set.
      for child in node.children where child.parent === node {
        removeSubtree(
          rootedAt: child,
          sparingVisitedNodes: sparingVisitedNodes,
          isSubtreeDescent: true,
          walk: walk
        )
      }
    }

    // Hosted detached subtrees: content this node resolved but did not commit
    // as a child (see `recordDetachedHostedSubtree`) is reachable through
    // neither the committed values above nor the parent links — its lifetime
    // anchors here. Visited roots (still being resolved by a live replacement)
    // and entity-routed re-homes are kept by the descent's standard guards.
    if let hostedRootIDs = detachedHostedSubtreeRootsByHost.removeValue(forKey: node.viewNodeID) {
      // Two phases so the ledger is never transiently one-sided: drop every
      // hostByRoot mirror first (the host's rootsByHost entry is already
      // gone), THEN recurse — the recursive removals re-validate the ledger
      // (F97) and would false-positive on a mid-loop half-removed state.
      for hostedRootID in hostedRootIDs.sorted() {
        detachedHostedSubtreeHostByRoot.removeValue(forKey: hostedRootID)
      }
      assertDetachedHostedLedgerInverse()
      for hostedRootID in hostedRootIDs.sorted() {
        guard let hostedRoot = nodeIfExists(for: hostedRootID) else {
          continue
        }
        // Spare a visited hosted root only while something OUTSIDE this
        // removal cascade still anchors it (a live parent or a live
        // re-binding evaluation host): "visited this frame" alone is not
        // liveness — a dismissing overlay entry resolves its content one
        // last time in the frame that tears the whole entry down, and
        // sparing on that visit strands the root with no anchor at all
        // (unreachable until an eventual same-identity re-mint reuses it —
        // the census leak the hosted ledger exists to prevent).
        let anchor = hostedRoot.parent ?? hostedRoot.evaluationHost
        let anchorSurvivesRemoval =
          anchor.map { anchor in
            nodeIfExists(for: anchor.viewNodeID) === anchor
              && !walk.enteredNodeIDs.contains(anchor.viewNodeID)
          } ?? false
        removeSubtree(
          rootedAt: hostedRoot,
          sparingVisitedNodes: anchorSurvivesRemoval,
          isSubtreeDescent: true,
          walk: walk
        )
      }
    }
    if let hostID = detachedHostedSubtreeHostByRoot.removeValue(forKey: node.viewNodeID) {
      detachedHostedSubtreeRootsByHost[hostID]?.remove(node.viewNodeID)
      if detachedHostedSubtreeRootsByHost[hostID]?.isEmpty == true {
        detachedHostedSubtreeRootsByHost.removeValue(forKey: hostID)
      }
      assertDetachedHostedLedgerInverse()
    }

    let lifecycleMetadata =
      if !node.previousLifecycleMetadata.isEmpty {
        node.previousLifecycleMetadata
      } else if !node.lifecycleMetadata.isEmpty {
        node.lifecycleMetadata
      } else {
        snapshot.lifecycleMetadata
      }

    let emitsOwnLifecycleEvents = node.participatesInStructuralLifecycle

    if emitsOwnLifecycleEvents {
      for task in lifecycleMetadata.tasks {
        appendTaskCancelEvent(
          identity: snapshot.identity,
          task: task,
          isStructural: true
        )
      }
    }
    if emitsOwnLifecycleEvents,
      !lifecycleMetadata.disappearHandlerIDs.isEmpty
    {
      structuralDisappearEvents.append(
        .init(
          identity: node.identity,
          operation: .disappear(
            handlerIDs: lifecycleMetadata.disappearHandlerIDs
          )
        )
      )
    }

    node.setLifecycleState(.disappearing)
    node.setCommittedPresence(false)
    node.parent = nil
    removeDependencyEdges(for: node)
    liveNodeIDs.remove(node.viewNodeID)
    invalidatedNodeIDs.remove(node.viewNodeID)
    graphLocalDirtyNodeIDs.remove(node.viewNodeID)

    if let owner = lifecycleEvaluationOwnersByNodeID.removeValue(forKey: node.viewNodeID) {
      lifecycleEvaluationTargetsByOwner[owner]?.remove(node.viewNodeID)
      if lifecycleEvaluationTargetsByOwner[owner]?.isEmpty == true {
        lifecycleEvaluationTargetsByOwner.removeValue(forKey: owner)
      }
    }
    if let targets = lifecycleEvaluationTargetsByOwner.removeValue(forKey: node.viewNodeID) {
      for target in targets {
        lifecycleEvaluationOwnersByNodeID.removeValue(forKey: target)
      }
    }
    lifecycleEvaluationTargetsRecordedByOwner.removeValue(forKey: node.viewNodeID)

    nodeIDsByStructuralPath[node.committed.structuralPath]?.remove(node.viewNodeID)
    if nodeIDsByStructuralPath[node.committed.structuralPath]?.isEmpty == true {
      nodeIDsByStructuralPath.removeValue(forKey: node.committed.structuralPath)
    }
    taskDescriptorNodeSlots = taskDescriptorNodeSlots.filter { $0.key.node != node.viewNodeID }
    if flattenedStateOwnerNodeIDByIdentity[node.identity] == node.viewNodeID {
      flattenedStateOwnerNodeIDByIdentity.removeValue(forKey: node.identity)
    }
    if nodeIDByIdentity[node.identity] == node.viewNodeID {
      nodeIDByIdentity.removeValue(forKey: node.identity)
    }
    if nodeIDByIdentity[node.resolvedIdentity] == node.viewNodeID {
      nodeIDByIdentity.removeValue(forKey: node.resolvedIdentity)
    }
    entityRoutingTable.release(node.viewNodeID)
    activeNavigationSurfaceContentNodeIDsByHost.removeValue(forKey: node.viewNodeID)
    identityByNodeID.removeValue(forKey: node.viewNodeID)
    nodesByNodeID.removeValue(forKey: node.viewNodeID)
    // The effect-owner index mirrors `nodesByNodeID` membership exactly (its
    // only removal is here, beside the node store's): a discarded node's ID
    // never re-enters the map (IDs are minted monotonically), so this cannot
    // strand a future owner.
    effectRegistrationOwnerNodeIDs.remove(node.viewNodeID)
  }

  private func removeResolvedNodeReuseCaches(
    rootedAt identity: Identity
  ) {
    resolvedNodeReuseCache = resolvedNodeReuseCache.filter { key, entry in
      let ownerMatches = key.owner == identity || key.owner.isDescendant(of: identity)
      let nodeMatches =
        entry.node.identity == identity || entry.node.identity.isDescendant(of: identity)
      return !ownerMatches && !nodeMatches
    }
  }

  private func removeResolvedSubtree(
    _ resolved: ResolvedNode,
    sparingVisitedNodes: Bool = false,
    walk: SubtreeRemovalWalk? = nil
  ) {
    let walk = walk ?? SubtreeRemovalWalk()
    let nodes = nodeIDsForResolvedNode(resolved)
      .compactMap { nodeIfExists(for: $0) }
      .sorted { lhs, rhs in
        if lhs.identity == rhs.identity {
          return lhs.viewNodeID < rhs.viewNodeID
        }
        return lhs.identity < rhs.identity
      }
    if !nodes.isEmpty {
      for node in nodes {
        removeSubtree(
          rootedAt: node,
          committedSnapshot: resolved,
          sparingVisitedNodes: sparingVisitedNodes,
          isSubtreeDescent: true,
          walk: walk
        )
      }
      return
    }

    if let node = nodeIfExists(for: resolved.identity) {
      removeSubtree(
        rootedAt: node,
        committedSnapshot: resolved,
        sparingVisitedNodes: sparingVisitedNodes,
        isSubtreeDescent: true,
        walk: walk
      )
      return
    }

    for child in resolved.children {
      removeResolvedSubtree(child, sparingVisitedNodes: sparingVisitedNodes, walk: walk)
    }
  }
}
