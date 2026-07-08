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

  /// Requests the coarse root sweep after a consumed event dispatch — but only
  /// when the dispatched action scheduled no invalidation of its own
  /// (mirroring ``recordFollowUpInvalidation(for:schedulerInvalidationsBeforeDispatch:)``).
  /// An action whose writes are tracked has already invalidated its precise
  /// readers; the redundant sweep would put the root identity in the frame's
  /// raw set — `root_invalidated` disables selective evaluation wholesale, and
  /// a presentation transition replays that set on every tick until it
  /// converges. The sweep stays as the backstop for actions with untracked
  /// side effects, which schedule nothing.
  func requestDispatchBackstopInvalidation(
    schedulerInvalidationsBeforeDispatch before: Set<Identity>
  ) {
    guard schedulerPendingInvalidations() == before else {
      return
    }
    InvalidationSourceTrace.note("dispatch-backstop", [rootIdentity])
    scheduler.requestInvalidation(of: [rootIdentity])
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
    let actionRequestedInvalidation = schedulerPendingInvalidations() != before
    guard !actionRequestedInvalidation else {
      return
    }
    // A handled action with no tracked side effect and no resolvable
    // dynamic-property-scope owner has an unknown effect scope, so the only
    // sound follow-up target is the content root. This class used to render
    // by accident: the owner identity (departed, or never registered when
    // the authoring context was unavailable at registration time) tripped
    // the unmapped-identity escalation into a full root evaluation. That
    // escalation is retired (F10 slice 1) — the queue boundary remaps or
    // drops unmapped identities — so the unattributable sweep is requested
    // explicitly instead.
    let registeredOwner = localActionRegistry.followUpInvalidationIdentity(for: actionIdentity)
    let identity =
      registeredOwner.flatMap { owner in
        renderer.hasLiveInvalidationTarget(for: owner) ? owner : nil
      } ?? rootIdentity
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
    let nextTick = now.advanced(by: animationController.animationFrameInterval)
    // CLAMP, don't guard (F79): this used to decline when
    // `scheduler.hasPendingFrame(at: nextTick)` — but a pending CAUSE
    // (input/invalidation) is not durable wake insurance: the frame draining
    // it can itself be skipped, leaving live animation work with no armed
    // deadline, parked until the next input ("stuck until you scroll"). The
    // unconditional arm is safe on both axes the old guard worried about:
    // the scheduler min-coalesces re-arms into its single deadline slot, so
    // re-arming is idempotent and only ever ADDS the tick this live work
    // genuinely needs; and the transition-burst cancel-cascade the guard was
    // introduced for (`7dcddf11` — switching away from a still-animating tab
    // kept the pump hot) was phantom orphaned work, root-fixed by the
    // departed-identity prune in `AnimationController.processResolvedTree`,
    // which keeps this method's `requiresContinuedAnimationFrames` entry
    // condition truthful.
    scheduler.requestDeadline(nextTick)
  }
}
