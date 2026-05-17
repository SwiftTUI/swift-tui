---
adr: "0020"
title: "Frame-tail layout worker after explicit layout stacks"
status: accepted
date: 2026-05-17
sources:
  - docs/plans/2026-05-16-001-pipeline-driver-hardening-plan.md
  - docs/plans/2026-05-17-004-stage-6-worker-recursion-hardening-plan.md
  - docs/plans/2026-05-17-006-explicit-layout-work-stack-migration-plan.md
  - docs/proposals/PIPELINE_DRIVER_AUDIT.md
  - docs/proposals/OFF_MAIN_PIPELINE_RENDERING.md
  - docs/proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md
---

# ADR-0020: Frame-tail layout worker after explicit layout stacks

## Context

The async frame-tail renderer originally kept a Darwin layout worker backed by
`pthread_create` and an 8 MiB stack. The audit flagged that as a
structured-concurrency exception. The first Stage 6 tranche accepted the worker
temporarily because built-in measurement and placement still had recursive child
traversal paths.

The explicit layout work-stack migration removed that stack-size reason:
built-in measurement and placement now run through explicit work stacks, and the
remaining custom-layout callback boundary is bounded and diagnostic. The worker
still provides useful serial isolation for frame-tail layout work, but it no
longer needs a manually sized native thread stack.

## Decision

Use a lazy serial `DispatchQueue` worker in
`Sources/SwiftTUIRuntime/Rendering/FrameTailLayoutWorker.swift` on platforms
with Dispatch. Do not use `pthread_create`, `pthread_join`, or manual stack-size
configuration for frame-tail layout.

Keep the concurrency-safety policy ban on `@safe`, `@unchecked Sendable`, and
`nonisolated(unsafe)` escape hatches so this worker cannot regain hidden unsafe
threading.

Accept the no-thread/no-Dispatch fallback as synchronous for WASI. The fallback
does not claim off-main execution; it exists so the same rendering API can build
for the current WASI target until the runtime has a platform capability model
for async frame-tail work.

## Consequences

The hand-rolled pthread code has been removed from the frame-tail layout
worker. The async renderer keeps ordered tail-job semantics through the serial
worker, and stack-safety now depends on the explicit layout work stacks plus the
bounded custom-layout compatibility boundary rather than on a larger native
thread stack.

The remaining limitation is not built-in layout recursion. Ordinary public
custom layouts can still call back into `LayoutEngine`; those calls are bounded
by the compatibility-depth policy and surface runtime issues when the limit is
exceeded.
