---
adr: "0020"
title: "Frame-tail layout worker remains isolated until layout recursion is bounded"
status: accepted
date: 2026-05-17
sources:
  - docs/plans/2026-05-16-001-pipeline-driver-hardening-plan.md
  - docs/plans/2026-05-17-004-stage-6-worker-recursion-hardening-plan.md
  - docs/proposals/PIPELINE_DRIVER_AUDIT.md
  - docs/proposals/OFF_MAIN_PIPELINE_RENDERING.md
  - docs/proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md
---

# ADR-0020: Frame-tail layout worker remains isolated until layout recursion is bounded

## Context

The async frame-tail renderer has a special Darwin layout worker backed by
`pthread_create` and an 8 MiB stack. The audit correctly flagged this as a
structured-concurrency exception and also noted that the old policy missed
`@safe`, allowing the worker to satisfy the hook while still hiding unsafe
thread calls.

The large stack is not an arbitrary implementation detail. Current stack-safety
tests cover several deep post-layout traversals, but the layout engine still has
recursive measurement and placement paths. A task-only replacement would move
those paths back onto a default worker stack before the recursion hazard is
bounded.

## Decision

Keep the Darwin large-stack layout worker for now, but isolate it in
`Sources/SwiftTUIRuntime/Rendering/FrameTailLayoutWorker.swift` and remove
`@safe` from the implementation. Unsafe pthread operations remain explicit
`unsafe` expressions inside that file.

Extend the concurrency-safety policy to ban `@safe` alongside
`@unchecked Sendable` and `nonisolated(unsafe)` so future escape hatches cannot
be introduced silently.

Accept the no-thread/no-Dispatch fallback as synchronous for WASI. The fallback
does not claim off-main execution; it exists so the same rendering API can build
for the current WASI target until the runtime has a platform capability model
for async frame-tail work.

## Consequences

The hand-rolled pthread code is still present, but it is now isolated,
ADR-justified, and covered by a policy that prevents the previous `@safe`
bypass from spreading.

The remaining Stage 6 work is explicit: bound or eliminate the recursive layout
paths, then re-evaluate a structured task or executor replacement for the
Darwin worker.
