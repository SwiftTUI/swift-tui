@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

// Value-typed sub-structs that cluster the AnimationController's per-frame
// state.  Each struct owns a cohesive group of fields that are checkpointed,
// restored, and reset together.  Grouping them lets ``AnimationController``
// snapshot and restore whole structs with one memberwise assignment apiece
// instead of hand-listing ~25 individual fields three times — the compiler's
// memberwise value semantics now carry the totality contract, so a new field
// added to any group is automatically included in checkpoint/restore/reset.
//
// The controller exposes each field through a private computed accessor that
// forwards to the backing struct, so the intricate per-tick animation logic is
// untouched and behavior is identical.

extension AnimationController {
  /// Snapshots captured at the end of the previous frame: the animatable
  /// snapshots, the retained resolved/placed trees, the matched-geometry
  /// bookkeeping, and the parent/child/identity topology used to detect
  /// insertions, removals, and matched-geometry swaps on the next frame.
  package struct PreviousFrameState: Sendable {
    package var snapshots: [Identity: AnimatableSnapshot] = [:]
    /// Presentation values realized during layout are absent from the head snapshot.
    /// Keep only the placed window; offscreen/replaced rows are pruned at the tail.
    package var realizedPresentationTargets: [AnimationKey: AnyAnimatable] = [:]
    /// The nearest resolved ancestor owns a layout-realized row's lifetime.
    /// A surviving owner permits viewport eviction to complete its animations;
    /// a departed owner makes them part of the orphan-completion prune.
    package var realizedPresentationOwners: [Identity: Identity] = [:]
    /// Per-slot rings of values written under `Transaction.tracksVelocity`,
    /// seeding the next `.animate(spring)` on the same slot (plan
    /// 2026-08-25-002 T4). Lives here so the frame-head draft's samples ride
    /// the checkpoint that publishes to the live controller; pruned with
    /// departed identities.
    package var velocitySamplers: [AnimationKey: SlotVelocitySampler] = [:]
    package var treeRoot: ResolvedNode?
    package var placedRoot: PlacedNode?
    package var matchedGeometryBounds: [MatchedGeometryKey: CellRect] = [:]
    package var matchedKeyIdentities: [MatchedGeometryKey: Identity] = [:]
    /// The co-present adoption offsets of the previous frame's placed tree
    /// (plan 2026-08-25-003 Stage A): where each adopted non-source was
    /// drawn relative to its baseline slot. A departing adoptee's frozen
    /// exit overlay is translated by its entry so it starts where the node
    /// was drawn; the baseline itself stays un-adopted.
    package var adoptionOffsets: [Identity: PlacedAnimationOverlayOffset] = [:]
    package var parentByIdentity: [Identity: Identity] = [:]
    package var childIndexByIdentity: [Identity: Int] = [:]
    package var identities: Set<Identity> = []
    /// Every `ViewNodeID` that resolved into a live node last frame. Persisted
    /// so removal detection can find a departed **occurrence** — a ViewNodeID
    /// that left the tree even while its `Identity` is still live (a duplicate
    /// `.id` shedding one of several occurrences) — and so a reparented
    /// ViewNodeID (same node, new parent Identity) is recognized as a survivor
    /// rather than a removal-plus-insertion.
    package var liveNodeIDs: Set<ViewNodeID> = []
    /// O(1) currency for the canonical ViewGraph inputs processed into this
    /// baseline. A tail-side graph write can advance the graph token without
    /// contributing ordinary resolve work to the next deadline frame; the
    /// renderer must then process that frame even when its resolve counters are
    /// otherwise empty.
    package var graphAnimationInputToken: UInt64?

    package init() {}

    /// Clears every field, preserving allocated capacity for the dictionary
    /// and set members so a reset on the hot path doesn't re-allocate.
    package mutating func reset() {
      snapshots.removeAll(keepingCapacity: true)
      realizedPresentationTargets.removeAll(keepingCapacity: true)
      realizedPresentationOwners.removeAll(keepingCapacity: true)
      velocitySamplers.removeAll(keepingCapacity: true)
      treeRoot = nil
      placedRoot = nil
      matchedGeometryBounds.removeAll(keepingCapacity: true)
      matchedKeyIdentities.removeAll(keepingCapacity: true)
      adoptionOffsets.removeAll(keepingCapacity: true)
      parentByIdentity.removeAll(keepingCapacity: true)
      childIndexByIdentity.removeAll(keepingCapacity: true)
      identities.removeAll(keepingCapacity: true)
      liveNodeIDs.removeAll(keepingCapacity: true)
      graphAnimationInputToken = nil
    }
  }

  /// What the controller keeps for the views and view modifiers that conform
  /// to `Animatable` (`AnimatableValueSite`).
  ///
  /// The animations themselves are entries of the active-animation map with
  /// a `.value` key, so they are swept, superseded and counted like every
  /// other animation. This struct holds what an animation does not: the
  /// target each site last resolved with, which is where the next change
  /// starts from, and the sample each animation in flight presents on the
  /// frame being prepared. It is part of the checkpoint, so a frame draft
  /// that is dropped takes its records with it.
  package struct ValueSiteState: Sendable {
    /// The `animatableData` each site last resolved with as its target.
    /// Records of sites that left the tree are pruned when the resolved tree
    /// is processed.
    package var targets: [AnimationKey: AnyAnimatable] = [:]
    /// The graph node that evaluates each site, when one does. A site's
    /// identity is the one its view resolves at. A view whose body root is a
    /// conditional or a lone `Group` commits its branch's node in its place,
    /// so that identity is not in the resolved tree while the view is. The
    /// node says the site is still there, and the head asks the graph which
    /// identity the node now answers to.
    package var ownerNodeIDs: [AnimationKey: ViewNodeID] = [:]
    /// The data each value animation in flight presents on this frame: the
    /// head's one evaluation of its curve, or its first value when it
    /// started during this frame's resolve. Every resolve of the site in
    /// the frame reads the same entry.
    package var samples: [AnimationKey: AnyAnimatable] = [:]
    /// The identities whose bodies run on this frame because a value
    /// animation ticked: the owners the head invalidated. Such a body runs
    /// for the tick alone, so its output takes this frame's transaction and
    /// not one an ancestor was resolved under on an earlier frame.
    package var tickedOwners: Set<Identity> = []
    /// The instant of the frame being prepared, set when the head ticks the
    /// value animations. A value animation that starts during resolve
    /// starts at this instant.
    package var frameInstant: MonotonicInstant?
    /// The data each value animation presented on the frame before this
    /// one: that frame's ``samples``. Together with ``targets`` it says what
    /// the body of a site last ran with, which is what is on screen. A
    /// removal that plays a transition body reads it to compare the body of
    /// its `.didDisappear` phase with the tree on screen under the same
    /// data.
    package var previousSamples: [AnimationKey: AnyAnimatable] = [:]
    /// The sites that resolved for the first time on the frame being
    /// prepared. A site of a transition body that is being inserted is among
    /// them: the frame head starts its animation from the data of the
    /// body's `.willAppear` phase, and no site that was already there is
    /// touched.
    package var freshKeys: Set<AnimationKey> = []
    /// Whether the frame head is resolving the graph: the time between the
    /// start and the end of the frame's transition collection. A site that
    /// resolves then does so because the node in ``ownerNodeIDs`` is being
    /// evaluated.
    package var headIsResolving = false
    /// The sites that resolved while the head of the frame being prepared
    /// was resolving.
    package var headResolvedKeys: Set<AnimationKey> = []
    /// The sites whose latest resolve came at another time: a view that
    /// resolves during layout, in a host of a late preference, or through a
    /// controller no frame head drives. For such a site, the evaluation of
    /// its owner node says nothing about whether the site resolves.
    package var lateKeys: Set<AnimationKey> = []
    /// The sites whose owner node ran while this frame's head was resolving
    /// and did not resolve them. A site resolves whenever the node that
    /// evaluates it runs, so the view at such a site is gone from that
    /// node's output, even where the node itself stays in the tree (a slot
    /// that keeps its node for the next occupant). Its record goes when the
    /// resolved tree is processed, after a removal that plays the view's
    /// transition has had the chance to take the site over.
    package var unresolvedKeys: Set<AnimationKey> = []

    package init() {}

    package mutating func reset() {
      targets.removeAll(keepingCapacity: true)
      ownerNodeIDs.removeAll(keepingCapacity: true)
      samples.removeAll(keepingCapacity: true)
      tickedOwners.removeAll(keepingCapacity: true)
      frameInstant = nil
      previousSamples.removeAll(keepingCapacity: true)
      freshKeys.removeAll(keepingCapacity: true)
      headIsResolving = false
      headResolvedKeys.removeAll(keepingCapacity: true)
      lateKeys.removeAll(keepingCapacity: true)
      unresolvedKeys.removeAll(keepingCapacity: true)
    }

    /// Starts the frame head's resolve: from here until
    /// ``finishHeadResolve(reEvaluatedNodeIDs:)`` a site that resolves is
    /// counted as resolved by its owner's evaluation.
    package mutating func beginHeadResolve() {
      headIsResolving = true
      if !headResolvedKeys.isEmpty {
        headResolvedKeys.removeAll(keepingCapacity: true)
      }
      if !unresolvedKeys.isEmpty {
        unresolvedKeys.removeAll(keepingCapacity: true)
      }
    }

    /// Notes that the site at `key` resolved.
    package mutating func noteResolve(of key: AnimationKey) {
      if headIsResolving {
        headResolvedKeys.insert(key)
        if !lateKeys.isEmpty {
          lateKeys.remove(key)
        }
      } else if !lateKeys.contains(key) {
        lateKeys.insert(key)
      }
    }

    /// Ends the frame head's resolve and lists the sites whose owner ran
    /// without resolving them (``unresolvedKeys``).
    ///
    /// `reEvaluatedNodeIDs` are the nodes that were evaluated; `nil` means
    /// every live node.
    package mutating func finishHeadResolve(reEvaluatedNodeIDs: Set<ViewNodeID>?) {
      headIsResolving = false
      guard !ownerNodeIDs.isEmpty, reEvaluatedNodeIDs.map({ !$0.isEmpty }) ?? true else {
        return
      }
      for (key, ownerNodeID) in ownerNodeIDs
      where !headResolvedKeys.contains(key) && !lateKeys.contains(key)
        && (reEvaluatedNodeIDs?.contains(ownerNodeID) ?? true)
      {
        unresolvedKeys.insert(key)
      }
    }

    /// Whether a live view still resolves the site at `key` in a tree with
    /// the given identities and node stamps.
    ///
    /// A site is live while its identity or its owner node is in the tree
    /// (see ``ownerNodeIDs``), unless that node ran this frame without
    /// resolving it.
    package func isLive(
      _ key: AnimationKey,
      identities: Set<Identity>,
      liveNodeIDs: Set<ViewNodeID>
    ) -> Bool {
      if !unresolvedKeys.isEmpty, unresolvedKeys.contains(key) {
        return false
      }
      return identities.contains(key.identity)
        || ownerNodeIDs[key].map(liveNodeIDs.contains) == true
    }
  }

  /// What the frame head decided for the transition bodies inserted on the
  /// frame being prepared, for the injection stage of the same frame.
  ///
  /// A view or a modifier of a body that conforms to `Animatable` resolves
  /// during the head, with the data of the identity phase, before the
  /// injection stage qualifies the insertion. The head therefore qualifies
  /// the insertion first, with the code the injection stage runs, starts the
  /// animation of each such site from the data of the `.willAppear` phase and
  /// evaluates the owners again. What it decided is kept here. The injection
  /// stage reads it instead of deciding again, so the data of the sites and
  /// the slots of the body animate under one decision, and the `.willAppear`
  /// phase is evaluated once.
  ///
  /// The records are part of the checkpoint, so they leave with a frame
  /// draft that is dropped. They are cleared when a frame begins to collect
  /// transitions and when the injection stage has read them.
  struct TransitionBodyInsertionRecords: Sendable {
    /// The decision for each inserted identity whose transition has a
    /// registered body.
    var decisions: [Identity: AnimationTransitionBodyInsertion.Decision] = [:]
    /// The roots of the `.willAppear` phase of each body the head
    /// evaluated, by the identity of its registration, each with the stamps
    /// of the modifiers outside the transition. The head carries those
    /// stamps: they are the difference between the live root and what the
    /// body alone left on it, and the registration the head reads and the
    /// tree it has come from one evaluation.
    var willAppearRoots: [Identity: [ResolvedNode]] = [:]

    var isEmpty: Bool {
      decisions.isEmpty && willAppearRoots.isEmpty
    }

    mutating func reset() {
      decisions.removeAll(keepingCapacity: true)
      willAppearRoots.removeAll(keepingCapacity: true)
    }
  }

  /// The already-sampled resolved-tree presentation for one animation tick.
  ///
  /// Late-preference reconciliation may rebuild the canonical resolved tree
  /// after the animation stage. Re-projecting this value is intentionally a
  /// pure tree rewrite: it never evaluates an animation curve a second time,
  /// advances custom animation state, or fires completions twice.
  package struct ResolvedPresentationProjection: Sendable {
    package var interpolatedByNodeID: [ViewNodeID: [AnimatableSlot: AnyAnimatable]] = [:]
    package var interpolatedIdentityByNodeID: [ViewNodeID: Identity] = [:]
    package var interpolatedByIdentity: [Identity: [AnimatableSlot: AnyAnimatable]] = [:]
    package var parentByIdentity: [Identity: Identity] = [:]
    package var childIndexByIdentity: [Identity: Int] = [:]
    package var removalInjectionsByParent: [Identity: [(childIndex: Int, snapshot: ResolvedNode)]] =
      [:]

    package init(
      interpolatedByNodeID: [ViewNodeID: [AnimatableSlot: AnyAnimatable]] = [:],
      interpolatedIdentityByNodeID: [ViewNodeID: Identity] = [:],
      interpolatedByIdentity: [Identity: [AnimatableSlot: AnyAnimatable]] = [:],
      parentByIdentity: [Identity: Identity] = [:],
      childIndexByIdentity: [Identity: Int] = [:],
      removalInjectionsByParent:
        [Identity: [(childIndex: Int, snapshot: ResolvedNode)]] = [:]
    ) {
      self.interpolatedByNodeID = interpolatedByNodeID
      self.interpolatedIdentityByNodeID = interpolatedIdentityByNodeID
      self.interpolatedByIdentity = interpolatedByIdentity
      self.parentByIdentity = parentByIdentity
      self.childIndexByIdentity = childIndexByIdentity
      self.removalInjectionsByParent = removalInjectionsByParent
    }
  }

  /// The `.transition()` registration maps.  Current registrations are
  /// collected this frame; previous registrations are preserved so removal
  /// detection can find transitions for views whose branches are gone; pending
  /// registrations buffer this frame's sink callbacks before they merge into
  /// the current maps in ``finishTransitionCollection()``.
  package struct TransitionRegistry: Sendable {
    package var byNodeID: [ViewNodeID: AnyTransition] = [:]
    package var identitiesByNodeID: [ViewNodeID: Identity] = [:]
    package var previousByNodeID: [ViewNodeID: AnyTransition] = [:]
    package var previousIdentitiesByNodeID: [ViewNodeID: Identity] = [:]
    package var pendingByNodeID: [ViewNodeID: AnyTransition] = [:]
    package var pendingIdentitiesByNodeID: [ViewNodeID: Identity] = [:]
    /// The node whose evaluation declared each registration, for the
    /// registrations another node than the registered one declared. A
    /// `.transition()` modifier registers every node it emits. An emitted
    /// node with a graph node of its own (each view of a transition body
    /// with several roots) is then registered by its host, and an evaluation
    /// of that node alone does not run the modifier again.
    package var declaringNodeIDsByNodeID: [ViewNodeID: ViewNodeID] = [:]
    package var pendingDeclaringNodeIDsByNodeID: [ViewNodeID: ViewNodeID] = [:]
    /// The registrations another node declared whose own node was evaluated
    /// this frame while the declaring node was not. The modifier did not
    /// run, so nothing registered them again, and whether they still hold
    /// depends on what their node emits now: a view that only ran again
    /// emits the identity that was registered, and a view that was replaced
    /// emits another. The resolved tree says which
    /// (``reconcile(liveNodeIDs:nodeIDByIdentity:)``).
    package var unconfirmedNodeIDs: Set<ViewNodeID> = []

    package init() {}

    /// Clears every registration map, preserving allocated capacity.
    package mutating func reset() {
      byNodeID.removeAll(keepingCapacity: true)
      identitiesByNodeID.removeAll(keepingCapacity: true)
      previousByNodeID.removeAll(keepingCapacity: true)
      previousIdentitiesByNodeID.removeAll(keepingCapacity: true)
      pendingByNodeID.removeAll(keepingCapacity: true)
      pendingIdentitiesByNodeID.removeAll(keepingCapacity: true)
      declaringNodeIDsByNodeID.removeAll(keepingCapacity: true)
      pendingDeclaringNodeIDsByNodeID.removeAll(keepingCapacity: true)
      unconfirmedNodeIDs.removeAll(keepingCapacity: true)
    }

    /// Starts the collection of a frame's registrations: the current maps
    /// become the previous ones, and the pending maps are emptied.
    package mutating func beginCollection() {
      previousByNodeID = byNodeID
      previousIdentitiesByNodeID = identitiesByNodeID
      pendingByNodeID.removeAll(keepingCapacity: true)
      pendingIdentitiesByNodeID.removeAll(keepingCapacity: true)
      pendingDeclaringNodeIDsByNodeID.removeAll(keepingCapacity: true)
      if !unconfirmedNodeIDs.isEmpty {
        unconfirmedNodeIDs.removeAll(keepingCapacity: true)
      }
    }

    /// Records a registration made during this frame's resolve.
    package mutating func registerPending(
      _ transition: AnyTransition,
      for identity: Identity,
      viewNodeID: ViewNodeID,
      declaringNodeID: ViewNodeID?
    ) {
      pendingByNodeID[viewNodeID] = transition
      pendingIdentitiesByNodeID[viewNodeID] = identity
      if let declaringNodeID, declaringNodeID != viewNodeID {
        pendingDeclaringNodeIDsByNodeID[viewNodeID] = declaringNodeID
      } else {
        pendingDeclaringNodeIDsByNodeID.removeValue(forKey: viewNodeID)
      }
    }

    /// Drops the registrations of the nodes that are not in `liveNodeIDs`.
    package mutating func pruneDepartedNodes(liveNodeIDs: Set<ViewNodeID>) {
      byNodeID = byNodeID.filter { viewNodeID, _ in liveNodeIDs.contains(viewNodeID) }
      identitiesByNodeID = identitiesByNodeID.filter { viewNodeID, _ in
        liveNodeIDs.contains(viewNodeID)
      }
      if !declaringNodeIDsByNodeID.isEmpty {
        declaringNodeIDsByNodeID = declaringNodeIDsByNodeID.filter { viewNodeID, _ in
          liveNodeIDs.contains(viewNodeID)
        }
      }
    }

    /// Merges the registrations collected this frame into the current maps
    /// and drops every registration whose declaration ran again without
    /// making it.
    ///
    /// `reEvaluatedNodeIDs` are the nodes whose declarations ran this frame;
    /// `nil` means every live node. `isLiveNode` says whether a node is
    /// still in the graph; `nil` means it is not known. The pending maps are
    /// left as they are, so merging twice gives the result of merging once.
    package mutating func mergePendingRegistrations(
      reEvaluatedNodeIDs: Set<ViewNodeID>?,
      isLiveNode: ((ViewNodeID) -> Bool)? = nil
    ) {
      // Merge newly registered transitions into the existing map so
      // that registrations for non-re-evaluated subtrees survive
      // across selective-evaluation frames.  Without this, a
      // PhaseAnimator-only tick would wipe every other subtree's
      // transition and the next removal couldn't find it.
      for (viewNodeID, transition) in pendingByNodeID {
        byNodeID[viewNodeID] = transition
        identitiesByNodeID[viewNodeID] = pendingIdentitiesByNodeID[viewNodeID]
        declaringNodeIDsByNodeID[viewNodeID] = pendingDeclaringNodeIDsByNodeID[viewNodeID]
      }

      // Prune registrations whose declaring node was re-evaluated this frame
      // but declared no `.transition()` (the pending entry is absent). A live
      // node that drops its transition modifier — while keeping its
      // ViewNodeID — would otherwise retain the stale registration and
      // mis-animate a *later* removal. A node that was reused (not in
      // `reEvaluatedNodeIDs`) is left alone: the merge above preserved its
      // registration and it did not re-run its declaration this frame. `nil`
      // treats the whole current map as re-evaluated (full evaluation), so
      // every un-re-collected entry is dropped.
      //
      // The declaring node is the registered node itself unless another
      // node's evaluation registered it. A view of a transition body with
      // several roots has its own graph node and is registered by the
      // body's host, and so is every view with a graph node of its own under
      // a `.transition()` over several views. Three things can then happen
      // to such a registration without its modifier running:
      //
      // - The declaring node left the graph. The modifier is gone, and the
      //   registration with it.
      // - The registered node was evaluated alone and emits what it did (a
      //   state it reads changed, or an animation of its `animatableData`
      //   ticked). The registration stands.
      // - The registered node was evaluated alone and now emits another
      //   view. The registration was for the view that left.
      //
      // The last two differ only in what the node emits, which the resolved
      // tree says. Such a registration is kept here and listed as
      // unconfirmed until that tree is read.
      var staleNodeIDs: [ViewNodeID] = []
      var unconfirmed: Set<ViewNodeID> = []
      for viewNodeID in byNodeID.keys where pendingByNodeID[viewNodeID] == nil {
        guard let reEvaluatedNodeIDs else {
          staleNodeIDs.append(viewNodeID)
          continue
        }
        guard let declaringNodeID = declaringNodeIDsByNodeID[viewNodeID] else {
          if reEvaluatedNodeIDs.contains(viewNodeID) {
            staleNodeIDs.append(viewNodeID)
          }
          continue
        }
        if reEvaluatedNodeIDs.contains(declaringNodeID) || isLiveNode?(declaringNodeID) == false {
          staleNodeIDs.append(viewNodeID)
        } else if reEvaluatedNodeIDs.contains(viewNodeID) {
          unconfirmed.insert(viewNodeID)
        }
      }
      for viewNodeID in staleNodeIDs {
        byNodeID.removeValue(forKey: viewNodeID)
        identitiesByNodeID.removeValue(forKey: viewNodeID)
        declaringNodeIDsByNodeID.removeValue(forKey: viewNodeID)
      }
      if unconfirmed != unconfirmedNodeIDs {
        unconfirmedNodeIDs = unconfirmed
      }
    }

    /// Brings the registrations in line with the tree the frame resolved.
    ///
    /// Every reader of a registration keys on the stamps of that tree, so
    /// this runs before any of them: a registration whose node was aliased
    /// away moves onto the node that carries its identity
    /// (``rehomeAliasedRegistrations(liveNodeIDs:nodeIDByIdentity:)``), and
    /// an unconfirmed one whose node no longer carries the registered
    /// identity is dropped. The injection stage calls it on the controller's
    /// maps, and the frame head on a copy of them, so the two decide on the
    /// same registrations.
    package mutating func reconcile(
      liveNodeIDs: Set<ViewNodeID>,
      nodeIDByIdentity: [Identity: ViewNodeID]
    ) {
      rehomeAliasedRegistrations(liveNodeIDs: liveNodeIDs, nodeIDByIdentity: nodeIDByIdentity)
      guard !unconfirmedNodeIDs.isEmpty else { return }
      for viewNodeID in unconfirmedNodeIDs {
        guard let identity = identitiesByNodeID[viewNodeID],
          nodeIDByIdentity[identity] != viewNodeID
        else { continue }
        byNodeID.removeValue(forKey: viewNodeID)
        identitiesByNodeID.removeValue(forKey: viewNodeID)
        declaringNodeIDsByNodeID.removeValue(forKey: viewNodeID)
      }
      unconfirmedNodeIDs.removeAll(keepingCapacity: true)
    }

    /// Moves each registration whose node id is not in the committed tree
    /// onto the node that carries its identity there.
    ///
    /// A node-backed conditional branch child registers under its own mint,
    /// but a one-element chain level absorbs its output and the committed
    /// tree carries the absorber's stamp. Every channel that reads a
    /// registration — the occurrence diff, the insertion lookup, the
    /// adopted-slot removal channel, and the live-node prune — keys on
    /// committed stamps, so a registration left keyed to the aliased-away
    /// mint is invisible to all of them: insertions never fire and
    /// branch-flip removals plan no exit overlay. Moving it onto the
    /// stamp-owning id restores the host-keyed registration the value-only
    /// fallback used to produce.
    package mutating func rehomeAliasedRegistrations(
      liveNodeIDs: Set<ViewNodeID>,
      nodeIDByIdentity: [Identity: ViewNodeID]
    ) {
      for (nodeID, identity) in identitiesByNodeID where !liveNodeIDs.contains(nodeID) {
        guard let liveNodeID = nodeIDByIdentity[identity],
          liveNodeID != nodeID,
          identitiesByNodeID[liveNodeID] == nil,
          let transition = byNodeID[nodeID]
        else { continue }
        byNodeID[liveNodeID] = transition
        identitiesByNodeID[liveNodeID] = identity
        // A re-homed registration is pruned by its new node, as before: the
        // absorber is evaluated whenever what it absorbs changes.
        declaringNodeIDsByNodeID.removeValue(forKey: liveNodeID)
        byNodeID.removeValue(forKey: nodeID)
        identitiesByNodeID.removeValue(forKey: nodeID)
        declaringNodeIDsByNodeID.removeValue(forKey: nodeID)
      }
    }
  }

  /// `withAnimation` completion bookkeeping: the registered completion closures,
  /// their per-batch active-animation ref counts, and the deadlines for batches
  /// that registered a completion but retained no animations.
  package struct BatchCompletionState: Sendable {
    /// Retainers that have not yet passed the `.removed` barrier (the curve
    /// is still running or the exit overlay is still on screen).
    package var batchRefCounts: [AnimationBatchID: Int] = [:]
    /// Retainers that have not yet passed the `.logicallyComplete` barrier.
    /// Every retain bumps both counts; a curve past its
    /// `logicallyComplete(after:)` instant, or an exit overlay whose curve
    /// ended, releases this one first and `batchRefCounts` later.
    package var batchLogicalRefCounts: [AnimationBatchID: Int] = [:]
    package var pendingEmptyBatchCompletions: [AnimationBatchID: MonotonicInstant] = [:]

    package init() {}

    /// Clears the batch ref-count bookkeeping, preserving allocated capacity.
    /// (The `withAnimation` completion closures live in ``CompletionLedger`` — the
    /// async-writable registration set — and are cleared by its `reset()`.)
    package mutating func reset() {
      batchRefCounts.removeAll(keepingCapacity: true)
      batchLogicalRefCounts.removeAll(keepingCapacity: true)
      pendingEmptyBatchCompletions.removeAll(keepingCapacity: true)
    }
  }

  /// One completion closure registered for a batch and the barrier it fires
  /// at. A batch holds a list: `withAnimation(_:completionCriteria:_:completion:)`
  /// registers one, `Transaction.addAnimationCompletion(criteria:_:)` any
  /// number, each with its own barrier.
  package struct AnimationCompletionRegistration: Sendable {
    package var barrier: AnimationCompletionBarrier
    package var closure: @MainActor @Sendable () -> Void

    package init(
      barrier: AnimationCompletionBarrier,
      closure: @escaping @MainActor @Sendable () -> Void
    ) {
      self.barrier = barrier
      self.closure = closure
    }
  }

  /// The set of registration maps an **async task** can grow on the *live*
  /// controller between frames — the `withAnimation` completion closures and the
  /// animation-box registrations. Grouping them here makes that set an enumerable
  /// type rather than a rule spread across `publishCommittedState`: every
  /// async-writable map lives in this struct, its whole-struct checkpoint covers
  /// them all, and ``concurrentRegistrations(since:)`` / ``reapply(_:)`` carry
  /// every one across an in-flight publish in a single place. Add a map here and
  /// the carry/checkpoint extend with it — closing the gap where a third map,
  /// open-coded into the publish path, would be silently orphaned.
  package struct CompletionLedger: Sendable {
    /// Completion registrations keyed by batch ID; each fires once every
    /// animation tagged with the batch ID passes its barrier. A batch's list
    /// is complete when its scope opens (registration precedes the body), so
    /// the keyed carry below stays exact.
    package var completions: [AnimationBatchID: [AnimationCompletionRegistration]] = [:]
    /// Animation boxes registered for the current frame, keyed by box.
    package var registeredAnimations: [AnimationBox: Animation] = [:]

    package init() {}

    /// Clears the async-writable registration set, preserving allocated capacity.
    package mutating func reset() {
      completions.removeAll(keepingCapacity: true)
      registeredAnimations.removeAll(keepingCapacity: true)
    }

    /// The registrations this (live) ledger gained since `baseline` — exactly the
    /// entries an async task inserted between frames. Enumerates **every**
    /// async-writable map, so a map added to the ledger is carried automatically.
    package func concurrentRegistrations(since baseline: CompletionLedger)
      -> ConcurrentRegistrations
    {
      ConcurrentRegistrations(
        completions: ConcurrentRegistrationCarry.sinceBaseline(
          live: completions,
          baseline: baseline.completions
        ),
        registeredAnimations: ConcurrentRegistrationCarry.sinceBaseline(
          live: registeredAnimations,
          baseline: baseline.registeredAnimations
        )
      )
    }

    /// Re-applies `carried` concurrent registrations into this (post-restore
    /// draft) ledger, never overwriting an entry the restored draft already holds.
    package mutating func reapply(_ carried: ConcurrentRegistrations) {
      ConcurrentRegistrationCarry.reapply(carried.completions, into: &completions)
      ConcurrentRegistrationCarry.reapply(carried.registeredAnimations, into: &registeredAnimations)
    }

    /// The carried async registrations between two ledger snapshots.
    package struct ConcurrentRegistrations: Sendable {
      package var completions: [AnimationBatchID: [AnimationCompletionRegistration]]
      package var registeredAnimations: [AnimationBox: Animation]
    }
  }

  /// Frame-head transaction bookkeeping: whether a transaction is open, the
  /// completions deferred until the transaction finishes, and the count of
  /// completions fired by the most recent frame head.
  package struct FrameHeadTransactionState: Sendable {
    package var isActive = false
    package var deferredCompletions: [@MainActor @Sendable () -> Void] = []
    package var lastCompletionCount = 0

    package init() {}

    /// Clears the transaction flag and deferred completions, preserving the
    /// completion array's allocated capacity.
    package mutating func reset() {
      isActive = false
      deferredCompletions.removeAll(keepingCapacity: true)
      lastCompletionCount = 0
    }
  }
}
