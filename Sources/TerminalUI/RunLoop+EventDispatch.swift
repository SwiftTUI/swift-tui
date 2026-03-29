import Core
import View

extension RunLoop {
  package enum RuntimeSignalDisposition {
    case continueFrame
    case exit(RunLoopExitReason)
  }

  package func handle(_ event: RuntimeEvent) -> RunLoopExitReason? {
    switch event {
    case .signal(let name):
      scheduler.requestSignal(named: name)
      switch signalDisposition(for: name) {
      case .continueFrame:
        return nil
      case .exit(let reason):
        return reason
      }
    case .input(let inputEvent):
      switch inputEvent {
      case .key(let keyEvent):
        scheduler.requestInput()
        return handleKeyEvent(keyEvent)
      case .mouse(let mouseEvent):
        if shouldScheduleFrame(for: mouseEvent) {
          scheduler.requestInput()
        }
        handleMouseEvent(mouseEvent)
        return nil
      }
    }
  }

  package func handleKeyEvent(
    _ keyEvent: KeyEvent
  ) -> RunLoopExitReason? {
    switch keyEvent {
    case .character("q"):
      return .quitKey
    case .ctrlC:
      return .ctrlC
    default:
      break
    }

    let focusedIdentity = focusTracker.currentFocusIdentity
    let focusedInteractions =
      focusedIdentity.flatMap { identity in
        latestSemanticSnapshot.focusRegions.first(where: { $0.identity == identity })
      }?.focusInteractions ?? .automatic

    if let focusedIdentity {
      if localKeyHandlerRegistry.dispatch(
        identity: focusedIdentity,
        event: localKeyEvent(for: keyEvent)
      ) {
        return nil
      }
    }

    if let keyHandler {
      switch keyHandler(keyEvent, focusedIdentity, stateContainer) {
      case .ignored:
        break
      case .handled:
        return nil
      case .exit(let reason):
        return reason
      }
    }

    if focusedInteractions == .edit {
      switch keyEvent {
      case .tab:
        focusTracker.focusNext()
        return nil
      case .shiftTab:
        focusTracker.focusPrevious()
        return nil
      case .ctrlC:
        return .ctrlC
      case .arrowLeft, .arrowRight, .arrowUp, .arrowDown, .enter, .space,
        .character, .escape, .backspace:
        return nil
      }
    }

    switch keyEvent {
    case .tab:
      focusTracker.focusNext()
      return nil
    case .shiftTab:
      focusTracker.focusPrevious()
      return nil
    case .arrowRight:
      focusTracker.moveFocus(.right)
      return nil
    case .arrowDown:
      focusTracker.moveFocus(.down)
      return nil
    case .arrowLeft:
      focusTracker.moveFocus(.left)
      return nil
    case .arrowUp:
      focusTracker.moveFocus(.up)
      return nil
    case .enter, .space:
      setPressedIdentity(focusedIdentity, transient: true)
      if let focusedIdentity {
        _ = localActionRegistry.dispatch(identity: focusedIdentity)
      }
      return nil
    case .ctrlC:
      return .ctrlC
    case .character, .escape, .backspace:
      return nil
    }
  }

  package func signalDisposition(for name: String) -> RuntimeSignalDisposition {
    switch name {
    case "SIGWINCH":
      return .continueFrame
    default:
      return .exit(.signal(name))
    }
  }

  package func localKeyEvent(
    for keyEvent: KeyEvent
  ) -> LocalKeyEvent {
    switch keyEvent {
    case .character(let character):
      return .character(character)
    case .enter:
      return .enter
    case .space:
      return .space
    case .tab:
      return .tab
    case .shiftTab:
      return .shiftTab
    case .arrowLeft:
      return .arrowLeft
    case .arrowRight:
      return .arrowRight
    case .arrowUp:
      return .arrowUp
    case .arrowDown:
      return .arrowDown
    case .backspace:
      return .backspace
    case .escape:
      return .escape
    case .ctrlC:
      return .ctrlC
    }
  }
}
