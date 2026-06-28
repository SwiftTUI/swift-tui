/// Gates the **reconciliation soundness probe**: the framework's reuse/skip
/// fast paths are guarded by oracles (stamp coherence, delta-checkpoint
/// equality, …) that historically ran only under `#if DEBUG` — so the
/// reconciliation-seam bug class they catch shipped *unobserved* in release.
///
/// This probe lets those same read-only oracles run on a **sampled fraction of
/// frames in release builds** (and on every frame under DEBUG/tests), turning a
/// whole class of "found by hand in the gallery" bugs into "caught at the seam".
///
/// - Default **off** in release; `SWIFTTUI_SOUNDNESS_PROBE=1` opts in (e.g. a CI
///   soak lane). Default **on** under DEBUG/tests.
/// - `SWIFTTUI_SOUNDNESS_PROBE_SAMPLE=N` runs the oracles on 1-in-`N` frames
///   (default 64 in release, 1 — every frame — under DEBUG/tests). Sampling is
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
  }

  package static func recordDeltaCheckpointViolation(_ detail: @autoclosure () -> String) {
    deltaCheckpointViolationCount += 1
    lastViolationDetail = detail()
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
        return 64
      #endif
    }
    return parsed
  }
}
