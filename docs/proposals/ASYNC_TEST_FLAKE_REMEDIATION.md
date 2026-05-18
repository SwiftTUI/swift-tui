# Async/Runtime Test Flake Remediation

## Status

Proposal, opened 2026-05-17.

This proposal responds to the load-sensitive test failures that interrupted
[`../plans/2026-05-17-009-pipeline-driver-followup-remediation-plan.md`](../plans/2026-05-17-009-pipeline-driver-followup-remediation-plan.md).
The medium-term goal is to make the async runtime deterministically awaitable.
The immediate goal is narrower: stabilize the remaining pipeline-driver work
without turning that work into a full runtime-scheduler rewrite.

The current resolution ledger shows the pipeline-driver work has already closed
F1, F2, F11, and F12 in code. The remaining remediation is therefore the
F3-F10/F13/F14 tranche, with F5 cancellation and F4 checkpoint/commit
correctness especially likely to exercise async runtime tests.

## Evidence Boundary

This proposal was opened from code/test-suite analysis, the follow-up plan's
known-flake registry, and one focused isolation rerun of the registered toast
test. The initial remediation tranche has now added a retained repeated-run
harness and one repeated under-load pass at current HEAD. Broader load campaigns
are still useful before assigning narrower root causes or expanding the
known-flake list.

Use these terms precisely:

- **Confirmed in this pass:** tests in the registry and nearby suites depend on
  real async tasks, event streams, deadlines, hosted sessions, process sessions,
  or wall-clock waits. The initial harness run recorded 2/2 passes for every
  current registry candidate under light CPU pressure.
- **Not confirmed in this pass:** the current flake frequency under heavier or
  longer load, the exact failing set under CI load, or whether every registered
  timeout is caused by the async renderer.
- **Fair current category:** "load-sensitive runtime/integration tests with
  async dependencies." Calling the whole set "async renderer flake" would
  overstate the evidence.

## Current Registry And Focused Reruns

Each registry candidate has a focused rerun command and a remediation owner.
The owner labels below name the responsible code area rather than an individual.

| Candidate | Category | Focused rerun command | Owner | Remediation path |
| --- | --- | --- | --- | --- |
| `InteractiveRuntimeTests.toastAutoDismissRerendersWithoutAdditionalInput` | Async/runtime-adjacent | `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/toastAutoDismissRerendersWithoutAdditionalInput` | runtime test support | Shared scaled waits; later runtime progress probe. |
| `AsyncFrameTailRenderingTests` | Async renderer/runtime | `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests` | runtime test support | Shared scaled waits; later runtime progress probe for exact commit/cancel milestones. |
| `HostedSurfaceRegressionTests` | Runtime/host integration with async dependencies | `swiftly run swift test --filter SwiftUIHostTests.HostedSurfaceRegressionTests` | host test support | Shared scaled waits and serialized suite; later continuation-backed hosted-frame waiters. |
| `SwiftUIHostAccessibilityTests` | Runtime/host integration with async dependencies | `swiftly run swift test --filter SwiftUIHostTests.SwiftUIHostAccessibilityTests` | host test support | Shared scaled waits with snapshot diagnostics and serialized suite; later continuation-backed hosted-frame waiters. |
| `RenderDiffTests` | Process/presentation integration and wall-clock sensitivity | `swiftly run swift test --filter SwiftTUITerminalTests.RenderDiffTests` | terminal embedding test support | Replace wall-clock presentation assertion with deterministic commit/write-shape assertions. |

## Initial Measurement Run

Retained run:

```bash
Scripts/repeat_async_flake_registry.sh --iterations 2 --load-workers 2 --allow-failures
```

Result artifacts:

- Summary: `/tmp/swift-tui-async-flake-registry-20260517-174856-49878/summary.tsv`
- Per-candidate logs: `/tmp/swift-tui-async-flake-registry-20260517-174856-49878/`

| Candidate | Pass | Fail | Skip | Total |
| --- | ---: | ---: | ---: | ---: |
| `AsyncFrameTailRenderingTests` | 2 | 0 | 0 | 2 |
| `HostedSurfaceRegressionTests` | 2 | 0 | 0 | 2 |
| `InteractiveRuntimeTests.toastAutoDismissRerendersWithoutAdditionalInput` | 2 | 0 | 0 | 2 |
| `RenderDiffTests` | 2 | 0 | 0 | 2 |
| `SwiftUIHostAccessibilityTests` | 2 | 0 | 0 | 2 |

This run is evidence that the current candidates pass repeated focused reruns
under light pressure after the initial test-support cleanup. It is not evidence
that the classes are impossible to flake under heavier CI contention.

## Problem Summary

The suspected flaky failures cluster around tests that drive a real `RunLoop`,
hosted session, process session, animation, toast, input stream, or presentation
surface, then wait for progress by polling observable side effects such as
rendered text, frame counts, semantic snapshots, or wall-clock durations.

The follow-up remediation plan's known-flake registry correctly protects the
pipeline branch from false red gates, but it is only a gate policy. It does not
measure or reduce the underlying flake rate. The codebase needs a second track:
first measure the current failures under load, then make runtime progress
awaitable enough that tests can wait for the actual event they care about
instead of guessing that a side effect will appear within a fixed time budget.

## Evidence From The Current Test Suite

- `InteractiveRuntimeTests.toastAutoDismissRerendersWithoutAdditionalInput`
  waits up to ten seconds for `terminal.frames` to contain a second frame whose
  text no longer includes the toast. The toast itself dismisses from a `.task`
  after `Task.sleep`. This is fairly categorized as async/runtime-adjacent.
- `HostedSurfaceRegressionTests` starts `HostedSceneSession` in a background
  task, sends input, and polls a `SurfaceRecorder` with a two-second timeout and
  five-millisecond sleeps. The animation case additionally requires observing a
  set of intermediate marker columns. This is runtime/host integration flake,
  not purely renderer flake.
- `SwiftUIHostAccessibilityTests` calls `SwiftUIHostSceneHost.start()` as a
  fire-and-forget action, then polls `latestSurface`,
  `latestSemanticSnapshot`, and `focusedAccessibilityIdentity`. This is
  host-session startup and host-frame delivery flake until proven narrower.
- `RenderDiffTests.latencyInjectedPresentationStaysResponsive` uses a real
  `TerminalProcessSession`, injects `Thread.sleep(0.050)` in `present`, and
  asserts a maximum wall-clock presentation duration below `0.100`. Under
  parallel CPU load, that assertion measures scheduler delay as well as the
  intended presentation behavior. This should not be categorized as async
  renderer flake without a narrower repro.
- Input tests already show the pressure point: one staggered-pointer test uses
  `usleep(50)` because `Task.sleep()` was too coarse and turned the test into a
  scheduler test. `InjectedTerminalInputReader` also schedules coalesced mouse
  flushes with a `Task.sleep` timer.
- The runtime itself has only coarse await points for tests: `RunLoop.run()`
  returns when the session exits, while `renderPendingFramesAsync` and the event
  pump operate internally. Tests infer intermediate progress from presentation
  surfaces rather than awaiting runtime milestones.

One focused local run of the registered toast test passed in isolation with:

```bash
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/toastAutoDismissRerendersWithoutAdditionalInput
```

That is consistent with the plan's registry: the failure mode is load-sensitive,
not a stable product regression.

## Current Categorization

| Test family | Fair current category | Why |
| --- | --- | --- |
| Toast auto-dismiss | Async/runtime-adjacent | Depends on `.task`, `Task.sleep`, invalidation, render scheduling, and a subsequent committed frame. |
| `AsyncFrameTailRenderingTests` stress cases | Async renderer/runtime | These intentionally exercise frame-tail suspension, queued input, cancellation/drop policy, and ordered commit. |
| `HostedSurfaceRegressionTests` | Runtime/host integration with async dependencies | Uses hosted sessions and host-frame delivery; a timeout could be startup, input routing, render scheduling, or presentation. |
| `SwiftUIHostAccessibilityTests` | Runtime/host integration with async dependencies | Polls host snapshots after fire-and-forget startup; not enough evidence to assign failures specifically to the async renderer. |
| `RenderDiffTests` timeout/latency cases | Process/presentation integration and wall-clock sensitivity | Uses subprocess output and artificial presentation delay; should be remediated, but not counted as async renderer flake without load data. |

The measurement work should report pass/fail rates by this categorization rather
than collapsing all timeouts into one "async" bucket.

## Root Cause Patterns

### 1. Progress Is Observed Indirectly

Most flaky async tests do not await "frame N committed", "input event drained",
"host frame delivered", or "scheduler idle". They poll secondary evidence such
as frame arrays or host snapshots. That is tolerable for a smoke test, but it
breaks down when the test is meant to guard a subtle runtime ordering contract.

### 2. Wall-Clock Time Is A Hidden Dependency

The suite has many fixed waits: two-second hosted-surface waits, ten-second
toast waits, five-hundred-millisecond follow-up-click waits, one-millisecond
input flush timers, and performance assertions based on `Date()` deltas. Under
load, these waits fail because the runtime made no progress fast enough, not
because the product behavior is wrong.

### 3. Runtime Tasks Are Not All Owned By A Test Clock Or A Drain Handle

Toast dismissal, spinner ticks, input coalescing, animation deadlines, event-pump
deadline wakes, hosted-session tasks, and process output all run through
different task/timer paths. There is no common "all runtime work relevant to this
frame has either completed or scheduled the next deadline" handle.

### 4. Host Tests Mix Startup, Input, Rendering, And Presentation

Hosted-surface and SwiftUI-host tests usually verify one product claim, but the
test path includes session startup, first render, input delivery, render
scheduling, semantic host-frame delivery, and presentation recording. A timeout
does not localize which boundary failed to advance.

### 5. Integration Tests Assert Performance With Wall Time

The render-diff latency test is valuable, but a hard `maxPresentationDuration <
0.100` assertion on a parallel runner is inherently load-sensitive. The repo's
own performance policy prefers deterministic work-shape assertions over broad
wall-clock checks; this test should follow that policy.

## Classification Of Fixes

### Easy Or Largely Easy

These should be done immediately, before continuing deep pipeline work.

| Fix | Why It Is Easy | Value |
| --- | --- | --- |
| Add a repeat-under-load flake runner for the current registry. | Script-only; no runtime behavior change. | Separates measured current flakes from inherited reports and produces pass/fail counts before deeper remediation. |
| Centralize async wait helpers in one test-support file. | Mostly test-only; replaces many local `waitUntil` / `valueWithTimeout` copies. | Standard timeout scaling, better timeout diagnostics, and less accidental 500 ms / 2 s variation. |
| Add `SWIFTTUI_TEST_TIMEOUT_SCALE` support to shared waits. | Test-support-only; no runtime behavior change. | Lets loaded local/CI runs lengthen waits without weakening assertions. |
| Require every known-flake registry entry to name the focused rerun command and an owner/remediation path. | Documentation/test-runner policy only. | Prevents the registry from becoming a permanent excuse list. |
| Convert negative waits to positive gates. | Narrow test edits. For example, instead of "no click frame within 500 ms", wait for a specific scroll commit before sending the click. | Reduces tests that fail because the machine was slow, not because state was wrong. |
| Replace the render-diff wall-clock assertion with deterministic write-shape assertions or move it to the performance pipeline. | Narrow test edit; the test already records presentation metrics and byte counts. | Removes a known load-sensitive timeout class from the pipeline gate. |
| Add `.serialized` to the small known-flaky host/integration suites while their deterministic hooks are being built. | Metadata-only or near-metadata-only. | Reduces parallel load amplification without pretending it is a permanent fix. |

These fixes are not enough to eliminate async flake. They are still worth doing
because they lower gate noise quickly and make the remaining failures easier to
triage.

### Hard, But Useful Ahead Of The Remaining Pipeline Work

These are harder because they introduce new test/runtime observability seams.
They should still happen before or early in the remaining pipeline-driver
tranche because that tranche needs reliable proof around cancellation,
commit/drop, focus convergence, and hosted presentation.

| Fix | Shape | Why It Should Happen Before The Pipeline Work Continues |
| --- | --- | --- |
| Add a `RunLoopProgressProbe` testing SPI. | A lightweight observer installed on `RunLoop` that records frame intent, acquisition result, commit number, render generation, event-drain count, and scheduler-idle transitions. Tests can `await probe.frameCommitted(where:)` and `await probe.idle()`. | The next pipeline findings touch side-effect staging, double commit, cancellation, dirty tracking, diagnostics, and frame drops. Those tests need to await exact runtime milestones instead of polling terminal text. |
| Add hosted-session frame await helpers. | `HostedSceneSession` / `HostedRasterSurface` testing SPI such as `startAndWaitForFirstFrame`, `waitForSemanticFrame(where:)`, and `waitForSurface(where:)` backed by continuations instead of polling arrays. | The registered host flakes are directly in hosted-session tests. This is contained enough to do now and will help prove pipeline changes through real host paths. |
| Make input coalescing flushable in tests. | Keep production timing, but expose a testing hook on `InjectedTerminalInputReader` / `InputReader` to flush pending coalescible mouse events synchronously. | Many pipeline and runtime tests queue pointer/input events while rendering is suspended. A flush hook removes timer noise without redesigning the public input model. |
| Make F5 event-driven cancellation an early remaining pipeline task. | Replace the cancellable tail's polling loop with a continuation/signalled state transition, as the plan already requires. | This is both a product finding and a flake reducer. It removes a fixed sleep from the hot cancellation path before later tests rely on cancellation timing. |
| Promote the load-repro script into a retained evidence artifact. | Preserve logs and counts under a predictable `/tmp` or CI artifact path, and summarize results in the proposal before changing runtime behavior. | The current registry relies on ad hoc evidence. The pipeline branch needs quick proof that a failing gate is a known load flake versus a real regression. |

The justification for doing these before the remaining pipeline work is that
they do not try to redesign the runtime. They add observability and targeted
control at the boundaries the pipeline tests already exercise. Without them,
F3-F10/F13 work will keep paying for ambiguous red gates.

### Hard, Better After The Pipeline Work

These are important, but they should wait until the pipeline-driver shape stops
moving.

| Fix | Why It Is Hard | Why It Should Wait |
| --- | --- | --- |
| Build a full deterministic runtime clock. | It would need to own `Task.sleep`-like behavior for toast, spinner, input coalescing, animation deadlines, gesture deadlines, event-pump wakeups, and possibly process/session pumps. | The remaining pipeline work will still change frame acquisition, cancellation, commit/drop, and diagnostics boundaries. A full clock now would be designed against moving seams and likely need rework. |
| Make all runtime child tasks structured under a drainable runtime task group. | Requires changing lifecycle task ownership, presentation tasks, event-pump tasks, hosted sessions, and possibly user-authored `.task` behavior. | Valuable for total determinism, but it changes production task semantics. The pipeline-driver fixes should first settle what a frame owns and when side effects commit. |
| Replace process/PTY integration tests with a deterministic subprocess simulator as the default gate path. | Requires a fake terminal-process transport that still proves render-diff behavior honestly. | Useful for long-term reliability, but the current pipeline work is mostly `RunLoop`/renderer/host-frame correctness. Process/PTY determinism can follow once core runtime determinism is in place. |
| Globally serialize async/runtime test targets. | Easy mechanically, but hard as a policy because it hides contention rather than eliminating it and can make the gate much slower. | Use temporary suite-level serialization for known flakes now. Revisit broader scheduling only after deterministic await hooks show which tests still need isolation. |
| Replace wall-clock performance tests with a complete diagnostics-backed performance gate. | Requires agreeing on stable metrics, thresholds, fixture ownership, and how this relates to `PERFORMANCE_EVALUATION.md`. | Do the narrow render-diff cleanup now. A comprehensive performance-gate migration belongs after pipeline instrumentation has stabilized. |

The distinction is risk and churn. "Hard but useful ahead" items add test
observability around current seams. "Hard, better after" items redefine runtime
scheduling or broad integration strategy; doing them before the pipeline-driver
work risks building determinism around code that the remediation plan is about
to change.

## Recommended Immediate Tranche

1. Keep the existing phase-gate flake policy for the pipeline branch, but add
   focused rerun commands and remediation owners to each known-flake entry.
2. Run the known registry and nearby runtime/host candidates repeatedly under
   optional CPU pressure, then update this proposal with pass/fail counts and
   the fair category for each failure.
3. Land shared async test-support helpers:
   - one `waitUntil` / `valueWithTimeout` implementation,
   - timeout scaling through `SWIFTTUI_TEST_TIMEOUT_SCALE`,
   - timeout errors that include last observed frame/snapshot/diagnostics.
4. Convert the known registered flakes to use either the shared helper or an
   explicit continuation-backed await point:
   - toast auto-dismiss,
   - `HostedSurfaceRegressionTests`,
   - `SwiftUIHostAccessibilityTests`,
   - `RenderDiffTests` timeout cases.
5. Add `RunLoopProgressProbe` and a hosted-session frame waiter before writing
   more cancellation/drop/commit tests.
6. Resume the pipeline-driver plan with F5 cancellation early, then continue
   through F4/F3/F6/F7/F8/F9/F10/F13/F14 using the probe-backed tests.

Progress:

- Completed: focused rerun commands and remediation owners are recorded above.
- Completed: `Scripts/repeat_async_flake_registry.sh` records repeated registry
  runs under optional CPU pressure with retained logs and pass/fail counts.
- Completed: shared async wait helpers provide timeout diagnostics and
  `SWIFTTUI_TEST_TIMEOUT_SCALE` support for the converted runtime, host, and
  render-diff tests.
- Completed: the registered toast, async frame-tail, host regression,
  SwiftUI-host accessibility, and render-diff candidates use either the shared
  helper or deterministic write-shape assertions.
- Completed: `RunLoopProgressProbe` provides frame-intent, acquisition,
  skipped-frame, committed-frame, event-drain, and scheduler-idle milestones;
  the toast auto-dismiss regression now waits for committed runtime progress.
- Completed: `HostedRasterSurface` retains recent semantic host frames and
  exposes continuation-backed `waitForFrame`, `waitForSurface`, and
  `waitForFrames` testing SPI; host regression tests now await those frame
  deliveries instead of polling a recorder.
- Completed: `InjectedTerminalInputReader` and `HostedSceneSession` expose
  package/SPI test hooks to flush pending coalesced mouse events without
  waiting for the production timer.
- Completed: F5 queued-tail cancellation no longer busy-polls with a
  one-millisecond main-actor sleep. The cancellable tail now waits on the
  token's queue-exit continuation and a scheduler-backed pending-frame awaiter.
- Completed: F4 checkpoint totality now has source-level guards requiring every
  mutable `ViewGraph` and `ViewNode` field to be checkpoint-covered, a live
  checkpoint-restore identity test, and an async preview-vs-real commit-plan
  equivalence test.
- Remaining: add the planned parallel-pressure mode to the registry harness,
  then resume the F3/F6/F7/F8/F9/F10/F13/F14 pipeline-driver findings with
  probe-backed tests.

## Acceptance Criteria

- `bun run test` still remains the completion gate for shared runtime changes.
- The proposal records at least one repeated under-load run over the registry
  candidates before assigning causes or expanding the known-flake list.
- A known load flake may be waived only when the focused rerun passes and the
  test is in the registry with a remediation owner.
- New async runtime tests must wait on an observable runtime or host event, not
  on a guessed sleep.
- Tests that intentionally use wall-clock timing must explain why a deterministic
  work-shape assertion is insufficient.
- The final pipeline-driver remediation must not leave the known-flake registry
  larger than it was at the start of this proposal.
