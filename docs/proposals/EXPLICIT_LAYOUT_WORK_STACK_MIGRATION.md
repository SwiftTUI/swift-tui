# Explicit Layout Work-Stack Migration

## Status

Accepted direction. Detailed implementation is tracked in
[`2026-05-17-006-explicit-layout-work-stack-migration-plan.md`](../plans/2026-05-17-006-explicit-layout-work-stack-migration-plan.md),
under Stage 6 of
[`2026-05-16-001-pipeline-driver-hardening-plan.md`](../plans/2026-05-16-001-pipeline-driver-hardening-plan.md).

This proposal closes the Stage 6 design choice: the long-term destination is a
full explicit work-stack layout engine, not a permanent recursion depth cap.
Temporary depth limits may be used as diagnostics or interim crash guards while
the migration is underway, but they are not the completed architecture.

## Decision Summary

SwiftTUI will migrate built-in layout measurement and placement away from
unbounded Swift call-stack recursion and onto explicit internal work stacks.

The end state is:

- `LayoutEngine.measure` is a shallow public entry point that drives an
  iterative measurement engine.
- `LayoutEngine.place` is a shallow public entry point that drives an iterative
  placement engine.
- Built-in layout walks do not require the Darwin frame-tail layout worker's
  8 MiB stack to survive deeply nested authored trees.
- Worker-safe custom layout has an explicit boundary that cannot silently
  reintroduce unbounded built-in recursion.
- Ordinary public custom layout remains allowed to fall back to the main actor,
  but any remaining recursive escape hatch is bounded, diagnostic, and not used
  as evidence that the built-in layout engine is stack-safe.
- Once built-in layout recursion is eliminated, the Darwin large-stack worker is
  re-evaluated for replacement with a structured task or custom executor.

The migration is intentionally staged because layout is observable. The final
architecture is not optional; the staging only controls how much risk each slice
takes on.

## Context

The async frame-tail renderer currently keeps a Darwin pthread worker with an
8 MiB stack. ADR 0020 accepts that worker temporarily because current built-in
layout still recurses through measurement and placement. Moving those paths back
onto a default task stack before fixing recursion could reintroduce stack
overflow for sufficiently deep resolved trees.

Existing stack-safety tests prove that several post-layout traversals are
iterative, including resolved-node lookup, placed-node semantic and draw
extraction, raster command walking, and metadata copy behavior. They do not
prove that `LayoutEngine.measure` or `LayoutEngine.place` can handle deeply
nested real layout trees.

The known recursive seams include:

- `LayoutEngine.measure`, which dispatches to child measurement and size
  calculation.
- `measureChildren`, which calls back into `measure` for wrappers, stacks,
  decoration, `ViewThatFits`, and custom layout.
- stack measurement, which performs ideal measurement, allocated remeasurement,
  fixed-size cross-axis reconciliation, and derived minimum-size traversal.
- `LayoutEngine.place`, which dispatches to child placement.
- placement paths that measure during placement, including layout-dependent
  content and indexed lazy-stack children.
- custom layout callbacks that can call `engine.measure` or `engine.place`.

The explicit work-stack migration fixes the built-in layout hazard at its
source instead of relying on a larger stack or a permanent depth ceiling.

## Goals

- Make built-in measurement and placement stack-safe for deeply nested resolved
  trees.
- Preserve current layout semantics, retained reuse behavior, diagnostics, and
  observable frame artifacts.
- Keep the public `LayoutEngine` surface stable unless a later custom-layout
  boundary requires a deliberate SPI or public API addition.
- Make every remaining recursive layout escape hatch explicit, tested, and
  diagnostic.
- Remove the architectural reason for the Darwin large-stack frame-tail worker.
- Land the migration in reviewable slices with focused tests before broad repo
  gates.

## Non-Goals

- Parallelizing layout subtrees.
- Rewriting the resolved, measured, or placed node product types for cosmetic
  reasons.
- Changing SwiftUI-shaped layout behavior.
- Running ordinary public custom layout off the main actor by default.
- Treating a global recursion cap as the final Stage 6 outcome.
- Replacing the Darwin worker before built-in layout recursion is eliminated.

## Final Architecture

### Measurement

Measurement becomes an iterative post-order traversal.

The measurement engine owns an explicit stack of measurement frames. A frame
contains the resolved node, proposal, pass context, child-work state, and any
layout-behavior-specific continuation data required to finish the node after its
children are measured.

Conceptually:

```text
push measure(root, proposal)
while stack is not empty:
  pop frame
  if frame needs child measurements:
    push continuation(frame)
    push child measurement frames in reverse output order
  else:
    finish node and publish MeasuredNode to its parent continuation
```

The exact internal frame names can differ, but the contract is strict:
finishing a node must not require recursive `measure` calls for built-in layout.

Multi-pass layout, especially stacks, is represented by continuation states
rather than nested calls. For example, stack measurement should move through
explicit states for ideal measurement, main-axis allocation, allocated
remeasurement, cross-axis reconciliation, derived minimum sizes, and final
container-allocation snapshots.

### Placement

Placement becomes an iterative pre/post-order traversal over the resolved tree
and the measured tree.

The placement engine owns an explicit stack of placement frames. A frame
contains the resolved node, measured node, bounds, viewport context, pass
context, and child-placement state. Finishing a node emits a `PlacedNode` to its
parent continuation.

Placement-time measurement remains legal only as explicit work. Layout-dependent
content realization and indexed lazy-stack visible children can enqueue
measurement work followed by placement work, but they do not call back into a
recursive built-in `measure` or `place` walk.

### Custom Layout Boundary

Custom layout is the main boundary that cannot be solved by only rewriting the
built-in engine.

The destination is:

- framework-owned and explicitly worker-safe custom layout receives
  stack-aware child measurement and placement operations;
- ordinary public custom layout keeps the existing main-actor fallback unless it
  opts into worker-safe execution;
- recursive calls from custom layout into the public `LayoutEngine` are treated
  as an explicit boundary, not as hidden built-in recursion;
- any fallback recursion that remains after the built-in migration has a
  deterministic depth policy and emits a runtime issue when exceeded.

This lets the built-in engine become stack-safe while preserving today's
authored custom-layout semantics.

### Worker Consequence

After built-in measurement and placement are iterative, the large-stack pthread
worker no longer has a layout-recursion justification. At that point Stage 6
reopens the worker implementation and evaluates a structured task or custom
executor replacement.

If custom layout still has bounded fallback recursion, that does not justify an
8 MiB built-in layout worker. It only justifies keeping the custom-layout
boundary explicit and diagnostic.

## Migration Plan

### Step 1 - Baseline Real Layout Stack Tests

Add regression tests that exercise actual `LayoutEngine.measure` and
`LayoutEngine.place`, not only post-layout traversal helpers.

Coverage should include:

- a deeply nested single-child wrapper chain;
- a deeply nested stack chain;
- placement of the measured deep trees;
- a layout-dependent content case that realizes children during placement;
- an indexed lazy-stack case that measures visible children during placement.

The tests should fail against the old recursive implementation at a depth that
is meaningful for default task stacks, while staying bounded enough for normal
CI runtime.

### Step 2 - Introduce Work-Stack Scaffolding

Add internal measurement and placement work-stack types without changing public
behavior.

This step should establish:

- frame enums or structs for measurement and placement continuations;
- deterministic child-result accumulation in source order;
- metric updates through `LayoutPassContext`;
- retained measurement and placement cache integration points;
- test hooks that can prove the iterative path is used for selected built-in
  layouts.

The first version can route only a narrow layout subset through the new
scaffolding while all other behavior still delegates to the existing code.

### Step 3 - Convert Leaf And Wrapper Measurement

Move leaf and simple wrapper measurement onto the iterative measurement engine.

Initial candidates:

- intrinsic leaves;
- `.padding`;
- `.safeAreaIgnoring`;
- `.border`;
- `.frame`;
- `.flexibleFrame`;
- `.offset`;
- `.position`;
- one-child intrinsic containers.

This is the first high-value slice because deeply nested wrapper chains are the
most direct stack-overflow shape and are common in authored SwiftUI-style code.

### Step 4 - Convert Branching Measurement

Move branching built-in measurement paths onto explicit continuations.

Coverage should include:

- `.intrinsic` nodes with children;
- `.overlay`;
- `.decoration`;
- `.safeAreaInset`;
- `.viewThatFits`;
- fallback child measurement order when a behavior's primary child is missing.

This step should preserve child measurement order and measured-child storage
semantics exactly, because retained layout and downstream placement depend on
those shapes.

### Step 5 - Convert Stack Measurement

Move stack and lazy-stack measurement onto explicit states.

This is the most delicate measurement step. It must preserve:

- ideal child measurement;
- spacing budget calculation;
- flexible-child expansion;
- compression;
- allocated child remeasurement;
- spacer main-axis correction;
- fixed-size cross-axis reconciliation;
- no-op remeasurement pruning;
- derived minimum-main-size behavior;
- container allocation snapshots for lazy stacks.

The target is not to simplify stack layout. The target is to express the
existing algorithm as explicit state transitions instead of nested calls.

### Step 6 - Convert Placement

Move built-in placement onto the iterative placement engine.

Coverage should include:

- intrinsic children;
- overlay alignment;
- stacks and lazy stacks;
- padding, safe-area, border, frame, flexible frame, offset, position, and
  decoration wrappers;
- layout-dependent content realization;
- indexed lazy-stack visible placement and its placement-time measurement.

Placement must keep recording placed frames through `LayoutPassContext` and must
preserve retained placement reuse behavior.

### Step 7 - Define The Custom Layout Escape Hatch

Make the custom-layout boundary explicit after the built-in engine is iterative.

This step should decide the exact shape of stack-aware custom-layout child
operations. The expected direction is:

- worker-safe custom layout receives operations that enqueue child measurement
  and placement through the iterative engine;
- ordinary public custom layout keeps main-actor fallback behavior;
- recursive public `engine.measure` / `engine.place` entry points remain
  available for compatibility but are protected by a deterministic depth policy;
- depth-limit failures emit a runtime issue with a stable code and identity.

This step is allowed to preserve a bounded compatibility fallback. It is not
allowed to reclassify custom-layout recursion as built-in layout stack safety.

### Step 8 - Remove Built-In Recursive Layout Walks

Delete or quarantine old recursive built-in measurement and placement helpers.

Add a focused guard so future built-in layout paths do not bypass the iterative
engine. The guard can be a combination of tests, comments at escape hatches, and
small script checks if the call graph settles into a pattern that is practical
to enforce mechanically.

At this point, deeply nested built-in layout should be safe on ordinary task
stacks without depending on the Darwin pthread stack size.

### Step 9 - Re-Evaluate The Frame-Tail Layout Worker

Once built-in recursion is gone, replace or justify the worker again.

Preferred outcome:

- remove the custom pthread worker;
- run frame-tail layout through a structured task or custom executor;
- keep ordered commit and existing async rendering semantics;
- update ADR 0020 or add a follow-up ADR recording the replacement.

If a custom executor is chosen, it must be justified by scheduling or runtime
isolation needs, not by stack size.

### Step 10 - Documentation And Cleanup

After the migration lands:

- update `ASYNC_RENDERING.md` to remove the large-stack caveat;
- update Stage 6 and parent pipeline hardening plans to shipped status;
- update `SOURCE_LAYOUT.md` if layout-engine files move or split;
- move the completed TODO entry into `CHANGELOG.md`;
- keep this proposal as the design record for why the iterative engine exists.

## Verification Strategy

Every implementation step should run the smallest focused tests first, then the
repo gate when shared behavior changes.

Focused checks:

```bash
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
./Scripts/check_concurrency_safety_policies.sh
```

Repo gate:

```bash
bun run test
```

`bun run test:all` is appropriate after broad layout behavior changes, example
package updates, or any step that modifies maintained examples outside the
gallery gate.

## Completion Criteria

This proposal is complete when:

- built-in `LayoutEngine.measure` and `LayoutEngine.place` no longer walk
  resolved trees through unbounded Swift recursion;
- deep real-layout regression tests cover measurement and placement, not just
  post-layout traversal;
- custom layout has an explicit stack-safe or bounded boundary;
- a deeply nested built-in layout tree can render without the large-stack Darwin
  worker;
- the frame-tail worker has been replaced or re-justified without stack-size as
  the reason; and
- focused stack/worker tests plus `bun run test` pass.
