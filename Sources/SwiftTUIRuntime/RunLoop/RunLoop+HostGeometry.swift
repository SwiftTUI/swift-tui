import SwiftTUICore

extension RunLoop {
  /// Cancels a coordinate stream without synthesizing a release/activation.
  /// Called before dispatch and before rendering, including deadline renders.
  func reconcileHostGeometry(_ geometry: HostGeometryStamp?) {
    guard observedHostGeometry != geometry else { return }
    if observedHostGeometry?.session != geometry?.session {
      // A new host session (a reconnected WebHost page) numbers its
      // accessibility requests afresh; the previous session's acknowledgement
      // would read as an answer to the new session's requests.
      latestAccessibilityActionResponse = nil
    }
    observedHostGeometry = geometry
    if pointerInteraction.isRouting, cancelledHostGeometryGestureCount < .max {
      cancelledHostGeometryGestureCount += 1
    }
    for (identity, recognizer) in localGestureRegistry.activeRecognizers()
    where recognizer.isActive {
      recognizer.tearDown()
      localGestureStateRegistry.resetAll(for: identity)
    }
    pointerInteraction.reset()
    setPressedIdentity(nil, transient: false)
    pendingClickFocusRestore = nil
    scrollMomentum.cancelAll()
    scrollPanVelocitySampler = PointerVelocitySampler()
    clearPointerHover()
    lastPointerLocation = nil
  }

  /// The producer's current request AND the applied interaction map must
  /// match. Checking only arrival time or only one of these admits stale hits.
  func acceptsHostPointer(_ event: MouseEvent) -> Bool {
    let current = presentationSurface.hostLayoutConfiguration().geometry
    reconcileHostGeometry(current)
    let accepted: Bool
    if let current {
      accepted =
        current.revision == 0
        ? event.hostGeometryStamp == nil || event.hostGeometryStamp == current
        : event.hostGeometryStamp == current && appliedHostGeometry == current
    } else {
      accepted = event.hostGeometryStamp == nil
    }
    if !accepted {
      if rejectedHostGeometryPointerCount < .max { rejectedHostGeometryPointerCount += 1 }
      // One stable issue per scene keeps high-rate stale motion diagnostics bounded.
      reportRuntimeIssue(
        .init(
          severity: .warning, code: "host.geometry.stalePointer",
          message: "Pointer input from an obsolete host geometry was rejected.",
          source: "HostGeometry"
        ))
    }
    return accepted
  }
}
