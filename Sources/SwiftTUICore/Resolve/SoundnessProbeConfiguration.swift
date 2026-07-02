/// Gates the **reconciliation soundness probe**: the framework's reuse/skip
/// fast paths are guarded by oracles (stamp coherence, delta-checkpoint
/// equality, …) that historically ran only under `#if DEBUG` — so the
/// reconciliation-seam bug class they catch shipped *unobserved* in release.
///
/// This probe lets those same read-only oracles run on a **sampled fraction of
/// frames in release builds** (and on every frame under DEBUG/tests), turning a
/// whole class of "found by hand in the gallery" bugs into "caught at the seam".
///
/// - Default **on** in every configuration (F34); `SWIFTTUI_SOUNDNESS_PROBE=0`
///   opts out.
/// - `SWIFTTUI_SOUNDNESS_PROBE_SAMPLE=N` runs the oracles on 1-in-`N` frames
///   (default 256 in release, 1 — every frame — under DEBUG/tests). Sampling is
///   driven by ``ViewGraph``'s monotonic frame counter, never a clock/RNG, so it
///   stays deterministic and replayable.
///
/// When the probe is off the per-frame cost is a single `Bool` store in
/// ``beginFrame(frameID:)`` and a single `Bool` read at each oracle call site —
/// no allocation, no oracle work. Mirrors ``MemoReuseConfiguration``.
@MainActor
package enum SoundnessProbeConfiguration {
  package static let environmentVariableName = FeatureGate.soundnessProbe.environmentVariableName
  package static let sampleEnvironmentVariableName = "SWIFTTUI_SOUNDNESS_PROBE_SAMPLE"

  /// Whether the probe is active at all. Off in release by default; on under
  /// DEBUG/tests. `SWIFTTUI_SOUNDNESS_PROBE=0` forces off, `=1` forces on.
  package static var isEnabled: Bool = environmentDefault()

  /// Run the oracles on 1-in-`N` frames. Clamped to `>= 1` at read time so a
  /// `0` can never produce a `% 0` trap.
  package static var sampleEveryNFrames: Int = sampleDefault()

  /// Set once per frame by ``beginFrame(frameID:)``; a cheap `Bool` read at each
  /// oracle call site. Always `false` while ``isEnabled`` is `false`.
  package static var isSampledFrame: Bool = false

  /// Soundness alarms. Read by tests today; a later increment routes these
  /// through `RuntimeIssue`/frame diagnostics (SwiftTUICore sits below the
  /// runtime layer and cannot reach the issue sink directly).
  package static var stampCoherenceViolationCount = 0
  package static var deltaCheckpointViolationCount = 0
  package static var rasterDamageMismatchCount = 0
  package static var teardownCoherenceViolationCount = 0
  package static var registrationPublicationViolationCount = 0
  package static var lastViolationDetail: String?

  /// Latch this frame's sampling decision from the monotonic frame counter.
  /// Short-circuits to a single `Bool` store when the probe is off.
  package static func beginFrame(frameID: UInt64) {
    guard isEnabled else {
      isSampledFrame = false
      return
    }
    isSampledFrame = frameID % UInt64(max(1, sampleEveryNFrames)) == 0
  }

  package static func recordStampCoherenceViolation(_ detail: @autoclosure () -> String) {
    stampCoherenceViolationCount += 1
    lastViolationDetail = detail()
    emitTrace("stamp-coherence")
  }

  package static func recordDeltaCheckpointViolation(_ detail: @autoclosure () -> String) {
    deltaCheckpointViolationCount += 1
    lastViolationDetail = detail()
    emitTrace("delta-checkpoint")
  }

  /// Records one caught incremental-raster mismatch (the F13 oracle repaired a
  /// surface whose proven damage was incomplete). The rasterizer itself may run
  /// on the frame-tail worker where this `@MainActor` state is unreachable, so
  /// the mismatch rides ``Rasterizer/RasterizationResult`` back to the frame
  /// coordinator, which records it here.
  package static func recordRasterDamageMismatch(_ detail: @autoclosure () -> String) {
    rasterDamageMismatchCount += 1
    lastViolationDetail = detail()
    emitTrace("raster-damage")
  }

  /// Records one caught teardown-coherence violation from the post-finalize
  /// oracle (F04): the committed tree referenced a removed node, or a live
  /// node was reachable from no committed anchor. The subtractive paths had
  /// no oracle at all before this — the churn sweep's demonstrated failure
  /// mode (removing live re-adopted nodes) was invisible to everything but
  /// fixture-enumerated stress shapes.
  package static func recordTeardownCoherenceViolation(_ detail: @autoclosure () -> String) {
    teardownCoherenceViolationCount += 1
    lastViolationDetail = detail()
    emitTrace("teardown-coherence")
  }

  /// Records one caught registration-publication divergence (F04): after a
  /// scoped restore, the live registries did not match a scratch full
  /// rebuild of the current frame's registrations.
  package static func recordRegistrationPublicationViolation(
    _ detail: @autoclosure () -> String
  ) {
    registrationPublicationViolationCount += 1
    lastViolationDetail = detail()
    emitTrace("registration-publication")
  }

  /// `SWIFTTUI_SOUNDNESS_PROBE_TRACE=1` emits one `[SOUNDNESS]` line per
  /// recorded violation (to `SWIFTTUI_SOUNDNESS_PROBE_TRACE_FILE`, else
  /// stderr). Counters alone are invisible outside the test process; a CI
  /// soak lane needs the violations in its log.
  package static let traceEnvironmentVariableName = "SWIFTTUI_SOUNDNESS_PROBE_TRACE"
  package static let traceFileEnvironmentVariableName = "SWIFTTUI_SOUNDNESS_PROBE_TRACE_FILE"
  package static var isTraceEnabled: Bool =
    FeatureFlags.environmentValue(named: traceEnvironmentVariableName).map {
      $0 != "0" && !$0.isEmpty
    } ?? false

  private static func emitTrace(_ kind: String) {
    guard isTraceEnabled else {
      return
    }
    DiagnosticTraceSink.emit(
      "[SOUNDNESS] \(kind): \(lastViolationDetail ?? "")\n",
      toFileAt: FeatureFlags.environmentValue(named: traceFileEnvironmentVariableName)
    )
  }

  private static func environmentDefault() -> Bool {
    FeatureGate.soundnessProbe.initialIsEnabled()
  }

  private static func sampleDefault() -> Int {
    guard let rawValue = FeatureFlags.environmentValue(named: sampleEnvironmentVariableName),
      let parsed = Int(rawValue), parsed > 0
    else {
      #if DEBUG
        return 1
      #else
        // 1-in-256 now that the probe defaults ON in release (F34): rare
        // enough that oracle frames vanish in steady-state profiles, frequent
        // enough that a persistent unsoundness surfaces within seconds at
        // interactive frame rates.
        return 256
      #endif
    }
    return parsed
  }
}
