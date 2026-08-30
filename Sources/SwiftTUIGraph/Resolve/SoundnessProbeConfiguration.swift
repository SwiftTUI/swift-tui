/// A complete point-in-time mirror of the soundness probe's process-global
/// counters.
///
/// Keep this as the single counter mirror for runtime reporting and test
/// attribution. `automaticLifetimeAnchorCount`,
/// `layoutShadowWindowedExclusionCount`, and
/// `layoutShadowDepthExclusionCount` are intentionally captured but
/// excluded from ``violationGrowth(since:)`` because they are informational,
/// not violations. `lastTeardownLeakUnreachableCount` is census currency
/// rather than a monotonic counter, so it supplies context for leak growth
/// instead of producing an independent growth event.
package struct SoundnessCounterSnapshot: Sendable, Equatable {
  package var stampCoherenceViolationCount: Int
  package var deltaCheckpointViolationCount: Int
  package var checkpointStoreViolationCount: Int
  package var rasterDamageMismatchCount: Int
  package var teardownCoherenceViolationCount: Int
  package var teardownCoherenceLeakCount: Int
  package var barrierNonConvergenceCount: Int
  package var automaticLifetimeAnchorCount: Int
  package var unclassifiedResolvedNodeCount: Int
  package var lastTeardownLeakUnreachableCount: Int
  package var registrationPublicationViolationCount: Int
  package var memoUnsoundSkipCount: Int
  package var duplicateRegistrationOverwriteCount: Int
  package var stateSlotRestorationDropCount: Int
  package var plannerTargetlessFrontierEscalationCount: Int
  package var lifecycleHandlerSkipCount: Int
  package var ambientEnvironmentFallbackReadCount: Int
  package var committedHandlerResolutionViolationCount: Int
  package var actionResolutionViolationCount: Int
  package var keyHandlerResolutionViolationCount: Int
  package var commandScopeResolutionViolationCount: Int
  package var dropScopeResolutionViolationCount: Int
  package var gestureRouteResolutionViolationCount: Int
  package var actionDispatchMissCount: Int
  package var strandedListingViolationCount: Int
  package var stateSeedFallbackViolationCount: Int
  package var stateCaptureMissViolationCount: Int
  package var dynamicPropertyMutationDiscardedCount: Int
  package var layoutShadowDivergenceCount: Int
  package var layoutShadowWindowedExclusionCount: Int
  package var layoutShadowDepthExclusionCount: Int
  package var lastViolationDetailByKind: [String: String]

  @MainActor
  package static func current() -> Self {
    Self(
      stampCoherenceViolationCount: SoundnessProbeConfiguration.stampCoherenceViolationCount,
      deltaCheckpointViolationCount: SoundnessProbeConfiguration.deltaCheckpointViolationCount,
      checkpointStoreViolationCount: SoundnessProbeConfiguration.checkpointStoreViolationCount,
      rasterDamageMismatchCount: SoundnessProbeConfiguration.rasterDamageMismatchCount,
      teardownCoherenceViolationCount:
        SoundnessProbeConfiguration.teardownCoherenceViolationCount,
      teardownCoherenceLeakCount: SoundnessProbeConfiguration.teardownCoherenceLeakCount,
      barrierNonConvergenceCount: SoundnessProbeConfiguration.barrierNonConvergenceCount,
      automaticLifetimeAnchorCount: SoundnessProbeConfiguration.automaticLifetimeAnchorCount,
      unclassifiedResolvedNodeCount: SoundnessProbeConfiguration.unclassifiedResolvedNodeCount,
      lastTeardownLeakUnreachableCount:
        SoundnessProbeConfiguration.lastTeardownLeakUnreachableCount,
      registrationPublicationViolationCount:
        SoundnessProbeConfiguration.registrationPublicationViolationCount,
      memoUnsoundSkipCount: SoundnessProbeConfiguration.memoUnsoundSkipCount,
      duplicateRegistrationOverwriteCount:
        SoundnessProbeConfiguration.duplicateRegistrationOverwriteCount,
      stateSlotRestorationDropCount:
        SoundnessProbeConfiguration.stateSlotRestorationDropCount,
      plannerTargetlessFrontierEscalationCount:
        SoundnessProbeConfiguration.plannerTargetlessFrontierEscalationCount,
      lifecycleHandlerSkipCount: SoundnessProbeConfiguration.lifecycleHandlerSkipCount,
      ambientEnvironmentFallbackReadCount:
        SoundnessProbeConfiguration.ambientEnvironmentFallbackReadCount,
      committedHandlerResolutionViolationCount:
        SoundnessProbeConfiguration.committedHandlerResolutionViolationCount,
      actionResolutionViolationCount:
        SoundnessProbeConfiguration.actionResolutionViolationCount,
      keyHandlerResolutionViolationCount:
        SoundnessProbeConfiguration.keyHandlerResolutionViolationCount,
      commandScopeResolutionViolationCount:
        SoundnessProbeConfiguration.commandScopeResolutionViolationCount,
      dropScopeResolutionViolationCount:
        SoundnessProbeConfiguration.dropScopeResolutionViolationCount,
      gestureRouteResolutionViolationCount:
        SoundnessProbeConfiguration.gestureRouteResolutionViolationCount,
      actionDispatchMissCount: SoundnessProbeConfiguration.actionDispatchMissCount,
      strandedListingViolationCount:
        SoundnessProbeConfiguration.strandedListingViolationCount,
      stateSeedFallbackViolationCount:
        SoundnessProbeConfiguration.stateSeedFallbackViolationCount,
      stateCaptureMissViolationCount:
        SoundnessProbeConfiguration.stateCaptureMissViolationCount,
      dynamicPropertyMutationDiscardedCount:
        SoundnessProbeConfiguration.dynamicPropertyMutationDiscardedCount,
      layoutShadowDivergenceCount:
        SoundnessProbeConfiguration.layoutShadowDivergenceCount,
      layoutShadowWindowedExclusionCount:
        SoundnessProbeConfiguration.layoutShadowWindowedExclusionCount,
      layoutShadowDepthExclusionCount:
        SoundnessProbeConfiguration.layoutShadowDepthExclusionCount,
      lastViolationDetailByKind: SoundnessProbeConfiguration.lastViolationDetailByKind
    )
  }

  package func violationGrowth(since previous: Self) -> [SoundnessCounterGrowth] {
    var growth: [SoundnessCounterGrowth] = []
    appendGrowth(
      kind: "stamp-coherence",
      previous: previous.stampCoherenceViolationCount,
      current: stampCoherenceViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: "delta-checkpoint",
      previous: previous.deltaCheckpointViolationCount,
      current: deltaCheckpointViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: "checkpoint-store",
      previous: previous.checkpointStoreViolationCount,
      current: checkpointStoreViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: "raster-damage",
      previous: previous.rasterDamageMismatchCount,
      current: rasterDamageMismatchCount,
      to: &growth
    )
    let teardownGrowth =
      teardownCoherenceViolationCount - previous.teardownCoherenceViolationCount
    let leakGrowth = teardownCoherenceLeakCount - previous.teardownCoherenceLeakCount
    appendGrowth(
      kind: "teardown-coherence",
      count: max(0, teardownGrowth - leakGrowth),
      to: &growth
    )
    appendGrowth(
      kind: "teardown-barrier-non-convergence",
      previous: previous.barrierNonConvergenceCount,
      current: barrierNonConvergenceCount,
      to: &growth
    )
    appendGrowth(
      kind: "resolve-lifetime-scope-unclassified",
      previous: previous.unclassifiedResolvedNodeCount,
      current: unclassifiedResolvedNodeCount,
      to: &growth
    )
    // Registration-publication and teardown-leak are census-pinned T-ratchet
    // residuals. The lane scan owns those budgets; suite attribution must not
    // turn known residual growth into an unquarantined test failure. Combined
    // teardown growth still reports its zero-census over-removal direction
    // after subtracting leak growth above.
    appendGrowth(
      kind: "memo-unsound-skip",
      previous: previous.memoUnsoundSkipCount,
      current: memoUnsoundSkipCount,
      to: &growth
    )
    appendGrowth(
      kind: "duplicate-registration",
      previous: previous.duplicateRegistrationOverwriteCount,
      current: duplicateRegistrationOverwriteCount,
      to: &growth
    )
    appendGrowth(
      kind: "state-slot-restoration-drop",
      previous: previous.stateSlotRestorationDropCount,
      current: stateSlotRestorationDropCount,
      to: &growth
    )
    appendGrowth(
      kind: "planner-targetless-frontier",
      previous: previous.plannerTargetlessFrontierEscalationCount,
      current: plannerTargetlessFrontierEscalationCount,
      to: &growth
    )
    appendGrowth(
      kind: "lifecycle-handler-skip",
      previous: previous.lifecycleHandlerSkipCount,
      current: lifecycleHandlerSkipCount,
      to: &growth
    )
    appendGrowth(
      kind: "ambient-environment-fallback",
      previous: previous.ambientEnvironmentFallbackReadCount,
      current: ambientEnvironmentFallbackReadCount,
      to: &growth
    )
    appendGrowth(
      kind: "committed-handler-resolution",
      previous: previous.committedHandlerResolutionViolationCount,
      current: committedHandlerResolutionViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: InteractiveHandlerResolutionFamily.action.traceKind,
      previous: previous.actionResolutionViolationCount,
      current: actionResolutionViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: InteractiveHandlerResolutionFamily.key.traceKind,
      previous: previous.keyHandlerResolutionViolationCount,
      current: keyHandlerResolutionViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: InteractiveHandlerResolutionFamily.command.traceKind,
      previous: previous.commandScopeResolutionViolationCount,
      current: commandScopeResolutionViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: InteractiveHandlerResolutionFamily.drop.traceKind,
      previous: previous.dropScopeResolutionViolationCount,
      current: dropScopeResolutionViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: InteractiveHandlerResolutionFamily.gesture.traceKind,
      previous: previous.gestureRouteResolutionViolationCount,
      current: gestureRouteResolutionViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: "action-dispatch-miss",
      previous: previous.actionDispatchMissCount,
      current: actionDispatchMissCount,
      to: &growth
    )
    appendGrowth(
      kind: "stranded-listing",
      previous: previous.strandedListingViolationCount,
      current: strandedListingViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: "state-seed-fallback",
      previous: previous.stateSeedFallbackViolationCount,
      current: stateSeedFallbackViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: "state-capture-miss",
      previous: previous.stateCaptureMissViolationCount,
      current: stateCaptureMissViolationCount,
      to: &growth
    )
    appendGrowth(
      kind: "dynamic-property-mutation-discarded",
      previous: previous.dynamicPropertyMutationDiscardedCount,
      current: dynamicPropertyMutationDiscardedCount,
      to: &growth
    )
    appendGrowth(
      kind: "layout-shadow-divergence",
      previous: previous.layoutShadowDivergenceCount,
      current: layoutShadowDivergenceCount,
      to: &growth
    )
    return growth
  }

  private func appendGrowth(
    kind: String,
    previous: Int,
    current: Int,
    to growth: inout [SoundnessCounterGrowth]
  ) {
    appendGrowth(kind: kind, count: current - previous, to: &growth)
  }

  private func appendGrowth(
    kind: String,
    count: Int,
    to growth: inout [SoundnessCounterGrowth]
  ) {
    guard count > 0 else {
      return
    }
    growth.append(
      SoundnessCounterGrowth(
        kind: kind,
        count: count,
        detail: lastViolationDetailByKind[kind]
      )
    )
  }
}

package struct SoundnessCounterGrowth: Sendable, Equatable {
  package var kind: String
  package var count: Int
  package var detail: String?
}

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
/// no allocation, no oracle work. Mirrors ``MemoSkipTrace``.
/// Process-global by design (F119): this subsystem's state is `@MainActor`
/// statics keyed by per-`ViewGraph` frame IDs, so two live graphs in one
/// process would interleave counters and misattribute trace lines. Note-only
/// until multi-scene hosting is real; the fix shape is scoping to the
/// `ViewGraph` instance (or task-locals, the animation-sink storages' shape).
///
/// The canonical invariant, enforcement, sampling, and test-owner map is
/// maintained in `docs/SOUNDNESS-ORACLES.md`.
@MainActor
package enum SoundnessProbeConfiguration {
  package static let environmentVariableName = FeatureGate.soundnessProbe.environmentVariableName
  package static let sampleEnvironmentVariableName = "SWIFTTUI_SOUNDNESS_PROBE_SAMPLE"

  /// Whether the probe is active at all. On in every configuration (F34);
  /// release runs the oracles on sampled frames only.
  /// `SWIFTTUI_SOUNDNESS_PROBE=0` forces off, `=1` forces on.
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
  package static var barrierNonConvergenceCount = 0
  package static var automaticLifetimeAnchorCount = 0
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
  package static var committedHandlerResolutionViolationCount = 0
  package static var actionResolutionViolationCount = 0
  package static var keyHandlerResolutionViolationCount = 0
  package static var commandScopeResolutionViolationCount = 0
  package static var dropScopeResolutionViolationCount = 0
  package static var gestureRouteResolutionViolationCount = 0
  package static var actionDispatchMissCount = 0
  package static var strandedListingViolationCount = 0
  package static var stateSeedFallbackViolationCount = 0
  package static var stateCaptureMissViolationCount = 0
  /// One `update(in:)` whose stored mutation the framework could not write
  /// back: the container is an enum, or the field's *static* type is
  /// existential, so the update ran on an extracted copy (plan
  /// 2026-08-30-001 §3.6). Detected in DEBUG only.
  package static var dynamicPropertyMutationDiscardedCount = 0
  package static var layoutShadowDivergenceCount = 0
  /// T-info currency for the layout shadow oracle's windowed carve-out:
  /// subtrees under a windowed lazy/hosted product are excluded from the
  /// sampled comparison (their stride is a running refinement the cold shadow
  /// pass legitimately cannot reproduce). Keeps the blind spot's size
  /// measured; an exclusion is not a violation.
  package static var layoutShadowWindowedExclusionCount = 0
  /// T-info currency for the layout shadow oracle's depth carve-out: a
  /// sampled frame whose SHADOW pass hit the engine re-entry depth budget
  /// (`layout.customLayoutDepthLimitExceeded`) is excluded whole. The
  /// all-fresh shadow legitimately consumes more re-entry depth than a
  /// production pass whose serve tiers skip interior descents, so at the
  /// budget boundary the shadow truncates geometry production computed —
  /// the 2026-08-11 mrkdwn false-alarm class. An exclusion is not a
  /// violation.
  package static var layoutShadowDepthExclusionCount = 0
  package static var lastViolationDetailByKind: [String: String] = [:]
  private static var lastViolationDetailStorage: String?
  package static var lastViolationDetail: String? {
    get { lastViolationDetailStorage }
    set { lastViolationDetailStorage = newValue }
  }

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
    recordViolationDetail(detail(), for: "stamp-coherence")
    emitTrace("stamp-coherence")
  }

  package static func recordDeltaCheckpointViolation(_ detail: @autoclosure () -> String) {
    deltaCheckpointViolationCount += 1
    let detail = detail()
    recordViolationDetail(detail, for: "delta-checkpoint")
    emitTrace("delta-checkpoint")
    assertZeroCensusViolation(detail)
  }

  /// Records one caught checkpoint-store incoherence (F29): restoring a
  /// just-created store-built checkpoint changed graph state — a store image
  /// went stale without its owner's generation moving, or membership drifted.
  package static func recordCheckpointStoreViolation(_ detail: @autoclosure () -> String) {
    checkpointStoreViolationCount += 1
    let detail = detail()
    recordViolationDetail(detail, for: "checkpoint-store")
    emitTrace("checkpoint-store")
    assertZeroCensusViolation(detail)
  }

  /// Records one caught incremental-raster mismatch (the F13 oracle repaired a
  /// surface whose proven damage was incomplete). The rasterizer itself may run
  /// on the frame-tail worker where this `@MainActor` state is unreachable, so
  /// the mismatch rides ``Rasterizer/RasterizationResult`` back to the frame
  /// coordinator, which records it here.
  package static func recordRasterDamageMismatch(_ detail: @autoclosure () -> String) {
    rasterDamageMismatchCount += 1
    recordViolationDetail(detail(), for: "raster-damage")
    emitTrace("raster-damage")
  }

  /// Records one sampled layout-shadow divergence: production measure/place
  /// geometry did not equal a fresh all-reuse-disabled pass over the same
  /// resolved tree and proposal. The layout stage may run on the frame-tail
  /// worker where this `@MainActor` state is unreachable, so the comparison
  /// summary rides the frame-tail layout output back to the frame coordinator,
  /// which records it here. The production value is never repaired before
  /// recording — the alarm, not a heal, is the deliverable.
  package static func recordLayoutShadowDivergence(_ detail: @autoclosure () -> String) {
    layoutShadowDivergenceCount += 1
    recordViolationDetail(detail(), for: "layout-shadow-divergence")
    emitTrace("layout-shadow-divergence")
  }

  /// Accumulates the layout shadow oracle's windowed-exclusion currency
  /// (T-info): how many windowed subtrees the sampled comparison skipped.
  /// Deliberately no trace line and no violation detail — an exclusion is a
  /// measured blind spot, not a violation.
  package static func recordLayoutShadowWindowedExclusions(_ count: Int) {
    layoutShadowWindowedExclusionCount += count
  }

  /// Accumulates the layout shadow oracle's depth-exclusion currency
  /// (T-info): sampled frames skipped whole because the fresh shadow pass
  /// hit the engine re-entry depth budget that production's serve-assisted
  /// pass stayed under. Deliberately no trace line and no violation detail.
  package static func recordLayoutShadowDepthExclusions(_ count: Int) {
    layoutShadowDepthExclusionCount += count
  }

  /// Records one caught teardown-coherence violation from the post-finalize
  /// oracle (F04): the committed tree referenced a removed node, or a live
  /// node was reachable from no committed anchor. The subtractive paths had
  /// no oracle at all before this — the churn sweep's demonstrated failure
  /// mode (removing live re-adopted nodes) was invisible to everything but
  /// fixture-enumerated stress shapes.
  package static func recordTeardownCoherenceViolation(_ detail: @autoclosure () -> String) {
    teardownCoherenceViolationCount += 1
    recordViolationDetail(detail(), for: "teardown-coherence")
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
    let detail = detail()
    recordViolationDetail(detail, for: "teardown-coherence")
    recordViolationDetail(detail, for: "teardown-coherence-leak")
    emitTrace("teardown-coherence-leak")
  }

  package static func recordBarrierNonConvergence(
    _ detail: @autoclosure () -> String
  ) {
    barrierNonConvergenceCount += 1
    recordViolationDetail(detail(), for: "teardown-barrier-non-convergence")
    emitTrace("teardown-barrier-non-convergence")
  }

  package static func recordAutomaticLifetimeAnchor() {
    automaticLifetimeAnchorCount += 1
  }

  package static func recordUnclassifiedResolvedNode(
    _ detail: @autoclosure () -> String
  ) {
    unclassifiedResolvedNodeCount += 1
    recordViolationDetail(detail(), for: "resolve-lifetime-scope-unclassified")
    emitTrace("resolve-lifetime-scope-unclassified")
  }

  /// Records one caught registration-publication divergence (F04): after a
  /// scoped restore, the live registries did not match a scratch full
  /// rebuild of the current frame's registrations.
  package static func recordRegistrationPublicationViolation(
    _ detail: @autoclosure () -> String
  ) {
    registrationPublicationViolationCount += 1
    recordViolationDetail(detail(), for: "registration-publication")
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
    let detail = detail()
    recordViolationDetail(detail, for: "memo-unsound-skip")
    emitTrace("memo-unsound-skip")
    assertZeroCensusViolation(detail)
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
    recordViolationDetail(detail(), for: "duplicate-registration")
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
    recordViolationDetail(detail(), for: "planner-targetless-frontier")
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
    recordViolationDetail(detail(), for: "lifecycle-handler-skip")
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
    recordViolationDetail(detail(), for: "ambient-environment-fallback")
    emitTrace("ambient-environment-fallback")
  }

  /// Records one imperative `@State` access that bottomed out at the
  /// authored initial value while capture binding was enabled (plan
  /// 2026-08-20-001 Stage 3): with captures live, every body-created
  /// closure carries its owner, so a seed fallback means an access no
  /// capture, refresh, or ambient rung could serve — the silent
  /// stale-state corruption class the capture pass exists to retire.
  /// Callers gate on the capture-binding configuration; with the gate off
  /// the fallback remains a loud RuntimeIssue outside this oracle.
  package static func recordStateSeedFallbackViolation(
    _ detail: @autoclosure () -> String
  ) {
    stateSeedFallbackViolationCount += 1
    recordViolationDetail(detail(), for: "state-seed-fallback")
    emitTrace("state-seed-fallback")
  }

  /// Records one bound capture whose owner was dead and whose fire-time
  /// identity refresh also failed (plan 2026-08-20-001 Stage 3), dropping
  /// the access to the ambient ladder. Committed removal legitimately
  /// takes this path, so a hit means a closure outlived its subtree —
  /// expected to hold at zero across the suite and fuzzer campaigns;
  /// deliberate-removal tests suppress tracing while proving the counter.
  /// Records one dynamic-property update whose stored mutation was discarded
  /// because the container shape has no writable field slot — an enum
  /// container, or a field whose static type is existential. The in-place
  /// contract (plan 2026-08-30-001 §3.1) covers strongly stored, statically
  /// typed fields of struct containers; this oracle makes the boundary loud
  /// instead of silent. DEBUG-only detection.
  package static func recordDynamicPropertyMutationDiscardedViolation(
    _ detail: @autoclosure () -> String
  ) {
    dynamicPropertyMutationDiscardedCount += 1
    recordViolationDetail(detail(), for: "dynamic-property-mutation-discarded")
    emitTrace("dynamic-property-mutation-discarded")
  }

  package static func recordStateCaptureMissViolation(
    _ detail: @autoclosure () -> String
  ) {
    stateCaptureMissViolationCount += 1
    recordViolationDetail(detail(), for: "state-capture-miss")
    emitTrace("state-capture-miss")
  }

  /// Records one dropped in-flight state-slot restoration (F93): a
  /// `StateMutationOverlay` — the carrier that preserves user state writes
  /// across a discarded async frame draft — named an owner node that no
  /// longer exists, so the write was silently lost (the F63/F43 incident
  /// class). Recorded unconditionally: the path is rare and every hit is a
  /// potential user-visible lost write.
  package static func recordStateSlotRestorationDrop(_ detail: @autoclosure () -> String) {
    stateSlotRestorationDropCount += 1
    let detail = detail()
    recordViolationDetail(detail, for: "state-slot-restoration-drop")
    emitTrace("state-slot-restoration-drop")
    assertZeroCensusViolation(detail)
  }

  /// Records one committed-tree handler ID that failed to resolve in the
  /// just-published live lifecycle registry (2026-07-17 campaign §5): the
  /// committed tree still names an appear/disappear handler whose owning
  /// node record is hollow, so the committed callback can never fire. The
  /// F04 publication oracle is structurally blind to this class — a scoped
  /// restore and a full rebuild read the SAME hollowed records and agree —
  /// so resolution is checked against the committed tree itself on sampled
  /// frames.
  package static func recordCommittedHandlerResolutionViolation(
    _ detail: @autoclosure () -> String
  ) {
    committedHandlerResolutionViolationCount += 1
    let detail = detail()
    recordViolationDetail(detail, for: "committed-handler-resolution")
    emitTrace("committed-handler-resolution")
    assertZeroCensusViolation(detail)
  }

  /// Records one interactive registration family named by the committed
  /// artifact but absent from the just-published live registry. These sampled
  /// findings intentionally remain non-asserting while the five family
  /// censuses establish their baseline.
  package static func recordInteractiveHandlerResolutionViolation(
    family: InteractiveHandlerResolutionFamily,
    detail: @autoclosure () -> String
  ) {
    switch family {
    case .action:
      actionResolutionViolationCount += 1
    case .key:
      keyHandlerResolutionViolationCount += 1
    case .command:
      commandScopeResolutionViolationCount += 1
    case .drop:
      dropScopeResolutionViolationCount += 1
    case .gesture:
      gestureRouteResolutionViolationCount += 1
    }
    let detail = detail()
    recordViolationDetail(detail, for: family.traceKind)
    emitTrace(family.traceKind)
  }

  /// Records an action dispatch whose registry lookup failed. A registered
  /// handler returning `false` is a successful lookup and does not use this
  /// channel.
  package static func recordActionDispatchMiss(
    _ detail: @autoclosure () -> String
  ) {
    actionDispatchMissCount += 1
    let detail = detail()
    recordViolationDetail(detail, for: "action-dispatch-miss")
    emitTrace("action-dispatch-miss")
  }

  /// Records one stranded listing (residual 2 of the reuse/freshness quirk
  /// register): a node still claims ownership of every child it lists while
  /// one of those children is seated under a different live parent. Nothing
  /// can carry that child's subtree change up to the claimant, so a later
  /// value-blind serve commits superseded interior content and stamps — the
  /// gallery Tab-wrap stamp-coherence crash's precursor state, previously
  /// observable only from a test that named the affected slot by hand.
  package static func recordStrandedListingViolation(
    _ detail: @autoclosure () -> String
  ) {
    strandedListingViolationCount += 1
    recordViolationDetail(detail(), for: "stranded-listing")
    emitTrace("stranded-listing")
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
    } ?? DebugTraceSelection.current.isArmed("soundness")

  private static func emitTrace(_ kind: String) {
    guard isTraceEnabled else {
      return
    }
    DebugLogRouter.emit(
      "[SOUNDNESS] \(kind): \(lastViolationDetailByKind[kind] ?? "")\n",
      toFileAt: DebugLogRouter.resolvedFilePath(
        override: FeatureFlags.environmentValue(named: traceFileEnvironmentVariableName),
        bundleFileName: "soundness.log"
      )
    )
  }

  private static func recordViolationDetail(_ detail: String, for kind: String) {
    lastViolationDetailByKind[kind] = detail
    lastViolationDetailStorage = detail
  }

  /// S2 promotion tier: the 2026-07-28 full-gate census observed no
  /// unexpected hits for these recorders. Keep the counter and trace visible
  /// before trapping so release builds and crash logs retain the forensic
  /// channel. Intentional oracle reductions disable `isEnabled` while proving
  /// the counter path.
  private static func assertZeroCensusViolation(_ detail: String) {
    #if DEBUG
      if isEnabled {
        assertionFailure(detail)
      }
    #endif
  }

  private static func environmentDefault() -> Bool {
    FeatureGate.soundnessProbe.initialIsEnabled()
  }

  private static func sampleDefault() -> Int {
    guard let rawValue = FeatureFlags.environmentValue(named: sampleEnvironmentVariableName),
      let parsed = Int(rawValue), parsed > 0
    else {
      if let selected = DebugTraceSelection.current.entry(named: "soundness")?.sampleEveryNFrames {
        return selected
      }
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
