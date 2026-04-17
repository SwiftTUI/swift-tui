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
      case .key(let keyPress):
        scheduler.requestInput()
        return handleKeyPress(keyPress)
      case .mouse(let mouseEvent):
        if shouldScheduleFrame(for: mouseEvent) {
          scheduler.requestInput()
        }
        handleMouseEvent(mouseEvent)
        return nil
      }
    }
  }

  package func handleKeyPress(
    _ keyPress: KeyPress
  ) -> RunLoopExitReason? {
    let keyEvent = keyPress.key

    // Default quit behavior.
    switch keyEvent {
    case .character("q") where keyPress.modifiers.isEmpty:
      return .quitKey
    case .character("c") where keyPress.modifiers == .ctrl:
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
        keyPress: keyPress
      ) {
        return nil
      }
    }

    if let keyHandler {
      switch keyHandler(keyPress, focusedIdentity, stateContainer) {
      case .ignored:
        break
      case .handled:
        return nil
      case .exit(let reason):
        return reason
      }
    }

    if focusedInteractions == .edit {
      switch keyPress {
      case KeyPress(.tab, modifiers: .shift):
        focusTracker.focusPrevious()
        return nil
      case KeyPress(.tab, modifiers: []):
        focusTracker.focusNext()
        return nil
      case KeyPress(.character("c"), modifiers: .ctrl):
        return .ctrlC
      case let keyPress where keyPress.modifiers.isEmpty:
        switch keyPress.key {
        case .arrowLeft, .arrowRight, .arrowUp, .arrowDown, .return, .space,
          .character, .escape, .backspace, .home, .end:
          return nil
        case .tab:
          return nil
        }
      default:
        return nil
      }
    }

    switch keyPress {
    case KeyPress(.tab, modifiers: .shift):
      focusTracker.focusPrevious()
      return nil
    case KeyPress(.tab, modifiers: []):
      focusTracker.focusNext()
      return nil
    case KeyPress(.arrowRight, modifiers: []):
      focusTracker.moveFocus(.right)
      return nil
    case KeyPress(.arrowDown, modifiers: []):
      focusTracker.moveFocus(.down)
      return nil
    case KeyPress(.arrowLeft, modifiers: []):
      focusTracker.moveFocus(.left)
      return nil
    case KeyPress(.arrowUp, modifiers: []):
      focusTracker.moveFocus(.up)
      return nil
    case KeyPress(.return, modifiers: []), KeyPress(.space, modifiers: []):
      setPressedIdentity(focusedIdentity, transient: true)
      if let focusedIdentity {
        let handled = localActionRegistry.dispatch(identity: focusedIdentity)
        if handled,
          let identity = localActionRegistry.followUpInvalidationIdentity(for: focusedIdentity)
        {
          postActionInvalidationIdentities.insert(identity)
        }
      }
      return nil
    case KeyPress(.character("c"), modifiers: .ctrl):
      return .ctrlC
    default:
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
}
