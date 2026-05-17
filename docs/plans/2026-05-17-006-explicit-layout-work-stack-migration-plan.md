---
title: "refactor: Stage 6 Task 5 - migrate layout to explicit work stacks"
type: refactor
status: shipped
date: 2026-05-17
depends_on:
  - "2026-05-17-004-stage-6-worker-recursion-hardening-plan.md"
  - "../proposals/EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md"
  - "../decisions/0020-off-main-layout-worker-concurrency.md"
---

# Stage 6 Task 5 - Explicit Layout Work-Stack Migration Plan

> **For agentic workers:** Execute this plan task-by-task. Keep the checkboxes
> current as work lands. Use `swiftly run swift ...`, not bare `swift`.

This plan implements the accepted direction in
[`EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md`](../proposals/EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md).
The destination is not a graceful recursion cap. The destination is iterative
built-in layout: `LayoutEngine.measure` and `LayoutEngine.place` become shallow
entry points that drive explicit internal work stacks.

Depth limits are allowed only as temporary crash guards or compatibility
boundaries for public custom-layout recursion. They are not the completed
architecture and must not be used as evidence that built-in layout is stack-safe.

## End State

This plan is complete when:

- built-in measurement walks no longer recurse through Swift call frames;
- built-in placement walks no longer recurse through Swift call frames;
- layout-dependent placement-time measurement and indexed lazy-stack
  placement-time measurement enqueue explicit work instead of calling recursive
  built-in layout entry points;
- stack measurement's ideal pass, allocation pass, remeasurement pass,
  cross-axis reconciliation, and minimum-main-size logic are expressed as
  explicit states;
- retained placement frame recording is stack-safe when reused placed subtrees
  are recorded through `LayoutPassContext`;
- custom layout has an explicit stack-safe or bounded compatibility boundary;
- the Darwin 8 MiB pthread worker no longer has a stack-size justification; and
- focused stack/worker tests plus `bun run test` pass.

## Invariants

- Preserve SwiftUI-shaped layout behavior. This migration changes traversal
  mechanics, not layout results.
- Preserve `ResolvedNode`, `MeasuredNode`, and `PlacedNode` product semantics.
  Do not reshape those products unless a subtask proves it is required.
- Preserve child output order.
- Preserve measurement-cache lookup/store semantics.
- Preserve retained measurement and placement reuse semantics.
- Preserve `LayoutPassContext` work metrics and placed-frame diagnostics.
- Preserve ordinary public custom-layout fallback behavior.
- Keep worker replacement separate from layout-engine migration.

## Definitions

- **Built-in layout:** layout behavior implemented by SwiftTUICore cases such as
  `.intrinsic`, `.stack`, `.lazyStack`, `.overlay`, `.padding`, `.safeAreaInset`,
  `.border`, `.frame`, `.flexibleFrame`, `.decoration`, and `.viewThatFits`.
- **Custom-layout boundary:** `.custom` behavior and any public custom-layout
  callback that can call `engine.measure` or `engine.place`.
- **Iterative measurement:** a measurement traversal where built-in child work
  is represented by explicit frames or continuations, not nested calls to
  `LayoutEngine.measure`.
- **Iterative placement:** a placement traversal where built-in child work is
  represented by explicit frames or continuations, not nested calls to
  `LayoutEngine.place`.
- **Compatibility depth limit:** a deterministic cap for recursion that remains
  only at public/custom escape hatches during or after the migration.

## Commit Boundaries

Prefer one commit per completed task group:

1. Test baseline and audit inventory.
2. Measurement work-stack scaffolding.
3. Leaf and wrapper measurement migration.
4. Branching measurement migration.
5. Stack and lazy-stack measurement migration.
6. Placement migration.
7. Custom-layout boundary and compatibility diagnostics.
8. Recursive helper removal and guardrails.
9. Worker replacement or re-justification.
10. Documentation cleanup and shipped-status updates.

Each commit should leave the focused tests green. Run `bun run test` before
calling a task group complete when the group changes shared runtime behavior.

## Task 0 - Preflight And Current Recursion Inventory

- [x] Confirm the worktree is clean or isolate unrelated changes before editing:

```bash
git status --short --branch
```

- [x] Re-run the current recursion inventory and record any new edges discovered
  since this plan was written:

```bash
rg -n "measure\\(|place\\(|subtreeHasFlexibleContent|minimumMainSize|recordPlacedFrames" \
  Sources/SwiftTUICore/Measure Sources/SwiftTUICore/Place Sources/SwiftTUICore/Commit \
  -g '*.swift'
```

- [x] Verify the current known hotspots are still accurate:

  - `Sources/SwiftTUICore/Measure/LayoutEngine.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+Measurement.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+Stack.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+CellSize.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+Alignment.swift`
  - `Sources/SwiftTUICore/Measure/CustomLayout.swift`
  - `Sources/SwiftTUICore/Place/LayoutEngine+Placement.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+RetainedLayout.swift`
  - `Sources/SwiftTUICore/Commit/RetainedResolveFrame.swift`

- [x] Confirm existing stack-safety tests still prove post-layout traversals, not
  real `LayoutEngine.measure` / `LayoutEngine.place` stack safety.
- [x] If the inventory finds additional built-in recursive paths, add them to
  this plan before implementation.

**Acceptance criteria:**

- The worker knows exactly which recursive paths are in scope.
- No code changes beyond plan/inventory notes are needed for this task.

## Task 1 - Real Layout Stack-Safety Test Harness

Add tests that exercise actual layout measurement and placement.

- [x] Add a focused test file or extend
  `Tests/SwiftTUICoreTests/StackSafetyRegressionTests.swift`.
- [x] Add helpers that build real `ResolvedNode` trees without using the public
  view DSL. The helpers should support:

  - deep one-child wrapper chains;
  - deep stack/lazy-stack chains;
  - branching overlay/decoration trees;
  - safe-area inset trees with two children;
  - layout-dependent content nodes that realize children during placement;
  - indexed lazy-stack nodes that measure visible children during placement.

- [x] Add non-crashing baseline correctness tests at moderate depth:

  - `deepWrapperChainsMeasureAndPlaceThroughLayoutEngine`
  - `deepStackChainsMeasureAndPlaceThroughLayoutEngine`
  - `deepBranchingBuiltInTreesMeasureAndPlaceThroughLayoutEngine`
  - `layoutDependentPlacementMeasuresRealizedChildrenThroughLayoutEngine`
  - `indexedLazyStackPlacementMeasuresVisibleChildrenThroughLayoutEngine`

- [x] Add a way for later tasks to prove a path used the iterative engine. Prefer
  package-internal test hooks or diagnostics over timing or crash-only tests.
- [x] Do not land a test whose only failure mode is process stack overflow. If a
  local crash repro is useful during development, keep it out of the committed
  gate or guard it behind an explicit local-only mechanism.
- [x] Establish target depths for final regression coverage. The final depths
  should be high enough to exceed realistic authored nesting and low enough to
  keep CI runtime stable.

**Acceptance criteria:**

- Focused tests compile and pass against the current implementation at moderate
  depth.
- The harness can later assert iterative traversal for migrated paths.
- Test helpers are specific to stack safety and do not become a second layout
  DSL.

**Verification:**

```bash
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
```

## Task 2 - Measurement Work-Stack Scaffolding

Introduce the iterative measurement engine without migrating all behavior at
once.

- [x] Add internal work-stack implementation files, for example:

  - `Sources/SwiftTUICore/Measure/LayoutEngine+MeasurementWorkStack.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+MeasurementFrames.swift`

- [x] Define explicit measurement frame and continuation types. They should
  carry at least:

  - resolved node;
  - proposal;
  - pass context;
  - child index or phase state;
  - accumulated child measurements;
  - cache/reuse state needed to finish the node;
  - layout-behavior-specific continuation payload.

- [x] Keep public `LayoutEngine.measure` stable.
- [x] Route a narrow behavior subset through the work-stack path first.
- [x] Preserve the current measurement pipeline order for each node:

  1. retained measurement lookup;
  2. measurement cache lookup;
  3. work-metric update;
  4. layout-dependent boundary handling;
  5. fixed-size proposal adjustment;
  6. child measurement;
  7. stored child measurement projection;
  8. measured-size calculation;
  9. container allocation snapshot;
  10. cache store.

- [x] Add package-internal instrumentation for tests to prove a migrated
  built-in path used the work-stack engine.
- [x] Remove old recursive helpers or keep them callable only as temporary
  fallbacks.

**Implementation note:** `LayoutEngine.measure` now routes through
`LayoutEngine+MeasurementWorkStack.swift` for all built-in measurement cases.
The old recursive measurement dispatcher and child-selection helpers were
removed rather than retained as fallbacks. Public custom-layout callbacks remain
the explicit compatibility boundary for user-authored recursive calls.

**Acceptance criteria:**

- The new scaffolding can measure at least one simple built-in path.
- Existing measurement cache and work metrics continue to pass focused tests.
- No public API changes are introduced.

**Verification:**

```bash
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
```

## Task 3 - Leaf And Wrapper Measurement Migration

Move simple measurement paths to the iterative measurement engine.

- [x] Convert intrinsic leaves with no children.
- [x] Convert one-child intrinsic containers.
- [x] Convert simple wrapper cases:

  - `.padding`
  - `.safeAreaIgnoring`
  - `.border`
  - `.frame`
  - `.flexibleFrame`
  - `.offset`
  - `.position`

- [x] Preserve proposal transforms exactly:

  - inset/outset proposal transforms;
  - fixed frame proposal replacement;
  - flexible frame child proposal dimensions;
  - fixed-size metadata application before child measurement;
  - clamping proposal behavior after measured-size calculation.

- [x] Preserve measured-size calculation by reusing existing pure helpers where
  possible.
- [x] Update deep wrapper-chain tests to assert the iterative path.
- [x] Increase wrapper-chain depth to the final regression target once the path
  is fully iterative.

**Acceptance criteria:**

- Deep wrapper-chain measure/place tests no longer depend on Swift call-stack
  depth for measurement.
- Existing layout behavior tests still pass.
- Recursive measurement calls for these built-in wrapper cases are removed or
  quarantined behind temporary fallback code that is no longer used by tests.

**Verification:**

```bash
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
swiftly run swift test --filter SwiftTUITests.Layout
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
```

## Task 4 - Branching Built-In Measurement Migration

Move branching built-in measurement paths to explicit continuations.

- [x] Convert `.intrinsic` nodes with multiple children.
- [x] Convert `.overlay`.
- [x] Convert `.decoration`.
- [x] Convert `.safeAreaInset`.
- [x] Convert `.viewThatFits`.
- [x] Preserve special child ordering:

  - overlay children are measured in source order;
  - decoration primary child is measured before decorations;
  - decoration children still return in source order;
  - safe-area inset adornment is measured before base content;
  - fallback paths for missing primary/inset children match current behavior.

- [x] Preserve measured-child storage semantics, including any retained-layout
  projection rules.
- [x] Add or update tests for:

  - deep branching overlay/decoration trees;
  - safe-area inset measurement ordering;
  - missing primary child fallback behavior.

**Acceptance criteria:**

- No built-in branching case calls recursive `measure` for child work.
- Child result order is unchanged.
- Retained measurement reuse still reports the same computed/reused counts for
  representative cases.

**Verification:**

```bash
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
swiftly run swift test --filter SwiftTUITests.LayoutDependentContainerHardeningTests
```

## Task 5 - Stack And Lazy-Stack Measurement Migration

Move the most complex built-in measurement path to explicit states.

- [x] Split stack measurement into named internal phases:

  - ideal child measurement;
  - spacing budget;
  - available main-axis calculation;
  - flexible-child expansion;
  - compression;
  - allocated child remeasurement;
  - spacer main-axis correction;
  - cross-axis reconciliation;
  - lazy-stack allocation snapshot;
  - final measured-size calculation.

- [x] Replace `children.map { measure(...) }` and enumerated child
  remeasurement with explicit child-measurement work.
- [x] Convert fixed-size cross-axis reconciliation so remeasured children are
  enqueued instead of recursively measured.
- [x] Convert `subtreeHasFlexibleContent` to an iterative traversal.
- [x] Convert `minimumMainSize` / `derivedMinimumMainSize` traversal to an
  iterative traversal or an explicit stack-state calculation.
- [x] Preserve no-op remeasurement pruning for rigid children.
- [x] Preserve indexed child source behavior and child source snapshot
  assumptions.
- [x] Add deep stack-chain tests that assert iterative stack measurement.
- [x] Add regression coverage for:

  - flexible child expansion;
  - compression;
  - spacer correction;
  - fixed-size cross-axis reconciliation;
  - lazy-stack allocation snapshots;
  - nested stacks containing decorations and wrappers.

**Acceptance criteria:**

- Stack and lazy-stack measurement do not recurse through built-in child
  measurement.
- `subtreeHasFlexibleContent` and minimum-size traversal are stack-safe.
- Existing stack layout behavior and retained reuse tests pass.
- Deep stack-chain tests run at the final target depth.

**Verification:**

```bash
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
swiftly run swift test --filter SwiftTUITests.Layout
```

## Task 6 - Placement Work-Stack Scaffolding

Introduce iterative placement scaffolding before converting all placement cases.

- [x] Add internal work-stack implementation files, for example:

  - `Sources/SwiftTUICore/Place/LayoutEngine+PlacementWorkStack.swift`
  - `Sources/SwiftTUICore/Place/LayoutEngine+PlacementFrames.swift`

- [x] Define explicit placement frame and continuation types. They should carry
  at least:

  - resolved node;
  - measured node;
  - bounds;
  - viewport context;
  - pass context;
  - child-placement phase state;
  - accumulated placed children.

- [x] Keep public `LayoutEngine.place` stable.
- [x] Preserve the current placement order for each node:

  1. retained placement lookup;
  2. work-metric update;
  3. placed-frame recording;
  4. child placement;
  5. content-bounds calculation;
  6. `PlacedNode` construction.

- [x] Add instrumentation for tests to prove a migrated built-in path used the
  placement work stack.

**Implementation note:** `LayoutEngine.place` now routes through
`LayoutEngine+PlacementWorkStack.swift`. The placement work stack records
`placementWorkStackSteps`, preserves retained placement reuse, and leaves
`LayoutEngine+Placement.swift` as pure placed-node construction helpers.

**Acceptance criteria:**

- Placement scaffolding can place at least one simple built-in path.
- Retained placement reuse still works for migrated paths.
- Placed-frame diagnostics still record the same identities and bounds.

**Verification:**

```bash
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
swiftly run swift test --filter SwiftTUITests.AnchorPreferenceSurfaceTests
```

## Task 7 - Built-In Placement Migration

Move built-in placement cases to the iterative placement engine.

- [x] Convert intrinsic child placement.
- [x] Convert overlay alignment placement.
- [x] Convert stack and lazy-stack placement.
- [x] Convert wrapper placement:

  - `.padding`
  - `.safeAreaIgnoring`
  - `.safeAreaInset`
  - `.border`
  - `.frame`
  - `.flexibleFrame`
  - `.offset`
  - `.position`
  - `.decoration`
  - `.viewThatFits`

- [x] Convert layout-dependent content placement so realized children are
  measured and placed through explicit work, not recursive built-in calls.
- [x] Convert indexed lazy-stack visible child placement so placement-time
  measurement is explicit work.
- [x] Preserve viewport clipping and visible-range behavior.
- [x] Preserve alignment-guide and `viewDimensions` behavior.
- [x] Convert `LayoutPassContext.recordPlacedFrames(in:)` to an iterative
  traversal if retained placement reuse can still recurse through deep placed
  trees.

**Implementation note:** Built-in child placement no longer calls back into
`LayoutEngine.place`; placement requests are queued and finished through
explicit work items. Layout-dependent content and indexed lazy-stack placement
still measure during placement, but those calls hit the iterative measurement
engine. Retained placed-frame recording now walks reused placed subtrees with an
explicit stack.

**Acceptance criteria:**

- Built-in placement no longer recursively calls `place` for child work.
- Placement-time measurement paths do not bypass the measurement work stack.
- Deep wrapper-chain and deep stack-chain placement tests assert iterative
  traversal.
- Retained placement frame recording is stack-safe.

**Verification:**

```bash
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
swiftly run swift test --filter SwiftTUITests.AnchorPreferenceSurfaceTests
swiftly run swift test --filter SwiftTUITests.LayoutDependentContainerHardeningTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
```

## Task 8 - Custom Layout Boundary And Compatibility Depth Policy

Make the custom-layout boundary explicit after built-in layout is iterative.

- [x] Audit every `CustomLayoutHandle` and `WorkerCustomLayoutProxy` path that
  can call back into `LayoutEngine.measure` or `LayoutEngine.place`.
- [x] Define stack-aware child measurement and placement operations for
  worker-safe/framework-owned custom layout. The operations should enqueue work
  through the iterative engine rather than recursively entering built-in layout.
- [x] Preserve ordinary public custom layout fallback behavior.
- [x] Add a deterministic compatibility depth policy for public recursive
  `engine.measure` / `engine.place` calls that remain available to custom
  layout.
- [x] Extend layout diagnostics so runtime frames can carry a stable runtime
  issue when the compatibility depth limit is exceeded.
- [x] Decide and document the behavior for direct Core-only `LayoutEngine`
  calls with no runtime `LayoutPassContext`. The behavior must be deterministic
  and must not crash the process.
- [x] Add tests for:

  - worker-safe custom layout measuring children through the iterative engine;
  - ordinary public custom layout fallback still working;
  - compatibility depth limit reporting a stable runtime issue;
  - direct Core-only depth-limit behavior.

**Acceptance criteria:**

- Custom layout cannot silently reintroduce unbounded built-in recursion.
- Any remaining custom-layout recursion is bounded and diagnostic.
- Public custom-layout semantics remain compatible.
- Runtime issue reporting is deterministic and test-covered.

**Verification:**

```bash
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
swiftly run swift test --filter SwiftTUIViewsTests
```

## Task 9 - Remove Or Quarantine Recursive Built-In Helpers

Delete old recursive built-in traversal paths or make them impossible to call
from built-in layout.

- [x] Search for direct child `measure` and `place` calls in built-in layout
  behavior implementations.
- [x] Remove temporary recursive fallback code from migrated built-in paths.
- [x] Keep any remaining recursive calls only at documented custom-layout
  compatibility boundaries.
- [x] Add a guardrail if the final call graph has a practical mechanical check.
  Possible forms:

  - a focused script under `Scripts/`;
  - a unit test that inspects package-internal instrumentation;
  - comments at the few allowed escape hatches plus regression tests.

- [x] Update stack-safety tests so a new built-in recursive path fails
  deterministically without relying on a stack overflow crash.
- [x] Update `SOURCE_LAYOUT.md` if files were added, moved, or renamed.

**Acceptance criteria:**

- Built-in layout has no recursive child traversal path left.
- Allowed custom-layout escape hatches are named and bounded.
- The repo has a deterministic regression guard for future bypasses.

**Verification:**

```bash
rg -n "measure\\(|place\\(" Sources/SwiftTUICore/Measure Sources/SwiftTUICore/Place -g '*.swift'
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
./Scripts/check_concurrency_safety_policies.sh
```

## Task 10 - Frame-Tail Worker Replacement Or Re-Justification

Revisit ADR 0020 once built-in layout no longer needs a large stack.

- [x] Prove deep built-in layout tests pass without depending on the Darwin
  pthread worker's 8 MiB stack.
- [x] Evaluate the replacement shape:

  - structured `Task` on the normal cooperative executor;
  - a custom executor justified by scheduling/isolation needs;
  - retaining the isolated worker for a reason other than stack size.

- [x] Prefer removing the custom pthread worker if no non-stack reason remains.
- [x] Preserve ordered async frame-tail semantics:

  - queued tail jobs may cancel before worker layout starts;
  - started worker jobs are awaited;
  - non-droppable completed frames commit in order;
  - stale visual-only completed frames follow the existing drop policy.

- [x] Update or replace `FrameTailLayoutWorker.swift`.
- [x] Update ADR 0020 or add a follow-up ADR recording the new decision.
- [x] Update WASI wording if the worker semantics change.

**Acceptance criteria:**

- The worker implementation no longer relies on stack size, or an ADR explains
  the remaining non-stack reason.
- Async frame-tail ordering and diagnostics tests pass.
- The concurrency safety policy remains clean.

**Verification:**

```bash
./Scripts/check_concurrency_safety_policies.sh
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
```

## Task 11 - Full Gate And Documentation Closure

Close the Stage 6 migration after implementation and worker follow-up land.

- [x] Run the full repo gate:

```bash
bun run test
```

- [x] Run broader coverage if layout behavior or examples changed materially:

```bash
bun run test:all
```

- Verification note: `bun run test:all` initially failed in
  `Examples/layouts`, `Examples/gifcat`, and `Examples/gifeditor` with
  SwiftPM testing-helper signal exits from stale incremental `.build` state
  after file moves. Cleaning those example `.build` directories and rerunning
  the failed slices passed:

```bash
swiftly run swift test --package-path Examples/layouts
swiftly run swift test --package-path Examples/gifcat
swiftly run swift test --package-path Examples/gifeditor
```

- [x] Update `ASYNC_RENDERING.md` to remove or revise the large-stack caveat.
- [x] Update `docs/plans/2026-05-17-004-stage-6-worker-recursion-hardening-plan.md`
  to mark Task 5 complete.
- [x] Update
  `docs/plans/2026-05-16-001-pipeline-driver-hardening-plan.md` Stage 6 status.
- [x] Move the completed TODO entry into `docs/CHANGELOG.md` with concise,
  self-standing wording and commit-hash-prefixed doc links where required by
  `AGENTS.md`.
- [x] Update `docs/README.md` planned/active plan listings.
- [x] Keep
  `docs/proposals/EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md` as the design record.

**Acceptance criteria:**

- Stage 6 no longer has open recursion/worker work.
- Current-state docs no longer imply that a large layout stack is required for
  built-in layout.
- Full repo verification has passed, or any unrelated blocker is documented with
  focused passing evidence.

## Recommended First Implementation Slice

Start with Tasks 0 through 2:

1. Refresh the recursion inventory.
2. Add real layout stack-safety tests and non-crashing iterative-path hooks.
3. Add measurement work-stack scaffolding for a narrow path.

That slice creates the evidence harness before the behavior migration begins and
keeps the first implementation review focused on mechanics rather than all
layout behavior at once.
