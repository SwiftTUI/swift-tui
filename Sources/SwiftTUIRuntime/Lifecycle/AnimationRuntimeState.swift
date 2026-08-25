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
  /// operates on intrinsic-layout leaves).  The `from` modifiers hold
  /// the starting delta; edge-relative moves are resolved against the
  /// render surface during placed sampling.
  case insertionOffset(from: TransitionModifiers)
  /// A matched-geometry animation between two placed bounds.  At
  /// progress 0 the target identity renders at `fromBounds` (the
  /// `properties` it tracks, measured around `anchor`); at progress 1 it
  /// renders at its natural new bounds (looked up in the current placed
  /// tree).
  case matchedGeometry(
    fromBounds: CellRect,
    properties: MatchedGeometryProperties,
    anchor: UnitPoint
  )
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
  /// The owner's identity in the most recently processed canonical tree.
  ///
  /// Entity-keyed interpolation uses this only to route through the resolved
  /// tree efficiently. Matching still keys on ``ownerViewNodeID``. A full
  /// resolved-tree pass refreshes the value after an identity-changing move;
  /// deadline-only ticks reuse it because their canonical tree is unchanged.
  package var resolvedIdentity: Identity? = nil
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
  /// Set once this animation released its logical retain on `batchID`
  /// early (an `Animation.logicallyComplete(after:)` curve past that
  /// instant), so the release at curve end decrements only the removed
  /// count.
  package var isLogicallyReleased = false
  /// The velocity this animation was released with, in progress units per
  /// second along its own `from -> to` axis (plan 2026-08-25-002 T4): the
  /// outgoing curve's velocity on a retarget, or the sampled velocity of
  /// preceding `tracksVelocity` writes. `nil` starts the curve at rest.
  /// Consumed by ``Animation/evaluate(elapsed:state:initialVelocity:)``.
  package var initialVelocity: Double? = nil
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
  /// Batch retained by this visual exit until its selected completion barrier.
  package var completionBatchID: AnimationBatchID? = nil
  /// The curve has reached its final value. The final overlay remains for one
  /// committed presentation turn so `.logicallyComplete` and `.removed` are
  /// observably distinct barriers.
  package var isLogicallyComplete = false
  /// Frozen PlacedNode subtree captured from the previous frame's
  /// placed tree at the moment the removal was snapped.  When
  /// present, the controller injects this subtree into the placed
  /// tree after layout (draw-only overlay) instead of re-injecting
  /// at the resolved level.  When nil (no previous placed tree
  /// cached), the controller falls back to the resolved-level
  /// injection path — see ``applyInterpolations(to:at:)``.
  package var placedSnapshot: PlacedNode? = nil
  /// Set when the departing subtree carries a matched-geometry instance
  /// whose key swapped to a live counterpart on the removal frame. The exit
  /// overlay then travels to the counterpart's rect while its transition
  /// plays, so the pair coincides and cross-fades along one path — the
  /// SwiftUI behavior where a view in its removal transition is positioned
  /// onto the new source. `nil` fades in place.
  package var matchedTravel: MatchedRemovalTravel? = nil
  /// Per-key persistent state threaded into the removal animation's
  /// ``CustomAnimation/animate(value:time:context:)`` on each tick.
  /// Built-in bezier/spring curves ignore this; custom animations can
  /// use it to persist bookkeeping across the frames of an exit
  /// transition (e.g. a spring that accumulates velocity).
  package var customState: AnimationState = .init()
}

/// The counterpart a departing matched-geometry instance travels toward
/// during its exit transition (``RemovalEntry/matchedTravel``).
package struct MatchedRemovalTravel: Sendable, Equatable {
  /// The matched node inside the frozen exit overlay: its frozen rect is
  /// the `from`, and the interpolated rect is applied to it (and its
  /// coextensive decoration) exactly as the live side applies a match.
  package var matchedIdentity: Identity
  /// The live identity that received the key this frame. Its rect is read
  /// from the current placed tree on every sample, so a destination that
  /// re-lays out mid-animation is still tracked.
  package var destinationIdentity: Identity
  /// The departing instance's own `properties` and `anchor`, as SwiftUI
  /// reads the non-source's configuration.
  package var properties: MatchedGeometryProperties
  package var anchor: UnitPoint

  package init(
    matchedIdentity: Identity,
    destinationIdentity: Identity,
    properties: MatchedGeometryProperties,
    anchor: UnitPoint
  ) {
    self.matchedIdentity = matchedIdentity
    self.destinationIdentity = destinationIdentity
    self.properties = properties
    self.anchor = anchor
  }
}
