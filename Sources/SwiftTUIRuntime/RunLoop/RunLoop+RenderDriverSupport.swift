import SwiftTUICore

extension RunLoop {
  package struct RenderIntentCoalescingDiagnostics: Equatable, Sendable {
    package var desiredGeneration: UInt64
    package var coalescedEventBatches: Int
    package var coalescedWakeCauses: Set<WakeCause>
    /// Number of scheduler requests coalesced into the active frame. Values
    /// greater than one indicate the active frame absorbed additional input,
    /// invalidation, signal, external, or deadline intents before rendering.
    package var intentRequestCount: Int
  }

  enum AnimationWakeTiming {
    // When a frame overruns its nominal 33 ms budget, the controller's
    // requested deadline can already be in the past by the time the run loop
    // reaches the scheduling site. Clamp overdue deadlines slightly into the
    // future so the next tick runs on the next event-loop turn without
    // busy-looping in-place.
    static var minimumLeadTime: Duration { .milliseconds(1) }
  }

  /// Strategy state describing how the async path acquired a frame; the
  /// synchronous path always supplies `.completed` / `nil`.
  struct FrameAcquisitionState {
    var tailJobState: FrameTailJobState = .completed
    var completedFrameDropDecision: CompletedFrameDropDecision?
  }

  package func nextRenderIntentDiagnostics(
    for scheduledFrame: ScheduledFrame
  ) -> RenderIntentCoalescingDiagnostics {
    defer {
      nextRenderIntentGeneration &+= 1
      pendingCoalescedEventBatches = 0
      pendingCoalescedWakeCauses.removeAll(keepingCapacity: true)
    }

    return RenderIntentCoalescingDiagnostics(
      desiredGeneration: nextRenderIntentGeneration,
      coalescedEventBatches: pendingCoalescedEventBatches,
      coalescedWakeCauses: pendingCoalescedWakeCauses.union(scheduledFrame.causes),
      intentRequestCount: scheduledFrame.intentRequestCount
    )
  }

  func scheduledFrameByReconcilingExternalState(
    _ scheduledFrame: ScheduledFrame,
    currentState: State
  ) -> ScheduledFrame {
    guard previousRenderedState != currentState else {
      return scheduledFrame
    }
    var reconciled = scheduledFrame
    reconciled.causes.insert(.invalidation)
    reconciled.invalidatedIdentities.insert(rootIdentity)
    reconciled.forceRootEvaluation = true
    return reconciled
  }

  /// The scheduled frame the eager focus-sync rerender pass renders.
  ///
  /// The rerender re-renders the same scheduled frame, folding in every
  /// identity invalidated since the previous pass began — resolve-time side
  /// effects that pass could not see at its head (default-focus seeding
  /// through a `@FocusState` request) plus the relocation side effects of
  /// focus-sync processing (binding-sync flips, the focus tracker's old/new
  /// notification, scroll-reveal offset writes). Their cones must conflict
  /// with retained reuse on the rerender or pre-relocation content survives
  /// the commit.
  ///
  /// The set is then resolved onto live graph targets — portal-translated
  /// first (an overlay-hosted identity maps to its live host, matching what
  /// the frame head's own translation would do), then filtered to identities
  /// the queue boundary can still resolve. A departed identity with a live
  /// ancestor is CARRIED: `ViewGraph.nodeIDsForInvalidation` remaps its
  /// evaluation onto that ancestor while the identity itself keeps its
  /// narrow ancestor-chain reuse-denial cone (F10 slice 1). Only identities
  /// with no live ancestor at all are dropped — there is no node their
  /// evaluation could target (the queue boundary would drop them anyway,
  /// census-visible), and mid-frame arrivals stay pending in the scheduler
  /// for the next frame regardless (the rerender only peeks).
  func rerenderScheduledFrame(
    from scheduledFrame: ScheduledFrame,
    convergence: FocusSyncConvergenceState
  ) -> ScheduledFrame {
    var rerender = scheduledFrame
    rerender.invalidatedIdentities = renderer.rerenderInvalidationTargets(
      scheduledFrame.invalidatedIdentities
        .union(convergence.midFrameRelocationInvalidations),
      contentRootIdentity: rootIdentity
    )
    return rerender
  }

  func mergeLifecycleCarryForward(
    _ carryForward: [LifecycleCommitEntry],
    into lifecycle: inout [LifecycleCommitEntry]
  ) {
    guard !carryForward.isEmpty else {
      return
    }
    let retainedCurrent = lifecycle.filter { !carryForward.contains($0) }
    lifecycle = carryForward + retainedCurrent
  }

  /// Drains gesture recognizer deadlines for a frame woken by a `.deadline`
  /// cause so recognizers that transition on this wake see their new phase
  /// reflected in the upcoming render pass.
  func drainGestureDeadlinesIfNeeded(for scheduledFrame: ScheduledFrame) {
    guard scheduledFrame.causes.contains(.deadline) else {
      return
    }
    if let triggeredDeadline = scheduledFrame.triggeredDeadline {
      drainGestureDeadlines(at: triggeredDeadline)
    } else {
      assertionFailure(
        "FrameScheduler produced .deadline cause without a triggeredDeadline; "
          + "gesture deadlines will not drain this frame."
      )
    }
  }
}
