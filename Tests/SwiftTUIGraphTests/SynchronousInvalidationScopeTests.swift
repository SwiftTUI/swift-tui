import Foundation
import Synchronization
import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Synchronous invalidation attribution")
struct SynchronousInvalidationScopeTests {
  @Test(
    "synchronous invalidations are attributed without changing scheduler intent",
    arguments: [false, true])
  func synchronousInvalidationsAreAttributed(animated: Bool) throws {
    let scheduler = FrameScheduler()
    let identity = testIdentity("Scope", "Synchronous")

    let tracked = SynchronousInvalidationScope.track(scheduler: scheduler) {
      requestInvalidation(scheduler: scheduler, identity: identity, animated: animated)
      return 42
    }

    #expect(tracked.value == 42)
    #expect(tracked.didRequestInvalidation)
    let frame = try #require(scheduler.consumeReadyFrame())
    #expect(frame.invalidatedIdentities == [identity])
    #expect(frame.intentRequestCount == 1)
    #expect(frame.hasExplicitAnimationTransactions == animated)
  }

  @Test("requests to another scheduler are not attributed", arguments: [false, true])
  func anotherSchedulerIsExcluded(animated: Bool) throws {
    let scheduler = FrameScheduler()
    let otherScheduler = FrameScheduler()
    let identity = testIdentity("Scope", "OtherScheduler")

    let tracked = SynchronousInvalidationScope.track(scheduler: scheduler) {
      requestInvalidation(scheduler: otherScheduler, identity: identity, animated: animated)
    }

    #expect(!tracked.didRequestInvalidation)
    #expect(scheduler.consumeReadyFrame() == nil)
    let otherFrame = try #require(otherScheduler.consumeReadyFrame())
    #expect(otherFrame.invalidatedIdentities == [identity])
  }

  @Test("an existing off-main producer remains unattributed while the scope is open")
  func existingOffMainProducerIsExcluded() async throws {
    let scheduler = FrameScheduler()
    let identity = testIdentity("Scope", "IndependentProducer")
    let started = ScopeTestConditionGate()
    let mayRequest = ScopeTestConditionGate()
    let completed = ScopeTestConditionGate()
    // Construct the independent task before entering the scope. Its request
    // must finish inside the synchronous operation, not merely race its edges.
    let producer = Task.detached {
      started.open()
      guard mayRequest.waitUntilOpen() else { return false }
      scheduler.requestInvalidation(of: [identity])
      completed.open()
      return true
    }
    defer { mayRequest.open() }
    #expect(started.waitUntilOpen(), "The independent producer did not start")

    let tracked = SynchronousInvalidationScope.track(scheduler: scheduler) {
      mayRequest.open()
      return completed.waitUntilOpen()
    }

    #expect(tracked.value, "The producer did not finish while the scope was open")
    #expect(!tracked.didRequestInvalidation)
    #expect(await producer.value)
    let frame = try #require(scheduler.consumeReadyFrame())
    #expect(frame.invalidatedIdentities == [identity])
  }

  @Test("an inherited main-actor task runs after the scope and does not contaminate later scopes")
  func inheritedMainActorTaskIsExcluded() async throws {
    let scheduler = FrameScheduler()
    let identity = testIdentity("Scope", "InheritedTask")

    let tracked = SynchronousInvalidationScope.track(scheduler: scheduler) {
      Task { @MainActor in
        scheduler.requestInvalidation(of: [identity])
      }
    }
    #expect(!tracked.didRequestInvalidation)
    #expect(scheduler.consumeReadyFrame() == nil)

    await tracked.value.value

    let frame = try #require(scheduler.consumeReadyFrame())
    #expect(frame.invalidatedIdentities == [identity])
    let laterScope = SynchronousInvalidationScope.track(scheduler: scheduler) {}
    #expect(!laterScope.didRequestInvalidation)
  }

  @Test("throwing restores the ambient scope and does not retain inherited task attribution")
  func throwingScopeDoesNotLeak() async throws {
    let scheduler = FrameScheduler()
    let identity = testIdentity("Scope", "AfterThrow")
    var inheritedTask: Task<Void, Never>?

    do {
      let _: (value: Void, didRequestInvalidation: Bool) =
        try SynchronousInvalidationScope.track(scheduler: scheduler) {
          inheritedTask = Task { @MainActor in
            scheduler.requestInvalidation(of: [identity])
          }
          throw ScopeTestFailure.expected
        }
      Issue.record("The synchronous operation should throw")
    } catch {
      #expect(error as? ScopeTestFailure == .expected)
    }

    #expect(scheduler.consumeReadyFrame() == nil)
    let task = try #require(inheritedTask)
    await task.value
    let frame = try #require(scheduler.consumeReadyFrame())
    #expect(frame.invalidatedIdentities == [identity])
    let laterScope = SynchronousInvalidationScope.track(scheduler: scheduler) {}
    #expect(!laterScope.didRequestInvalidation)
  }

  @Test("nested scopes attribute requests to the innermost scope")
  func nestedScopeOwnsItsRequests() {
    let scheduler = FrameScheduler()
    let identity = testIdentity("Scope", "Nested")

    let outer = SynchronousInvalidationScope.track(scheduler: scheduler) {
      SynchronousInvalidationScope.track(scheduler: scheduler) {
        scheduler.requestInvalidation(of: [identity])
      }
    }

    #expect(outer.value.didRequestInvalidation)
    #expect(!outer.didRequestInvalidation)
  }

  @Test("returning from a nested scope restores the outer scope")
  func nestedScopeRestoresOuterScope() {
    let scheduler = FrameScheduler()
    let identity = testIdentity("Scope", "Outer")

    let outer = SynchronousInvalidationScope.track(scheduler: scheduler) {
      let inner = SynchronousInvalidationScope.track(scheduler: scheduler) {}
      scheduler.requestInvalidation(of: [identity])
      return inner.didRequestInvalidation
    }

    #expect(!outer.value)
    #expect(outer.didRequestInvalidation)
  }

  private func requestInvalidation(
    scheduler: FrameScheduler,
    identity: Identity,
    animated: Bool
  ) {
    if animated {
      scheduler.requestInvalidation(
        of: [identity],
        animation: .disabled,
        batchID: nil,
        isContinuous: false,
        customValues: [:],
        tracksVelocity: false
      )
    } else {
      scheduler.requestInvalidation(of: [identity])
    }
  }
}

private enum ScopeTestFailure: Error, Equatable {
  case expected
}

/// A real synchronous barrier is necessary because `track` cannot suspend.
/// The condition determines progress; the deadline only bounds a broken test.
private final class ScopeTestConditionGate: Sendable {
  private let condition = NSCondition()
  private let isOpen = Mutex(false)

  func open() {
    condition.lock()
    isOpen.withLock { $0 = true }
    condition.broadcast()
    condition.unlock()
  }

  func waitUntilOpen() -> Bool {
    let deadline = Date().addingTimeInterval(30)
    condition.lock()
    defer { condition.unlock() }
    while !isOpen.withLock({ $0 }) {
      guard condition.wait(until: deadline) else {
        return isOpen.withLock { $0 }
      }
    }
    return true
  }
}
