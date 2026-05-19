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
