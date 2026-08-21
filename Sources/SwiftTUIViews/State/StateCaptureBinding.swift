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

  package init(
    owner: StateOwnerHandle,
    identity: Identity,
    graphScope: StateGraphScopeID,
    path: StateSlotPath
  ) {
    self.owner = owner
    self.identity = identity
    self.graphScope = graphScope
    self.path = path
  }
}

/// A wrapper copy's capture state. Tri-state because class containers bind
/// through shared memory: a struct copy is private to its mount (overwriting
/// is always correct), but one class instance mounted at several identities
/// shares this slot, and last-writer-wins would collapse every mount onto
/// one owner — the demotion latch keeps those instances on the ambient
/// ladder instead.
package enum StateCaptureSlot: Sendable {
  case unbound
  case bound(StateCaptureBinding)
  case conflicted
}

/// Framework-internal in-place capture binding. Deliberately package-scoped:
/// third parties cannot conform, so `DynamicProperty.update`'s nonmutating
/// contract ("a plain value mutation cannot be silently applied to an
/// extracted copy") stays intact for them — the bind pass is the only
/// mutator, and it writes through the container instance body evaluation
/// actually consumes.
@MainActor
package protocol CaptureBindableDynamicProperty {
  /// `sharedMutableContainer` is true when the container is a class
  /// instance: overwriting a *different, still-live* owner then demotes the
  /// slot to `.conflicted` instead of last-writer-wins. Overwriting a dead
  /// owner (identity churn, teardown) is a normal re-bind.
  mutating func bindCapture(
    _ binding: StateCaptureBinding,
    sharedMutableContainer: Bool
  )
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
    case classConflictDemoted = "state.captureBind.classConflictDemoted"
    // Imperative read-path rungs (plan Stage 0 ladder census + capture rungs).
    case captureHit = "state.capture.hit"
    case captureRefreshedOwner = "state.capture.refreshedOwner"
    case captureMiss = "state.capture.miss"
    case ladderExactOwner = "state.ladder.exactOwner"
    case ladderAncestorWalk = "state.ladder.ancestorWalk"
    case ladderSoleBinding = "state.ladder.soleBinding"
    case ladderMinted = "state.ladder.minted"
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
      case .bindSkippedTier, .bindNoOwner, .classConflictDemoted, .captureMiss,
        .ladderExactOwner, .ladderAncestorWalk, .ladderSoleBinding, .ladderMinted,
        .seedFallback:
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
