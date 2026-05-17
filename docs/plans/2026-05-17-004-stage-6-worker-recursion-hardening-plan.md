---
title: "refactor: Stage 6 - harden frame-tail worker and recursion policy"
type: refactor
status: active
date: 2026-05-17
depends_on:
  - "2026-05-16-001-pipeline-driver-hardening-plan.md"
  - "2026-05-17-002-stage-0-contract-guards-plan.md"
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
an explicit policy. The immediate shipped tranche isolates the retained
large-stack worker, closes the `@safe` policy bypass, and records the WASI
synchronous fallback. The remaining tranche must either bound or remove the
layout recursion that forced the large stack before replacing the Darwin worker
with a task-only implementation.

**Architecture:** The async frame-tail path has two different queues: a normal
renderer queue and a special layout worker. The layout worker exists because
deep built-in layout can still recurse enough to need a larger-than-default
thread stack. Until that recursion is bounded or converted to explicit stacks,
removing the Darwin worker is riskier than isolating it.

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
- [x] Keep the Darwin 8 MiB pthread stack because layout recursion is not yet
  bounded.
- [x] Keep `FrameTailRenderer.swift` focused on retained tail state, async tail
  orchestration, diagnostics, and cancellation.

## Task 3 - Close The Escape-Hatch Policy Gap

- [x] Remove `@safe` from the Darwin worker implementation.
- [x] Extend `Scripts/check_concurrency_safety_policies.sh` so checked-in Swift
  sources cannot add `@safe`.
- [x] Keep existing bans on `@unchecked Sendable` and `nonisolated(unsafe)`.

## Task 4 - Record The Platform Decision

- [x] Add ADR 0020 documenting why the pthread worker remains for now.
- [x] Record the WASI behavior: the no-thread/no-Dispatch fallback is
  synchronous by design until the renderer API grows a gated async capability
  model.

## Task 5 - Remaining Recursion Work

- [ ] Convert the hot recursive layout measurement/placement walks to explicit
  work stacks, or introduce a graceful depth limit that cannot crash the
  process.
- [ ] Once recursion is bounded, re-evaluate replacing the Darwin large-stack
  worker with a structured task or custom executor implementation.
- [ ] Add regression coverage that would fail if a new deep layout path bypasses
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

- the pthread code is isolated and ADR-justified;
- `@safe`, `@unchecked Sendable`, and `nonisolated(unsafe)` are blocked by the
  local concurrency-safety policy;
- WASI's synchronous fallback is documented;
- layout recursion is either bounded or converted to explicit work stacks; and
- the focused worker/stack tests plus `bun run test` pass.
