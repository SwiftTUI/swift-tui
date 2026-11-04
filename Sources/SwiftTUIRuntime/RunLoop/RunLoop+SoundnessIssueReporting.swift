import SwiftTUICore

/// Last-seen totals of the soundness probe's violation counters, kept on the
/// run loop so frame acquisition and shutdown report only new violations.
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
  package var layoutShadowDivergence = 0

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
    counts.layoutShadowDivergence = snapshot.layoutShadowDivergenceCount
    return counts
  }
}

extension RunLoop {
  /// F34: route soundness-probe violations through the host-facing
  /// ``RuntimeIssueSink``. The probe's counters live in `SwiftTUICore`, below
  /// the issue sink, so the run loop reads totals at frame and shutdown boundaries
  /// and emits one warning per violation kind that grew — turning what were
  /// test-only counters into signals the host can surface in the builds users
  /// actually run.
  @MainActor
  package func reportNewSoundnessProbeViolations() {
    let snapshot = SoundnessCounterSnapshot.current()
    var counts = lastSeenSoundnessViolationCounts
    var issues: [RuntimeIssue] = []
    reportSoundnessViolationGrowth(
      kind: .stampCoherence,
      total: snapshot.stampCoherenceViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.stampCoherence,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .deltaCheckpoint,
      total: snapshot.deltaCheckpointViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.deltaCheckpoint,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .checkpointStore,
      total: snapshot.checkpointStoreViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.checkpointStore,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .rasterDamage,
      total: snapshot.rasterDamageMismatchCount,
      snapshot: snapshot,
      lastSeen: &counts.rasterDamage,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .teardownCoherence,
      total: snapshot.teardownCoherenceViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.teardownCoherence,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .registrationPublication,
      total: snapshot.registrationPublicationViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.registrationPublication,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .memoUnsoundSkip,
      total: snapshot.memoUnsoundSkipCount,
      snapshot: snapshot,
      lastSeen: &counts.memoUnsoundSkip,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .handlerResolutionAction,
      total: snapshot.actionResolutionViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.handlerResolutionAction,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .handlerResolutionKey,
      total: snapshot.keyHandlerResolutionViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.handlerResolutionKey,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .handlerResolutionCommand,
      total: snapshot.commandScopeResolutionViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.handlerResolutionCommand,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .handlerResolutionDrop,
      total: snapshot.dropScopeResolutionViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.handlerResolutionDrop,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .handlerResolutionGesture,
      total: snapshot.gestureRouteResolutionViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.handlerResolutionGesture,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .actionDispatchMiss,
      total: snapshot.actionDispatchMissCount,
      snapshot: snapshot,
      lastSeen: &counts.actionDispatchMiss,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .strandedListing,
      total: snapshot.strandedListingViolationCount,
      snapshot: snapshot,
      lastSeen: &counts.strandedListing,
      issues: &issues
    )
    reportSoundnessViolationGrowth(
      kind: .layoutShadowDivergence,
      total: snapshot.layoutShadowDivergenceCount,
      snapshot: snapshot,
      lastSeen: &counts.layoutShadowDivergence,
      issues: &issues
    )
    // Publish every high-water mark before invoking host code. A sink may
    // re-enter reporting, including recording a different violation kind.
    lastSeenSoundnessViolationCounts = counts
    reportRuntimeIssues(issues)
  }

  @MainActor
  private func reportSoundnessViolationGrowth(
    kind: SoundnessViolationKind,
    total: Int,
    snapshot: SoundnessCounterSnapshot,
    lastSeen: inout Int,
    issues: inout [RuntimeIssue]
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
    issues.append(
      RuntimeIssue(
        severity: .warning,
        code: "soundness.\(kind.issueName)",
        message:
          "\(newViolations) sampled soundness violation(s): "
          + (snapshot.lastViolationDetailByKind[kind] ?? "no detail recorded"),
        source: "SoundnessProbe"
      )
    )
  }
}
