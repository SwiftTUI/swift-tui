---
title: "bug: gallery one-shot animations snap after async Option 3"
type: bug
status: active
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

It drives the real `AnimationsTab` through `RunLoop.run()`, clicks the actual
offset example's `right` button, and asserts that the rendered `slide me` marker
visits at least one intermediate cell column between its starting column and the
final `offset(x: 30)` column.

Observed split:

```bash
swiftly run swift test --package-path Examples/gallery --filter GalleryDemoViewsTests.AnimationRegressionTests
```

- `4e848ea`: fails. The marker columns after input are `[3, 33]`, a direct
  snap from the initial column to the final column.
- `7dfc91b3032e83ed626c597df741f8d248480cdf`: passes with the same test patch
  applied in a throwaway worktree.

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

## Current Failure Model

The leading model is that an input-triggered animation transaction can be
prepared, superseded, and aborted before its tail job starts, while the
scheduler intent that carried the animation request has already been consumed.

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

This is still a failure model, not a proven root cause. The new regression test
pins the user-visible behavior before changing the runtime again.

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

## Fix Direction

Do not treat this as a request to restart `PhaseAnimator` tasks. The failing
test demonstrates that the button action runs and the final state commits.

The likely fix must preserve or replay animation-bearing scheduled-frame intent
across pre-start tail cancellation. Candidate directions:

- Do not consume a one-shot animation request until the corresponding prepared
  frame successfully commits.
- Or, when aborting a prepared frame head before tail start, requeue the same
  invalidated identities, animation request, and batch ID so the next prepared
  frame sees the original transaction.
- Preserve transition and completion registration semantics with the same rule,
  because transitions and completion callbacks are also batch/transaction
  scoped.

Any fix needs explicit duplicate-work guards. Replaying the scheduler intent
must not replay the input event or run the button action twice. The replay unit
should be the already-recorded render invalidation plus animation transaction
metadata, not the user event.

## Verification Commands

Current failing proof:

```bash
swiftly run swift test --package-path Examples/gallery --filter GalleryDemoViewsTests.AnimationRegressionTests
```

Good-commit proof used for this note:

```bash
git worktree add /tmp/swift-terminal-ui-good-animation-test 7dfc91b3032e83ed626c597df741f8d248480cdf
git -C /tmp/swift-terminal-ui-good-animation-test apply /tmp/swift-terminal-ui-animation-regression-test.patch
swiftly run swift test --package-path Examples/gallery --filter GalleryDemoViewsTests.AnimationRegressionTests
```

Full `bun run test` is not expected to pass while this regression test is
intentionally red on head.
