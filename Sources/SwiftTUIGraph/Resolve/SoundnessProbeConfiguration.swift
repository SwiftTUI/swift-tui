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
/// Process-global by design (F119): this subsystem's state is `@MainActor`
/// statics keyed by per-`ViewGraph` frame IDs, so two live graphs in one
/// process would interleave counters and misattribute trace lines. Note-only
/// until multi-scene hosting is real; the fix shape is scoping to the
/// `ViewGraph` instance (or task-locals, the animation-sink storages' shape).
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
  package static var checkpointStoreViolationCount = 0
  package static var rasterDamageMismatchCount = 0
  package static var teardownCoherenceViolationCount = 0
  /// The under-removal (leak) subclass of `teardownCoherenceViolationCount`:
  /// stored nodes unreachable from the committed root (F91). Counted
  /// separately so the leak residual class is independently watchable — the
  /// over-removal direction asserts in DEBUG, this one is gated by
  /// baseline-ratchet tests until the residual burns down to zero.
  package static var teardownCoherenceLeakCount = 0
  package static var lifetimeRelationViolationCount = 0
  package static var barrierNonConvergenceCount = 0
  package static var automaticLifetimeAnchorCount = 0
  package static var resolveLifetimeScopeManualMismatchCount = 0
  package static var unclassifiedResolvedNodeCount = 0
  /// The unreachable-node census size of the most recent leak record: the
  /// F91 ratchet asserts this stays at its pinned baseline (a growing census
  /// is the "residual class grows silently" failure the split exists to
  /// catch), without parsing the human-facing detail string.
  package static var lastTeardownLeakUnreachableCount = 0
  package static var registrationPublicationViolationCount = 0
  package static var memoUnsoundSkipCount = 0
  package static var duplicateRegistrationOverwriteCount = 0
  package static var stateSlotRestorationDropCount = 0
  package static var plannerTargetlessFrontierEscalationCount = 0
  package static var lifecycleHandlerSkipCount = 0
  package static var ambientEnvironmentFallbackReadCount = 0
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

  /// Records one caught checkpoint-store incoherence (F29): restoring a
  /// just-created store-built checkpoint changed graph state — a store image
  /// went stale without its owner's generation moving, or membership drifted.
  package static func recordCheckpointStoreViolation(_ detail: @autoclosure () -> String) {
    checkpointStoreViolationCount += 1
    lastViolationDetail = detail()
    emitTrace("checkpoint-store")
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

  /// Records one caught under-removal (leak) census violation (F91): stored
  /// node(s) unreachable from the committed root at the finalize barrier.
  /// Increments BOTH the combined teardown-coherence counter (so existing
  /// scenario delta-asserts keep covering both directions) and the
  /// leak-specific counter the F91 ratchet tests watch.
  package static func recordTeardownCoherenceLeak(
    _ detail: @autoclosure () -> String,
    unreachableCount: Int
  ) {
    teardownCoherenceViolationCount += 1
    teardownCoherenceLeakCount += 1
    lastTeardownLeakUnreachableCount = unreachableCount
    lastViolationDetail = detail()
    emitTrace("teardown-coherence-leak")
  }

  package static func recordLifetimeRelationViolation(
    _ detail: @autoclosure () -> String
  ) {
    lifetimeRelationViolationCount += 1
    lastViolationDetail = detail()
    emitTrace("lifetime-relation")
  }

  package static func recordBarrierNonConvergence(
    _ detail: @autoclosure () -> String
  ) {
    barrierNonConvergenceCount += 1
    lastViolationDetail = detail()
    emitTrace("teardown-barrier-non-convergence")
  }

  package static func recordAutomaticLifetimeAnchor() {
    automaticLifetimeAnchorCount += 1
  }

  package static func recordResolveLifetimeScopeManualMismatch(
    _ detail: @autoclosure () -> String
  ) {
    resolveLifetimeScopeManualMismatchCount += 1
    lastViolationDetail = detail()
    emitTrace("resolve-lifetime-scope-manual-mismatch")
  }

  package static func recordUnclassifiedResolvedNode(
    _ detail: @autoclosure () -> String
  ) {
    unclassifiedResolvedNodeCount += 1
    lastViolationDetail = detail()
    emitTrace("resolve-lifetime-scope-unclassified")
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

  /// Records one caught memo-soundness violation (F90): the shadow oracle
  /// (``MemoSkipTrace``) found a would-skip node — view value structurally
  /// equal, reuse guards passed, **no recorded dynamic reads** — whose freshly
  /// recomputed output diverged from the committed output on a *content* field
  /// (``ResolvedNode/memoUnsoundContentDivergence(from:)``). That is a
  /// comparator false-equal: had the production memo gate skipped this node it
  /// would have served stale UI. Bookkeeping-only divergences (entity
  /// occurrence re-stamps) stay in `MemoSkipTrace`'s histogram and do not
  /// raise this alarm.
  package static func recordMemoUnsoundSkip(_ detail: @autoclosure () -> String) {
    memoUnsoundSkipCount += 1
    lastViolationDetail = detail()
    emitTrace("memo-unsound-skip")
  }

  /// Records one caught same-identity duplicate registration (F104): a
  /// single-handler-per-identity family (action, bare key handler, drop
  /// destination, keyCommand binding) recorded the same key twice within one
  /// capture session, so the second write silently replaced the first.
  /// Last-write-wins is the documented contract, but a duplicate inside one
  /// session means two authored registrations collided on one identity —
  /// the recurring duplicate/stale-registration bug shape, previously
  /// invisible everywhere in the family.
  package static func recordDuplicateRegistrationOverwrite(
    _ detail: @autoclosure () -> String
  ) {
    duplicateRegistrationOverwriteCount += 1
    lastViolationDetail = detail()
    emitTrace("duplicate-registration")
  }

  /// Records one dirty-plan escalation caused by a target-less frontier node
  /// (F160): a queued dirty node had no stitchable evaluator anywhere on its
  /// chain. Before F160 the planner silently dropped just that node from the
  /// plan and `finalizeFrame` wiped the dirty rails — the node's
  /// re-evaluation was lost for the session. The planner now escalates the
  /// whole plan to a root evaluation (safe), and this counter makes the
  /// class watchable: a nonzero steady-state count means selective
  /// evaluation is being defeated by an unplannable dirty source. Recorded
  /// unconditionally: the path is rare and every hit was previously a
  /// silently lost re-evaluation.
  package static func recordPlannerTargetlessFrontierEscalation(
    _ detail: @autoclosure () -> String
  ) {
    plannerTargetlessFrontierEscalationCount += 1
    lastViolationDetail = detail()
    emitTrace("planner-targetless-frontier")
  }

  /// Records one committed lifecycle handler (appear/disappear/change) whose
  /// lookup failed at commit time (F163) — a committed callback that silently
  /// never fired, the task path's publication-loss class extended to the
  /// handler legs. Recorded unconditionally: the path should be rare and the
  /// per-kind instance counters live on `LifecycleCoordinator`; this static
  /// mirrors them onto the probe's trace channel for calibration sweeps.
  package static func recordLifecycleHandlerSkip(
    _ detail: @autoclosure () -> String
  ) {
    lifecycleHandlerSkipCount += 1
    lastViolationDetail = detail()
    emitTrace("lifecycle-handler-skip")
  }

  /// Records one `@Environment` read that fell back to default values while
  /// an authoring/dispatch scope was bound (F136): the scope that dispatched
  /// the read failed to establish the registration-time environment, so the
  /// read silently produced `EnvironmentValues()` defaults — the
  /// "`@Environment` in action closures sees DEFAULTS" family. Reads with no
  /// authoring scope at all (direct construction outside a scene, unit
  /// tests) are deliberately not counted: defaults are the documented
  /// behavior there. Recorded unconditionally: an in-scope hit was
  /// previously a silent wrong value.
  package static func recordAmbientEnvironmentFallbackRead(
    _ detail: @autoclosure () -> String
  ) {
    ambientEnvironmentFallbackReadCount += 1
    lastViolationDetail = detail()
    emitTrace("ambient-environment-fallback")
  }

  /// Records one dropped in-flight state-slot restoration (F93): a
  /// `StateMutationOverlay` — the carrier that preserves user state writes
  /// across a discarded async frame draft — named an owner node that no
  /// longer exists, so the write was silently lost (the F63/F43 incident
  /// class). Recorded unconditionally: the path is rare and every hit is a
  /// potential user-visible lost write.
  package static func recordStateSlotRestorationDrop(_ detail: @autoclosure () -> String) {
    stateSlotRestorationDropCount += 1
    lastViolationDetail = detail()
    emitTrace("state-slot-restoration-drop")
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
