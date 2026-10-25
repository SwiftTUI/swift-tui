package import SwiftTUIGraph

/// Staging gate for bound-at-capture state ownership (plan 2026-08-20-001).
/// Test-settable latch over `SWIFTTUI_STATE_CAPTURE_BINDING`; the bind pass
/// is the only production writer of captures, so with the gate off the
/// capture read rung is inert by construction.
@MainActor
package enum StateCaptureBindingConfiguration {
  package static var isEnabled: Bool = FeatureGate.stateCaptureBinding.initialIsEnabled()
}

/// The owner a wrapper copy was bound to when the body that captured it was
/// evaluated. A *resolver* input, not storage: reads and writes re-resolve
/// the live node from these handles on every access — exactly like the
/// graph-slot location closures — so checkpoint rewind and dormant archives
/// observe nothing new.
package struct StateCaptureBinding: Sendable {
  /// The exact node-lifetime handle the enclosing body evaluation bound.
  package let owner: StateOwnerHandle
  /// The evaluation's resolve identity, for the dead-owner refresh: when the
  /// handle no longer resolves, the identity maps through the live graph's
  /// identity index to the current occupant node (same graph scope only, so
  /// committed removal still falls through).
  package let identity: Identity
  package let graphScope: StateGraphScopeID
  /// The wrapper container's discovered-property path — the same value
  /// `DynamicPropertyPathScope.current` holds during the wrapper's
  /// `update(in:)` — so a capture-minted location names the identical
  /// path-qualified slot.
  package let path: StateSlotPath
  /// Whether the owner's node had no invalidator when the bind pass ran: the
  /// one-shot `DefaultRenderer` snapshot path, whose graph is not a mount
  /// lifetime. Its writes mirror into the authored seed (`State`'s graph-slot
  /// setter), and a write whose capture later misses keeps that mirror, since
  /// a later snapshot of the same view value is its only reader. A capture of
  /// an invalidator-backed owner that misses names a retired mount lifetime,
  /// and its write is discarded (STUI-1173, STUI-1241).
  package let isSnapshotOwner: Bool

  package init(
    owner: StateOwnerHandle,
    identity: Identity,
    graphScope: StateGraphScopeID,
    path: StateSlotPath,
    isSnapshotOwner: Bool = false
  ) {
    self.owner = owner
    self.identity = identity
    self.graphScope = graphScope
    self.path = path
    self.isSnapshotOwner = isSnapshotOwner
  }
}

/// Independent routes carried by a prepared private working copy. Owned slots
/// are optional: graphless rendering still captures environment and services.
package struct DynamicPropertyCaptureContext: Sendable {
  package var ownedSlot: StateCaptureBinding?
  package var environment: EnvironmentValues
  package var focusedValues: CapturedFocusedValuesRoute

  package func appending(_ index: Int) -> Self {
    var copy = self
    if let ownedSlot {
      copy.ownedSlot = StateCaptureBinding(
        owner: ownedSlot.owner, identity: ownedSlot.identity,
        graphScope: ownedSlot.graphScope, path: ownedSlot.path.appending(index),
        isSnapshotOwner: ownedSlot.isSnapshotOwner)
    }
    return copy
  }
}

/// The graph route is live; only the no-provider fallback is a snapshot.
package struct CapturedFocusedValuesRoute: Sendable {
  package var graphScope: StateGraphScopeID?
  package var snapshot: FocusedValues

  @MainActor
  package var current: FocusedValues {
    graphScope.flatMap { LiveFocusedValuesRegistry.currentFocusedValues(for: $0) } ?? snapshot
  }
}

/// Framework-internal capture preparation, separate from the public mutating
/// update pass and its reuse certificate. Typed custom wrappers inherit this
/// preparation through their stored built-ins without a public owner protocol.
@MainActor
package protocol CaptureBindableDynamicProperty {
  /// Overwrites the private copy immediately before authored code consumes it.
  mutating func bindCapture(_ context: DynamicPropertyCaptureContext)
}

/// Census over capture binding and imperative-state resolution: which bind
/// outcomes and which resolution rungs served. Counters are DEBUG-only (the
/// release body of `record` is empty); the event vocabulary is available in
/// every configuration so call sites need no conditional compilation.
@MainActor
package enum StateCaptureCensus {
  package enum Event: String, CaseIterable, Sendable {
    // Bind-pass outcomes.
    case bindBound = "state.captureBind.bound"
    case bindSkippedTier = "state.captureBind.skippedTier"
    case bindNoOwner = "state.captureBind.noOwner"
    case focusUnprepared = "focus.capture.unprepared"
    case focusRetired = "focus.capture.retiredOwner"
    case gestureUnprepared = "gesture.capture.unprepared"
    case gestureRetired = "gesture.capture.retiredOwner"
    // Imperative read-path rungs (plan Stage 0 ladder census + capture rungs).
    case captureHit = "state.capture.hit"
    case captureRefreshedOwner = "state.capture.refreshedOwner"
    case captureMiss = "state.capture.miss"
    case ladderExactOwner = "state.ladder.exactOwner"
    case seedFallback = "state.ladder.seedFallback"
  }

  #if DEBUG
    package private(set) static var counts: [Event: Int] = [:]

    /// Suite-scale census instrument (plan 2026-08-20-001 Stages 0/4/5):
    /// when `SWIFTTUI_STATE_CAPTURE_CENSUS_FILE` names a file, every
    /// ladder/seed/miss/skip event appends one line there — `sort | uniq -c`
    /// over a full-suite run is the rung census that gates ladder deletion.
    /// Hit-path events (`captureHit`, `captureRefreshedOwner`, `bindBound`)
    /// stay counter-only: they are hot and carry no deletion signal.
    private static let censusFilePath: String? =
      FeatureFlags.environmentValue(named: "SWIFTTUI_STATE_CAPTURE_CENSUS_FILE")

    private static func emitCensusLine(for event: Event) {
      guard let censusFilePath else {
        return
      }
      switch event {
      case .captureHit, .captureRefreshedOwner, .bindBound:
        return
      case .bindSkippedTier, .bindNoOwner, .captureMiss, .ladderExactOwner,
        .seedFallback, .focusUnprepared, .focusRetired, .gestureUnprepared, .gestureRetired:
        DebugLogRouter.emit(
          "[STATE-CENSUS] \(event.rawValue)\n",
          toFileAt: censusFilePath
        )
      }
    }
  #endif

  @inline(__always)
  package static func record(_ event: Event) {
    #if DEBUG
      counts[event, default: 0] += 1
      emitCensusLine(for: event)
    #endif
  }

  #if DEBUG
    package static func count(of event: Event) -> Int {
      counts[event] ?? 0
    }

    package static func resetForTesting() {
      counts.removeAll(keepingCapacity: false)
    }
  #endif
}
