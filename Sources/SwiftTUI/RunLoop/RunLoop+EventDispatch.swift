import SwiftTUICore
import SwiftTUIViews

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
      case .paste(let pasteEvent):
        scheduler.requestInput()
        handlePaste(pasteEvent)
        return nil
      case .drop(let paths, let context):
        scheduler.requestInput()
        _ = handleDrop(paths: paths, context: context)
        return nil
      }
    }
  }

  package func handleKeyPress(
    _ keyPress: KeyPress
  ) -> RunLoopExitReason? {
    // Scope-based keyCommand dispatch for modifier-bearing keys.
    // Walks the current focus chain shallowest-first; a matching
    // keyCommand consumes the event (or blocks dispatch if disabled)
    // before the configured exit bindings run — so a consumer that
    // registers a `keyCommand` for an exit key (e.g. Ctrl+D) takes
    // precedence over the framework-level exit for the duration that
    // scope is on the focus chain.
    if !keyPress.modifiers.isEmpty {
      let binding = KeyBinding(key: keyPress.key, modifiers: keyPress.modifiers)
      if commandRegistry.dispatch(key: binding, along: currentFocusScopePath()) {
        scheduler.requestInvalidation(of: [rootIdentity])
        return nil
      }
    }

    // Configured exit bindings are the single source of truth for
    // framework-level exits. The runtime never hardcodes an exit key
    // outside this check; consumers that pass ``ExitKeyBindings.none``
    // opt out of framework-provided exits entirely.
    if exitKeyBindings.contains(keyPress) {
      return .userExit(keyPress)
    }

    let focusedIdentity = focusTracker.currentFocusIdentity
    let focusedInteractions =
      focusedIdentity.flatMap { identity in
        latestSemanticSnapshot.focusRegions.first(where: { $0.identity == identity })
      }?.focusInteractions ?? .automatic

    if let focusedIdentity,
      localKeyHandlerRegistry.hasHandler(identity: focusedIdentity)
    {
      let handled = localKeyHandlerRegistry.dispatch(
        identity: focusedIdentity,
        keyPress: keyPress
      )
      scheduler.requestInvalidation(of: [rootIdentity])
      if handled {
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

    // Framework-reserved single-key handling: bare Escape dismisses the
    // topmost eligible portal entry. Widgets and consumer `keyHandler`
    // closures get a chance to claim Escape first via the two branches
    // above; if they don't, the framework takes over so users can always
    // bail out of a modal with a single key. Toasts are not dismissed;
    // they auto-expire.
    if keyPress == KeyPress(.escape, modifiers: []) {
      if let dismiss = renderer.topmostEscapeDismissAction() {
        dismiss()
        scheduler.requestInvalidation(of: [rootIdentity])
        return nil
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

    if keyPress == KeyPress(.escape, modifiers: []) {
      if let pop = renderer.topmostNavigationDestinationPopAction(
        along: currentFocusScopePath()
      ) {
        pop()
        scheduler.requestInvalidation(of: [rootIdentity])
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
    default:
      return nil
    }
  }

  /// Routes a bracketed-paste burst either to a registered drop
  /// destination (when the payload parses into one or more
  /// path-shaped tokens and some scope on the focus chain claims it),
  /// a focused text-input paste handler, or the character-key pipeline.
  ///
  /// Leafmost-first bubbling is handled inside
  /// ``DropDestinationRegistry.dispatch(paths:along:)``; this method
  /// hands the registry the shallowest-first focus scope path and
  /// only honors consumption when the registry reports `true`.
  package func handlePaste(_ pasteEvent: PasteEvent) {
    let paths = parseDroppedPaths(pasteEvent.content)
    if !paths.isEmpty {
      let consumed = dropDestinationRegistry.dispatch(
        paths: paths,
        context: .init(),
        along: currentFocusScopePath()
      )
      if consumed { return }
    }
    if let focusedIdentity = focusTracker.currentFocusIdentity,
      localKeyHandlerRegistry.dispatchPaste(
        identity: focusedIdentity,
        content: pasteEvent.content
      )
    {
      scheduler.requestInvalidation(of: [rootIdentity])
      return
    }
    // Fall through: re-emit the paste content as a sequence of
    // character key events so text-input views (TextEditor,
    // SecureField, REPL-style consumers) continue to see pasted
    // text. This preserves pre-bracketed-paste behavior for the
    // non-drop case.
    for scalar in pasteEvent.content.unicodeScalars {
      // Skip control characters except common whitespace.
      guard scalar.value >= 0x20 || scalar == "\n" || scalar == "\t" else {
        continue
      }
      let key: KeyEvent
      switch scalar {
      case "\n", "\r": key = .return
      case "\t": key = .tab
      case " ": key = .space
      default:
        let character = Character(String(scalar))
        key = .character(character)
      }
      _ = handleKeyPress(KeyPress(key, modifiers: []))
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

  @discardableResult
  package func handleDrop(
    paths: [DroppedPath],
    context: DropContext
  ) -> Bool {
    let scopePath = spatialDropScopePath(for: context) ?? currentFocusScopePath()
    return dropDestinationRegistry.dispatch(
      paths: paths,
      context: context,
      along: scopePath
    )
  }

  package func spatialDropScopePath(
    for context: DropContext
  ) -> [Identity]? {
    let point: Point?
    if let pointer = context.pointer {
      point = pointer.location
    } else {
      point = context.location
    }
    guard let point else {
      return nil
    }

    return latestSemanticSnapshot.focusRegions
      .filter { region in region.rect.contains(point) }
      .max { lhs, rhs in lhs.scopePath.count < rhs.scopePath.count }?
      .scopePath
  }

  /// Returns the scope path for the currently focused region, or an
  /// empty array when nothing is focused. The path is ordered
  /// shallowest-first and includes the focused node's own identity
  /// when that node is itself a scope boundary — so a focused Panel
  /// sees its own commands as claimable.
  package func currentFocusScopePath() -> [Identity] {
    guard let focusedIdentity = focusTracker.currentFocusIdentity else {
      return []
    }
    return latestSemanticSnapshot.focusRegions
      .first(where: { $0.identity == focusedIdentity })?
      .scopePath ?? []
  }
}
