# Soundness oracles

This is the canonical HEAD-state map of SwiftTUI's reconciliation and runtime
soundness probes. Each probe row is part of the implementation contract. Add
the source item first. Then add its documentation and tests. A new `record*`
function, counter, or trace kind in
[`SoundnessProbeConfiguration.swift`](../Sources/SwiftTUIGraph/Resolve/SoundnessProbeConfiguration.swift)
requires three additions: a row here, a counter snapshot entry, and an owning
test.
`Scripts/check_soundness_oracle_map.sh` derives those inventories from source
and makes drift fail the repository policy phase.

## Enforcement model

- **T-fail** means any emitted trace is a gate failure. The DEBUG-only
  `assertZeroCensusViolation` subset also traps at the recording site.
- **T-ratchet** means the committed
  [`soundness_quarantine.txt`](../Scripts/soundness_quarantine.txt) pins an
  exact residual count. Growth fails. An exact baseline warns. Shrinkage
  prompts reducing the ledger.
- **T-info** records measurements rather than violations. It has no trace kind
  and cannot fail the gate by itself.

The local test gate and release soundness lane arm
`SWIFTTUI_SOUNDNESS_PROBE_TRACE`, write per-step trace files, and pass them to
[`scan_soundness_traces.sh`](../Scripts/scan_soundness_traces.sh). Serialized
test suites can also use `SoundnessCounterSnapshot` deltas for attribution.
An intentional oracle-reduction test suppresses tracing or the DEBUG assertion
window while leaving the counter path observable.

Sampling is deterministic. `sampleEveryNFrames` defaults to every frame in
DEBUG/tests and one frame in 256 in release. The release soundness lane forces
one. Rows marked **sampled frame** run only when
`isSampledFrame == true`. Rows marked **event** record every time their rare
failure or diagnostic path executes while the configuration enables the probe.

### Assertion-only oracles outside the counter map

The map below is derived from the `record*` functions in
`SoundnessProbeConfiguration`. One oracle has no recorder and therefore no row:
`RetainedFrameIndex.init(patching:with:verifyingAgainstFullRebuild:)` checks a
patched retained-frame index byte-for-byte against a full rebuild and traps with
`preconditionFailure` on divergence. It is DEBUG-only and, until 2026-08-27,
consulted no probe at all — a raw `#if DEBUG`, so every shape-stable frame in
every debug build paid for the full rebuild the patch path exists to avoid.
It now takes the sampling decision as a parameter, threaded down from the main
actor by the frame tail (the index is built on the frame-tail worker, and the
probe is main-actor state — the same hop
`Rasterizer.rasterizeCollectingVisibleIdentities(verifyIncrementalRasterDamage:)`
makes). Direct callers, which are tests, keep it on by default.

If it ever grows a counter, it belongs in the map below under the usual rule.

## Current map

Each table row carries a machine-readable `oracle-map` comment in its final
cell. Keep the comment's kind, recorder, and counter spellings exact.

| Kind / invariant family | Mechanism and source anchor | Enforcement | Sampling | Failure channel | Owning tests | Residual / quarantine |
| --- | --- | --- | --- | --- | --- | --- |
| `stamp-coherence` — retained snapshot stamps agree with live node ownership | Retained write-back and subtree stamp comparisons in [`ViewNode.swift`](../Sources/SwiftTUIGraph/Resolve/ViewNode.swift) | T-fail. DEBUG call-site assertion, release recorder | Every DEBUG comparison. Sampled release frame | Assertion or trace scan | `SoundnessProbeConfigurationTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: stamp-coherence ; recordStampCoherenceViolation ; stampCoherenceViolationCount --> |
| `delta-checkpoint` — delta restore reproduces the captured graph | Restore-and-compare in [`ViewGraph.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraph.swift) | T-fail. DEBUG zero-census assertion | Sampled checkpoint path | Assertion, trace scan, serialized snapshot delta | `SoundnessAssertPromotionTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: delta-checkpoint ; recordDeltaCheckpointViolation ; deltaCheckpointViolationCount --> |
| `checkpoint-store` — stored node images remain coherent with owner generations and membership | Capture/store verification in [`ViewGraph.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraph.swift) | T-fail. DEBUG zero-census assertion | Sampled checkpoint path | Assertion, trace scan, serialized snapshot delta | `NodeCheckpointImageStoreTests`, `SoundnessAssertPromotionTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: checkpoint-store ; recordCheckpointStoreViolation ; checkpointStoreViolationCount --> |
| `raster-damage` — incremental damage equals a fresh raster | [`DefaultRendererFrameTailCoordinator.swift`](../Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameTailCoordinator.swift) reports the fresh-raster shadow comparison from `Rasterizer` | T-fail. The renderer repairs the mismatch before publication | Every DEBUG raster with a shadow comparison. Sampled release raster | Trace scan and serialized snapshot delta | `SoundnessProbeConfigurationTests`, `SoundnessFailureChannelTests`, raster stress fixtures | None. Repair preserves output but does not excuse the alarm  <!-- oracle-map: raster-damage ; recordRasterDamageMismatch ; rasterDamageMismatchCount --> |
| `teardown-coherence` — no committed node is over-removed | Post-finalize reachability audit in [`ViewGraph.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraph.swift) | T-fail. DEBUG call-site assertion | Sampled frame | Assertion, trace scan, serialized snapshot delta | teardown/presentation/framework stress suites, `SoundnessFailureChannelTests` | None  <!-- oracle-map: teardown-coherence ; recordTeardownCoherenceViolation ; teardownCoherenceViolationCount --> |
| `teardown-coherence-leak` — no stored node is unreachable from the committed root | Under-removal arm of the same reachability audit | T-ratchet | Sampled frame | Exact-count trace scan. Leak census currency | `SoundnessProbeConfigurationTests`, framework lifecycle stress suites, `SoundnessFailureChannelTests` | Quarantined at 174 (re-measured 2026-08-28 after the generated seam-case islands took the `hostedDetached` anchor production records for them, which retired the graph lane's entire 325-line contribution; 499 before that, 478 at `Program-5-S0`). Also updates combined teardown count and `lastTeardownLeakUnreachableCount`  <!-- oracle-map: teardown-coherence-leak ; recordTeardownCoherenceLeak ; teardownCoherenceViolationCount,teardownCoherenceLeakCount,lastTeardownLeakUnreachableCount --> |
| `teardown-barrier-non-convergence` — teardown reaches a fixed point within its derived bound | Fixed-point barrier in [`ViewGraph.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraph.swift) | T-fail | Event | Trace scan and serialized snapshot delta | `TeardownBarrierFixedPointTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: teardown-barrier-non-convergence ; recordBarrierNonConvergence ; barrierNonConvergenceCount --> |
| `automatic-lifetime-anchor` — detached results requiring inferred durable ownership | Resolve-scope classification in [`ResolveLifetimeScope.swift`](../Sources/SwiftTUIGraph/Resolve/ResolveLifetimeScope.swift) | T-info. Counter only | Event | Snapshot/reporting only. Deliberately no trace | `ResolveLifetimeScopeTests`, `SoundnessProbeConfigurationTests` | Informational adoption currency, not a violation  <!-- oracle-map: automatic-lifetime-anchor ; recordAutomaticLifetimeAnchor ; automaticLifetimeAnchorCount --> |
| `resolve-lifetime-scope-unclassified` — every observed live resolved node has a durable lifetime classification | Resolve-scope close audit in [`ResolveLifetimeScope.swift`](../Sources/SwiftTUIGraph/Resolve/ResolveLifetimeScope.swift) | T-fail. DEBUG scope assertion | Event | Assertion, trace scan, serialized snapshot delta | `ResolveLifetimeScopeTests`, `DroppedElementAnchoringTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: resolve-lifetime-scope-unclassified ; recordUnclassifiedResolvedNode ; unclassifiedResolvedNodeCount --> |
| `registration-publication` — scoped registry publication matches a scratch full rebuild | Publication fingerprint comparison in [`ViewGraphFrameDraft.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraphFrameDraft.swift) | T-ratchet | Sampled frame | Exact-count trace scan | `RuntimeRegistrationRestoreScopingTests`, `GesturePairedRouteLivenessTests`, `SoundnessFailureChannelTests` | Quarantined at 64 (re-measured 2026-08-28 after the scratch stopped being built with all fifteen registries regardless of the live target's membership; 1,199 before that). The scratch now mirrors the target (`RuntimeRegistrationSet.scratch(mirroringMembershipOf:)`) — comparing a sparse live target against an all-member rebuild reported every registration in the graph as `live=0 rebuilt=1`  <!-- oracle-map: registration-publication ; recordRegistrationPublicationViolation ; registrationPublicationViolationCount --> |
| `memo-unsound-skip` — a memo candidate never skips when fresh output differs in content | Shadow recomputation in [`MemoSkipTrace.swift`](../Sources/SwiftTUIGraph/Resolve/MemoSkipTrace.swift) | T-fail. DEBUG zero-census assertion | Sampled frame | Assertion, trace scan, serialized snapshot delta | `MemoSoundnessAlarmTests`, `EquatableViewReuseTests`, `SoundnessAssertPromotionTests` | None  <!-- oracle-map: memo-unsound-skip ; recordMemoUnsoundSkip ; memoUnsoundSkipCount --> |
| `duplicate-registration` — one capture session does not overwrite a single-slot identity | Registration capture guard in [`ViewNode.swift`](../Sources/SwiftTUIGraph/Resolve/ViewNode.swift) | T-fail | Sampled frame | Trace scan and serialized snapshot delta | `DuplicateRegistrationProbeTests`, `SoundnessFailureChannelTests` | Key-command carry-over is an intentional exemption tested at HEAD  <!-- oracle-map: duplicate-registration ; recordDuplicateRegistrationOverwrite ; duplicateRegistrationOverwriteCount --> |
| `planner-targetless-frontier` — dirty work is never silently discarded for lack of a stitchable evaluator | Root-escalation alarm in [`ViewGraphDirtyEvaluationPlanning.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraphDirtyEvaluationPlanning.swift) | T-fail | Event | Trace scan and serialized snapshot delta | `FrameworkStressGraphPlanningAndRoutingTests`, `SoundnessFailureChannelTests` | Safe root fallback preserves output. Alarm still fails  <!-- oracle-map: planner-targetless-frontier ; recordPlannerTargetlessFrontierEscalation ; plannerTargetlessFrontierEscalationCount --> |
| `lifecycle-handler-skip` — a committed lifecycle callback resolves when dispatched | Lookup-miss alarm in [`LifecycleCoordinator.swift`](../Sources/SwiftTUIRuntime/Lifecycle/LifecycleCoordinator.swift) | T-fail | Event | Trace scan and serialized snapshot delta | `LifecycleCoordinatorSkipTests`, `TimelineTaskStartSkipRuntimeTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: lifecycle-handler-skip ; recordLifecycleHandlerSkip ; lifecycleHandlerSkipCount --> |
| `ambient-environment-fallback` — a bound authoring/dispatch scope never reads default environment by accident | Scoped fallback alarm in [`Environment.swift`](../Sources/SwiftTUIViews/Environment/Environment.swift) | T-fail | Event | Trace scan and serialized snapshot delta | `HandlerIntakeAmbientScopeTests`, `SoundnessFailureChannelTests` | Reads with no bound scope are intentionally outside the oracle  <!-- oracle-map: ambient-environment-fallback ; recordAmbientEnvironmentFallbackRead ; ambientEnvironmentFallbackReadCount --> |
| `state-slot-restoration-drop` — accepted async reconciliation never loses an in-flight state write | Missing-owner restoration alarm in [`ViewGraph.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraph.swift) | T-fail. DEBUG zero-census assertion | Event | Assertion, trace scan, serialized snapshot delta | `StateSlotTests`, `SoundnessAssertPromotionTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: state-slot-restoration-drop ; recordStateSlotRestorationDrop ; stateSlotRestorationDropCount --> |
| `committed-handler-resolution` — committed lifecycle handler IDs resolve in the published registry | Shared committed walk in [`CommittedHandlerResolutionOracle.swift`](../Sources/SwiftTUIGraph/Resolve/CommittedHandlerResolutionOracle.swift) | T-fail. DEBUG zero-census assertion | Sampled frame | Assertion, trace scan, serialized snapshot delta | `CommittedHandlerResolutionOracleTests`, `SoundnessAssertPromotionTests`, `SoundnessFailureChannelTests` | Change handlers use dispatch queues and are outside committed metadata  <!-- oracle-map: committed-handler-resolution ; recordCommittedHandlerResolutionViolation ; committedHandlerResolutionViolationCount --> |
| `handler-resolution-action` — committed action identity resolves in the live action registry | Action leg of the shared committed walk | T-fail | Sampled frame | Trace scan and serialized snapshot delta | `CommittedHandlerResolutionOracleTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: handler-resolution-action ; recordInteractiveHandlerResolutionViolation ; actionResolutionViolationCount --> |
| `handler-resolution-key` — committed key/paste identity resolves in the live key registry | Key/paste leg of the shared committed walk | T-fail | Sampled frame | Trace scan and serialized snapshot delta | `CommittedHandlerResolutionOracleTests`, `SoundnessFailureChannelTests` | Either key or paste registration satisfies the inventory  <!-- oracle-map: handler-resolution-key ; recordInteractiveHandlerResolutionViolation ; keyHandlerResolutionViolationCount --> |
| `handler-resolution-command` — committed command scope resolves in the live command registry | Command leg of the shared committed walk | T-fail | Sampled frame | Trace scan and serialized snapshot delta | `CommittedHandlerResolutionOracleTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: handler-resolution-command ; recordInteractiveHandlerResolutionViolation ; commandScopeResolutionViolationCount --> |
| `handler-resolution-drop` — committed drop scope resolves in the live drop registry | Drop leg of the shared committed walk | T-fail | Sampled frame | Trace scan and serialized snapshot delta | `CommittedHandlerResolutionOracleTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: handler-resolution-drop ; recordInteractiveHandlerResolutionViolation ; dropScopeResolutionViolationCount --> |
| `handler-resolution-gesture` — committed gesture route resolves both recognizer and pointer handler | Gesture leg of the shared committed walk | T-fail | Sampled frame | Trace scan and serialized snapshot delta | `CommittedHandlerResolutionOracleTests`, `SoundnessFailureChannelTests` | A present partial pair fails. An absent optional registry is outside caller scope. **No ledger row** (2026-08-28): it measured 0 on macOS and Linux from 2026-08-22 and its zero row was removed, which changes nothing about enforcement — a recurrence fails the scan as "is not quarantined" exactly as it previously failed as "exceeds baseline=0". It was temporarily quarantined at 1 on 2026-08-14 for `GestureScroll026`  <!-- oracle-map: handler-resolution-gesture ; recordInteractiveHandlerResolutionViolation ; gestureRouteResolutionViolationCount --> |
| `action-dispatch-miss` — dispatch never targets a missing published action | Failed lookup in [`LocalActionRegistry.swift`](../Sources/SwiftTUIGraph/Runtime/LocalActionRegistry.swift) | T-fail | Event | Trace scan and serialized snapshot delta | `CommittedHandlerResolutionOracleTests`, `SoundnessFailureChannelTests` | A found handler returning `false` is not a lookup miss. **No ledger row** (2026-08-28): the single quarantined line was a deliberate negative probe, not a defect. `DormantTabStateTests` asserted `!actions.dispatch(...)` to prove a dormant payload had dropped its registration, and the alarm fires on a lookup MISS — so it fired precisely when that assertion PASSED. The assertion now reads `hasHandler`, which is both alarm-free and what it actually claims to test  <!-- oracle-map: action-dispatch-miss ; recordActionDispatchMiss ; actionDispatchMissCount --> |
| `stranded-listing` — a node never claims a child seated under another live parent | Post-finalize listing audit in [`ViewGraph.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraph.swift) | T-fail. DEBUG call-site assertion | Sampled frame | Assertion, trace scan, serialized snapshot delta | `StrandedListingProbeTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: stranded-listing ; recordStrandedListingViolation ; strandedListingViolationCount --> |
| `state-seed-fallback` — with capture binding enabled, no imperative `@State` access bottoms out at the authored seed | Fallback reporter in [`State.swift`](../Sources/SwiftTUIViews/State/State.swift), recorded only while `StateCaptureBindingConfiguration.isEnabled` (plan 2026-08-20-001 Stage 3) | T-fail | Event | Trace scan and serialized snapshot delta | `StateCaptureBindingTests`, `SoundnessFailureChannelTests` | Gate-off accesses keep the loud RuntimeIssue outside this oracle  <!-- oracle-map: state-seed-fallback ; recordStateSeedFallbackViolation ; stateSeedFallbackViolationCount --> |
| `state-capture-miss` — a bound capture's dead owner always recovers through the fire-time identity refresh | Capture rung in [`State.swift`](../Sources/SwiftTUIViews/State/State.swift), recorded only while `StateCaptureBindingConfiguration.isEnabled` | T-fail | Event | Trace scan and serialized snapshot delta | `StateCaptureBindingTests`, `SoundnessFailureChannelTests` | Committed removal legitimately falls through to the exact dispatch tier or the loud seed; deliberate-removal tests suppress tracing while proving the counter  <!-- oracle-map: state-capture-miss ; recordStateCaptureMissViolation ; stateCaptureMissViolationCount --> |
| `layout-shadow-divergence` — sampled cached measure/place geometry equals a fresh all-reuse-disabled pass | Shadow layout comparison in [`LayoutShadowOracle.swift`](../Sources/SwiftTUICore/Measure/LayoutShadowOracle.swift), run by the frame tail's layout stage and recorded by [`DefaultRendererFrameTailCoordinator.swift`](../Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameTailCoordinator.swift) | T-fail. DEBUG call-site assertion. The production value is never repaired before recording | Every DEBUG layout stage. Sampled release frame | Assertion, trace scan, serialized snapshot delta | `LayoutShadowOracleTests`, `SoundnessProbeConfigurationTests`, `SoundnessAssertPromotionTests`, `SoundnessFailureChannelTests` | Windowed lazy/hosted subtrees are excluded (cold shadow stride) and counted by the T-info exclusion counter; the placed walk applies the same skip-and-count at estimate-carrying lazy containers (`lazyChildScrollEstimates`) and at ancestors whose bounds absorbed the estimate, because a lazy product measured inside a custom scroll layout's subview walk is invisible to the measured-tree carve-out (the 2026-08-11 mrkdwn `ScrollContent` false-alarm class); a frame whose SHADOW pass hits the engine re-entry depth budget is excluded whole and counted by the T-info depth-exclusion counter (the all-fresh shadow consumes more re-entry depth than production's serve-assisted pass, so at the budget boundary it truncates geometry production computed); the shadow re-evaluates in-pass-verified hysteresis seeds instead of re-deciding bistable fixed points  <!-- oracle-map: layout-shadow-divergence ; recordLayoutShadowDivergence,recordLayoutShadowWindowedExclusions,recordLayoutShadowDepthExclusions ; layoutShadowDivergenceCount,layoutShadowWindowedExclusionCount,layoutShadowDepthExclusionCount --> |


## Counter-consumer contract

A new violation class is not complete until all five pieces land together:

1. A `record*` entry point in `SoundnessProbeConfiguration`.
2. A stable kebab-case trace kind, unless the row is explicitly T-info.
3. A counter mirrored by `SoundnessCounterSnapshot`.
4. Exactly one row and `oracle-map` marker in this document.
5. A deterministic owning test. When the class emits a trace, the owning tests
   include `SoundnessFailureChannelTests`.

The policy script rejects missing, duplicate, and unknown kinds. It requires
an entry for every current recorder and counter. One recorder can serve
several kinds, as the five interactive handler families do. One class can
update combined and class-specific counters, as teardown leak does.

## Quarantined residuals

Two kinds carry a ledger row and are therefore ratcheted rather than failing
outright. This section is their durable tracking reference. Before this section
existed, a stage tag (`Program-5-S0`) in
[`soundness_quarantine.txt`](../Scripts/soundness_quarantine.txt) was the only
record of *why* the team quarantined them. The tag names a program but does not
explain the reason.

| Kind | Baseline | Measured 2026-08-28 | Provenance | What the residual is | Burn-down expectation |
| --- | --: | --: | --- | --- | --- |
| `registration-publication` | 64 | 64 | `Program-5-S0`, re-measured `runtime-lane-unmasked`, reduced by `toolbar-strip-follow-up` (2026-08-22) and by `oracle-membership-mirror` (2026-08-28) | Entirely the OVER-publication arm — a scoped removal fails to clear an entry, in two shapes: 58 stacked duplicates (`live=2 rebuilt=1`, key+paste pairs on text controls and a ScrollView key trio) and 6 stale survivors of a departed node (`live=1 rebuilt=0`) | Fix the removal/restore axis mismatch. The removal matches registration-KEY identity prefixes while the restore selects by NODE identity, so a control registering under an identity outside the removal cover keeps its old entry and the restore adds a second on top |
| `teardown-coherence-leak` | 174 | 174 | `Program-5-S0`, re-measured `runtime-lane-unmasked`, reduced by `seam-fixture-anchor-fidelity` (2026-08-28) | Existing unreachable-node residual (under-removal arm), now the runtime lane's F91 class alone: `.id`-rebound owners and List/lazy content that land with `anchors=[]`, hosted-detached nodes whose host chain does not reach the root, and entity-routed nodes the census deliberately refuses to seed (`liveEntityHomeByIdentity` is zeroed before the walk) | Reduce with teardown-lifetime work. See the leak census currency |

The two zero rows are gone. `action-dispatch-miss` and
`handler-resolution-gesture` were burned down on 2026-08-28 and their rows
removed; both kinds are back to plain `T-fail`, and a recurrence fails the scan
as "is not quarantined" — the same hard error a `count=0` row produced as
"exceeds baseline=0".

### The 2026-08-28 burn-down: two whole classes were measurement artifacts

`registration-publication` fell 1,199 → 64 and `teardown-coherence-leak`
499 → 174 with no change to any reconciliation, teardown, or publication
behaviour. Neither move was coverage: the runtime shard that carried 995 of the
1,199 reported the identical `834 tests in 35 suites` before and after, and the
graph lane moved 480 → 482 only because this change added two tests. Both were
the measuring apparatus being wrong about what it measured,
and the two failure shapes are worth naming because nothing in a green gate
distinguishes them from real defects.

**The oracle and its subject were not comparable.** `RuntimeRegistrationSet`'s
fifteen member registries are all `Optional`, and `allRegistries` is a
`compactMap` over them — a host installs the registries it needs. The F04
publication oracle built its comparison scratch with
`RuntimeRegistrationSet.scratch()`, which unconditionally constructs all
fifteen. A bare `ResolveContext` — every `DefaultRenderer` stress render —
installs none, so on those frames the oracle compared an **empty** live target
against a fully populated rebuild and reported every registration the graph
held as `live=0 rebuilt=1`. That was 995 of the runtime lane's 1,199, and no
scoped restore was ever at fault: publishing into a registry the target does
not have is a no-op by construction, so there is nothing there for a scoped
restore to get wrong. The scratch now mirrors the target's membership
(`RuntimeRegistrationSet.scratch(mirroringMembershipOf:)`), which leaves the
oracle strict over every registry that exists and silent about the ones that
cannot hold anything. `RuntimeRegistrationRestoreScopingTests`'
`sparseLiveTargetDoesNotTripPublicationOracle` pins it; the existing phantom
test still proves the oracle fires on a genuine divergence.

**The fixture did not model the shape it claimed to.** All 325 of the graph
lane's leaks came from `RuntimeRegistrationRestoreScopingTests`' generated seam
cases. Those cases seed capture-island nodes — `PortalIsland`, `OverlayIsland`,
`LazyTabIsland`, `SheetCapturedIsland`, `LazyViewportIsland`,
`IdentityRerootIsland` — that are deliberately committed in no children array,
exactly as a lazy tab body or a presentation-portal attachment is. In the
framework such a node is kept alive by the `hostedDetached` anchor its host's
resolve-lifetime scope records (`ResolveLifetimeScope.swift`). The fixture
drives `beginEvaluation` directly and recorded no anchor, so every island
landed with `anchors=[] parent=nil evalHost=nil hosted=none` and the
finalize-barrier census was correct to call it unreachable. The fixture now
anchors each island to its declaring sibling host. **The census was right; the
fixture was unfaithful** — and a fixture that omits the very anchor whose
absence the census exists to detect will always read as a leak.

The two count=1-class rows were the same kind of error at smaller scale.
`action-dispatch-miss` was one deliberate negative probe: `DormantTabStateTests`
asserted `!actions.dispatch(...)` to prove a dormant payload had dropped its
registration, and the alarm fires on a lookup **miss** — so it fired precisely
when that assertion **passed**. (The ledger described it as burning down "with
its already-failing test"; the test was not failing, and could not have been.)
The assertion now reads `hasHandler`, which is alarm-free and is also what the
assertion claims to test — `dispatch` conflates "no handler" with "handler
returned `false`". `handler-resolution-gesture` had measured 0 on both platforms
since 2026-08-22 and was held as a zero row "so a recurrence fails"; a
recurrence already failed either way, so the row bought a `WARNING` line and the
false implication that the class was a formally accepted defect.

Standing lesson, alongside the coverage one below: before treating a
quarantined count as a defect population, check that the **oracle and its
comparison subject are actually comparable**, and that the **fixture models the
production shape it claims to**. Coverage is not the only way these numbers lie.

Both new figures are confirmed on two platforms — a full macOS `bun run test`
and the arm64 Linux container lane in worktree source mode each report 64 and
174 exactly — which the 2026-08-14 pair never were.

The current scan:

```
WARNING: registration-publication count=64 matches baseline=64
WARNING: teardown-coherence-leak count=174 matches baseline=174
PASS: soundness trace counts are within their exact quarantine baselines
```

### These counts are coverage-sensitive — read this before calling one a regression

A count measures violations *observed*, so it scales with how much of the suite
actually ran. A lane that dies partway makes every downstream figure read low,
and the next person to record a baseline writes that low number down. This has
now happened twice, from two different causes:

1. **2026-08-14, deadlock.** The runtime lane was hanging and dying to the
   1200s watchdog, so traces after that suite went unobserved. Fixing it moved
   `registration-publication` 1194 → 1216 and `teardown-coherence-leak`
   478 → 497, and first surfaced `action-dispatch-miss` and
   `handler-resolution-gesture` at 1 each.
2. **2026-08-14, crash.** The figures from (1) were *themselves* truncated. A
   test subscripted past the end of a raster row after a failed bounds
   `#expect`, so a failing assertion killed the test process and aborted the
   lane. Before that fix no run with ≥1000 tests completed at all; after it the
   lane reports 3247 tests in 357 suites, and the honest figures are 1237 and
   499.

Neither move was a new defect — in both cases the only change was to test code.
Before treating a moved count as a regression, ask whether lane coverage
changed. Two cheap checks: `grep` the gate log for
`exited with unexpected signal`, and compare the runtime lane's reported test
total against a known-good run.

An unguarded subscript after a bounds `#expect` is the specific hazard: Swift
Testing's `#expect` does not stop execution, so the next line runs anyway and
one failing test becomes a lane-wide coverage hole.

### What a green scan does and does not prove

Other documents describe the ledger as "exact-count". Read that carefully,
because the enforcement is **asymmetric**
([`scan_soundness_traces.sh`](../Scripts/scan_soundness_traces.sh)):

| Observed vs baseline | Verdict |
| --- | --- |
| `actual > baseline` | **FAIL** — growth is a hard error |
| `actual == baseline` | WARNING, "matches baseline" |
| `actual < baseline` | WARNING, "reduce the ledger" |
| any count with no ledger row | **FAIL** — "is not quarantined" |

So the baseline is a **ceiling with a shrink nudge**, not an assertion of the
current count. A green scan proves `actual ≤ baseline`. It does *not* prove
`actual == baseline`. A baseline left too high after a fix produces only a
warning. People can miss a warning in a passing gate.

**Do not treat a green gate as evidence that these numbers are current.** A
`> 0` count with no row fails the gate. This rule stops the system from silently
absorbing a *new* kind.

### Reconciliation with the S0 findings census (2026-07-30)

The S0 findings report and this ledger disagree, and the disagreement is
expected rather than a defect. The report is a **pre-S1** census. The ledger is
**post-S1**:

The S0 columns below are a **dated snapshot** and are kept as history. Only the
last column is current:

| Kind | S0 raw | S0 injected | S0 residual | Ledger post-S1 | Measured 2026-07-30 | 2026-08-14 | 2026-08-22 | **Ledger and measured 2026-08-28** |
| --- | --: | --: | --: | --: | --: | --: | --: | --: |
| `registration-publication` | 1,197 | 1 | 1,196 | 1194 | 1122 | 1237 | 1194 | **64** |
| `teardown-coherence-leak` | 479 | 1 | 478 | 478 | 478 | 499 | 499 | **174** |

Read that 2026-07-30 column as a *floor observed under partial coverage*, not as
a truth the later figures contradict. `registration-publication`'s apparent
drop to 1122 and its later rise to 1237 are the same phenomenon seen from two
sides: how much of the runtime lane completed on the day of the measurement.
See the coverage-sensitivity note above for the two truncations involved. The
2026-08-22 move back to 1194 is a genuine burn-down, not coverage: the lane
completed on both platforms, and the 43 residuals were the toolbar strip
shrinking under a frontier-scoped plan (its departed item's registration
survived the scoped reset until the host next applied); the strip now
schedules a host follow-up frame.

S1's scoped-restore suppression is the one genuine movement of the pre-2026-08-28
columns: it changed the S0 report's 1,196 to the ledger's 1194, which the ledger
row recorded as "post-suppression scoped-restore residual".

The 2026-08-28 column is a different kind of movement again, and the largest:
neither coverage nor a reconciliation fix, but two measurement artifacts being
removed from the apparatus — see the burn-down section above. Read every earlier
column as a population that was mostly not defects.

**No document here is the authority. Only a fresh trace-armed full-gate run
is.** The S0 report is a dated snapshot and is not maintained. The ledger is a
ceiling; read it as "what will fail the gate", not "what is true". A standalone
`scan_soundness_traces.sh` is not a substitute either — it reads whatever
`.build/soundness-trace` has accumulated from ad-hoc `swift test` runs and
reports inflated counts, whereas a full `bun run test` clears that directory
first.

## Layout branching ledger

[`Scripts/layout_branching_ledger.txt`](../Scripts/layout_branching_ledger.txt)
is a ratchet in this document's T-ratchet style, but it is a **layout work
metric**, not a graph probe: it has no `SoundnessProbeConfiguration` recorder,
no trace kind, and no oracle-map row. Each ledger row pins a ceiling on the
child-measure-requests-per-container-computation ratio (milli-units) that one
`BranchingFactorOracleTests` fixture measures, split built-in vs custom
(plan 2026-08-11-004 Stage 0). The counters live in
`LayoutBranchingMetrics` (`Sources/SwiftTUICore/Commit/FrameMetrics.swift`)
and ride the frame diagnostic record into the TSV sinks.

Enforcement mirrors the trace scanner's asymmetry: a measured ratio above its
ceiling fails, an exact match passes as "matches baseline", below-baseline
passes with a "reduce the ledger" warning on stderr. CI never rewrites the
ledger; reductions are manual commits. The suite also fails on drift in
either direction between the ledger's rows and its own fixture coverage, so
a row cannot silently outlive (or predate) its fixture. A request is counted
at its issue site and still counts when a cache or retained serve answers
it — the ledger pins *shape*; cache warmth changes cost, which the unledgered
computation counters report separately.

## Known blind spots and scoping debt

The probe state remains process-global `@MainActor` storage. Concurrent graphs
interleave sampling decisions, counters, details, and trace lines. Snapshot
deltas are therefore safe for attribution only in serialized suites. The trace
scan is the cross-suite verdict, not a claim of per-test ownership.
We defer per-`ViewGraph` scoping until multi-scene hosting makes that
architecture real.

The `layout-shadow-divergence` row closes the former measure/place blind spot:
on a sampled frame the tail's layout stage re-runs measure and place with every
reuse tier disabled (no measurement cache, no retained session) and pair-walks
the production trees against the fresh ones on identity, `measuredSize`, and
placed `bounds`, without repairing the production value before recording. Its
measured holes are deliberate and there are exactly two. First, subtrees under
a windowed lazy or hosted product are skipped, because the production window
stride is a running refinement the cold shadow pass legitimately cannot
reproduce; each skip counts into `layoutShadowWindowedExclusionCount`. Second,
a frame whose SHADOW pass hits the engine re-entry depth budget is skipped
whole and counted into `layoutShadowDepthExclusionCount`: the all-fresh shadow
consumes strictly more re-entry depth than a production pass whose serve tiers
skip interior descents, so at the budget boundary the shadow truncates
(`layout.customLayoutDepthLimitExceeded`) geometry production legitimately
computed — the 2026-08-11 mrkdwn examples-gate false alarm, pinned by the
depth-asymmetry red proof in `LayoutShadowOracleTests`. Both holes are
fresh-pass-definition boundaries, not comparison bugs; if a THIRD carve-out
ever seems necessary, treat it as a design smell to revisit, not a routine
expansion.

Two resolve-domain inputs are part of the fresh-pass definition rather than
the carve-out. First, the scratch context is seeded with the production
pass's layout-dependent realizations and never realizes live: realization
resolves authored content against the live graph — reading and writing it —
and is not idempotent within a frame (the first realization's entity commits
change what a second one resolves), so realized children are input to the
fresh pass exactly as the resolved tree is, and the observe-only contract
holds by construction. Second, the scratch context carries the production
session as `measurementSeedSession`, consumed only by the custom-layout
hysteresis-seeding seam (`RetainedMeasurementSeedableLayout`). The scroll
indicator gutter is bistable by design — a confirmed seed keeps the previous
frame's fixed point as anti-flicker hysteresis — so an unseeded shadow would
re-decide knife-edge content and report a legitimate fixed-point difference as
a divergence. Seeding is sound where stride seeding was not: the seam's
contract verifies every derived seed against fresh in-pass measurement, so a
seeded shadow still recomputes all geometry and still catches every unsound
product serve. What it deliberately does not police is the seed-verification
logic itself; a layout that trusts an unverified seed needs its own owning
test.

Equality remains an open-ended audit family. When you add a field to an
enumerated payload comparator, update its equivalence contract and adversarial
test together. Otherwise, the comparator can produce a false-equal reuse
decision. The current map
covers the memo-content and stamp consequences that reach existing probes. It
does not turn the absence of a payload-specific row into proof of coverage.

## Implementation pitfall: stranded-listing identity spaces

The stranded-listing implementation must compare **objects**, not names from
mixed identity systems. `identityByNodeID` describes nodes in
`resolvedIdentity` space, while `ViewNode.identity` and `parent.identity` are
authored-space names. Comparing those maps manufactured 13 to 14 apparent
co-listings on a healthy graph. `ViewGraphStrandedListingProbe.swift` instead
tests `child.parent !== node`, the same object relation the upward staleness
walk follows.

