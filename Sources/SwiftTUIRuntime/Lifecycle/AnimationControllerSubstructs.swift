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
    package var completionClosures: [AnimationBatchID: @Sendable () -> Void] = [:]
    package var batchRefCounts: [AnimationBatchID: Int] = [:]
    package var pendingEmptyBatchCompletions: [AnimationBatchID: MonotonicInstant] = [:]

    package init() {}

    /// Clears all completion bookkeeping, preserving allocated capacity.
    package mutating func reset() {
      completionClosures.removeAll(keepingCapacity: true)
      batchRefCounts.removeAll(keepingCapacity: true)
      pendingEmptyBatchCompletions.removeAll(keepingCapacity: true)
    }
  }

  /// Frame-head transaction bookkeeping: whether a transaction is open, the
  /// completions deferred until the transaction finishes, and the count of
  /// completions fired by the most recent frame head.
  package struct FrameHeadTransactionState: Sendable {
    package var isActive = false
    package var deferredCompletions: [@Sendable () -> Void] = []
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
