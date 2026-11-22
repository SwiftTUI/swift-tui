import SwiftTUICore

extension RunLoop {
  package func configuredUserExit(_ keyPress: KeyPress) -> RunLoopExitReason? {
    guard currentInputOrigin != .browser, presentationSurface.supportsUserExit else {
      reportRuntimeIssue(
        RuntimeIssue(
          severity: .error,
          code: .Lifecycle.userExitUnsupported,
          message: "Exit keys cannot end an app on this host. The session is still running."
        )
      )
      return nil
    }
    return .userExit(keyPress)
  }

  package var runtimeRegistrations: RuntimeRegistrationSet {
    RuntimeRegistrationSet(
      actionRegistry: localActionRegistry,
      keyHandlerRegistry: localKeyHandlerRegistry,
      terminationRegistry: localTerminationRegistry,
      pointerHandlerRegistry: localPointerHandlerRegistry,
      gestureRegistry: localGestureRegistry,
      gestureStateRegistry: localGestureStateRegistry,
      defaultFocusRegistry: localDefaultFocusRegistry,
      focusBindingRegistry: localFocusBindingRegistry,
      focusedValuesRegistry: localFocusedValuesRegistry,
      scrollPositionRegistry: localScrollPositionRegistry,
      lifecycleRegistry: localLifecycleRegistry,
      taskRegistry: localTaskRegistry,
      preferenceObservationRegistry: localPreferenceObservationRegistry,
      commandRegistry: commandRegistry,
      dropDestinationRegistry: dropDestinationRegistry
    )
  }

  /// Asks the event pump for the run loop's next wake. `run()` calls this at
  /// the end of each turn of its loop, where it goes on to wait for an event.
  /// It also calls it twice during start-up. The first of those calls
  /// follows the first presentation, and no wait follows it: start-up then
  /// asks the scheduler itself whether a frame is ready, and when one is and
  /// no input waits, it runs one more pass and calls this again. The loop's
  /// first wait comes after that.
  ///
  /// One reading of the clock decides. The scheduler says what is next after
  /// that instant, and there are three answers:
  ///
  /// - Nothing is pending and nothing is armed. The run loop waits. A later
  ///   request for an invalidation, an external wake or a deadline wakes it
  ///   through the scheduler's wake handler.
  /// - The next wake is later than the reading. The event pump sleeps for the
  ///   time between the two, measured from that same reading, and then wakes
  ///   the run loop.
  /// - A frame is ready at the reading: a cause is pending, or a deadline is
  ///   due. The run loop must not wait, so the event pump wakes it at once.
  ///
  /// The third answer does not rest on how the frame driver's last pass
  /// ended. A pass looks at the scheduler at its own, earlier instant, and a
  /// deadline can come due after that look. No request stands behind such a
  /// deadline, so the pump holds no wake for it. A pass can also end with
  /// ready work on purpose: at the acquisition limit, for pending input, at
  /// the work budget. Where a request of that turn has put a wake into the
  /// pump already, this one joins it: the pump holds one wake at most.
  ///
  /// A wake at once has to lead to a frame, or the run loop would spin. So
  /// the run loop asks for one only when the frame driver has acquired a
  /// frame since it last asked. In a session, a frame that is ready and that
  /// the next turn does not acquire means a terminal handoff: the frame
  /// driver renders nothing until the handoff ends, and its end wakes the
  /// run loop (`performTerminalHandoff`). The same rule bounds a test that
  /// pins `frameClock` behind the wall clock, where this reading sees a
  /// deadline as due and the frame driver's reading does not.
  package func requestNextWake(
    using eventPump: EventPump
  ) {
    let now = MonotonicInstant.now()
    guard let nextWake = scheduler.nextWakeInstant(after: now) else {
      return
    }

    let sleepDuration = now.duration(to: nextWake)
    guard sleepDuration <= .zero else {
      eventPump.scheduleDeadlineWake(sleepDuration)
      return
    }

    guard renderIntentGenerationAtLastImmediateWake != nextRenderIntentGeneration else {
      return
    }
    renderIntentGenerationAtLastImmediateWake = nextRenderIntentGeneration
    eventPump.wakeNow()
  }

  package func terminationDisposition(
    for exitReason: RunLoopExitReason
  ) -> TerminationDisposition {
    let disposition = localTerminationRegistry.dispatch(
      TerminationRequest(exitReason),
      preferredPath: currentFocusScopePath()
    )
    if exitReason == .inputEnded {
      return .allow
    }
    return disposition
  }

  package func updateFocusPresentation(
    _ presentation: FocusPresentation
  ) {
    guard currentFocusPresentation != presentation else {
      return
    }

    currentFocusPresentation = presentation
    focusPresentationHandler?(presentation)
  }
}

extension TerminationRequest {
  package init(_ exitReason: RunLoopExitReason) {
    switch exitReason {
    case .programmatic:
      self = .programmatic
    case .userExit(let keyPress):
      self = .userExit(keyPress)
    case .signal(let name):
      self = .signal(name)
    case .inputEnded:
      self = .inputEnded
    }
  }
}
