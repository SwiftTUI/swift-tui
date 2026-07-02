extension RuntimeRegistrationSet {
  /// Order-insensitive projection of every registry's keyed contents: one
  /// `registry|key` bucket per registration, with a count where handlers
  /// stack. Handlers are closures and cannot be compared for equality; keys
  /// and per-key counts are exactly the surface the scoped-restore bug class
  /// corrupts (missing, stale, or duplicated registrations after a partial
  /// republication). Used by the sampled publication oracle to compare a
  /// scoped restore against a scratch full rebuild — see
  /// ``ViewGraphFrameDraft/commitRuntimeRegistrations(from:)``.
  package func publicationOracleFingerprint() -> [String: Int] {
    var fingerprint: [String: Int] = [:]
    func add(_ registry: String, _ key: String, count: Int = 1) {
      guard count > 0 else {
        return
      }
      fingerprint["\(registry)|\(key)", default: 0] += count
    }

    if let actionRegistry {
      for identity in actionRegistry.snapshot().keys {
        add("action", identity.path)
      }
    }
    if let keyHandlerRegistry {
      for identity in keyHandlerRegistry.snapshot().keys {
        add("keyHandler", identity.path)
      }
      for (identity, handlers) in keyHandlerRegistry.snapshotKeyPressHandlers() {
        add("keyPress", identity.path, count: handlers.count)
      }
      for (identity, handlers) in keyHandlerRegistry.snapshotPasteHandlers() {
        add("paste", identity.path, count: handlers.count)
      }
    }
    if let terminationRegistry {
      for (identity, handlers) in terminationRegistry.snapshot() {
        add("termination", identity.path, count: handlers.count)
      }
    }
    if let pointerHandlerRegistry {
      for routeID in pointerHandlerRegistry.snapshot().keys {
        add("pointer", String(describing: routeID))
      }
      for routeID in pointerHandlerRegistry.snapshotHover().keys {
        add("hover", String(describing: routeID))
      }
    }
    if let gestureRegistry {
      for identity in gestureRegistry.snapshot().keys {
        add("gesture", identity.path)
      }
    }
    if let gestureStateRegistry {
      for (identity, bindings) in gestureStateRegistry.snapshot() {
        add("gestureState", identity.path, count: bindings.count)
      }
    }
    if let defaultFocusRegistry {
      let snapshot = defaultFocusRegistry.snapshot()
      for scope in snapshot.scopes {
        add("defaultFocusScope", scope.identity.path)
      }
      for candidate in snapshot.candidates {
        add("defaultFocusCandidate", candidate.identity.path)
      }
    }
    if let focusBindingRegistry {
      for registration in focusBindingRegistry.snapshot() {
        add("focusBinding", "\(registration.identity.path)#\(registration.bindingID)")
      }
    }
    if let focusedValuesRegistry {
      for registration in focusedValuesRegistry.snapshot() {
        add("focusedValues", registration.identity.path)
      }
    }
    if let scrollPositionRegistry {
      for registration in scrollPositionRegistry.snapshot() {
        add("scrollPosition", registration.identity.path)
      }
    }
    if let lifecycleRegistry {
      let snapshot = lifecycleRegistry.snapshot()
      for handlerID in snapshot.appearHandlers.keys {
        add("lifecycleAppear", handlerID)
      }
      for handlerID in snapshot.disappearHandlers.keys {
        add("lifecycleDisappear", handlerID)
      }
      for handlerID in snapshot.changeHandlers.keys {
        add("lifecycleChange", handlerID)
      }
    }
    if let taskRegistry {
      for (identity, registrations) in taskRegistry.snapshot() {
        add("task", identity.path, count: registrations.count)
      }
    }
    if let preferenceObservationRegistry {
      for registration in preferenceObservationRegistry.snapshot() {
        add(
          "preferenceObservation",
          "\(registration.identity.path)#\(registration.handlerID)"
        )
      }
    }
    if let commandRegistry {
      for (identity, bindings) in commandRegistry.snapshot().keyCommandsByScope {
        add("command", identity.path, count: bindings.count)
      }
    }
    if let dropDestinationRegistry {
      for identity in dropDestinationRegistry.snapshot().handlersByScope.keys {
        add("dropDestination", identity.path)
      }
    }
    return fingerprint
  }
}
