---
adr: "0021"
title: "Unified sync/async frame driver body"
type: decision
status: accepted
date: 2026-05-17
sources:
  - docs/proposals/PIPELINE_DRIVER_FOLLOWUP_AUDIT.md
  - docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
---

# ADR-0021: Unified sync/async frame driver body

## Context

`Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift` carried two
near-identical per-frame drivers:

- `renderPendingFrames(renderedFrames:)` — synchronous, `throws`. Used by
  ~85 test call sites; its non-`async` signature must be preserved because
  Swift cannot call an `async` function from a synchronous context.
- `renderPendingFramesAsync(renderedFrames:eventPump:)` — `async throws`.
  Used by production `RunLoop.swift` and by tests.

Audit finding **F2** flagged these as a copy-paste fork: the focus-sync
convergence loop, pointer-capture release, lifecycle carry-forward,
focus/scroll sync, `presentCommittedFrame`, animation-deadline rescheduling,
and the ~90-field `FrameDiagnosticRecord` construction were duplicated
verbatim across two ~350-line bodies. Any fix to one body silently skipped
the other.

A structural `diff` of the two function bodies was produced (extracting
lines 95–448 vs 689–1165 of `RunLoop+Rendering.swift`). The diff reported
exactly the difference regions inventoried below — there were **no**
unexplained per-line divergences inside the post-acquisition body. The two
bodies differed only in: the function signature, the `frameLoop:` label, the
artifact-acquisition block, two `FrameDiagnosticRecord` fields fed by
acquisition-strategy state (`tailJobState`, `completedFrameDropDecision`),
and an async-only post-frame cooperative yield on pending events.

### Difference inventory

Every region the `diff` reported, classified as `structural` (belongs in the
shared body), `strategy-specific` (belongs in the artifact-acquisition
strategy), or `bug` (a real defect):

| # | Difference (diff region) | Classification | Disposition |
|---|--------------------------|----------------|-------------|
| 1 | Function signature: `renderPendingFrames(renderedFrames:) throws` vs `renderPendingFramesAsync(renderedFrames:eventPump:) async throws -> RunLoopExitReason?` | strategy-specific | Both entry points kept verbatim; each is a thin delegator. The sync entry point's non-`async` `throws` signature is preserved (~85 test call sites depend on it). |
| 2 | `frameLoop:` label on the `while let scheduledFrame` loop | strategy-specific | The label exists only to support `continue frameLoop` from the async cancelled/dropped branches. Each entry point keeps its own `while consumeReadyFrame` loop; the async loop keeps its label. The loop body delegates to the shared method. |
| 3 | Extra locals `tailJobState` / `completedFrameDropDecision` | strategy-specific | These describe how the async path acquired the frame. Modeled as payload of the shared `FrameAcquisitionOutcome.rendered` case; the sync path supplies `.completed` / `nil`. |
| 4 | `shouldCancelQueuedTail` / `shouldCancelQueuedTailForMode` nested funcs | strategy-specific | Pure cancellation policy for `renderAsyncCancellable`; lives inside the async acquisition closure. |
| 5 | Artifact acquisition: sync calls `renderer.render(...)`; async branches on `renderMode` between `renderer.render`, `renderer.renderAsync`, `renderer.renderAsyncCancellable` | strategy-specific | This IS the strategy boundary. The shared body never renders; it consumes a `FrameAcquisitionOutcome`. Sync delegator acquires synchronously; async delegator acquires (awaiting) inside the focus-sync loop. |
| 6 | Async-only `cancelledBeforeStart` branch: report issues, carry lifecycle forward, `cancelledRenderCount += 1`, replay intent, `logCancelledFrameTail`, `continue frameLoop` | strategy-specific | Cancellation is only reachable via `renderAsyncCancellable`. Handled in the async delegator, which `continue`s its loop without invoking the shared body. The sync path can never produce this outcome. |
| 7 | Async-only `droppedCompleted` branch: report issues, carry lifecycle forward, `logDroppedCompletedFrame`, `continue frameLoop` | strategy-specific | Same as #6 — only `renderAsyncCancellable` drops completed frames. Handled in the async delegator. |
| 8 | `FrameDiagnosticRecord.tailJobState`: sync hardcodes `FrameTailJobState.completed.rawValue`; async uses `tailJobState.rawValue` | structural | The shared body emits `outcome.tailJobState.rawValue`. The sync delegator passes `.completed`, which is exactly the value the old sync code hardcoded — behavior is byte-identical. |
| 9 | `FrameDiagnosticRecord.dropDecision` / `dropReconciliationMode` / `dropReconciliationEffects`: sync hardcodes `commitOrdered` / `"-"` / `"-"`; async derives from `completedFrameDropDecision` | structural | The shared body derives from the passed `CompletedFrameDropDecision?`. The sync delegator passes `nil`, and `nil` yields exactly `commitOrdered` / `"-"` / `"-"` via the same `?? ` fallbacks — behavior is byte-identical. |
| 10 | Async-only post-frame cooperative yield: `if eventPump?.hasPendingEvents() == true { break }` | strategy-specific | Cooperative-yield policy for interactive event pumping; the sync path has no `eventPump`. Kept in the async delegator's loop, after the shared body returns. |
| 11 | Async function `return nil` at end | strategy-specific | The async entry point returns `RunLoopExitReason?`; the convenience `renderPendingFramesAsync(renderedFrames:)` overload discards it. Kept in the async delegator. |

No diff region was left unclassified. **No region was classified as a
`bug`**: every divergence is either the function boundary itself or a
deliberate strategy difference, and differences #8 and #9 are structural
fields whose previous sync hardcoded constants are reproduced exactly by
passing the corresponding empty/`nil` strategy state.

## Decision

There is exactly **one** private `@MainActor` per-frame processing body,
`applyAcquiredFrame(...)`, holding every line classified `structural`: the
focus-sync convergence loop's *post-render* convergence handling, pointer
capture release, lifecycle carry-forward merge, focus/scroll/focused-value
sync, `presentCommittedFrame`, preference-observation reconciliation,
animation-deadline rescheduling, observation pruning, and the full
`FrameDiagnosticRecord` construction.

The strategy boundary is modeled by a private enum:

```swift
private enum FrameAcquisitionOutcome {
  case rendered(FrameArtifacts, FrameTailJobState, CompletedFrameDropDecision?)
  case skipped
}
```

The focus-sync convergence loop must re-render to converge, and rendering is
the one operation that differs between sync and async. The loop is therefore
parameterized over an **acquisition closure** that returns a
`FrameAcquisitionOutcome` — the sync delegator passes a non-`async` closure
calling `renderer.render`; the async delegator passes an `async` closure
branching on `renderMode`. Because Swift cannot await from a synchronous
context, the shared focus-sync loop and post-acquisition body are factored as
a non-`async` method, and the **async** path runs its own copy of the
focus-sync loop (the only place a suspension point is needed) while
delegating the entire post-acquisition body to the same shared
`applyAcquiredFrame`. Approach (a) from the task brief is adopted: the
post-acquisition body is the non-`async` `applyAcquiredFrame`; only artifact
*acquisition* differs between entry points.

Concretely:

- `applyAcquiredFrame(...)` — private `@MainActor`, non-`async`. Takes the
  converged `FrameArtifacts`, the per-frame focus/scroll change flags, the
  `FrameTailJobState`, the `CompletedFrameDropDecision?`, and the
  `ScheduledFrame` / diagnostics context. Contains every `structural` line.
- `renderPendingFrames(renderedFrames:)` — keeps its exact
  `throws` (non-`async`) signature. Loops over ready frames; runs the
  focus-sync convergence loop with a synchronous `renderer.render`
  acquisition; calls `applyAcquiredFrame` with `tailJobState: .completed`,
  `completedFrameDropDecision: nil`.
- `renderPendingFramesAsync(renderedFrames:eventPump:)` — keeps its
  `async throws -> RunLoopExitReason?` signature. Loops over ready frames
  (with the `frameLoop:` label); runs the focus-sync convergence loop with
  an `async` acquisition branching on `renderMode`; routes
  `cancelledBeforeStart` / `droppedCompleted` outcomes through its own
  `continue frameLoop` (the `.skipped` shape); calls the same
  `applyAcquiredFrame` with the strategy-derived `tailJobState` and
  `completedFrameDropDecision`; performs the cooperative event-pump yield.

Both entry points become thin delegators (each well under 60 lines). The
~90-field diagnostics record, the focus-sync convergence handling, and every
post-render side effect now live in exactly one place.

## Consequences

- A bug fix or behavior change to per-frame processing is made once and
  applies to both drivers — F2 is structurally closed, not just documented.
- The sync entry point's signature is unchanged; the ~85 synchronous test
  call sites compile and behave identically.
- The async entry point's signature, `frameLoop` label, cancellation/drop
  handling, and cooperative yield are unchanged.
- `PipelineDriverParityTests` gains a frame-driver parity test that drives
  one frame through each entry point over equivalent `RunLoop`s and asserts
  the committed frame count and `latestSemanticSnapshot` match. This pins the
  two delegators to identical observable behavior.
- The focus-sync convergence loop body is necessarily expressed twice (once
  per entry point) because one copy must `await` and one must not — Swift has
  no `reasync`. This is the single irreducible duplication; it is a ~25-line
  loop wrapper, not the ~350-line processing body, and the processing body it
  wraps (`applyAcquiredFrame`) is fully shared. The acquisition closure +
  `FrameAcquisitionOutcome` enum keep even that wrapper's divergence confined
  to the `await` keyword and the cancelled/dropped routing.
