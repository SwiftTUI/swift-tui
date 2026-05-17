# Pipeline Driver Audit

**Status:** Historical findings document, opened 2026-05-16. The investigation
captured the gap between the *formalized* render pipeline the repository
advertised and the *driver* that actually executed every frame before the
pipeline-driver hardening roadmap. Stage 8 of that roadmap reconciled the
current architecture docs with the shipped composed driver. The findings below
remain the evidence record for the pre-hardening state; they no longer override
[`ARCHITECTURE.md`](../ARCHITECTURE.md).

**Scope:** the render driver and the adjacent contracts that decide whether the
advertised pipeline is enforceable — `DefaultRenderer` / `renderView`, the
frame-tail machinery, retained phase reuse, raster damage, commit/presentation
handoff, and the tests that claim coverage over those seams. It is a companion to
[`PIPELINE_BOUNDARY_HARDENING.md`](./PIPELINE_BOUNDARY_HARDENING.md), which
hardens the *phase-product types*. This document concerns the *control flow that
crosses those boundaries at runtime* — the part boundary hardening does not
touch.

**Owner:** closed by the pipeline-driver hardening roadmap.

## Stage 8 outcome summary

| # | Finding | Outcome |
| --- | --- | --- |
| 1 | The formalized `Renderer<Root>` pipeline is unused outside tests | Resolved by Stage 3: the generic helper was removed and `DefaultRenderer` now runs `RuntimeRenderPipeline`. |
| 2 | `renderView` does not execute seven ordered phases | Resolved by Stage 3 and Stage 8: docs now distinguish runtime composition from phase-product order. |
| 3 | Sync and async render heads are ~120 duplicated lines | Resolved by Stage 1, then enforced by the Stage 3 composition. |
| 4 | Resolve mutates five subsystems; commit is not the side-effect boundary | Resolved by the Finding 4 follow-up: prepared heads now use draft/commit boundaries and the declared rollback-effect model was removed. |
| 5 | The "strict ordered pipeline" is a bounded fixpoint loop | Resolved by Stage 2: late-preference reconciliation is named and bounded. |
| 6 | Hand-rolled `pthread`; concurrency escape-hatch policy bypassed | Resolved by Stage 6: worker ownership and recursion safety were hardened. |
| 7 | Off-main frame-tail rendering is a synchronous no-op on WASI | Documented by Stage 6 as a compatibility boundary. |
| 8 | `FrameDropEligibility.Blocker` is a ~24-flag correctness surface | Resolved by Stage 5: completed-frame decisions use the shipped impact product. |
| 9 | ~13 render entry points span the {sync,async,cancellable,reconciled} cube | Resolved by Stage 3: sync, async, and cancellable are execution strategies over one composition. |
| 10 | `FrameDiagnostics` is a ~30-field god struct with dual code paths | Resolved by the source-breaking cleanup: diagnostics are grouped records, `collectsDiagnostics` is gone, and artifact equality ignores diagnostics sidecars. |
| 11 | Animation is an unnamed phase that mutates the resolved tree | Resolved by Stage 2 and composed by Stage 3. |
| 12 | Governance documentation has already diverged from the implementation | Resolved by Stage 8. |
| 13 | Retained reuse freshness depends on hand-maintained equivalence/projection rules | Hardened by Stage 0 guardrails; future fields still need classification. |
| 14 | Raster damage is advisory; missing invalidation can underpaint silently | Resolved by Stage 4: fresh raster and incremental repaint are split. |
| 15 | `PresentationSurface` is terminal-shaped even for semantic/non-terminal hosts | Resolved by Stage 7: host presentation roles are split. |
| 16 | `FrameArtifacts` is an inspection bundle, not a narrow phase contract | Resolved by Stage 0 source docs and Stage 8 architecture wording. |
| 17 | Tests protect known incidents more than the advertised architecture | Hardened by Stage 0 contract guards. |

## Why this exists

[`ARCHITECTURE.md`](../ARCHITECTURE.md), [`AGENTS.md`](../../AGENTS.md), and ADR
[`0002-seven-phase-pipeline-not-collapsed.md`](../decisions/0002-seven-phase-pipeline-not-collapsed.md)
all assert the same headline contract:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

> "That ordering is visible in `DefaultRenderer`, `FrameArtifacts`, `Pipeline`,
> and the regression suites."

This audit checked whether that is true of the code that runs. It is true of the
*types*. It is not true of the *driver*.

## Summary of findings

| # | Finding | Severity |
| --- | --- | --- |
| 1 | The formalized `Renderer<Root>` pipeline is unused outside tests | Critical |
| 2 | `renderView` does not execute seven ordered phases | High |
| 3 | Sync and async render heads are ~120 duplicated lines | High |
| 4 | Resolve mutates five subsystems; commit is not the side-effect boundary | High |
| 5 | The "strict ordered pipeline" is a bounded fixpoint loop | High |
| 6 | Hand-rolled `pthread`; concurrency escape-hatch policy bypassed | High |
| 7 | Off-main frame-tail rendering is a synchronous no-op on WASI | Medium |
| 8 | `FrameDropEligibility.Blocker` is a ~24-flag correctness surface | High |
| 9 | ~13 render entry points span the {sync,async,cancellable,reconciled} cube | Medium |
| 10 | `FrameDiagnostics` is a ~30-field god struct with dual code paths | Medium |
| 11 | Animation is an unnamed phase that mutates the resolved tree | Medium |
| 12 | Governance documentation has already diverged from the implementation | High |
| 13 | Retained reuse freshness depends on hand-maintained equivalence/projection rules | High |
| 14 | Raster damage is advisory; missing invalidation can underpaint silently | High |
| 15 | `PresentationSurface` is terminal-shaped even for semantic/non-terminal hosts | Medium |
| 16 | `FrameArtifacts` is an inspection bundle, not a narrow phase contract | Medium |
| 17 | Tests protect known incidents more than the advertised architecture | Medium |

---

## Finding 1 — The formalized pipeline is dead code

`Sources/SwiftTUICore/Pipeline/Pipeline.swift` defines `Renderer<Root>`: a
generic struct of seven phase closures whose `renderFrame` runs them in linear
order. It is exactly the pipeline the docs describe.

`Renderer<Root>.renderFrame` / `.noOp()` are referenced **only** in
`Tests/SwiftTUICoreTests/PipelineTests.swift` and
`Tests/SwiftTUITests/Phase0FoundationTests.swift`. No production code constructs
a `Renderer<Root>` or calls `renderFrame`.

The real entry point is `DefaultRenderer.render`
(`Sources/SwiftTUIRuntime/SwiftTUI.swift:190`), which calls `renderView`
(`SwiftTUI.swift:295`) — a ~260-line imperative function that never touches
`Renderer<Root>`.

The project therefore ships two renderers: the clean, documented, formal one
that two test files exercise; and the ad-hoc imperative one that every real
frame goes through. ADR 0002 defends "not collapsing the phases," but what it
defends is the *type* split. The *driver* collapsed the phases into one function
and the ADR never recorded that the defended artifact and the running artifact
diverged.

**This is the most serious finding: the headline architectural claim is not true
of the code that runs.**

## Finding 2 — `renderView` does not execute seven ordered phases

`renderView` (`SwiftTUI.swift:295`–`556`), in execution order:

1. **resolve** — interleaved with registration drafting, `frameState` mutation,
   selective-evaluation gating, portal-root wrapping, evaluator installation,
   and dirty-queue management.
2. **animation injection** — `animationController.applyInterpolations(to:
   &resolved)` mutates the resolved tree in place (`SwiftTUI.swift:390`). The
   inline comment reads "This is the only pipeline insertion for animation."
3. **late-preference reconciliation loop** — see Finding 5.
4. **frame tail** — `FrameTailRenderer` fuses measure + place + semantics + draw
   + raster into one unit.
5. **commit** + diagnostics.

The honest description of the driver is **three stages** — head, tail, commit —
not seven phases. The seven names survive as struct types and as per-phase
timing fields populated by instrumentation *inside* the fused tail. Per-phase
timings measured inside a fused function are not evidence of a phase boundary.

Fusing measure/place/raster is a legitimate performance choice. The debt is the
gap between that choice and a doc that still asserts seven independently
observable phases each run once.

## Finding 3 — Sync and async heads are copy-pasted

`renderView` (sync, `SwiftTUI.swift:295`–`556`) and `prepareFrameHead` (async,
`SwiftTUI.swift:662`–`811`) contain ~120 lines of near-identical code:
registration-draft creation, `resolveContext` assembly, `frameState.update`, the
`canUseSelectiveEvaluation` gate, portal-context derivation,
`PresentationPortalRoot` wrapping, root/evaluator installation, dirty queueing,
transition collection, `renderPipelineTree`, `wrapInContainerSafeArea`,
animation processing, `retainedInput`, and `LayoutPassContext` construction.

These were forked, not shared. A fix to the selective-evaluation gate in one
path will silently not reach the other. This is the drift class that
[`PIPELINE_BOUNDARY_HARDENING.md`](./PIPELINE_BOUNDARY_HARDENING.md) exists to
prevent — and the renderer's own front door violates it.

## Finding 4 — Commit is not the side-effect boundary

[`ARCHITECTURE.md`](../ARCHITECTURE.md) states "Commit is the main-actor
side-effect boundary." But resolve mutates at least five subsystems before
commit: `viewGraph` (`beginFrame`, `invalidate`, `setRootEvaluator`,
`evaluateDirtyNodes`), `frameState`, `presentationPortalState`,
`observationBridge`, and `animationController`.

The proof is the async path. `prepareFrameHead` captures
`viewGraphCheckpoint`, `frameStateCheckpoint`, `presentationPortalCheckpoint`,
`observationBridgeCheckpoint`, and `animationCheckpoint`; `abortPreparedFrameHead`
(`SwiftTUI.swift:122`) rolls all five back. Transactional rollback of five
mutable subsystems is necessary only because resolve is not side-effect-free.

ADR [`0004-frame-head-abort-reverted.md`](../decisions/0004-frame-head-abort-reverted.md)
records that a clean abortable head was attempted and reverted. The
checkpoint/restore code is the residue of that attempt — a half-transactional
system kept because a fully transactional one did not work and a fully pure
resolve was never built.

## Finding 5 — The pipeline is a bounded fixpoint loop

`renderLayoutResolvingLatePreferences` (`SwiftTUI.swift:559`) runs layout, calls
`reconcileLatePreferenceConsumers`, and on `requiresRelayout` re-runs the entire
layout — up to `maxLatePreferenceReconciliationPasses = 4` (`SwiftTUI.swift:11`).
On the 5th failure it emits `latePreferenceReconciliationLimitIssue` and renders
anyway.

Consequences:

- measure + place can run 4× per frame; the "phases run once in order" model is
  false for any view using preference-fed-back layout.
- `4` is a magic constant with no derivation.
- The give-up branch means a legitimately deep preference dependency chain
  renders with stale geometry and only logs a diagnostic — a correctness
  compromise presented as a guardrail.

Preference-driven layout is genuinely a fixpoint problem. The debt is not the
loop; it is that the loop contradicts the documented model instead of being
designed into it.

## Finding 6 — Hand-rolled `pthread`; escape-hatch policy bypassed

`prek.toml` installs a `structured-concurrency-escape-hatches` hook that blocks
`@unchecked Sendable` and `nonisolated(unsafe)`. The Darwin branch of
`FrameTailLayoutWorker` (`Rendering/FrameTailRenderer.swift:377`) instead:

- calls `pthread_create` with a manually allocated 8 MB stack
  (`FrameTailRenderer.swift:378`), and `pthread_join` in `deinit`;
- does manual lifetime management via `Unmanaged.passRetained` / `fromOpaque`;
- guards a job queue with a `DispatchSemaphore` plus `Mutex`;
- wraps the `unsafe pthread_*` calls in `@safe`.

`@safe` is not on the hook's banlist, so the policy is satisfied on a
technicality while the code does exactly the unstructured, manually
memory-managed concurrency the hook exists to forbid.

Two further problems follow:

- **The 8 MB stack** exists because the layout engine recurses deeply enough to
  overflow a default thread stack. `Tests/SwiftTUICoreTests/StackSafetyRegressionTests.swift`
  is a tripwire, not a fix: a sufficiently nested view tree remains an
  unbounded-input crash. The stack size raises the cliff; it does not remove it.

## Finding 7 — Off-main rendering is a no-op on WASI

`FrameTailLayoutWorker` has three `#if` variants
(`FrameTailRenderer.swift:311`/`471`/`485`): Darwin pthread, Dispatch queue, and
an `#else` that runs the operation inline and synchronously. On WASI, "off-main
frame-tail rendering" — a feature with its own proposal
([`OFF_MAIN_PIPELINE_RENDERING.md`](./OFF_MAIN_PIPELINE_RENDERING.md)) and plan
— is a no-op. The async API shape is preserved while the concurrency behavior
diverges by platform. One API, three semantics.

## Finding 8 — Frame-drop eligibility is a ~24-flag correctness surface

`FrameDropEligibility.Blocker` (`Pipeline/FrameDropEligibility.swift:36`) is a
`CaseIterable` enum with roughly 24 cases — `lifecycleAppear`,
`lifecycleDisappear`, `lifecycleChange`, `taskStart`, `taskCancel`,
`handlerInstallations`, `customLayoutFallback`, `focusGraph`,
`focusBindingSync`, `focusedValueSync`, `scrollSync`,
`preferenceObservationDelta`, `animationCompletion`, `animationTransition`,
`animationTransaction`, `workerCustomLayoutCacheUpdate`,
`retainedLayoutBaseline`, `retainedRasterBaseline`, `presentationFullRepaint`,
`graphicsReplay`, `diagnosticsFullRecord`, `unobservable`, and more.

Each case is a reason a completed async frame cannot be dropped. The
cancellation optimization is correct only if every feature that mutates
committed state remembers to register a blocker. The correctness surface is the
power set of those flags and grows by one dimension per feature; a missed
blocker silently drops a frame that carried a real lifecycle or task event.

`DefaultRenderer.init` hardcodes `completedFramePolicy = .dropCompletedVisualOnly`
(`SwiftTUI.swift:51`). The policy is a field implying configurability, but the
public renderer pins it.

## Finding 9 — The render-entry combinatorial explosion

`SwiftTUI.swift` exposes, on the render path: `render`, `renderAsync`,
`renderAsyncCancellable`, `renderView`, `renderViewAsync`, `prepareFrameHead`,
two `renderFrameTailAsync` overloads,
`renderFrameTailAsyncWithoutLatePreferenceReconciliation`,
`renderLayoutResolvingLatePreferences`,
`renderLayoutResolvingLatePreferencesAsync`, `renderFrameTailLayoutAsync`, and
`renderFrameTailCancellable` — roughly 13 functions covering the cross product
of {sync, async} × {cancellable, not} × {late-preference reconciled, offloaded}.
The cross product is managed by duplication rather than composition — the job a
real phase abstraction (Finding 1) would have done.

## Finding 10 — `FrameDiagnostics` god struct

Historical state: `FrameDiagnostics` (`Commit/FrameArtifacts.swift`) had ~30
stored properties and a ~30-parameter `init`. It was `Equatable, Sendable`, so
every frame could allocate and structurally compare it. Adding one diagnostic
touched the struct, the `init`, `summarize(...)`, and `SnapshotRenderer`. The
`collectsDiagnostics: Bool` flag existed to skip building it — confirming the
cost was known — and created a second render path that could diverge from the
first.

Resolution: the source-breaking cleanup decomposed diagnostics into grouped
input, count, work, presentation, timing, runtime, and drop records. Rendering
now always builds diagnostics, `DefaultRenderer` no longer exposes
`collectsDiagnostics`, `FrameDiagnostics` is no longer `Equatable`, and
`FrameArtifacts` equality compares the frame products while ignoring diagnostic
sidecars.

## Finding 11 — Animation is an unnamed phase

`animationController.applyInterpolations(to: &resolved)` (`SwiftTUI.swift:390`)
mutates the resolved tree between resolve and measure. It is an eighth phase the
seven-phase contract does not name. The inline comment "This is the only
pipeline insertion for animation" is a defensive marker on a deliberate contract
deviation — it documents the smell rather than removing it.

## Finding 12 — Governance documentation has outrun the code

The repository carries 36 `docs/` files, 39 plan docs, 38 proposal docs, 17
ADRs, a public-surface policy, a public-API ratchet, and the "Important Data
Products" ownership table in [`ARCHITECTURE.md`](../ARCHITECTURE.md). For a
pre-1.0, single-maintainer, AI-assisted package, the ratio of process artifacts
to load-bearing API is inverted, and Finding 1 is the proof it is not working:
the doc says the pipeline is "visible in `Pipeline`," and `Pipeline` is dead
code.

`Harden pipeline boundary contracts` (the most recent driver-adjacent commit)
hardened the *type products*. That is worth doing, but it hardens the structs,
not the driver, and the driver is the only place the boundaries are crossed at
runtime. The hardening effort is aimed at the part that was already sound.

## Finding 13 — Retained reuse freshness is a hand-maintained contract

The retained layout path is performance-critical, but its correctness rests on
manual agreement between several structs:

- `ResolvedNode.isEquivalentForMeasurement` and
  `ResolvedNode.isEquivalentForPlacement`
  (`Sources/SwiftTUICore/Resolve/ResolvedNode.swift:863`) decide whether a prior
  measured or placed product can be reused.
- `PlacedNodeResolvedMetadata`
  (`Sources/SwiftTUICore/Place/PlacedNode.swift:10`) carries the resolved-phase
  projection that must be synchronized into reused placed nodes.
- `synchronizeRetainedPhaseMetadata`
  (`Sources/SwiftTUICore/Measure/LayoutEngine+RetainedLayout.swift:89`) rewrites
  resolved-derived mirrors after retained placement reuse.
- `computeSupportsRetainedReuse`
  (`Sources/SwiftTUICore/Resolve/ResolvedNode.swift:740`) excludes some dynamic
  node classes from retained reuse.

This is a brittle freshness protocol. Adding a new field to `ResolvedNode` or
`PlacedNode` forces a hidden classification decision: does it affect
measurement, placement, semantics, draw, lifecycle, damage, commit, or only
diagnostics? If that decision is missed, the system can reuse a stale measured
or placed product while every phase type remains well-formed.

`Tests/SwiftTUICoreTests/LayoutEngineTests.swift` covers one important retained
metadata synchronization case, but the architecture still depends on convention:
there is no mechanical test that fails when a new resolved-derived field is
added without an equivalence/projection decision.

## Finding 14 — Raster damage cannot self-correct incomplete invalidation

`Rasterizer.rasterizeCollectingVisibleIdentities`
(`Sources/SwiftTUICore/Raster/Rasterizer.swift:55`) accepts a previous surface
and optional `PresentationDamage`. That means rasterization is not just a pure
`DrawNode -> RasterSurface` conversion; it is also an incremental reuse adapter.

The danger is soundness. `refineDamage` compares previous and current rows only
inside the rows already marked dirty
(`Sources/SwiftTUICore/Raster/Rasterizer+Damage.swift:60`). The paint pass can
skip subtrees outside the dirty row range
(`Sources/SwiftTUICore/Raster/Rasterizer+Paint.swift:97`). If upstream
invalidation fails to include a changed row, raster refinement has no global
diff step that can discover the miss. The wrong previous pixels can survive,
and the pipeline will still report a successful raster product.

This is a reasonable optimization only if the invalidation graph is treated as a
soundness-critical Interface, not as a hint. Today the code reads like the
reverse: damage is advisory for hosts, but internally it also gates whether
painting happens.

## Finding 15 — The presentation seam is terminal-shaped

`PresentationSurface` (`Sources/SwiftTUIRuntime/Terminal/PresentationSurface.swift:142`)
requires terminal operations: entering/exiting alternate screen, raw mode,
cursor movement, cursor style, writes, clear, flush, and size. Semantic host
frames are layered on top of that same Interface
(`Sources/SwiftTUIRuntime/Terminal/PresentationSurface.swift:206`), and
`RunLoop.presentCommittedFrame` dispatches through semantic, damage-aware, and
fallback branches
(`Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift:1436`).

For real terminals, that shape is natural. For WebHost, SwiftUIHost, JSON,
accessible, or future native hosts, it is an Adapter smell: non-terminal hosts
must conform to terminal obligations even when the semantic frame is the real
product they consume. The result is a shallow seam with too many irrelevant
methods and too much fallback behavior.

The stronger shape would split the Interfaces: surface metrics, terminal command
writer, raster presentation, semantic host-frame presentation, and damage-aware
presentation. Then a semantic host would not have to pretend to be a terminal
just to receive the richer committed frame.

## Finding 16 — `FrameArtifacts` is an inspection bundle, not a narrow contract

`FrameArtifacts` (`Sources/SwiftTUICore/Commit/FrameArtifacts.swift:166`) carries
the resolved, measured, placed, semantic, draw, raster, damage, draw-identity,
commit-plan, scroll-geometry, custom-layout, and diagnostics products. That is
excellent for previews, debugging, assertions, and host adapters. It is weak as
an architecture contract.

The problem is that the bundle mixes products with different authority:

- canonical phase products (`resolvedTree`, `measuredTree`, `semanticSnapshot`);
- decorated or baseline-sensitive products (`placedTree`,
  `retainedLayoutBaseline`);
- advisory optimization hints (`presentationDamage`, `drawnIdentities`);
- side-effect plans (`commitPlan`);
- diagnostics and performance metadata.

The more consumers reach into `FrameArtifacts`, the easier it becomes to use the
wrong field as truth. The type is a good inspection seam, but it should not be
treated as proof that the phase seams are enforceable.

## Finding 17 — The tests are broad but mostly incident-shaped

The regression surface is better than average: retained metadata reuse,
async-frame ordering, presentation overlays, raster damage, terminal batching,
and phase diagnostics all have tests. The weak spot is architectural coverage.

One example: `DiagnosticsAndCacheTests` has a test named
`snapshotRendererExposesResolvedPlacedSemanticDrawRasterAndDiagnostics`
(`Tests/SwiftTUITests/DiagnosticsAndCacheTests.swift:1041`), but the assertions
primarily check visible tags in resolved, semantic, raster, and diagnostics
output. That is useful, but it is not a contract test for all advertised phase
products.

The missing layer is invariant testing: tests that fail when new resolved fields
do not participate in retained reuse decisions; when a `PlacedNode` construction
path bypasses metadata projection; when a committed side effect lacks
frame-drop classification; or when a host path loses semantic-frame sequence or
damage metadata. Current tests prove many bugs stay fixed. They do not prove the
pipeline model itself is hard to violate.

---

## What is genuinely sound

This audit is sharp because the bar the project set for itself is high. The
following hold up:

- The phase-product types (`ResolvedNode`, `MeasuredNode`, `PlacedNode`,
  `SemanticSnapshot`, `DrawNode`, `RasterSurface`, `CommitPlan`) are cleanly
  separated, `Sendable`, and well-owned. The type split is real.
- The "computed vs reused" diagnostic vocabulary makes incremental-reuse
  regressions localizable.
- Coordinate-domain discipline (integer cells for layout, continuous for
  pointer/draw) is coherent.
- There is real regression coverage around retained metadata synchronization,
  async frame-tail ordering, presentation overlays, and raster damage. The issue
  is not absence of tests; it is that the tests do not yet encode the advertised
  architecture as invariants.
- The ADR practice is real and honest — ADR 0004 records a revert.
- Strict-concurrency / `Sendable` adoption is thorough; the `pthread` is the one
  exception, not the norm.

---

## Proposals

The proposals below are directional. Nothing here should be landed blind; each
carries enumerated risk. They are ordered cheap → structural.

### P1 — Resolve the `Renderer<Root>` contradiction (pick one)

The headline asset — "a formalized pipeline" — is currently a claim, not a
mechanism. Choose:

- **P1a (honest, cheap).** Demote the seven-phase claim to match reality.
  Document the three real stages (head / tail / commit), name animation
  injection and late-preference reconciliation as the loop-bearing stages they
  are, and either delete `Pipeline.swift`'s `Renderer<Root>` or relabel it
  explicitly as a teaching/testing harness, not "the pipeline."
- **P1b (ambitious, structural).** Make `DefaultRenderer` drive a composed phase
  abstraction so the phase order is enforced by composition rather than asserted
  by prose. Sync / async / cancellable then become phase-wrapper strategies,
  collapsing Findings 1, 3, and 9 together.

Doing neither — continuing to harden type contracts while the driver stays an
unverified monolith — is the path that compounds debt. P1b is what the repo's
own documents are asking for; P1a is the minimum to make the docs true.

**Risk:** P1b is a deep refactor of the hottest code path; it must be staged
behind the existing regression suites (`PipelineTests`,
`LayoutAndRenderingPipelineTests`, `AsyncFrameTailRenderingTests`,
`DiagnosticsAndCacheTests`) and profiled, since composition can cost
allocations the current monolith avoids.

### P2 — De-duplicate the sync/async head (Finding 3)

Extract the shared ~120 lines of `renderView` and `prepareFrameHead` into one
`prepareFrameHead`-shaped function; have the sync path call it and finish
synchronously. This is mechanical and independently valuable, and it is a
prerequisite that de-risks P1b. **Risk:** the sync path currently has no
checkpoint capture; unifying must not impose checkpoint cost on the sync path.

### P3 — Name and bound the loop (Finding 5, Finding 11)

Make the late-preference reconciliation loop and animation injection
first-class, named stages in whatever model P1 lands. Replace the magic `4` with
a derived or documented bound, and decide explicitly whether exceeding the bound
is a logged degradation or a hard diagnostic surfaced to the author.

### P4 — Bring the layout worker under structured concurrency (Finding 6, 7)

Replace the hand-rolled `pthread` with a task-based or `Executor`-based worker,
or — if a deep stack is genuinely required — isolate the unsafe thread code
behind a single audited type with an explicit ADR justifying the escape and
amending the `structured-concurrency-escape-hatches` policy to cover `@safe`.
Separately, decide whether WASI's synchronous fallback (Finding 7) is acceptable
and document it, or gate the async API off where it cannot be honored.

### P5 — Audit the layout engine's recursion depth (Finding 6)

`StackSafetyRegressionTests` proves the team knows layout recursion is a
concern. Treat deep nesting as an unbounded-input hazard: either bound recursion
depth with a graceful error, or convert the hot recursive layout walks to an
explicit work stack. The 8 MB thread stack is mitigation, not a fix.

### P6 — Constrain the frame-drop correctness surface (Finding 8)

The ~24-blocker model makes every future feature's review longer. Investigate
inverting it: instead of enumerating every reason a frame *cannot* drop, derive
droppability from a small, closed property of `CommitPlan` (e.g. "the plan
carries no observable side effect"). If the enumerated model must stay, add a
test that fails when a new committed-side-effect type ships without a
corresponding `Blocker`.

### P7 — Add retained-reuse invariant tests (Finding 13)

Add a mechanical guard around the retained freshness contract. At minimum:

- every resolved-derived field mirrored into `PlacedNode` must appear in a
  projection synchronization test;
- every new `ResolvedNode` field must be classified for measurement,
  placement, semantics, draw, lifecycle, damage, commit, or diagnostics;
- retained placement reuse must have a focused test for any field that can
  affect semantics, draw, lifecycle, or host damage without affecting geometry.

This is cheaper than removing retained reuse and directly targets the current
failure mode: silent staleness after a future field addition.

### P8 — Split fresh rasterization from incremental repaint (Finding 14)

Keep the optimization, but stop naming it as the raster phase itself. A clean
shape is:

```text
draw -> fresh raster
draw + previous raster + sound damage -> incremental repaint adapter
```

That split lets tests assert the pure raster product independently from the
reuse optimization. It also clarifies that damage must be sound before it is
allowed to suppress painting.

### P9 — Split host presentation Interfaces (Finding 15)

Decompose `PresentationSurface` into smaller roles: terminal command surface,
surface metrics provider, raster presentation surface, semantic host-frame
surface, and damage-aware variants. Existing terminal hosts can compose all of
them. Semantic hosts should not need to inherit raw-mode and cursor-write
obligations to receive `SemanticHostFrame`.

This is not primarily aesthetic. It would make the producer/consumer contract at
`RunLoop.presentCommittedFrame` explicit and reduce fallback ambiguity.

### P10 — Treat `FrameArtifacts` as an inspection product (Finding 16)

Keep `FrameArtifacts`, but stop using its breadth as architectural evidence.
Document which fields are canonical, which are decorated projections, which are
advisory hints, and which are diagnostics. Tests and host adapters should prefer
phase-specific products or semantic host frames over opportunistic reads from
the artifact bundle.

### P11 — Add architecture-contract tests (Finding 17)

Create a small suite whose names match the claimed architecture rather than past
bugs. Candidate tests:

- all committed side-effect kinds force non-droppable completed frames;
- semantic host-frame sequence and damage survive async cancellation/drop paths;
- focus/default-focus convergence cannot present stale semantic snapshots;
- retained layout reuse updates every non-geometry resolved projection;
- incremental raster repaint is byte-for-byte equivalent to fresh raster for a
  curated mutation matrix.

## Remaining follow-ups

The original suggested next step was to land P2, add the lowest-risk P7/P11
contract guards, then decide P1a versus P1b. That sequence landed in favor of
P1b. The later follow-up work also closed Finding 4 and Finding 10, so this
audit no longer carries an open implementation follow-up.

## Related docs

- [`ARCHITECTURE.md`](../ARCHITECTURE.md) — the seven-phase claim this audit tests
- [`PIPELINE_BOUNDARY_HARDENING.md`](./PIPELINE_BOUNDARY_HARDENING.md) — hardens
  the phase-product types; this audit covers the driver instead
- [`ASYNC_RENDERING.md`](../ASYNC_RENDERING.md) — async frame-tail vocabulary
- [`OFF_MAIN_PIPELINE_RENDERING.md`](./OFF_MAIN_PIPELINE_RENDERING.md) — the
  off-main feature Finding 7 concerns
- [`HOST_RENDERING_PIPELINES.md`](../HOST_RENDERING_PIPELINES.md) — host-facing
  rendering flow and presentation handoff
- [`SEMANTIC_HOST_FRAME_API.md`](./SEMANTIC_HOST_FRAME_API.md) — semantic
  host-frame producer/consumer contract
- [`ASYNC_FRAME_STALE_POLICY.md`](./ASYNC_FRAME_STALE_POLICY.md) — completed
  frame drop policy and blocker model
- ADR [`0002-seven-phase-pipeline-not-collapsed.md`](../decisions/0002-seven-phase-pipeline-not-collapsed.md)
- ADR [`0004-frame-head-abort-reverted.md`](../decisions/0004-frame-head-abort-reverted.md)
