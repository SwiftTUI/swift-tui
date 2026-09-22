@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@Suite("Cross-isolation condition cancellation", .timeLimit(.minutes(1)))
struct ConditionSignalTests {
  @Test func alreadyTrue() async {
    await ConditionSignal().wait(until: { true })
  }

  @Test func cancellationBeforeRegistration() async {
    let start = AsyncEvent()
    let signal = ConditionSignal()
    let task = Task {
      await start.wait()
      await signal.wait(until: { false })
      #expect(Task.isCancelled)
    }
    task.cancel()
    await task.value
  }

  @Test func cancellationAfterRegistrationReleasesPredicate() async {
    final class Owner: Sendable {}
    weak var released: Owner?
    let signal = ConditionSignal()
    let registered = AsyncEvent()
    let task: Task<Void, Never>
    do {
      let owner = Owner()
      released = owner
      task = Task {
        await signal.wait {
          withExtendedLifetime(owner) { registered.fire() }
          return false
        }
      }
    }
    await registered.wait()
    task.cancel()
    await task.value
    #expect(released == nil)
    signal.notify()
  }

  @Test func notifyAndCancelRace() async {
    for _ in 0..<100 {
      let signal = ConditionSignal()
      let ready = Mutex(false)
      let registered = AsyncEvent()
      let task = Task {
        await signal.wait {
          registered.fire()
          return ready.withLock { $0 }
        }
        // This re-enters the signal after resumption: never resume under lock.
        signal.notify()
      }
      await registered.wait()
      await withTaskGroup(of: Void.self) { group in
        group.addTask { task.cancel() }
        group.addTask {
          ready.withLock { $0 = true }
          signal.notify()
        }
      }
      await task.value
    }
  }

  @Test func cancellationDoesNotRemoveOtherWaiters() async {
    let signal = ConditionSignal()
    let ready = Mutex(false)
    let registered = AsyncEvent()
    let cancelled = Task {
      await signal.wait {
        registered.fire()
        return false
      }
    }
    await registered.wait()
    let observers = (0..<4).map { _ in
      Task { await signal.wait { ready.withLock { $0 } } }
    }
    cancelled.cancel()
    await cancelled.value
    ready.withLock { $0 = true }
    signal.notify()
    for observer in observers { await observer.value }
  }

  @Test func exhaustedBudgetCancelsAndJoinsRegisteredWait() async {
    let signal = ConditionSignal()
    let clock = ManualStageClock()
    do {
      try await signal.wait(
        until: {
          clock.advance()
          return false
        },
        for: "test shutdown: expected final frame",
        within: ProgressBudget(stages: 1),
        on: clock
      )
      Issue.record("missing event unexpectedly completed")
    } catch let error as StageBudgetExceeded {
      #expect(error.label == "test shutdown: expected final frame")
    } catch {
      Issue.record("unexpected error: \(error)")
    }
    // The cancelled predicate must be removed, so this cannot advance again.
    signal.notify()
    #expect(await clock.currentStage() == 1)
  }
}
