---
title: "refactor: Stage 2 - name hidden pipeline stages"
type: refactor
status: shipped
date: 2026-05-17
depends_on:
  - "2026-05-16-001-pipeline-driver-hardening-plan.md"
  - "2026-05-16-002-stage-1-unify-render-head-plan.md"
  - "2026-05-12-002-late-preference-reconciliation-plan.md"
  - "../proposals/PIPELINE_DRIVER_AUDIT.md"
---

# Stage 2 - Name Hidden Pipeline Stages Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with
> `superpowers:executing-plans` or the local equivalent. This is **Stage 2** of
> [`2026-05-16-001-pipeline-driver-hardening-plan.md`](./2026-05-16-001-pipeline-driver-hardening-plan.md);
> it addresses audit proposal **P3** (Findings 5 and 11).

**Goal:** Promote the two hidden runtime stages into named code units before
Stage 3 introduces composition:

```text
head -> animation injection -> late-preference reconciliation loop -> frame tail -> commit
```

**Architecture:** Stage 1 extracted `computeFrameHead`, but that head still
contains inline animation injection, and the frame tail still has duplicated
sync/async late-preference fixpoint loops. Stage 2 does not change behavior. It
names those stages, centralizes the reconciliation bound and bound-exceeded
policy, and records the policy decision in an ADR so Stage 3 can compose the
real pipeline instead of burying these units in fused functions again.

**Tech Stack:** Swift 6.3 strict concurrency, Swift Testing, `SwiftTUIRuntime`,
and the focused runtime suites that cover animation, toolbar reconciliation,
and sync/async artifact parity.

---

## Current Source Anchors

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - `computeFrameHead`: currently calls `animationController.processResolvedTree`
    and `animationController.applyInterpolations` inline.
  - `renderLayoutResolvingLatePreferences`: synchronous bounded reconciliation
    loop.
  - `renderLayoutResolvingLatePreferencesAsync`: async bounded reconciliation
    loop with the same policy duplicated by hand.
  - `maxLatePreferenceReconciliationPasses = 4`: undocumented bound.
- `Sources/SwiftTUIViews/ActionScopes/Toolbar.swift`
  - `reconcileLatePreferenceConsumers(in:)`: current only late-preference
    consumer.
- `docs/plans/2026-05-12-002-late-preference-reconciliation-plan.md`
  - shipped original loop contract and toolbar-only scope.

## Task 1 - Verify The Stage 1 Baseline

- [x] Run:

```bash
swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.ToolbarTests
```

Expected: all pass before the refactor starts. If not, stop and resolve the
baseline.

## Task 2 - Name Animation Injection

- [x] Add a private `AnimationInjectionStage` in `SwiftTUI.swift`.
- [x] Give it one `@MainActor` `apply(...)` method that documents the contract:
  it mutates the resolved tree after resolve and before measure, and it is the
  only resolved-tree animation insertion point.
- [x] Replace the inline animation block in `computeFrameHead` with
  `AnimationInjectionStage(controller: animationController).apply(...)`.
- [x] Keep `MonotonicInstant.now()` ownership in `computeFrameHead`; the stage
  consumes a timestamp rather than selecting one so frame-head diagnostics and
  existing tick behavior stay unchanged.

## Task 3 - Name And Centralize Late-Preference Reconciliation

- [x] Add a private `LatePreferenceReconciliationPolicy` with an explicit
  `maximumRelayoutPasses` and `boundExceededBehavior`.
- [x] Keep the existing bound-exceeded behavior: emit
  `latePreference.reconciliationLimitExceeded` and commit the last fully laid
  out tree with the current realized layout-dependent content. Do not trap or
  fail rendering in this stage.
- [x] Add a private `LatePreferenceReconciliationStage` that owns the sync and
  async wrappers plus shared step/finalization helpers.
- [x] Re-point `renderLayoutResolvingLatePreferences` and
  `renderLayoutResolvingLatePreferencesAsync` to the named stage.
- [x] Remove the duplicated `for 0..<maxLatePreferenceReconciliationPasses`
  bodies from `DefaultRenderer`; both wrappers must use the same policy object.

## Task 4 - Record The Bound Decision

- [x] Create `docs/decisions/0018-late-preference-reconciliation-bound.md`.
- [x] Record why Stage 2 keeps the warning-and-commit policy:
  - the current shipped toolbar-only reconciler is bounded and diagnostic;
  - a hard failure would turn authored preference depth into a frame-killing
    runtime error;
  - a derived bound needs more than one late-preference consumer before it can
    be justified;
  - Stage 3 should compose the loop as a loop-bearing stage, not hide it.
- [x] Update the Stage 2 section of the roadmap to link this plan and the ADR.

## Task 5 - Verify And Ship The Stage

- [x] Run focused suites:

```bash
swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.ToolbarTests
swiftly run swift test --filter AnimationController
```

- [x] Run the repo gate because this touches shared runtime code:

```bash
bun run test
```

- [x] Mark this plan `status: shipped` and add a short shipped record once the
  code and ADR are verified.

## Shipped Record

Stage 2 names animation injection through `AnimationInjectionStage` and routes
the frame-head resolved-tree mutation through that stage. The timestamp remains
owned by `computeFrameHead`, preserving existing frame-head timing behavior.

Late-preference reconciliation now runs through `LatePreferenceReconciliationStage`
for both sync and async render paths. The stage owns the shared policy, step
logic, relayout input construction, and bound-exceeded finalization. The runtime
bound remains four relayout passes and the bound-exceeded behavior remains the
shipped warning-and-commit degradation policy.

ADR 0018 records why the bound stays diagnostic for the toolbar-only reconciler
and why graph-derived bounds are deferred until more late-preference consumers
exist.

## Exit Criteria

Stage 2 is complete when:

- Animation injection has a named stage object/function and no longer appears as
  an inline anonymous block in `computeFrameHead`.
- Late-preference reconciliation has a named loop-bearing stage used by both
  sync and async render paths.
- The reconciliation bound is documented in code and in ADR 0018.
- The bound-exceeded behavior is explicit and unchanged: warning diagnostic,
  then commit from the last fully laid-out tree.
- The focused suites and `bun run test` pass.

## Non-goals

- Do not introduce the composed render-pipeline abstraction. That is Stage 3.
- Do not add new public API for late-preference reconciliation.
- Do not extend late-preference reconciliation beyond toolbar hosts.
- Do not replace the bound with a speculative graph-depth solver before more
  consumers exist.
