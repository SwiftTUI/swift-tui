import SwiftTUICore

extension RunLoop {
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
    localTerminationRegistry.dispatch(
      TerminationRequest(exitReason),
      preferredPath: currentFocusScopePath()
    )
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
    case .userExit(let keyPress):
      self = .userExit(keyPress)
    case .signal(let name):
      self = .signal(name)
    case .inputEnded:
      self = .inputEnded
    }
  }
}
