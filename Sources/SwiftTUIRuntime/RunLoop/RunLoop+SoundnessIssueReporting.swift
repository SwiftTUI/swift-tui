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

  package init() {}

  /// The probe's live process-global totals. A run loop baselines against
  /// these when it starts so it reports only violations recorded during its
  /// own lifetime — a fresh run loop in a long test process must not
  /// re-report earlier fixtures' violations as its own first-frame findings.
  @MainActor
  package static func currentTotals() -> SoundnessViolationCounts {
    var counts = SoundnessViolationCounts()
    counts.stampCoherence = SoundnessProbeConfiguration.stampCoherenceViolationCount
    counts.deltaCheckpoint = SoundnessProbeConfiguration.deltaCheckpointViolationCount
    counts.checkpointStore = SoundnessProbeConfiguration.checkpointStoreViolationCount
    counts.rasterDamage = SoundnessProbeConfiguration.rasterDamageMismatchCount
    counts.teardownCoherence = SoundnessProbeConfiguration.teardownCoherenceViolationCount
    counts.registrationPublication =
      SoundnessProbeConfiguration.registrationPublicationViolationCount
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
    var counts = lastSeenSoundnessViolationCounts
    reportSoundnessViolationGrowth(
      kind: "stampCoherence",
      total: SoundnessProbeConfiguration.stampCoherenceViolationCount,
      lastSeen: &counts.stampCoherence
    )
    reportSoundnessViolationGrowth(
      kind: "deltaCheckpoint",
      total: SoundnessProbeConfiguration.deltaCheckpointViolationCount,
      lastSeen: &counts.deltaCheckpoint
    )
    reportSoundnessViolationGrowth(
      kind: "checkpointStore",
      total: SoundnessProbeConfiguration.checkpointStoreViolationCount,
      lastSeen: &counts.checkpointStore
    )
    reportSoundnessViolationGrowth(
      kind: "rasterDamage",
      total: SoundnessProbeConfiguration.rasterDamageMismatchCount,
      lastSeen: &counts.rasterDamage
    )
    reportSoundnessViolationGrowth(
      kind: "teardownCoherence",
      total: SoundnessProbeConfiguration.teardownCoherenceViolationCount,
      lastSeen: &counts.teardownCoherence
    )
    reportSoundnessViolationGrowth(
      kind: "registrationPublication",
      total: SoundnessProbeConfiguration.registrationPublicationViolationCount,
      lastSeen: &counts.registrationPublication
    )
    lastSeenSoundnessViolationCounts = counts
  }

  @MainActor
  private func reportSoundnessViolationGrowth(
    kind: String,
    total: Int,
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
          + (SoundnessProbeConfiguration.lastViolationDetail ?? "no detail recorded"),
        source: "SoundnessProbe"
      )
    )
  }
}
