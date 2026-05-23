# ``SwiftTUITestSupport``

Poll-free synchronisation primitives for deterministic, flake-resistant tests.

## Overview

`SwiftTUITestSupport` is the shared toolkit the SwiftTUI test suites use to
*wait for things to happen* without polling a predicate on a timer. It is
exported as a library product so packages in the sibling
`SwiftTUI/swift-tui-examples` repository can synchronise their own tests on the
same primitives.

The classic test wait — set a flag, then loop on a clock until either the flag
flips or a timeout elapses — fails for a structural reason: the timeout is a
wall-clock bound, and a shared CI core can starve the producer long enough to
blow that bound even though nothing is actually wrong. The result is a flaky
test that passes on a laptop and fails under load.

The primitives here remove the clock from the waiting path. A waiter suspends
on an *event* or a *condition* and is resumed the instant a producer signals
it — never on a timer. A starved producer simply delays the waiter; it can
never *fail* it.

When a failure bound is still needed — to stop a genuinely stuck test from
hanging forever — these primitives measure it in *runtime stages* rather than
seconds (see ``StageClock``). A stage count is identical on fast and slow
hardware, so the bound is deterministic and never fails spuriously.

The package is exposed through `@_spi(Testing)`; it is test scaffolding, not
part of the public SwiftTUI surface.

## Topics

### Event Signals

- ``AsyncEvent``

### Condition Signals

- ``MainActorConditionSignal``
- ``ConditionSignal``

### Stage Budgets

- ``StageClock``
- ``ProgressBudget``
- ``withStageBudget(_:within:on:_:)``
- ``StageBudgetExceeded``
- ``ManualStageClock``
- ``ExhaustedStageClock``

### Guides

- <doc:Synchronising-Without-Polling>
