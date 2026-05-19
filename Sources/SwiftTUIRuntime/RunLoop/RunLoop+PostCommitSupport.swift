import SwiftTUICore

struct CommittedFramePresentationResult {
  var metrics: PresentationMetrics
  var duration: Duration
}

extension RunLoop {
  func presentationDamage(
    for artifacts: FrameArtifacts,
    convergence: FocusSyncConvergenceState
  ) -> PresentationDamage? {
    if convergence.rerenderedForFocusSync {
      nil
    } else {
      artifacts.presentationDamage
    }
  }

  func presentCommittedFrameWithDiagnosticsTiming(
    _ artifacts: FrameArtifacts,
    damage: PresentationDamage?,
    hasDiagnosticsLogger: Bool
  ) throws -> CommittedFramePresentationResult {
    let presentStart: ContinuousClock.Instant?
    let presentClock: ContinuousClock?
    if hasDiagnosticsLogger {
      let clock = ContinuousClock()
      presentClock = clock
      presentStart = clock.now
    } else {
      presentClock = nil
      presentStart = nil
    }

    let metrics = try presentCommittedFrame(
      artifacts,
      damage: damage
    )
    let duration: Duration =
      if let presentStart, let presentClock {
        presentStart.duration(to: presentClock.now)
      } else {
        .zero
      }
    return CommittedFramePresentationResult(
      metrics: metrics,
      duration: duration
    )
  }

  func flushPostActionInvalidations() {
    guard !postActionInvalidationIdentities.isEmpty else {
      return
    }

    scheduler.requestInvalidation(of: postActionInvalidationIdentities)
    postActionInvalidationIdentities.removeAll(keepingCapacity: true)
  }

  func requestNextAnimationFrameIfNeeded(
    _ animationTick: AnimationTickResult
  ) {
    guard runtimeConfiguration.motion == .normal,
      animationTick.hasPendingWork,
      let nextDeadline = animationTick.nextDeadline
    else {
      return
    }

    let now = MonotonicInstant.now()
    let scheduledDeadline =
      if nextDeadline > now {
        nextDeadline
      } else {
        now.advanced(by: AnimationWakeTiming.minimumLeadTime)
      }
    scheduler.requestDeadline(scheduledDeadline)
  }
}
