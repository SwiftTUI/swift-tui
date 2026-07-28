import SwiftTUICore

/// Last-seen totals of the soundness probe's violation counters, kept on the
/// run loop so each applied frame reports only newly recorded violations.
package struct SoundnessViolationCounts: Sendable, Equatable {
  package var stampCoherence = 0
  package var deltaCheckpoint = 0
  package var checkpointStore = 0
  package var rasterDamage = 0
  package var teardownCoherence = 0
  package var registrationPublication = 0
  package var memoUnsoundSkip = 0
  package var handlerResolutionAction = 0
  package var handlerResolutionKey = 0
  package var handlerResolutionCommand = 0
  package var handlerResolutionDrop = 0
  package var handlerResolutionGesture = 0
  package var actionDispatchMiss = 0
  package var strandedListing = 0

  package init() {}

  /// The probe's live process-global totals. A run loop baselines against
  /// these when it starts so it reports only violations recorded during its
  /// own lifetime — a fresh run loop in a long test process must not
  /// re-report earlier fixtures' violations as its own first-frame findings.
  @MainActor
  package static func currentTotals() -> SoundnessViolationCounts {
    let snapshot = SoundnessCounterSnapshot.current()
    var counts = SoundnessViolationCounts()
    counts.stampCoherence = snapshot.stampCoherenceViolationCount
    counts.deltaCheckpoint = snapshot.deltaCheckpointViolationCount
    counts.checkpointStore = snapshot.checkpointStoreViolationCount
    counts.rasterDamage = snapshot.rasterDamageMismatchCount
    counts.teardownCoherence = snapshot.teardownCoherenceViolationCount
    counts.registrationPublication = snapshot.registrationPublicationViolationCount
    counts.memoUnsoundSkip = snapshot.memoUnsoundSkipCount
    counts.handlerResolutionAction = snapshot.actionResolutionViolationCount
    counts.handlerResolutionKey = snapshot.keyHandlerResolutionViolationCount
    counts.handlerResolutionCommand = snapshot.commandScopeResolutionViolationCount
    counts.handlerResolutionDrop = snapshot.dropScopeResolutionViolationCount
    counts.handlerResolutionGesture = snapshot.gestureRouteResolutionViolationCount
    counts.actionDispatchMiss = snapshot.actionDispatchMissCount
    counts.strandedListing = snapshot.strandedListingViolationCount
    return counts
  }
}

extension RunLoop {
  /// F34: route soundness-probe violations through the host-facing
  /// ``RuntimeIssueSink``. The probe's counters live in `SwiftTUICore`, below
  /// the issue sink, so the run loop polls the totals once per applied frame
  /// and emits one warning per violation kind that grew — turning what were
  /// test-only counters into signals the host can surface in the builds users
  /// actually run.
  @MainActor
  package func reportNewSoundnessProbeViolations() {
    let snapshot = SoundnessCounterSnapshot.current()
    var counts = lastSeenSoundnessViolationCounts
    reportSoundnessViolationGrowth(
      kind: "stampCoherence",
      total: snapshot.stampCoherenceViolationCount,
      detail: snapshot.lastViolationDetailByKind["stamp-coherence"],
      lastSeen: &counts.stampCoherence
    )
    reportSoundnessViolationGrowth(
      kind: "deltaCheckpoint",
      total: snapshot.deltaCheckpointViolationCount,
      detail: snapshot.lastViolationDetailByKind["delta-checkpoint"],
      lastSeen: &counts.deltaCheckpoint
    )
    reportSoundnessViolationGrowth(
      kind: "checkpointStore",
      total: snapshot.checkpointStoreViolationCount,
      detail: snapshot.lastViolationDetailByKind["checkpoint-store"],
      lastSeen: &counts.checkpointStore
    )
    reportSoundnessViolationGrowth(
      kind: "rasterDamage",
      total: snapshot.rasterDamageMismatchCount,
      detail: snapshot.lastViolationDetailByKind["raster-damage"],
      lastSeen: &counts.rasterDamage
    )
    reportSoundnessViolationGrowth(
      kind: "teardownCoherence",
      total: snapshot.teardownCoherenceViolationCount,
      detail: snapshot.lastViolationDetailByKind["teardown-coherence"],
      lastSeen: &counts.teardownCoherence
    )
    reportSoundnessViolationGrowth(
      kind: "registrationPublication",
      total: snapshot.registrationPublicationViolationCount,
      detail: snapshot.lastViolationDetailByKind["registration-publication"],
      lastSeen: &counts.registrationPublication
    )
    reportSoundnessViolationGrowth(
      kind: "memoUnsoundSkip",
      total: snapshot.memoUnsoundSkipCount,
      detail: snapshot.lastViolationDetailByKind["memo-unsound-skip"],
      lastSeen: &counts.memoUnsoundSkip
    )
    reportSoundnessViolationGrowth(
      kind: "handlerResolutionAction",
      total: snapshot.actionResolutionViolationCount,
      detail: snapshot.lastViolationDetailByKind["handler-resolution-action"],
      lastSeen: &counts.handlerResolutionAction
    )
    reportSoundnessViolationGrowth(
      kind: "handlerResolutionKey",
      total: snapshot.keyHandlerResolutionViolationCount,
      detail: snapshot.lastViolationDetailByKind["handler-resolution-key"],
      lastSeen: &counts.handlerResolutionKey
    )
    reportSoundnessViolationGrowth(
      kind: "handlerResolutionCommand",
      total: snapshot.commandScopeResolutionViolationCount,
      detail: snapshot.lastViolationDetailByKind["handler-resolution-command"],
      lastSeen: &counts.handlerResolutionCommand
    )
    reportSoundnessViolationGrowth(
      kind: "handlerResolutionDrop",
      total: snapshot.dropScopeResolutionViolationCount,
      detail: snapshot.lastViolationDetailByKind["handler-resolution-drop"],
      lastSeen: &counts.handlerResolutionDrop
    )
    reportSoundnessViolationGrowth(
      kind: "handlerResolutionGesture",
      total: snapshot.gestureRouteResolutionViolationCount,
      detail: snapshot.lastViolationDetailByKind["handler-resolution-gesture"],
      lastSeen: &counts.handlerResolutionGesture
    )
    reportSoundnessViolationGrowth(
      kind: "actionDispatchMiss",
      total: snapshot.actionDispatchMissCount,
      detail: snapshot.lastViolationDetailByKind["action-dispatch-miss"],
      lastSeen: &counts.actionDispatchMiss
    )
    reportSoundnessViolationGrowth(
      kind: "strandedListing",
      total: snapshot.strandedListingViolationCount,
      detail: snapshot.lastViolationDetailByKind["stranded-listing"],
      lastSeen: &counts.strandedListing
    )
    lastSeenSoundnessViolationCounts = counts
  }

  @MainActor
  private func reportSoundnessViolationGrowth(
    kind: String,
    total: Int,
    detail: String?,
    lastSeen: inout Int
  ) {
    guard total > lastSeen else {
      // Also resets after a counter restore (tests save/restore the probe's
      // process-global counters), so a stale high-water mark cannot suppress
      // real future reports.
      lastSeen = min(lastSeen, total)
      return
    }
    let newViolations = total - lastSeen
    lastSeen = total
    reportRuntimeIssue(
      RuntimeIssue(
        severity: .warning,
        code: "soundness.\(kind)",
        message:
          "\(newViolations) sampled soundness violation(s): "
          + (detail ?? "no detail recorded"),
        source: "SoundnessProbe"
      )
    )
  }
}
