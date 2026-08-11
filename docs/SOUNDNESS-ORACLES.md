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
| `teardown-coherence-leak` — no stored node is unreachable from the committed root | Under-removal arm of the same reachability audit | T-ratchet | Sampled frame | Exact-count trace scan. Leak census currency | `SoundnessProbeConfigurationTests`, framework lifecycle stress suites, `SoundnessFailureChannelTests` | Quarantined at 478 (`Program-5-S0`). Also updates combined teardown count and `lastTeardownLeakUnreachableCount`  <!-- oracle-map: teardown-coherence-leak ; recordTeardownCoherenceLeak ; teardownCoherenceViolationCount,teardownCoherenceLeakCount,lastTeardownLeakUnreachableCount --> |
| `teardown-barrier-non-convergence` — teardown reaches a fixed point within its derived bound | Fixed-point barrier in [`ViewGraph.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraph.swift) | T-fail | Event | Trace scan and serialized snapshot delta | `TeardownBarrierFixedPointTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: teardown-barrier-non-convergence ; recordBarrierNonConvergence ; barrierNonConvergenceCount --> |
| `automatic-lifetime-anchor` — detached results requiring inferred durable ownership | Resolve-scope classification in [`ResolveLifetimeScope.swift`](../Sources/SwiftTUIGraph/Resolve/ResolveLifetimeScope.swift) | T-info. Counter only | Event | Snapshot/reporting only. Deliberately no trace | `ResolveLifetimeScopeTests`, `SoundnessProbeConfigurationTests` | Informational adoption currency, not a violation  <!-- oracle-map: automatic-lifetime-anchor ; recordAutomaticLifetimeAnchor ; automaticLifetimeAnchorCount --> |
| `resolve-lifetime-scope-unclassified` — every observed live resolved node has a durable lifetime classification | Resolve-scope close audit in [`ResolveLifetimeScope.swift`](../Sources/SwiftTUIGraph/Resolve/ResolveLifetimeScope.swift) | T-fail. DEBUG scope assertion | Event | Assertion, trace scan, serialized snapshot delta | `ResolveLifetimeScopeTests`, `DroppedElementAnchoringTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: resolve-lifetime-scope-unclassified ; recordUnclassifiedResolvedNode ; unclassifiedResolvedNodeCount --> |
| `registration-publication` — scoped registry publication matches a scratch full rebuild | Publication fingerprint comparison in [`ViewGraphFrameDraft.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraphFrameDraft.swift) | T-ratchet | Sampled frame | Exact-count trace scan | `RuntimeRegistrationRestoreScopingTests`, `GesturePairedRouteLivenessTests`, `SoundnessFailureChannelTests` | Quarantined at 1,194 (`Program-5-S0`)  <!-- oracle-map: registration-publication ; recordRegistrationPublicationViolation ; registrationPublicationViolationCount --> |
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
| `handler-resolution-gesture` — committed gesture route resolves both recognizer and pointer handler | Gesture leg of the shared committed walk | T-fail | Sampled frame | Trace scan and serialized snapshot delta | `CommittedHandlerResolutionOracleTests`, `SoundnessFailureChannelTests` | A present partial pair fails. An absent optional registry is outside caller scope  <!-- oracle-map: handler-resolution-gesture ; recordInteractiveHandlerResolutionViolation ; gestureRouteResolutionViolationCount --> |
| `action-dispatch-miss` — dispatch never targets a missing published action | Failed lookup in [`LocalActionRegistry.swift`](../Sources/SwiftTUIGraph/Runtime/LocalActionRegistry.swift) | T-fail | Event | Trace scan and serialized snapshot delta | `CommittedHandlerResolutionOracleTests`, `SoundnessFailureChannelTests` | A found handler returning `false` is not a lookup miss  <!-- oracle-map: action-dispatch-miss ; recordActionDispatchMiss ; actionDispatchMissCount --> |
| `stranded-listing` — a node never claims a child seated under another live parent | Post-finalize listing audit in [`ViewGraph.swift`](../Sources/SwiftTUIGraph/Resolve/ViewGraph.swift) | T-fail. DEBUG call-site assertion | Sampled frame | Assertion, trace scan, serialized snapshot delta | `StrandedListingProbeTests`, `SoundnessFailureChannelTests` | None  <!-- oracle-map: stranded-listing ; recordStrandedListingViolation ; strandedListingViolationCount --> |
| `layout-shadow-divergence` — sampled cached measure/place geometry equals a fresh all-reuse-disabled pass | Shadow layout comparison in [`LayoutShadowOracle.swift`](../Sources/SwiftTUICore/Measure/LayoutShadowOracle.swift), run by the frame tail's layout stage and recorded by [`DefaultRendererFrameTailCoordinator.swift`](../Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameTailCoordinator.swift) | T-fail. DEBUG call-site assertion. The production value is never repaired before recording | Every DEBUG layout stage. Sampled release frame | Assertion, trace scan, serialized snapshot delta | `LayoutShadowOracleTests`, `SoundnessProbeConfigurationTests`, `SoundnessAssertPromotionTests`, `SoundnessFailureChannelTests` | Windowed lazy/hosted subtrees are excluded (cold shadow stride) and counted by the T-info exclusion counter; the shadow re-evaluates in-pass-verified hysteresis seeds instead of re-deciding bistable fixed points  <!-- oracle-map: layout-shadow-divergence ; recordLayoutShadowDivergence,recordLayoutShadowWindowedExclusions ; layoutShadowDivergenceCount,layoutShadowWindowedExclusionCount --> |


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

Two kinds are `T-ratchet` rather than `T-fail`. This section is their durable
tracking reference. Before this section existed, a stage tag (`Program-5-S0`)
in [`soundness_quarantine.txt`](../Scripts/soundness_quarantine.txt) was the
only record of *why* the team quarantined them. The tag names a program but does
not explain the reason.

| Kind | Baseline | Measured 2026-07-30 | Provenance | What the residual is | Burn-down expectation |
| --- | --: | --: | --- | --- | --- |
| `registration-publication` | 1194 | **1122** | `Program-5-S0` | Post-suppression scoped-restore residual | Reduce with the next scoped-restore fix. Not expected to reach zero on its own |
| `teardown-coherence-leak` | 478 | 478 | `Program-5-S0` | Existing unreachable-node residual (under-removal arm) | Reduce with teardown-lifetime work. See the leak census currency |

`registration-publication` is **72 below its baseline** at HEAD. The gate
reports this as a warning in every passing run:

```
WARNING: registration-publication count=1122 is below baseline=1194; reduce the ledger
WARNING: teardown-coherence-leak count=478 matches baseline=478
PASS: soundness trace counts are within their exact quarantine baselines
```

The ratchet works, but the ledger is stale. When the next change touches this
area, reduce the ledger row to the measured count. A baseline that is 72 too
high allows 72 regressions before the gate fails.

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

There are **three** numbers in play, not two, and only the third is current:

| Kind | S0 raw | S0 injected | S0 residual | Ledger (post-S1) | **Measured at HEAD** |
| --- | --: | --: | --: | --: | --: |
| `registration-publication` | 1,197 | 1 | 1,196 | 1194 | **1122** |
| `teardown-coherence-leak` | 479 | 1 | 478 | 478 | **478** |

`teardown-coherence-leak` reconciles exactly across all three: S1's suppression
work removed none of its lines, and nothing since has either.

`registration-publication` moved twice. S1's scoped-restore suppression changed
the S0 report's 1,196 to the ledger's 1194. The ledger row records this as
"post-suppression scoped-restore residual". Later work removed another 72
lines and produced the measured 1122, but nobody reduced the ledger. The
scanner only warns below the baseline, so this drift remained easy to miss.

**None of the three documents was the current authority. Only a fresh
trace-armed run is.** The S0 report is a dated snapshot and is not maintained.
The ledger is a ceiling that has drifted 72 above reality. Read the ledger as
"what will fail the gate", not "what is true".

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
remaining measured hole is deliberate: subtrees under a windowed lazy or hosted
product are skipped, because the production window stride is a running
refinement the cold shadow pass legitimately cannot reproduce, and each skip
counts into `layoutShadowWindowedExclusionCount` so the hole's size stays
visible. If that carve-out ever has to widen beyond windowed products, treat it
as a design smell to revisit, not a routine expansion.

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

