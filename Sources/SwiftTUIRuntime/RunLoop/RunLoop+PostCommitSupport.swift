import SwiftTUICore

struct CommittedFramePresentationResult {
  var metrics: PresentationMetrics
  var duration: Duration
}

extension RunLoop {
  func presentationDamage(
    for artifacts: FrameArtifacts,
    convergence _: FocusSyncConvergenceState
  ) -> PresentationDamage? {
    // Async acquisition may commit renderer artifacts that are later withheld
    // from the presentation stream. Frontends consume damage relative to the
    // last surface they actually received, so derive that contract here.
    RasterSurfaceDamageDiff.diff(
      previous: previousPresentedRasterSurface,
      current: artifacts.rasterSurface
    )
  }

  func recordPresentedRasterSurface(_ surface: RasterSurface) {
    previousPresentedRasterSurface = surface
  }

  func presentCommittedFrameWithDiagnosticsTiming(
    _ artifacts: FrameArtifacts,
    damage: PresentationDamage?,
    hasFrameSink: Bool
  ) throws -> CommittedFramePresentationResult {
    let presentStart: ContinuousClock.Instant?
    let presentClock: ContinuousClock?
    if hasFrameSink {
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

    InvalidationSourceTrace.note("post-action", postActionInvalidationIdentities)
    scheduler.requestInvalidation(of: postActionInvalidationIdentities)
    postActionInvalidationIdentities.removeAll(keepingCapacity: true)
  }

  /// The scheduler's coalesced invalidation identities right now — used to tell
  /// whether a just-dispatched action requested an invalidation of its own.
  func schedulerPendingInvalidations() -> Set<Identity> {
    (scheduler as? FrameScheduler)?.pendingInvalidatedIdentities ?? []
  }

  /// Records a control action's coarse follow-up invalidation — but skips it
  /// when the action already requested a (reader-attributed) invalidation, so a
  /// redundant owner-scope sweep does not re-resolve a disjoint subtree.
  ///
  /// The follow-up identity is the action's dynamic-property-scope owner; under
  /// reader attribution that owner is frequently an *ancestor* of a large reused
  /// subtree (a sheet/palette background), and the action's `@State` write has
  /// already invalidated the precise readers (or the owner itself, via the
  /// no-reader fallback). So the follow-up is redundant whenever the dispatch
  /// invalidated anything; it is kept only as a backstop for actions with
  /// untracked side effects (which request nothing). Reader-attribution-off is
  /// byte-identical (the follow-up is always inserted).
  func recordFollowUpInvalidation(
    for actionIdentity: Identity,
    schedulerInvalidationsBeforeDispatch before: Set<Identity>
  ) {
    guard let identity = localActionRegistry.followUpInvalidationIdentity(for: actionIdentity)
    else {
      return
    }
    let actionRequestedInvalidation =
      ReaderAttributionConfiguration.isEnabled
      && schedulerPendingInvalidations() != before
    guard !actionRequestedInvalidation else {
      return
    }
    postActionInvalidationIdentities.insert(identity)
  }

  func requestNextAnimationFrameIfNeeded(
    _ animationTick: AnimationTickResult
  ) {
    guard runtimeConfiguration.motion == .normal else {
      return
    }

    let now = MonotonicInstant.now()
    if animationTick.hasPendingWork, let nextDeadline = animationTick.nextDeadline {
      let scheduledDeadline =
        if nextDeadline > now {
          nextDeadline
        } else {
          now.advanced(by: AnimationWakeTiming.minimumLeadTime)
        }
      scheduler.requestDeadline(scheduledDeadline)
      return
    }

    // Even when THIS frame's tick reported no pending work, the LIVE controller
    // can still hold an active animation or an unfired `withAnimation` completion
    // that a discarded/superseded sibling frame's drain rolled back onto live (the
    // committing draft only reports the work IT saw). Without this the pump would
    // idle with an un-drained animation, so the animation never ticks to logical
    // completion and its deferred completion never fires — a `PhaseAnimator` loop
    // would advance one phase and then stall. Keep the pump alive until live is
    // genuinely drained.
    if renderer.internalAnimationController.requiresContinuedAnimationFrames {
      scheduler.requestDeadline(
        now.advanced(by: renderer.internalAnimationController.animationFrameInterval)
      )
    }
  }

  /// Re-arms the animation deadline after a SKIPPED async frame
  /// (cancelled-before-start or dropped-completed) when the live controller still
  /// has un-drained animation work.
  ///
  /// A skipped frame abandons its draft without committing, so — unlike the
  /// committed and elided paths — it never reschedules the next deadline. If the
  /// skipped frame was the one draining an animation, the live controller keeps
  /// that animation active (its draft's drain was discarded) but no deadline is
  /// armed, so the run loop idles and the deferred `withAnimation` completion
  /// (e.g. a `PhaseAnimator` loop's per-phase completion) never fires until an
  /// unrelated event happens to wake the loop — the "stuck until you scroll"
  /// symptom. Keep the pump alive so the animation re-drains and its completion
  /// fires on the next committed frame.
  func requestNextAnimationFrameAfterSkippedFrameIfNeeded() {
    let animationController = renderer.internalAnimationController
    guard runtimeConfiguration.motion == .normal,
      animationController.requiresContinuedAnimationFrames
    else {
      return
    }
    let now = MonotonicInstant.now()
    scheduler.requestDeadline(now.advanced(by: animationController.animationFrameInterval))
  }
}
