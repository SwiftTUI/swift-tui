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
      adoptAbsorbedDetachedHostedRoots(from: node)
      removeSubtree(
        rootedAt: node,
        policy: .absorbingIntoCollapse
      )
    }
  }

  /// Re-homes a reclaimed shadow's LIVE hosted-detached roots onto the
  /// shadow's own declaring host before the reclaim strips the edge.
  ///
  /// A collapse chain hosts each level on the one above it, so an interior
  /// mint's hosting claim can be the ONLY structural anchor its surviving
  /// content has: an `AnyView` payload whose content re-roots through
  /// `.id(_:)` converges on the interior `…/Content` node, and the enclosing
  /// `…/ScopedAnyViewContent` mint that hosts it is exactly the shadow this
  /// reclaim removes. Every path out of `removeSubtree` then drops that edge
  /// — the pre-decision `hostedDetached` strip, `removeRemovalEdges` for the
  /// relation targets, and finally `removeNode` — while the target itself is
  /// SPARED as visited-this-frame. What survives is anchored only by its
  /// entity home, and an entity home is not a lifetime owner: the F91
  /// reachability census deliberately refuses to seed one
  /// (`LifetimeRelationCensus` zeroes `liveEntityHomeByIdentity`), so the live
  /// content and its whole subtree read as stored-but-unreachable for the rest
  /// of the frame.
  ///
  /// Hosting is transitive under collapse. When the shadow is itself a
  /// detached root of a live host, that host becomes the declaring host of
  /// whatever the shadow was hosting — the same transitive re-home
  /// ``adoptAbsorbedRuntimeRegistrations`` performs for the interior's
  /// bookkeeping. Only targets visited this frame move: an unvisited target is
  /// genuinely departing with the shadow and the cascade must still reach it.
  func adoptAbsorbedDetachedHostedRoots(from node: ViewNode) {
    let hostNodeID = lifetimeAnchors.anchors(for: node.viewNodeID)
      .compactMap { anchor -> ViewNodeID? in
        guard case .hostedDetached(let host) = anchor,
          host != node.viewNodeID,
          nodeIfExists(for: host) != nil
        else {
          return nil
        }
        return host
      }
      .min()
    guard let hostNodeID else {
      return
    }
    for targetNodeID in lifetimeAnchors.targets(of: .hostedDetached(node.viewNodeID)).sorted()
    where targetNodeID != hostNodeID {
      guard let target = nodeIfExists(for: targetNodeID),
        target.visitedThisFrame(currentFrameID)
      else {
        continue
      }
      recordDetachedHostedNode(targetNodeID, hostedByNodeID: hostNodeID)
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
    for (ordinal, slot) in taskDescriptorSlots(ownedBy: node.viewNodeID) {
      let adoptedKey = TaskDescriptorSlotKey(node: absorberID, ordinal: ordinal)
      if taskDescriptorSlot(for: adoptedKey) == nil {
        setTaskDescriptorSlot(slot, for: adoptedKey)
      }
    }
  }
}
