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
    // Every key press invalidates the pending traversal record; the focus
    // traversal branches below re-record it. The record must only ever
    // describe the *latest* input, so a landing region that vanishes later
    // for unrelated reasons (a navigation push, a tab switch) keeps the
    // tracker's ordinary re-seat behavior.
    pendingFocusTraversal = nil
    // Scope-based keyCommand dispatch for modifier-bearing keys (plus
    // bare function keys, which never produce text and so are safe to
    // dispatch unmodified — this runs before edit-focus absorption, so
    // F-key commands fire even while a text input is focused).
    // Walks the current focus chain shallowest-first; a matching
    // keyCommand consumes the event (or blocks dispatch if disabled)
    // before the configured exit bindings run — so a consumer that
    // registers a `keyCommand` for an exit key (e.g. Ctrl+D) takes
    // precedence over the framework-level exit for the duration that
    // scope is on the focus chain.
    if !keyPress.modifiers.isEmpty
      || KeyBinding.allowsModifierlessCommands(for: keyPress.key)
    {
      let binding = KeyBinding(key: keyPress.key, modifiers: keyPress.modifiers)
      let invalidationsBeforeDispatch = schedulerPendingInvalidations()
      if commandRegistry.dispatch(key: binding, along: commandDispatchScopePath()) {
        requestDispatchBackstopInvalidation(
          schedulerInvalidationsBeforeDispatch: invalidationsBeforeDispatch
        )
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
    let focusedActivationIdentity = focusedIdentity.flatMap {
      activationIdentity(for: $0)
    }
    let focusedInteractions =
      focusedIdentity.flatMap { identity in
        latestSemanticSnapshot.focusRegions.first(where: { $0.identity == identity })
      }?.focusInteractions ?? .automatic

    if let focusedIdentity {
      // Bubble from the focused identity up its hosting chain (SwiftUI
      // parity: `.onKeyPress` above a `.frame`/`.id` boundary registers at
      // the structural ancestor identity, which an identity-string walk
      // cannot reach from a rerooted focus identity). The focused identity
      // itself dispatches first, preserving stacked-handler priority and
      // editor interception at the exact identity.
      let invalidationsBeforeDispatch = schedulerPendingInvalidations()
      var handled = false
      for identity in renderer.viewGraph.keyEventBubblePath(from: focusedIdentity)
      where localKeyHandlerRegistry.hasHandler(identity: identity) {
        if localKeyHandlerRegistry.dispatch(identity: identity, keyPress: keyPress) {
          handled = true
          break
        }
      }
      // The handler's own `@State` writes already invalidate the precise
      // readers (reader attribution), so the coarse root sweep is redundant
      // whenever the dispatch invalidated anything — and a full-tree re-resolve
      // on every key is expensive (e.g. re-running a presenting view's whole
      // body for each character typed into a focused TextField). An UNHANDLED
      // key gets no backstop either (mirroring the control-action path, which
      // records follow-ups only for handled dispatches): the handler declined
      // the event, and every fall-through branch below carries its own
      // backstop — a declined ESC previously root-swept here before the
      // framework dismiss branch even ran, riding the close transition's
      // replayed sets as `root_invalidated`.
      if handled {
        requestDispatchBackstopInvalidation(
          schedulerInvalidationsBeforeDispatch: invalidationsBeforeDispatch
        )
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
        let invalidationsBeforeDispatch = schedulerPendingInvalidations()
        dismiss()
        requestDispatchBackstopInvalidation(
          schedulerInvalidationsBeforeDispatch: invalidationsBeforeDispatch
        )
        return nil
      }
    }

    if focusedInteractions == .edit {
      switch keyPress {
      case KeyPress(.tab, modifiers: .shift):
        performFocusTraversal(step: -1) { focusTracker.focusPrevious() }
        return nil
      case KeyPress(.tab, modifiers: []):
        performFocusTraversal(step: 1) { focusTracker.focusNext() }
        return nil
      case let keyPress where keyPress.modifiers.isEmpty:
        switch keyPress.key {
        case .arrowLeft, .arrowRight, .arrowUp, .arrowDown,
          .character, .escape, .backspace, .home, .end,
          .insert, .delete, .pageUp, .pageDown, .functionKey:
          return nil
        case .return, .space:
          if focusedActivationIdentity == nil {
            return nil
          }
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
        let invalidationsBeforeDispatch = schedulerPendingInvalidations()
        pop()
        requestDispatchBackstopInvalidation(
          schedulerInvalidationsBeforeDispatch: invalidationsBeforeDispatch
        )
        return nil
      }
    }

    switch keyPress {
    case KeyPress(.tab, modifiers: .shift):
      performFocusTraversal(step: -1) { focusTracker.focusPrevious() }
      return nil
    case KeyPress(.tab, modifiers: []):
      performFocusTraversal(step: 1) { focusTracker.focusNext() }
      return nil
    case KeyPress(.arrowRight, modifiers: []):
      performFocusTraversal(step: 1) { focusTracker.moveFocus(.right) }
      return nil
    case KeyPress(.arrowDown, modifiers: []):
      performFocusTraversal(step: 1) { focusTracker.moveFocus(.down) }
      return nil
    case KeyPress(.arrowLeft, modifiers: []):
      performFocusTraversal(step: -1) { focusTracker.moveFocus(.left) }
      return nil
    case KeyPress(.arrowUp, modifiers: []):
      performFocusTraversal(step: -1) { focusTracker.moveFocus(.up) }
      return nil
    case KeyPress(.return, modifiers: []), KeyPress(.space, modifiers: []):
      setPressedIdentity(focusedIdentity, transient: true)
      if let actionIdentity = focusedActivationIdentity {
        let invalidationsBeforeDispatch = schedulerPendingInvalidations()
        let handled = localActionRegistry.dispatch(identity: actionIdentity)
        if handled {
          recordFollowUpInvalidation(
            for: actionIdentity,
            schedulerInvalidationsBeforeDispatch: invalidationsBeforeDispatch
          )
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
      let consumed = dispatchNonSpatialDrop(
        paths: paths,
        context: .init()
      )
      if consumed { return }
    }
    if let focusedIdentity = focusTracker.currentFocusIdentity {
      let invalidationsBeforeDispatch = schedulerPendingInvalidations()
      if localKeyHandlerRegistry.dispatchPaste(
        identity: focusedIdentity,
        content: pasteEvent.content
      ) {
        requestDispatchBackstopInvalidation(
          schedulerInvalidationsBeforeDispatch: invalidationsBeforeDispatch
        )
        return
      }
    }
    // Fall through: re-emit the paste content as a sequence of
    // character key events so text-input views (TextEditor,
    // SecureField, REPL-style consumers) continue to see pasted
    // text. This preserves pre-bracketed-paste behavior for the
    // non-drop case.
    //
    // Gated on a focused consumer that can treat the keys as TEXT — an
    // editing region or a key handler on the focus bubble path. Without
    // the gate, pasted bytes became control events on whatever was
    // focused: a multi-line paste with a destructive button focused
    // fired it once per newline (F164). `.return`/`.tab` are never
    // synthesized from pasted content even for eligible consumers —
    // activation and traversal must not be forgeable from a paste;
    // faithful multi-line insertion is the paste-HANDLER path above.
    guard focusedRegionAcceptsSynthesizedPasteText() else { return }
    // Iterate grapheme clusters, not scalars: multi-scalar characters
    // (ZWJ emoji, combining sequences) must arrive as one key event.
    for character in pasteEvent.content {
      // Skip control characters (including \n and \t — see the gate
      // comment above). Multi-scalar clusters are never control
      // characters.
      if character.unicodeScalars.count == 1,
        let scalar = character.unicodeScalars.first,
        scalar.value < 0x20 || scalar.value == 0x7F
      {
        continue
      }
      let key: KeyEvent =
        switch character {
        case " ": .space
        default: .character(character)
        }
      _ = handleKeyPress(KeyPress(key, modifiers: []))
    }
  }

  /// Whether the current focus can consume synthesized paste characters as
  /// text: the focused region declares editing interactions, or an identity
  /// on its key-event bubble path has a key handler (REPL-style consumers).
  private func focusedRegionAcceptsSynthesizedPasteText() -> Bool {
    guard let focusedIdentity = focusTracker.currentFocusIdentity else {
      return false
    }
    for identity in renderer.viewGraph.keyEventBubblePath(from: focusedIdentity)
    where localKeyHandlerRegistry.hasHandler(identity: identity) {
      return true
    }
    let region = focusTracker.focusRegions.first { region in
      region.identity == focusedIdentity
    }
    return region?.focusInteractions == .edit
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
    if let scopePath = spatialDropScopePath(for: context) {
      return dropDestinationRegistry.dispatch(
        paths: paths,
        context: context,
        along: scopePath
      )
    }
    return dispatchNonSpatialDrop(paths: paths, context: context)
  }

  /// Dispatches a location-free drop along the focused scope chain first,
  /// then — when the focus chain declines or nothing is focused — along the
  /// active/visible command-host chain. A drop is an attention-directed
  /// event with no spatial anchor in a terminal, so a visible bare-`Panel`
  /// destination with no focusable content must still be reachable; this is
  /// the drop-side twin of key commands' activation by visible context
  /// (`commandDispatchScopePath`).
  private func dispatchNonSpatialDrop(
    paths: [DroppedPath],
    context: DropContext
  ) -> Bool {
    let focusPath = currentFocusScopePath()
    if dropDestinationRegistry.dispatch(
      paths: paths,
      context: context,
      along: focusPath
    ) {
      return true
    }
    let activePath = latestSemanticSnapshot.activeCommandScopePath
    guard activePath != focusPath else { return false }
    return dropDestinationRegistry.dispatch(
      paths: paths,
      context: context,
      along: activePath
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

  /// Scope path along which a key command dispatches.
  ///
  /// Prefers the focused region's chain — when focus exists, the focused leaf's
  /// `scopePath` already extends through every ancestor command host (each
  /// `Panel` is a scope boundary), so it is the complete, correct walk. When
  /// nothing is focused, falls back to the **active/visible context**
  /// (`activeCommandScopePath`): the deepest visible hosting region's scope
  /// chain. This lets a command-host region (e.g. a bare `Panel` with no
  /// focusable child) fire its commands without being a focus target —
  /// activation by visible context, not by focusing the host.
  package func commandDispatchScopePath() -> [Identity] {
    let focusPath = currentFocusScopePath()
    if !focusPath.isEmpty {
      return focusPath
    }
    return latestSemanticSnapshot.activeCommandScopePath
  }
}
