# Synchronising Without Polling

Pick the right wait primitive for what a test is observing.

## Overview

Every primitive in this package answers the same question — *how does a test
wait for the runtime to reach a state?* — but they differ in **where the
observed state lives** and **whether the wait carries a failure bound**.

## Choosing A Primitive

- Use ``AsyncEvent`` when the test waits for a **one-shot occurrence** — "the
  runtime started", "the surface closed". Any number of waiters can observe the
  same firing, and a waiter that arrives *after* the firing returns
  immediately. Firing more than once is harmless.

- Use ``MainActorConditionSignal`` when the observed state lives **on the
  `MainActor`** and changes more than once. The producer calls `notify()` after
  each change it owns; waiters re-test their predicate only then, never on a
  clock.

- Use ``ConditionSignal`` for the same job when the observed state lives
  **behind a lock** rather than on the `MainActor`. It is the cross-isolation
  counterpart of ``MainActorConditionSignal``. Call `notify()` outside any lock
  the predicate itself acquires, so the two always lock in the same order.

None of these three carries a timeout. That is deliberate: a starved producer
must *delay* a waiter, never *fail* it. The test synchronises on the state
change, not on the wall clock.

## Adding A Failure Bound

A test that waits forever on a real bug is as unhelpful as a flaky one. When a
wait should *fail* if progress genuinely stops, bound it with a stage budget
rather than a wall-clock timeout.

A ``StageClock`` counts units of runtime progress — for the run loop, one
completed turn. ``withStageBudget(_:within:on:_:)`` races an operation against
a ``ProgressBudget`` of stages and throws ``StageBudgetExceeded`` if the budget
runs out first. Because the bound is a stage *count*, it is identical on a fast
laptop and a slow CI runner — the same budget that finishes in 6 s on the
laptop finishes in 30 s under load, and passes on both.

Budgeted overloads on ``AsyncEvent`` and ``MainActorConditionSignal`` let a
bounded wait read as a single call:

```swift
try await event.wait(for: "runtime start", within: budget, on: clock)
```

To unit-test budget logic itself, drive a ``ManualStageClock`` by hand, or use
``ExhaustedStageClock`` to exercise the budget-exceeded path deterministically
without racing a real clock past its deadline.

## The Legacy Polling Helpers

The `AsyncTestSupport.swift` file still provides the older `waitUntil(...)`
family and `valueWithTimeout(...)`. These *do* poll a predicate under a
wall-clock timeout, scaled by the `SWIFTTUI_TEST_TIMEOUT_SCALE` environment
variable so slow runners get proportionally longer.

They remain only as a fallback for waits not yet migrated to the poll-free
primitives. `Scripts/check_test_sync_policies.sh` ratchets their use downward —
prefer ``AsyncEvent`` or a condition signal for any new test.
