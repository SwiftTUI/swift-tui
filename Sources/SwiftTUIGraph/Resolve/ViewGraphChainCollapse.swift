// Chain-collapse pruning, extracted from ViewGraph.swift (F115): the
// finalize-barrier reclaim of nodes stranded when a transparent chain
// collapse absorbs an interior mint's output (see `reindexIdentity`'s
// shadowing record). Registration/task-slot re-homing to the absorber
// happens here before the reclaim so the F43 start-skip cannot recur.

extension ViewGraph {
  /// Reclaims nodes stranded by a transparent chain collapse this frame. A
  /// composite resolving through an identity-extending but node-less layer (a
  /// conditional branch) mints its own node during a cold resolve;
  /// `normalizeResolvedElements(count == 1)` then returns its output directly
  /// and the enclosing chain level's apply absorbs it — the inner node is
  /// never wired as a graph child, its identity index entry is overwritten by
  /// the absorber's reindex (`reindexIdentity` records that shadowing here),
  /// and no structural diff, entity release, or committed-snapshot descent can
  /// reach it again. Warm resolves land on the absorber via the identity
  /// index, so the stranded mint is exclusively a cold-resolve artifact.
  ///
  /// The reclaim is deferred to the finalize barrier because a shadowing alone
  /// does not prove abandonment mid-resolve: a duplicate-occurrence sibling
  /// (G13) legitimately overwrites the shared identity entry while the earlier
  /// occurrence is still awaiting its parent's apply. By the barrier, every
  /// live node reached by the frame's walk is parented (`ViewNode.apply` wires
  /// parent links) or is an entity's routed home — a shadowed, same-frame,
  /// parentless, non-routed node is unreachable by construction.
  func pruneAbsorbedShadowedNodes(
    activeEntities: Set<EntityIdentity>
  ) {
    let candidates = teardownBarrierWork.nodeIDs(for: .absorbedShadow)
    guard !candidates.isEmpty else {
      return
    }
    consumeTeardownWork(.absorbedShadow, for: candidates)
    for nodeID in candidates.sorted() {
      // Two stranded shapes qualify:
      // - a same-frame mint (`!wasPresentAtFrameStart`) — the cold-resolve
      //   chain-collapse artifact, reclaimable even though its mint visited it;
      // - a WARM strand (`!visitedThisFrame`) — the same absorbed interior
      //   discovered late: the absorber re-shadows its identity entry on every
      //   apply, so lookups land on the absorber and the interior is never
      //   visited again. Parentless, un-routed, and index-shadowed, nothing
      //   can reach it; without this arm it leaks until (at best) an identity
      //   prefix sweep. A visited warm node stays: something resolved it this
      //   frame, so it is live (a re-rooted control, a hosted detached root).
      guard let node = nodeIfExists(for: nodeID),
        node.viewNodeID != root?.viewNodeID,
        !node.wasPresentAtFrameStart || !node.visitedThisFrame(currentFrameID),
        node.parent == nil
      else {
        continue
      }
      // A flatten-shadowed state owner is reachable by construction —
      // authoring-host resolution prefers it over its absorber — and its
      // lifetime anchors to the absorber's hosted-detached edge. Reclaiming
      // it here (the creation frame leaves it parentless: the absorber's
      // apply absorbed its output) would drop the live `@State`/`@FocusState`
      // slots it hosts and re-seed them on the absorber next pass.
      if flattenedStateOwnerNodeIDByIdentity[node.identity] == node.viewNodeID {
        continue
      }
      if let context = lifetimeReachabilityContext(activeEntities: activeEntities),
        lifetimeAnchors.qualifiedEntityHome(
          for: nodeID,
          context: context
        ) != nil
      {
        continue
      }
      // An entity's live home is never reclaimed here: adoption and the
      // outermost-claim rule move entity homes through `nodeForIdentity`, and
      // a routed node reached by shadowing (a re-rooted stable-`.id` control
      // is parent-detached by design) is still the entity's binding — its
      // lifetime belongs to the entity lifecycle (release/pending-removal).
      // Unless the home is stale: routing alone cannot prove liveness when
      // claims are suppressed inside a hosting boundary (`entityHosting`) —
      // the shadow that put this node in the candidate set means the arriving
      // tree re-resolved its identity onto a different node. A live home owns
      // its resolved-identity index entry (its apply reindexed it); duplicate
      // occurrences (> 0) share entries by design and stay route-governed.
      // The interior recorded runtime registrations while evaluating the chain
      // whose committed value the absorber now carries (the stamp fixed
      // point). Re-home that bookkeeping to the identity's current owner
      // before reclaiming the node — publication rebuilds walk live nodes
      // only, so registrations left on the reclaimed interior are silently
      // dropped and its committed tasks never start ("no task registration at
      // commit", the F43 start-skip).
      adoptAbsorbedRuntimeRegistrations(from: node)
      removeSubtree(
        rootedAt: node,
        sparingVisitedNodes: true,
        ignoringLifetimeAnchors: true
      )
    }
  }

  func adoptAbsorbedRuntimeRegistrations(from node: ViewNode) {
    guard node.registeredHandlers.hasRuntimeRegistrations,
      let absorberID = nodeIDByIdentity[node.identity],
      absorberID != node.viewNodeID,
      let absorber = nodesByNodeID[absorberID]
    else {
      return
    }
    absorber.adoptRuntimeRegistrations(from: node)
    // The interior's task-descriptor identity slots move with the
    // registrations: the absorber evaluates this chain on the next warm
    // resolve, and a slot left keyed to the reclaimed node would miss,
    // mint a fresh identity token, and plan a spurious cancel + restart
    // of a task whose `.task(id:)` value never changed.
    for (key, slot) in taskDescriptorNodeSlots where key.node == node.viewNodeID {
      let adoptedKey = TaskDescriptorSlotKey(node: absorberID, ordinal: key.ordinal)
      if taskDescriptorNodeSlots[adoptedKey] == nil {
        taskDescriptorNodeSlots[adoptedKey] = slot
      }
    }
  }
}
