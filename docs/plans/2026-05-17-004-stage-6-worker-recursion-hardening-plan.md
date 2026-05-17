---
title: "refactor: Stage 6 - harden frame-tail worker and recursion policy"
type: refactor
status: shipped
date: 2026-05-17
depends_on:
  - "2026-05-16-001-pipeline-driver-hardening-plan.md"
  - "2026-05-17-002-stage-0-contract-guards-plan.md"
  - "../proposals/EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md"
  - "../proposals/PIPELINE_DRIVER_AUDIT.md"
  - "../proposals/OFF_MAIN_PIPELINE_RENDERING.md"
  - "../proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md"
---

# Stage 6 - Frame-Tail Worker And Recursion Hardening Plan

> **For agentic workers:** Execute this plan task-by-task with
> `superpowers:executing-plans` or the local equivalent. This is **Stage 6** of
> [`2026-05-16-001-pipeline-driver-hardening-plan.md`](./2026-05-16-001-pipeline-driver-hardening-plan.md);
> it addresses audit proposal **P4/P5** (Findings 6 and 7).

**Goal:** Bring the off-main layout worker and deep-layout recursion story under
an explicit policy. The shipped result isolates the frame-tail worker, closes the
`@safe` policy bypass, records the WASI synchronous fallback, migrates built-in
layout to explicit work stacks, and removes the Darwin pthread/large-stack
worker.

**Migration decision:** the long-term destination is the full explicit
work-stack migration in
[`EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md`](../proposals/EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md).
The detailed work plan is
[`2026-05-17-006-explicit-layout-work-stack-migration-plan.md`](./2026-05-17-006-explicit-layout-work-stack-migration-plan.md).
Depth limits remain only at the public/custom-layout compatibility boundary; the
completed Stage 6 architecture is iterative built-in measurement and placement.

**Architecture:** The async frame-tail path has two different queues: a normal
renderer queue and a serial layout worker. Built-in layout stack safety now lives
in the explicit measurement and placement work stacks, not in a larger native
thread stack.

## Task 1 - Baseline And Audit

- [x] Run the full repo gate before starting the Stage 6 tranche:

```bash
bun run test
```

- [x] Audit existing stack-safety coverage in
  `Tests/SwiftTUICoreTests/StackSafetyRegressionTests.swift`.
- [x] Confirm the current tests prove several post-layout traversals are
  iterative, but do **not** prove that all layout measurement/placement
  recursion is bounded.

## Task 2 - Isolate The Worker

- [x] Move the frame-tail layout worker out of `FrameTailRenderer.swift` into a
  dedicated private implementation file.
- [x] Initially kept the Darwin 8 MiB pthread stack before the explicit layout
  work stacks landed.
- [x] Keep `FrameTailRenderer.swift` focused on retained tail state, async tail
  orchestration, diagnostics, and cancellation.

## Task 3 - Close The Escape-Hatch Policy Gap

- [x] Remove `@safe` from the Darwin worker implementation.
- [x] Extend `Scripts/check_concurrency_safety_policies.sh` so checked-in Swift
  sources cannot add `@safe`.
- [x] Keep existing bans on `@unchecked Sendable` and `nonisolated(unsafe)`.

## Task 4 - Record The Platform Decision

- [x] Add ADR 0020 documenting the temporary pthread worker and later serial
  worker replacement.
- [x] Record the WASI behavior: the no-thread/no-Dispatch fallback is
  synchronous by design until the renderer API grows a gated async capability
  model.

## Task 5 - Remaining Recursion Work

- [x] Execute
  [`2026-05-17-006-explicit-layout-work-stack-migration-plan.md`](./2026-05-17-006-explicit-layout-work-stack-migration-plan.md),
  which implements the full explicit layout work-stack migration described in
  [`EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md`](../proposals/EXPLICIT_LAYOUT_WORK_STACK_MIGRATION.md).
- [x] Treat any graceful depth limit as an interim guard or custom-layout
  compatibility boundary, not as the final built-in layout architecture.
- [x] Once built-in recursion is eliminated, re-evaluate replacing the Darwin
  large-stack worker with a structured task or custom executor implementation.
- [x] Add regression coverage that would fail if a new deep layout path bypasses
  the bounded/iterative traversal policy.

## Verification

```bash
./Scripts/check_concurrency_safety_policies.sh
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
bun run test
```

## Exit Criteria

This Stage 6 plan is complete only when:

- the pthread code has been removed from the frame-tail layout worker;
- `@safe`, `@unchecked Sendable`, and `nonisolated(unsafe)` are blocked by the
  local concurrency-safety policy;
- WASI's synchronous fallback is documented;
- built-in layout recursion has migrated to explicit work stacks; and
- the focused worker/stack tests plus `bun run test` pass.
