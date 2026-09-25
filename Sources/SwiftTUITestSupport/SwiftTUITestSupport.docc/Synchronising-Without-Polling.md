# Synchronizing Without Polling

Pick the right wait primitive for what a test is observing.

## Overview

Every primitive in this package answers the same question: *how does a test
wait for the runtime to reach a state?* They differ in where the observed
state lives and whether the wait carries a failure bound.

## Choosing A Primitive

- Use ``AsyncEvent`` when the test waits for a **one-shot occurrence** such as
  "the runtime started" or "the surface closed". Any number of waiters can
  observe the same firing, and a waiter that arrives *after* the firing returns
  immediately. Firing more than once is harmless.

- Use ``MainActorConditionSignal`` when the observed state lives **on the
  `MainActor`** and changes more than once. The producer calls `notify()` after
  each change it owns. Waiters evaluate their predicate only then, never on a
  clock.

- Use ``ConditionSignal`` for the same job when the observed state lives
  **behind a lock** rather than on the `MainActor`. It is the cross-isolation
  counterpart of ``MainActorConditionSignal``. Call `notify()` outside any lock
  the predicate itself acquires, so the two always lock in the same order.

All three resume on cancellation. A plain wait returning does not prove its
predicate held: check cancellation before asserting progress. During teardown,
cancel and join every task that owns a wait; an active call retains its signal.
`ConditionSignal` removes cancelled predicates under its lock and resumes
continuations after releasing it. Predicates must not re-enter that signal.
`MainActorConditionSignal` resumes a cancelled waiter on a later `MainActor`
turn, but `notify()` never evaluates that waiter's predicate after the
cancellation.

None of these three carries a timeout. That is deliberate: a starved producer
must *delay* a waiter, never *fail* it. The test synchronises on the state
change, not on the wall clock.

## Adding A Failure Bound

A test that waits forever on a real bug is as unhelpful as a flaky one. When a
wait must fail after progress stops, use a stage budget instead of a wall-clock
timeout.

A ``StageClock`` counts units of runtime progress: for the run loop, one
completed turn. ``withStageBudget(_:within:on:_:)`` races an operation against
a ``ProgressBudget`` of stages and throws ``StageBudgetExceeded`` if the budget
runs out first. The bound is a stage *count*, so it is identical on a fast
laptop and a slow CI runner. The same budget can finish in 6 s on the laptop and
30 s under load. Both runs pass.

Budgeted overloads on ``AsyncEvent``, ``MainActorConditionSignal`` and
``ConditionSignal`` let a
bounded wait read as a single call:

```swift
try await event.wait(for: "runtime start", within: budget, on: clock)
```

Name the owning test stage and expected event in the label. The budget cancels
and joins losing work. Its 30-second wall-clock backstop diagnoses a completely
idle progress clock; it is not a scheduling-speed expectation.

To do a unit test of budget logic, drive a ``ManualStageClock`` by hand. Or use
``ExhaustedStageClock`` to exercise the budget-exceeded path deterministically
without racing a real clock past its deadline.

## The Legacy Polling Helpers

The `AsyncTestSupport.swift` file still provides the older `waitUntil(...)`
family and `valueWithTimeout(...)`. These *do* poll a predicate under a
wall-clock timeout, scaled by the `SWIFTTUI_TEST_TIMEOUT_SCALE` environment
variable so slow runners get proportionally longer.

They remain only as a fallback for waits not yet migrated to the poll-free
primitives. `Scripts/check_test_sync_policies.sh` ratchets their use downward.
Prefer ``AsyncEvent`` or a condition signal for any new test.
