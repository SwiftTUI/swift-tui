---
title: "bug: gallery one-shot animations snap after async Option 3"
type: fix
status: shipped
date: 2026-05-01
depends_on:
  - "2026-05-01-006-async-frame-head-draft-transaction-plan.md"
  - "../ASYNC_RENDERING.md"
  - "../proposals/ANIMATION_PLAN.md"
---

# Gallery Animation Regression Notes

## Summary

The gallery animation regression is real and is not explained by
`PhaseAnimator` simply failing to start.

The identified-good commit is:

```text
7dfc91b3032e83ed626c597df741f8d248480cdf
```

The failing head under investigation is:

```text
4e848eaeca547787c11e84e7866ade0ff43415ba
```

The automated regression guard added with these notes is:

```text
Examples/gallery/Tests/GalleryDemoViewsTests/AnimationRegressionTests.swift
```

It drives the real `AnimationsTab` through `RunLoop.run()` and covers the
regression two ways:

- `animationsTabOffsetButtonRendersIntermediateFramesWhilePhaseAnimatorIsVisible`
  clicks the actual offset example's `right` button and asserts that the
  rendered `slide me` marker visits at least one intermediate cell column
  between its starting column and the final `offset(x: 30)` column.
- `diagnosticsExposeAnimationIntentAndCancellationStateOnGalleryPath` enables
  `FrameDiagnosticsLogger` on the same interaction and asserts that the real
  gallery path records explicit animation commits and cancellation diagnostics.
  When that path does cancel an animation-bearing frame, it also asserts that a
  later committed frame carries animation intent.
- `AsyncFrameTailRenderingTests/cancelledAnimationIntentIsReplayedIntoReplacementFrameDiagnostics`
  deterministically forces a pre-start cancellation of an animation-bearing
  frame and asserts that the replacement committed frame still carries explicit
  animation intent.
- `AnimationSchedulerTests` covers the scheduler-level replay rules: replay
  merges invalidated identities and transaction metadata, does not replay
  input-only frames, and does not replace a newer explicit animation.

Observed split:

```bash
swiftly run swift test --package-path Examples/gallery --filter GalleryDemoViewsTests.AnimationRegressionTests
```

- `4e848ea`: fails. The marker columns after input are `[3, 33]`, a direct
  snap from the initial column to the final column.
- `4e848ea`: the diagnostic test also fails. It observes
  `tail_job_state=cancelled_before_start`,
  `tail_cancel_reason=newer_render_intent`, and
  `scheduled_animation_request=animate` / `scheduled_animation_batch=-` on the
  cancelled click frame, followed by committed deadline frames with
  `scheduled_animation_request=inherit`.
- `7dfc91b3032e83ed626c597df741f8d248480cdf`: the visual test passes with the
  same visual-test patch applied in a throwaway worktree. The diagnostic test
  uses instrumentation added after this commit, so it is a head-side regression
  localization guard rather than a direct old-commit comparison.

Fixed-head verification:

- The gallery visual guard now passes and captures intermediate marker columns.
- The deterministic async-tail diagnostic guard observes the cancelled
  animation-bearing frame followed by a committed replacement frame with
  `scheduled_animation_request=animate` and active controller animations.

## User-Visible Symptoms

Starting the gallery directly on the animations tab can allow the continuously
running `PhaseAnimator` section to keep advancing. That is useful evidence:
the animation deadline loop is not globally dead.

However, other animations on the same tab still regress:

- `withAnimation` examples, such as the offset example, commit the final state
  without visible interpolation.
- Transition examples are consistent with the same failure class: insertion and
  removal commit without the transition overlay being driven through the active
  transaction.
- Completion examples are also suspect because completion registration is tied
  to the animation batch that must survive through frame commit.

The important distinction is continuous deadline-driven animation versus
one-shot, input-triggered animation transactions. The former can continue once
it already has active animation state. The latter depends on preserving the
transaction attached to the input-caused state write until the frame that
commits the state change.

## Confirmed Root Cause

An input-triggered animation transaction could be prepared, superseded, and
aborted before its tail job started, while the scheduler intent that carried the
animation request had already been consumed.

The relevant runtime path is:

1. A button action enters `withAnimation`.
2. View-owned `@State` mutates while `AnimationContextStorage.currentRequest`
   and the batch ID are active.
3. The state slot invalidates through `AnimationAwareInvalidating`, which
   records the animation request on `FrameScheduler`.
4. `RunLoop.run()` consumes a `ScheduledFrame` carrying that animation request
   and prepares the frame head.
5. Under Option 3, the queued frame tail can be cancelled before worker layout
   starts if a newer render intent arrives.
6. `abortPreparedFrameHead` restores graph, resolve, animation, lifecycle,
   task, and retained-tail checkpoints.
7. The newer render then commits the final authored state, but no longer has
   the consumed one-shot animation request, so the rendered result snaps.

This model accounts for the user's refinement: a visible `PhaseAnimator` can
keep ticking while the one-shot transition and `withAnimation` examples fail.
The ticking phase animator creates deadline pressure and can keep its own
active animation state alive, but it does not prove that a separate
input-scoped transaction survived to commit.

The fix replays the cancelled frame's render-invalidation intent back into the
pending scheduler work before the run loop advances to the replacement frame.
The replay unit is the recorded invalidated identities plus animation request
and batch ID; it does not replay input causes, signal causes, external wakes, or
the user action that produced the state change.

## Why Existing Coverage Missed It

Existing coverage includes useful pieces, but not this composed failure:

- Direct renderer tests can prove interpolation when an animation request is
  passed explicitly, but they do not exercise `RunLoop.run()` consumption,
  frame-head preparation, queued-tail cancellation, and ordered commit.
- Runtime tests that count frames prove that something continues to present,
  not that a specific input-triggered `withAnimation` commits intermediate
  surfaces.
- A minimal synthetic `ScrollView` plus `PhaseAnimator` plus `Button` fixture
  still animates on head, so the regression requires the real gallery tab's
  composed view shape and scheduling pressure.
- Existing gallery tests focus on tab switching, state ownership, and
  continuous animation frame production. They did not click a gallery
  animation control and inspect intermediate render positions.

## Regression Test Shape

The new test is intentionally in the gallery package rather than the root test
target. It imports `GalleryDemoViews`, renders `AnimationsTab`, and uses the
same `RunLoop` path the example uses at runtime.

Test flow:

1. Render `AnimationsTab` once with `DefaultRenderer` to find the cell center
   of the real `right` button.
2. Start `RunLoop.run()` with a recording terminal host.
3. Wait until the `slide me` marker has appeared.
4. Send mouse down/up to the button.
5. Wait for the final `offset(x: 30)` column.
6. Assert that at least one rendered frame after the input has a marker column
   strictly between the starting and final columns.

On the bad head the final frame is present, but the intermediate frame is not.
That is the signature of transaction loss rather than a missed click or a
broken button action.

The companion gallery diagnostic test records TSV diagnostics for the same
interaction. It uses the animation-focused fields added to
`FrameDiagnosticsLogger`:

- `scheduled_animation_request`: `inherit`, `disabled`, or `animate` from the
  consumed `ScheduledFrame`.
- `scheduled_animation_batch`: the opaque batch ID value when present, or `-`.
- `animation_controller_active_animations`: controller active-animation count
  at diagnostic emission time.
- `animation_controller_pending_work`: whether the controller still has pending
  animation work at diagnostic emission time.

The deterministic root runtime diagnostic forces the bad-head signature: an
`animate` scheduled frame cancelled before tail start, followed by a replacement
frame. The shipped fix requires that replacement frame to commit with
`scheduled_animation_request=animate` and active controller animations.

## Fix

`FrameScheduler` now implements `CancelledFrameIntentReplaying`. On pre-start
tail cancellation, `RunLoop.renderPendingFramesAsync` asks the scheduler to
merge the cancelled frame's invalidated identities, animation request, and batch
ID back into pending render work.

Coalescing rules:

- Replayed cancelled frames synthesize only `.invalidation` work.
- Input, signal, external, and deadline causes are not replayed.
- A cancelled explicit animation is restored only if no newer explicit
  animation is already pending.
- A cancelled batch ID is restored only if no newer batch ID is already pending.
- Input-only cancelled frames are ignored.

## Verification Commands

Targeted verification:

```bash
swiftly run swift test --filter CoreTests.AnimationSchedulerTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/cancelledAnimationIntentIsReplayedIntoReplacementFrameDiagnostics
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/diagnosticsCountInputQueuedDuringAsyncRenderSuspension
swiftly run swift test --package-path Examples/gallery --filter GalleryDemoViewsTests.AnimationRegressionTests
```

Good-commit proof used for this note:

```bash
git worktree add /tmp/swift-tui-good-animation-test 7dfc91b3032e83ed626c597df741f8d248480cdf
git -C /tmp/swift-tui-good-animation-test apply /tmp/swift-tui-animation-regression-test.patch
swiftly run swift test --package-path Examples/gallery --filter GalleryDemoViewsTests.AnimationRegressionTests
```
