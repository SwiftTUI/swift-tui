@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

// In-flight animation runtime state.
//
// `AnimationModels.swift` holds the *keying* types (`AnimatableSlot`,
// `AnimationKey`); this file holds the per-animation runtime state the
// `AnimationController` mutates each tick — what kind of animation is running,
// its in-flight record, the tick result it produces, and the retained snapshot
// of a removed view awaiting its exit transition.

/// Per-kind payload carried on ``ActiveAnimation``.  The case selects
/// how the animation is sampled and how its output is applied to the
/// resolved/placed tree.
package enum AnimationKind: Sendable {
  /// A property animation on a specific ``AnimatableSlot``.  The
  /// `from`/`to` values are interpolated and written back through
  /// ``AnimationController/applyValue``.
  case property(from: AnyAnimatable, to: AnyAnimatable)
  /// A transition-driven insertion offset animation applied at
  /// placed level (cannot route through the slot path because it
  /// operates on intrinsic-layout leaves).  The `from` tuple holds
  /// the starting (x, y) delta; the animation interpolates from
  /// `from` toward (0, 0).
  case insertionOffset(from: (x: Int, y: Int))
  /// A matched-geometry translation animation between two placed
  /// bounds.  At progress 0 the target identity renders at
  /// `fromBounds`; at progress 1 it renders at its natural new
  /// bounds (looked up in the current placed tree).
  case matchedGeometry(fromBounds: CellRect)
}

/// An animation currently in flight for one ``AnimationKey``.
package struct ActiveAnimation: Sendable {
  /// The per-kind payload.  Selects how this animation is sampled
  /// and applied to the tree.
  package var kind: AnimationKind
  package var animationBox: AnimationBox
  /// The runtime entity (``ViewNodeID``) this animation belongs to, captured at
  /// registration when the keying ``Identity`` still resolved to this node.
  /// Property interpolation is applied by this id so an in-flight animation
  /// follows an entity that moves to a new ``Identity`` (e.g. an `.id`-keyed
  /// view re-parented between containers), instead of resetting (G10a). `nil`
  /// for animations registered without a resolved node id; those fall back to
  /// the ``AnimationKey`` identity.
  package var ownerViewNodeID: ViewNodeID? = nil
  package var startTime: MonotonicInstant
  /// Per-key persistent state threaded into
  /// ``CustomAnimation/animate(value:time:context:)`` on each tick.
  /// Built-in bezier/spring curves ignore this; custom animations can
  /// use it to persist bookkeeping across frames.
  package var customState: AnimationState = .init()
  /// Batch identifier copied from ``TransactionSnapshot/animationBatchID``
  /// at enqueue time.  Used to look up a registered completion closure
  /// when every animation in the batch has drained.
  package var batchID: AnimationBatchID?
}

/// Result of a tick: tells the runtime whether more frames are needed
/// and when the next one should arrive.
///
/// Phase 4 split the previously overloaded ``hasActiveAnimations`` /
/// ``affectedIdentities`` fields:
///
/// - ``hasPendingWork`` is the scheduling signal — `true` whenever the
///   tick produced any work that needs another frame, including
///   identity-agnostic stranded-batch drains.
/// - ``redrawIdentities`` is the visibility signal — the set of view
///   identities whose rendered cells must be redrawn this frame.  May
///   be empty even when ``hasPendingWork`` is `true` (the drain case),
///   so the run loop must not gate the wake-up on this set being
///   non-empty.
package struct AnimationTickResult: Sendable {
  /// `true` when the tick produced pending work and the scheduler
  /// should wake up again before ``nextDeadline``.
  package var hasPendingWork: Bool
  /// The absolute time by which the scheduler must wake for the
  /// next tick.  `nil` when no wake-up is needed.
  package var nextDeadline: MonotonicInstant?
  /// Identities whose rendered cells need to be redrawn this frame.
  /// Used by the render pipeline's incremental presentation diff to
  /// decide which subtrees need re-rasterizing — NOT by the run loop
  /// to decide whether to schedule another tick.
  package var redrawIdentities: Set<Identity>

  package init(
    hasPendingWork: Bool = false,
    nextDeadline: MonotonicInstant? = nil,
    redrawIdentities: Set<Identity> = []
  ) {
    self.hasPendingWork = hasPendingWork
    self.nextDeadline = nextDeadline
    self.redrawIdentities = redrawIdentities
  }
}

/// Snapshot of a removed view retained for visual-only exit animation.
///
/// The snapshot holds the full subtree as it existed at the moment the
/// node was removed from the live resolved tree, along with the parent
/// identity and child-index needed to re-inject the subtree in roughly
/// the same visual position during the removal animation.
package struct RemovalEntry: Sendable {
  package var identity: Identity
  package var snapshot: ResolvedNode
  package var parentIdentity: Identity?
  package var childIndex: Int
  package var transition: AnyTransition
  package var animationBox: AnimationBox?
  package var startTime: MonotonicInstant
  /// Opacity at the moment the removal was snapped.  Normally `1.0`
  /// (the identity phase value), but when the view was still fading
  /// in via an interrupted insertion, the controller samples the
  /// mid-flight opacity and stores it here so the removal continues
  /// from the value currently on screen instead of snapping back
  /// to full opacity.
  package var startOpacity: Double = 1.0
  /// Frozen PlacedNode subtree captured from the previous frame's
  /// placed tree at the moment the removal was snapped.  When
  /// present, the controller injects this subtree into the placed
  /// tree after layout (draw-only overlay) instead of re-injecting
  /// at the resolved level.  When nil (no previous placed tree
  /// cached), the controller falls back to the resolved-level
  /// injection path — see ``applyInterpolations(to:at:)``.
  package var placedSnapshot: PlacedNode? = nil
  /// Per-key persistent state threaded into the removal animation's
  /// ``CustomAnimation/animate(value:time:context:)`` on each tick.
  /// Built-in bezier/spring curves ignore this; custom animations can
  /// use it to persist bookkeeping across the frames of an exit
  /// transition (e.g. a spring that accumulates velocity).
  package var customState: AnimationState = .init()
}
