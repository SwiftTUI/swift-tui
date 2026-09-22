# ``SwiftTUITestSupport``

Poll-free synchronization primitives for deterministic, flake-resistant tests.

## Overview

`SwiftTUITestSupport` is the shared toolkit the SwiftTUI test suites use to
*wait for things to happen* without polling a predicate on a timer. It is
exported as a library product so packages in the sibling
`SwiftTUI/swift-tui-examples` repository can synchronize their own tests on the
same primitives.

The classic test wait sets a flag and polls it until success or a timeout. This
method has a structural error. The timeout uses wall-clock time. A shared CI
core can starve the producer until the timeout occurs. The product can remain
correct while the test fails. Thus, the test passes on a laptop but fails under
load.

The primitives here remove the clock from the waiting path. A waiter suspends
on an *event* or a *condition*. A producer signal resumes it, not a timer. A
starved producer delays the waiter but cannot fail it.

Use a failure bound to stop a test that cannot make progress. These primitives
measure the bound in *runtime stages*, not seconds. See ``StageClock``. A stage
count is identical on fast and slow hardware. Thus, the bound is deterministic.

Real-terminal journeys are the exception: a PTY is an operating-system
resource outside the runtime stage model.
``waitForANSIVisibleScreen(on:screen:deadline:condition:)`` therefore combines
readable events with an explicit wall-clock deadline and a bounded drain
budget. It never uses fixed sleeps.

The package is exposed through `@_spi(Testing)`. It is test scaffolding, not
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

### Real Terminal Journeys

- ``RealTerminalPTYPair``
- ``RealTerminalPTYReadableSource``
- ``ANSIVisibleScreen``
- ``waitForANSIVisibleScreen(on:screen:deadline:condition:)``
- ``writeAllBytes(_:to:)``

### Guides

- <doc:Synchronising-Without-Polling>
