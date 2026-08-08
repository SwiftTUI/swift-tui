import SwiftTUICore

extension RunLoop {
  /// Tick cadence for scroll momentum, matching the animation controller's 33 ms
  /// frame interval so a fling decays in step with how animations advance.
  ///
  /// A measured 16 ms adaptive arm (scroll-latency R1.5, plan 2026-08-08-001)
  /// was refuted at the vehicle: the committed presentation cadence of a fling
  /// is already ~16 ms effective in the high-velocity window (each tick's
  /// registry write is followed by the `@State`-echo invalidation frame — two
  /// committed frames per 33 ms tick), and past that window the integer-cell
  /// crossing rate of the decaying velocity (12.5 ms/cell at the 80 cells/s
  /// seed cap) is the binding smoothness ceiling, not the tick interval. The
  /// 16 ms arm measured +6% fling CPU, +36% scheduler ticks, identical
  /// committed-frame count, and no interval-metric improvement — a formal
  /// gate FAIL. `ScrollMomentumController.step(to:)` integrates the exact
  /// decay, so a future cadence change stays trajectory-invariant.
  private var scrollMomentumFrameInterval: Duration { .milliseconds(33) }

  /// Records a captured scroll-pan sample for release-velocity estimation.
  /// Called from the run loop's captured `.dragged` branch (and the
  /// drag-threshold takeover) — the altitude at which coalescing has already
  /// happened, so the sampler sees the same merged stream the view does.
  func recordScrollPanSample(
    location: PointerLocation,
    timestamp: MonotonicInstant
  ) {
    scrollPanVelocitySampler.record(location: location.location, time: timestamp)
  }

  /// Seeds (or clears the sampler for) a fling when a captured scroll pan
  /// releases. Called from `handleMouseUp`'s captured branch *before* the
  /// capture state is torn down by its `defer`.
  ///
  /// No-op unless the released route is an actual scroll route with extents and
  /// motion is enabled; momentum is opt-out under reduced motion, like animations.
  func beginScrollMomentumOnReleaseIfNeeded(
    routeIdentity: Identity,
    releaseLocation: PointerLocation,
    timestamp: MonotonicInstant
  ) {
    defer { scrollPanVelocitySampler.clear() }

    guard runtimeConfiguration.motion == .normal,
      let context = scrollContext(for: routeIdentity)
    else {
      return
    }

    scrollPanVelocitySampler.record(location: releaseLocation.location, time: timestamp)
    guard let pointerVelocity = scrollPanVelocitySampler.velocity(at: timestamp) else {
      return
    }

    // Content follows the finger: offset velocity is the negation of pointer
    // velocity (the pan maps `offset = startOffset − (location − startLocation)`).
    let offsetVelocity = Vector(dx: -pointerVelocity.dx, dy: -pointerVelocity.dy)
    let canScrollX = context.contentBounds.size.width > context.viewportRect.size.width
    let canScrollY = context.contentBounds.size.height > context.viewportRect.size.height

    let started = scrollMomentum.begin(
      identity: routeIdentity,
      offsetVelocity: offsetVelocity,
      canScrollX: canScrollX,
      canScrollY: canScrollY,
      now: timestamp,
      bindingSourceID: localScrollPositionRegistry.bindingSourceID(for: routeIdentity)
    )
    if started {
      scheduler.requestDeadline(timestamp.advanced(by: scrollMomentumFrameInterval))
    }
  }

  /// Retires any fling whose scroll route re-registered a DIFFERENT authored
  /// binding since the fling began (a conditional swapped the `position:`
  /// binding under a stable route identity). Runs after focus sync, once the
  /// frame's live registrations are current. Late-binding dispatch would
  /// otherwise glide the fling into the replacement binding — a scroll the
  /// new binding's owner never initiated.
  func reconcileScrollMomentumBindings() {
    guard scrollMomentum.hasActiveMomentum else {
      return
    }
    for identity in scrollMomentum.activeIdentities {
      scrollMomentum.retireIfBindingChanged(
        identity: identity,
        currentSourceID: localScrollPositionRegistry.bindingSourceID(for: identity)
      )
    }
  }

  /// Cancels any fling on the scroll route that contains `identity` — used to
  /// stop momentum when a fresh press or wheel notch lands inside that scroll
  /// view (touch-to-stop). `identity` is the hit/route identity of the new input,
  /// a descendant (or the route itself) of the flinging scroll route.
  func cancelScrollMomentum(containing identity: Identity) {
    guard scrollMomentum.hasActiveMomentum else {
      return
    }
    scrollMomentum.cancel(forDescendant: identity)
  }

  /// Advances active scroll momentum on a deadline-driven frame, writing the
  /// decayed offset into `localScrollPositionRegistry` so the *same* frame
  /// renders it, then re-arms the next tick.
  ///
  /// Sits beside `drainGestureDeadlinesIfNeeded(for:)` — both are pre-render,
  /// deadline-driven mutations. The 33 ms cadence is paced by the scheduler
  /// deadline, never by the `@State`-write invalidation each `scrollBy`
  /// queues: momentum advances only on a `.deadline` frame, so the follow-up
  /// invalidation frame does not re-advance the physics and cannot busy-loop.
  /// In practice the deadline frame itself elides (its registry write lands
  /// as a pending invalidation for the NEXT frame) and that follow-up
  /// invalidation frame renders the moved offset — one full pipeline per
  /// tick either way. (A wheel `.scrolled` never schedules an input frame at
  /// all — `shouldScheduleFrame` is false for it — so the wheel path has no
  /// analogous second frame; its binding write and spine invalidation
  /// coalesce into one scheduled frame by construction.)
  func advanceScrollMomentumIfNeeded(for scheduledFrame: ScheduledFrame) {
    guard scrollMomentum.hasActiveMomentum else {
      return
    }
    guard scheduledFrame.causes.contains(.deadline) else {
      // Not our cadence tick — keep a deadline armed so the loop wakes to tick.
      rearmScrollMomentumDeadline(from: frameClock())
      return
    }

    let now = scheduledFrame.triggeredDeadline ?? frameClock()
    for tick in scrollMomentum.step(to: now) where tick.deltaX != 0 || tick.deltaY != 0 {
      let moved = localScrollPositionRegistry.scrollBy(
        x: tick.deltaX,
        y: tick.deltaY,
        scopeIdentity: tick.identity
      )
      if !moved {
        // Clamped to no movement (content edge) or the registration is gone
        // (tab switch / content removal): this route is finished.
        scrollMomentum.cancel(tick.identity)
      }
    }
    rearmScrollMomentumDeadline(from: now)
  }

  private func rearmScrollMomentumDeadline(from now: MonotonicInstant) {
    guard scrollMomentum.hasActiveMomentum else {
      return
    }
    // Deadlines armed here during a drain pass are withheld by the pass's
    // `DeadlineArmCut` and consumed by the next pass, so the re-arm cannot
    // recreate the F41 drain livelock — the consumable set of one pass stays
    // finite.
    scheduler.requestDeadline(now.advanced(by: scrollMomentumFrameInterval))
  }
}
