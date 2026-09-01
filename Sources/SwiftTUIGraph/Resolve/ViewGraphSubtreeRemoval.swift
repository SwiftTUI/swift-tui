// The subtree-removal cascade, extracted from ViewGraph.swift (F115): the
// teardown walk that retires a departing node tree — committed-snapshot
// descent with per-cascade re-entrancy guarding, visited-node sparing,
// entity-routed deferral to the frame barrier, hosted-detached descent, and
// the index/lifecycle cleanup fan-out. Consumes ViewGraph's module-internal
// state accessors; the comment-justified special cases inside are
// load-bearing and ordered — see each guard's rationale before reordering.

/// Which liveness guards a removal cascade trusts.
///
/// Removal reaches a node for several different reasons, and each reason
/// believes a different set of liveness proxies. These were three independent
/// boolean parameters threaded through every recursive call: eight expressible
/// combinations, four of them meant by anyone. Each preset below is exactly one
/// real call shape.
///
/// Note what a descent does NOT inherit: ``ignoringLifetimeAnchors(_:)`` and
/// the barrier adjudication apply to the node they were chosen for, never to
/// its descendants. The barrier proved *that root* unreachable; a collapse
/// absorbed *that target*. Descendants start from ``ordinary`` again, carrying
/// only the spare decision. That was previously an accident of default
/// parameter values at each recursive call.
struct SubtreeRemovalPolicy: Sendable, Equatable {
  /// Spare a visited node reached by descent, deferring its verdict to the
  /// teardown barrier instead of removing it now.
  var sparesVisitedDescendants: Bool
  /// Consult durable lifetime anchors as a liveness proxy for a
  /// parent-detached node.
  var consultsLifetimeAnchors: Bool
  /// Apply the parent-detached keep-guard at all.
  var appliesParentDetachedKeepGuard: Bool

  /// Every guard applies and nothing is spared for having been visited.
  static let ordinary = Self(
    sparesVisitedDescendants: false,
    consultsLifetimeAnchors: true,
    appliesParentDetachedKeepGuard: true
  )

  /// Reconciliation teardown: a visited descendant may belong to the arriving
  /// tree, so its verdict is deferred rather than decided here.
  static let sparingVisitedDescendants = Self(
    sparesVisitedDescendants: true,
    consultsLifetimeAnchors: true,
    appliesParentDetachedKeepGuard: true
  )

  /// Chain collapse and absorbed shadows: the target's remaining anchors are
  /// inside the cascade, so anchors prove nothing about its liveness. Visited
  /// descendants are still spared — absorption is a fact about the target, not
  /// about the tree beneath it.
  static let absorbingIntoCollapse = Self(
    sparesVisitedDescendants: true,
    consultsLifetimeAnchors: false,
    appliesParentDetachedKeepGuard: true
  )

  /// Barrier strand pruning: the census reachability walk already proved this
  /// root dead, so the keep-guard's liveness proxies must not re-spare it — a
  /// stranded island root keeps its identity index entry precisely BECAUSE no
  /// teardown path ever reached it. Descendants are a separate question and are
  /// still spared: only the root was adjudicated.
  static let barrierAdjudicated = Self(
    sparesVisitedDescendants: true,
    consultsLifetimeAnchors: true,
    appliesParentDetachedKeepGuard: false
  )

  /// The policy a descendant inherits: this cascade's spare decision, and
  /// nothing else.
  var forDescent: Self {
    Self.ordinary.sparingVisitedDescendants(sparesVisitedDescendants)
  }

  func sparingVisitedDescendants(_ spares: Bool) -> Self {
    var policy = self
    policy.sparesVisitedDescendants = spares
    return policy
  }

  func ignoringLifetimeAnchors(_ ignores: Bool) -> Self {
    var policy = self
    policy.consultsLifetimeAnchors = !ignores
    return policy
  }
}

extension ViewGraph {
  /// Per-cascade re-entrancy guard for subtree removal. One walk instance is
  /// created at each removal root and threaded through the descent, so aliased
  /// identity/structural-path lookups cannot re-enter a node the cascade is
  /// already removing.
  final class SubtreeRemovalWalk {
    var enteredNodeIDs: Set<ViewNodeID> = []
    var relationCascadeNodeIDs: Set<ViewNodeID> = []
    var reuseCacheEvictionRoots: [Identity] = []
    /// Memoized no-argument reachability context for this cascade. This is
    /// sound while that context depends only on `root`, which is never
    /// reassigned during a removal cascade.
    private var memoizedContext: LifetimeReachabilityContext??

    func reachabilityContext(
      _ build: () -> LifetimeReachabilityContext?
    ) -> LifetimeReachabilityContext? {
      if let memoizedContext {
        return memoizedContext
      }
      let built = build()
      memoizedContext = .some(built)
      return built
    }
  }

  func removeSubtree(
    rootedAt node: ViewNode,
    committedSnapshot: ResolvedNode? = nil,
    policy: SubtreeRemovalPolicy = .ordinary,
    isSubtreeDescent: Bool = false,
    walk: SubtreeRemovalWalk? = nil
  ) {
    guard let current = nodesByNodeID[node.viewNodeID],
      current === node,
      nodesByOwnerLifetimeID[node.ownerLifetimeID] === node
    else {
      return
    }
    let ownsWalk = walk == nil
    let walk = walk ?? SubtreeRemovalWalk()
    defer {
      if ownsWalk {
        flushReuseCacheEvictions(walk)
      }
    }
    // The descent below walks committed snapshots whose identity and
    // structural-path lookups can alias a node already being removed higher in
    // this same cascade (an absolute-`.id` re-root shares structural paths with
    // its wrapper). Re-entering it re-runs the whole body with no progress —
    // track entered nodes per removal cascade and run the node-local teardown
    // once. A re-entry still descends its own snapshot's children: an aliased
    // snapshot can cover departed descendants the first entry's snapshot does
    // not, and the descent strictly shrinks into the finite resolved tree.
    if walk.relationCascadeNodeIDs.isEmpty {
      walk.relationCascadeNodeIDs = lifetimeAnchors.removalCascade(
        from: node.viewNodeID
      )
    }
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
          removeResolvedSubtree(child, policy: policy.forDescent, walk: walk)
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
          policy: policy.forDescent,
          isSubtreeDescent: true,
          walk: walk
        )
      }
      return
    }
    let relationTargets = lifetimeAnchors.removalTargets(of: node.viewNodeID)

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
    if policy.sparesVisitedDescendants,
      isSubtreeDescent,
      node.visitedThisFrame(currentFrameID)
    {
      // The spare is provisional. "Visited this frame" also holds for a node
      // a SUPERSEDED same-frame pass resolved and the committed pass dropped
      // (a node-backed style-body island under the toolbar capture-host seam:
      // an earlier reconcile pass visits the old item's ButtonBody chain, the
      // committed pass drops the item, and this spare would strand the whole
      // island — nothing anchors it once the departing wrapper's teardown
      // clears its parent/committedValue/hostedDetached edges). Defer the
      // final verdict to the teardown barrier, where every apply has settled:
      // a genuinely re-adopted node holds a durable anchor there and is kept;
      // an anchor-less spare is the strand and is reclaimed.
      enqueueTeardownWork(.sparedVisitedDescent, for: node.viewNodeID)
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
    // A barrier-adjudicated removal root (`pruneSparedVisitedDescentStrands`)
    // was already proven unreachable by the census reachability walk — the
    // keep-guard's liveness proxies must not re-spare it: a stranded island
    // root keeps its identity index entry precisely BECAUSE no teardown path
    // ever reached it, so index ownership is not evidence of adoption there.
    // Every other caller keeps the guard: the proxies protect live re-rooted
    // controls and flattened state owners mid-frame.
    if policy.appliesParentDetachedKeepGuard,
      node.parent == nil,
      node.viewNodeID != root?.viewNodeID,
      node.visitedThisFrame(currentFrameID)
    {
      let hasDurableAnchorOutsideCascade =
        policy.consultsLifetimeAnchors
        && (walk.reachabilityContext { lifetimeReachabilityContext() }.map { context in
          lifetimeAnchors.hasAnchorOutside(
            node.viewNodeID,
            excluding: walk.relationCascadeNodeIDs,
            context: context
          )
        } ?? false)
      if hasDurableAnchorOutsideCascade {
        return
      }
      if nodeIDByIdentity[node.identity] == node.viewNodeID
        || nodeIDByIdentity[node.resolvedIdentity] == node.viewNodeID
        || entityRoutingTable.entityByNodeID[node.viewNodeID].map({ entity in
          entityRoutingTable.route(entity) == node.viewNodeID
        }) ?? false
      {
        // Index ownership and an entity route are LIVENESS PROXIES, not
        // lifetime anchors, so this keep is provisional in exactly the way the
        // visited-descendant spare above is — and for the same reason: the
        // cascade is not finished. Every remaining stage of it still severs
        // edges, and the ones that name THIS node are severed with no second
        // look, because a node already in `enteredNodeIDs` is skipped by both
        // the hosted-detached and the relation-target loops of every later
        // source. A picker's detached `PickerOptions/Group[i]` nodes are the
        // measured shape: the descent reaches one through the departing
        // control, keeps it here on its identity-index entry, and the control's
        // own relation loop then removes `parent`/`committedValue`/
        // `hostedDetached` to it and skips it as already-entered — leaving it
        // stored, anchorless and unreachable for the census to report.
        // Defer to the teardown barrier instead, where every apply and every
        // edge has settled: `pruneSparedVisitedDescentStrands` keeps a node the
        // census reachability walk can still reach (a genuine mid-frame
        // re-adoption acquires a durable anchor by then) and reclaims one it
        // cannot. The proxies still do their job — they stop the removal HERE,
        // mid-cascade, which is what protects a live re-rooted control — they
        // just no longer stand in for a settled verdict.
        enqueueTeardownWork(.sparedVisitedDescent, for: node.viewNodeID)
        return
      }
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
      enqueueTeardownWork(.entityRoutedRemoval, for: node.viewNodeID)
      return
    }

    node.prepareForFrame(currentFrameID)
    let snapshot = committedSnapshot ?? node.committed
    walk.reuseCacheEvictionRoots.append(node.identity)
    if node.resolvedIdentity != node.identity {
      walk.reuseCacheEvictionRoots.append(node.resolvedIdentity)
    }
    if snapshot.identity != node.identity,
      snapshot.identity != node.resolvedIdentity
    {
      walk.reuseCacheEvictionRoots.append(snapshot.identity)
    }
    if snapshot.children.isEmpty {
      for child in node.children {
        removeSubtree(
          rootedAt: child,
          policy: policy.forDescent,
          isSubtreeDescent: true,
          walk: walk
        )
      }
    } else {
      for child in snapshot.children {
        removeResolvedSubtree(child, policy: policy.forDescent, walk: walk)
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
          policy: policy.forDescent,
          isSubtreeDescent: true,
          walk: walk
        )
      }
    }

    // A hosted-detached target's root lifetime ends with its declaring host.
    // Remove the source edges before descending, then tear down the explicit
    // target root even when a weak/non-structural fact would otherwise spare a
    // visited node. Only descendants are spared when another durable anchor
    // survives outside this complete removal cascade. This is the relation-
    // native form of the hosted-root teardown semantics.
    let hostedDetachedTargets = lifetimeAnchors.targets(
      of: .hostedDetached(node.viewNodeID)
    )
    for targetNodeID in hostedDetachedTargets.sorted() {
      lifetimeAnchors.remove(
        anchor: .hostedDetached(node.viewNodeID),
        for: targetNodeID
      )
    }
    for targetNodeID in hostedDetachedTargets.sorted() {
      guard !walk.enteredNodeIDs.contains(targetNodeID),
        let target = nodeIfExists(for: targetNodeID)
      else {
        continue
      }
      let anchorSurvivesRemoval =
        walk.reachabilityContext { lifetimeReachabilityContext() }.map { context in
          lifetimeAnchors.hasAnchorOutside(
            targetNodeID,
            excluding: walk.relationCascadeNodeIDs,
            context: context
          )
        } ?? false
      removeSubtree(
        rootedAt: target,
        policy: .ordinary.sparingVisitedDescendants(anchorSurvivesRemoval),
        isSubtreeDescent: true,
        walk: walk
      )
    }

    // Relation-native downward traversal catches children represented only by
    // a durable lifetime edge. Snapshotting happened before any node-local
    // cleanup; remove this source's exact edges, then spare a target only when
    // another anchor survives outside the complete cascade.
    for targetNodeID in relationTargets.sorted() {
      lifetimeAnchors.removeRemovalEdges(
        from: node.viewNodeID,
        to: targetNodeID
      )
      guard !walk.enteredNodeIDs.contains(targetNodeID),
        let target = nodeIfExists(for: targetNodeID)
      else {
        continue
      }
      let targetIsAbsorbed =
        teardownBarrierWork.reasons(for: targetNodeID).contains(.absorbedShadow)
      if !targetIsAbsorbed,
        let context = walk.reachabilityContext({ lifetimeReachabilityContext() }),
        lifetimeAnchors.keepDecision(
          for: targetNodeID,
          removalCascade: walk.relationCascadeNodeIDs,
          context: context
        ).shouldKeep
      {
        continue
      }
      if targetIsAbsorbed {
        adoptAbsorbedRuntimeRegistrations(from: target)
      }
      removeSubtree(
        rootedAt: target,
        policy: policy.forDescent.ignoringLifetimeAnchors(targetIsAbsorbed),
        isSubtreeDescent: true,
        walk: walk
      )
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
      // Keyed by the handler IDs, mirroring `appendStructuralAppearEvent`: a
      // single-child flattening absorber and the lone `ForEach` element it
      // committed both carry the element's disappear IDs, and a container
      // teardown reaches both nodes (the element through its hosted-detached
      // edge). Whichever the cascade reaches first publishes; the second is
      // the same registration (org task T171).
      let operation = LifecycleCommitOperation.disappear(
        handlerIDs: lifecycleMetadata.disappearHandlerIDs
      )
      if !structuralDisappearEvents.contains(where: { $0.operation == operation }) {
        structuralDisappearEvents.append(
          .init(identity: node.identity, operation: operation)
        )
      }
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
    removeTaskDescriptorSlots(ownedBy: node.viewNodeID)
    if flattenedStateOwnerNodeIDByIdentity[node.identity] == node.viewNodeID {
      flattenedStateOwnerNodeIDByIdentity.removeValue(forKey: node.identity)
    }
    if nodeIDByIdentity[node.identity] == node.viewNodeID {
      nodeIDByIdentity.removeValue(forKey: node.identity)
    }
    if nodeIDByIdentity[node.resolvedIdentity] == node.viewNodeID {
      nodeIDByIdentity.removeValue(forKey: node.resolvedIdentity)
    }
    releaseEntityRoute(for: node.viewNodeID)
    lifetimeAnchors.removeNode(node.viewNodeID)
    discardTeardownWork(for: node.viewNodeID)
    identityByNodeID.removeValue(forKey: node.viewNodeID)
    nodesByNodeID.removeValue(forKey: node.viewNodeID)
    // A sanctioned successor may already serve this immutable owner lifetime.
    // Retiring an older representation must not erase the successor's route.
    if nodesByOwnerLifetimeID[node.ownerLifetimeID] === node {
      nodesByOwnerLifetimeID.removeValue(forKey: node.ownerLifetimeID)
    }
    // The effect-owner index mirrors `nodesByNodeID` membership exactly (its
    // only removal is here, beside the node store's). Raw IDs can repeat after
    // checkpoint rollback, but the exact-node + owner-lifetime CAS at this
    // function's entry proves this removal still targets the current occupant.
    effectRegistrationOwnerNodeIDs.remove(node.viewNodeID)
  }

  private func flushReuseCacheEvictions(_ walk: SubtreeRemovalWalk) {
    guard !resolvedNodeReuseCache.isEmpty,
      !walk.reuseCacheEvictionRoots.isEmpty
    else {
      return
    }

    // Component-wise preorder keeps every descendant contiguous behind its
    // ancestor, so the previous retained root is the only possible ancestor.
    let sortedRoots = Set(walk.reuseCacheEvictionRoots).sorted(by: identityPathLessThan)
    var minimalRoots: [Identity] = []
    minimalRoots.reserveCapacity(sortedRoots.count)
    for root in sortedRoots {
      if let previous = minimalRoots.last,
        root.isDescendant(of: previous)
      {
        continue
      }
      minimalRoots.append(root)
    }

    #if DEBUG
      noteReuseCacheEvictionFlush()
    #endif
    resolvedNodeReuseCache = resolvedNodeReuseCache.filter { key, entry in
      !minimalRoots.contains { root in
        root.isAncestor(of: key.owner)
          || root.isAncestor(of: entry.node.identity)
      }
    }
  }

  private func identityPathLessThan(_ lhs: Identity, _ rhs: Identity) -> Bool {
    for (lhsComponent, rhsComponent) in zip(lhs.components, rhs.components) {
      if lhsComponent != rhsComponent {
        return lhsComponent < rhsComponent
      }
    }
    return lhs.components.count < rhs.components.count
  }

  private func removeResolvedSubtree(
    _ resolved: ResolvedNode,
    policy: SubtreeRemovalPolicy = .ordinary,
    walk: SubtreeRemovalWalk? = nil
  ) {
    let ownsWalk = walk == nil
    let walk = walk ?? SubtreeRemovalWalk()
    defer {
      if ownsWalk {
        flushReuseCacheEvictions(walk)
      }
    }
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
          policy: policy.forDescent,
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
        policy: policy.forDescent,
        isSubtreeDescent: true,
        walk: walk
      )
      return
    }

    for child in resolved.children {
      removeResolvedSubtree(child, policy: policy.forDescent, walk: walk)
    }
  }
}
