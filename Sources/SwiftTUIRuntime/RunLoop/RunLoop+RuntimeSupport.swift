import SwiftTUICore

extension RunLoop {
  package func configuredUserExit(_ keyPress: KeyPress) -> RunLoopExitReason? {
    guard presentationSurface.supportsUserExit else {
      reportRuntimeIssue(
        RuntimeIssue(
          severity: .error,
          code: "lifecycle.userExitUnsupported",
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

  package func scheduleNextWakeIfNeeded(
    using eventPump: EventPump
  ) {
    let now = MonotonicInstant.now()
    guard let nextWake = scheduler.nextWakeInstant(after: now),
      nextWake > now
    else {
      return
    }

    let sleepDuration = now.duration(to: nextWake)
    if sleepDuration > .zero {
      eventPump.scheduleDeadlineWake(sleepDuration)
    }
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
