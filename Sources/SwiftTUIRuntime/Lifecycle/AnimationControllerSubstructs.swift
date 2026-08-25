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
    package var treeRoot: ResolvedNode?
    package var placedRoot: PlacedNode?
    package var matchedGeometryBounds: [MatchedGeometryKey: CellRect] = [:]
    package var matchedKeyIdentities: [MatchedGeometryKey: Identity] = [:]
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
      treeRoot = nil
      placedRoot = nil
      matchedGeometryBounds.removeAll(keepingCapacity: true)
      matchedKeyIdentities.removeAll(keepingCapacity: true)
      parentByIdentity.removeAll(keepingCapacity: true)
      childIndexByIdentity.removeAll(keepingCapacity: true)
      identities.removeAll(keepingCapacity: true)
      liveNodeIDs.removeAll(keepingCapacity: true)
      graphAnimationInputToken = nil
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

    package init() {}

    /// Clears every registration map, preserving allocated capacity.
    package mutating func reset() {
      byNodeID.removeAll(keepingCapacity: true)
      identitiesByNodeID.removeAll(keepingCapacity: true)
      previousByNodeID.removeAll(keepingCapacity: true)
      previousIdentitiesByNodeID.removeAll(keepingCapacity: true)
      pendingByNodeID.removeAll(keepingCapacity: true)
      pendingIdentitiesByNodeID.removeAll(keepingCapacity: true)
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
