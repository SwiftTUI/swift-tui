import Synchronization
import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private func awaitStressGate(_ gate: OneShotContinuationGate) async {
  await withCheckedContinuation { continuation in
    gate.install(continuation)
  }
}

private final class CancellationStressCounter: Sendable {
  private let value = Mutex(0)
  func increment() { value.withLock { $0 += 1 } }
  var count: Int { value.withLock { $0 } }
}

@Suite("SwiftTUI cancellation state-machine stress behavior", .serialized)
struct FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 001 cancel-before-start is idempotent")
  func cancellationState001CancelBeforeStartIsIdempotent() {
    // Hypothesis: a second cancellation can transition the token away from its terminal state.
    let token = FrameTailJobCancellationToken()
    #expect(token.cancelBeforeStart())
    for _ in 0..<32 {
      #expect(!token.cancelBeforeStart())
      #expect(token.currentState == .cancelledBeforeStart)
    }
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 002 repeated start preserves started state")
  func cancellationState002RepeatedStartPreservesStartedState() {
    // Hypothesis: repeated start notifications can become false after the first transition.
    let token = FrameTailJobCancellationToken()
    for _ in 0..<32 { #expect(token.markStarted()) }
    #expect(token.currentState.rawValue == "started")
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 003 completion before start is inert")
  func cancellationState003CompletionBeforeStartIsInert() {
    // Hypothesis: a premature completion can skip the queued/start arbitration entirely.
    let token = FrameTailJobCancellationToken()
    token.markCompleted()
    #expect(token.currentState.rawValue == "queued")
    #expect(token.markStarted())
    token.markCompleted()
    #expect(token.currentState.rawValue == "completed")
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 004 late cancellation cannot undo start")
  func cancellationState004LateCancellationCannotUndoStart() {
    // Hypothesis: cancelBeforeStart can win after markStarted publishes started.
    let token = FrameTailJobCancellationToken()
    #expect(token.markStarted())
    for _ in 0..<32 { #expect(!token.cancelBeforeStart()) }
    #expect(token.currentState.rawValue == "started")
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 005 start resumes every queued waiter")
  func cancellationState005StartResumesEveryQueuedWaiter() async {
    // Hypothesis: draining the waiter dictionary can omit continuations under fanout.
    let token = FrameTailJobCancellationToken()
    let states = await withTaskGroup(of: String.self, returning: [String].self) { group in
      for _ in 0..<64 {
        group.addTask { await token.waitUntilLeavesQueue().rawValue }
      }
      await Task.yield()
      #expect(token.markStarted())
      var values: [String] = []
      for await value in group { values.append(value) }
      return values
    }
    #expect(states.count == 64)
    #expect(states.allSatisfy { $0 == "started" })
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 006 cancellation resumes every queued waiter")
  func cancellationState006CancellationResumesEveryQueuedWaiter() async {
    // Hypothesis: cancellation fanout can resume only the first registered waiter.
    let token = FrameTailJobCancellationToken()
    let states = await withTaskGroup(of: String.self, returning: [String].self) { group in
      for _ in 0..<64 {
        group.addTask { await token.waitUntilLeavesQueue().rawValue }
      }
      await Task.yield()
      #expect(token.cancelBeforeStart())
      var values: [String] = []
      for await value in group { values.append(value) }
      return values
    }
    #expect(states.count == 64)
    #expect(states.allSatisfy { $0 == "cancelled_before_start" })
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 007 cancelled waiter does not consume transition")
  func cancellationState007CancelledWaiterDoesNotConsumeTransition() async {
    // Hypothesis: removing one cancelled waiter can steal another waiter's continuation.
    let token = FrameTailJobCancellationToken()
    let cancelled = Task { await token.waitUntilLeavesQueue().rawValue }
    let survivor = Task { await token.waitUntilLeavesQueue().rawValue }
    await Task.yield()
    cancelled.cancel()
    _ = await cancelled.value
    #expect(token.markStarted())
    #expect(await survivor.value == "started")
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 008 pre-cancelled wait returns promptly")
  func cancellationState008PreCancelledWaitReturnsPromptly() async {
    // Hypothesis: cancellation observed before waiter registration can still install a leak.
    let token = FrameTailJobCancellationToken()
    let task = Task {
      unsafe withUnsafeCurrentTask { task in
        unsafe task?.cancel()
      }
      return await token.waitUntilLeavesQueue().rawValue
    }
    #expect(await task.value == "queued")
    #expect(token.cancelBeforeStart())
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 009 completed token never installs waiters")
  func cancellationState009CompletedTokenNeverInstallsWaiters() async {
    // Hypothesis: the initial state check can race and suspend on an already completed token.
    let token = FrameTailJobCancellationToken()
    #expect(token.markStarted())
    token.markCompleted()
    for _ in 0..<32 {
      #expect(await token.waitUntilLeavesQueue().rawValue == "completed")
    }
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 010 start and cancel have one winner")
  func cancellationState010StartAndCancelHaveOneWinner() async {
    // Hypothesis: independent transitions can both report success under contention.
    for _ in 0..<100 {
      let token = FrameTailJobCancellationToken()
      async let started = Task.detached { token.markStarted() }.value
      async let cancelled = Task.detached { token.cancelBeforeStart() }.value
      let results = await (started, cancelled)
      #expect([results.0, results.1].filter { $0 }.count == 1)
      #expect(["started", "cancelled_before_start"].contains(token.currentState.rawValue))
    }
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 011 resume before install completes")
  func cancellationState011ResumeBeforeInstallCompletes() async {
    // Hypothesis: an early winner can be forgotten before the continuation arrives.
    for _ in 0..<100 {
      let gate = OneShotContinuationGate()
      gate.resume()
      await awaitStressGate(gate)
    }
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 012 install before resume completes")
  func cancellationState012InstallBeforeResumeCompletes() async {
    // Hypothesis: a waiting continuation can be overwritten or left suspended.
    for _ in 0..<100 {
      let gate = OneShotContinuationGate()
      let task = Task { await awaitStressGate(gate) }
      await Task.yield()
      gate.resume()
      await task.value
    }
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 013 repeated resume wakes exactly once")
  func cancellationState013RepeatedResumeWakesExactlyOnce() async {
    // Hypothesis: repeated winners can resume the same checked continuation twice.
    let gate = OneShotContinuationGate()
    let counter = CancellationStressCounter()
    let task = Task {
      await awaitStressGate(gate)
      counter.increment()
    }
    await Task.yield()
    for _ in 0..<1_000 { gate.resume() }
    await task.value
    #expect(counter.count == 1)
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 014 concurrent resume swarm has one effect")
  func cancellationState014ConcurrentResumeSwarmHasOneEffect() async {
    // Hypothesis: lock handoff can expose the stored continuation to two resumers.
    let gate = OneShotContinuationGate()
    let counter = CancellationStressCounter()
    let waiter = Task {
      await awaitStressGate(gate)
      counter.increment()
    }
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<128 { group.addTask { gate.resume() } }
    }
    await waiter.value
    #expect(counter.count == 1)
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 015 alternating install-resume races never hang")
  func cancellationState015AlternatingInstallResumeRacesNeverHang() async {
    // Hypothesis: rapid winner/installer ordering changes can strand a pending state.
    for generation in 0..<200 {
      let gate = OneShotContinuationGate()
      if generation.isMultiple(of: 2) {
        gate.resume()
        await awaitStressGate(gate)
      } else {
        let waiter = Task { await awaitStressGate(gate) }
        await Task.yield()
        gate.resume()
        await waiter.value
      }
    }
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 016 newest buffering retains exact suffix")
  func cancellationState016NewestBufferingRetainsExactSuffix() async {
    // Hypothesis: finish can flush an evicted prefix back into a newest-only buffer.
    let stream = makeManagedAsyncStream(bufferingPolicy: .bufferingNewest(2)) {
      (continuation: AsyncStream<Int>.Continuation) in
      for value in 0..<10 { continuation.yield(value) }
      continuation.finish()
      return { _ in }
    }
    var values: [Int] = []
    for await value in stream { values.append(value) }
    #expect(values == [8, 9])
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 017 oldest buffering retains exact prefix")
  func cancellationState017OldestBufferingRetainsExactPrefix() async {
    // Hypothesis: finish can replace retained oldest values with later rejected yields.
    let stream = makeManagedAsyncStream(bufferingPolicy: .bufferingOldest(3)) {
      (continuation: AsyncStream<Int>.Continuation) in
      for value in 0..<10 { continuation.yield(value) }
      continuation.finish()
      return { _ in }
    }
    var values: [Int] = []
    for await value in stream { values.append(value) }
    #expect(values == [0, 1, 2])
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 018 zero buffering finishes without phantom value")
  func cancellationState018ZeroBufferingFinishesWithoutPhantomValue() async {
    // Hypothesis: a zero-capacity stream can retain the last rejected element at finish.
    let stream = makeManagedAsyncStream(bufferingPolicy: .bufferingNewest(0)) {
      (continuation: AsyncStream<Int>.Continuation) in
      for value in 0..<20 { continuation.yield(value) }
      continuation.finish()
      return { _ in }
    }
    var values: [Int] = []
    for await value in stream { values.append(value) }
    #expect(values.isEmpty)
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 019 task-backed burst preserves order")
  func cancellationState019TaskBackedBurstPreservesOrder() async {
    // Hypothesis: producer completion can overtake its final buffered yields.
    let stream = makeTaskBackedAsyncStream {
      (continuation: AsyncStream<Int>.Continuation) in
      for value in 0..<100 { continuation.yield(value) }
      continuation.finish()
    }
    var values: [Int] = []
    for await value in stream { values.append(value) }
    #expect(values == Array(0..<100))
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 020 consumer cancellation reaches producer")
  func cancellationState020ConsumerCancellationReachesProducer() async {
    // Hypothesis: a suspended consumer can terminate without cancelling the backing task.
    let counter = CancellationStressCounter()
    let stream = makeTaskBackedAsyncStream {
      (continuation: AsyncStream<Int>.Continuation) in
      continuation.yield(1)
      while !Task.isCancelled { await Task.yield() }
      counter.increment()
    }
    let consumer = Task {
      var iterator = stream.makeAsyncIterator()
      _ = await iterator.next()
      _ = await iterator.next()
    }
    for _ in 0..<20 { await Task.yield() }
    consumer.cancel()
    _ = await consumer.result
    for _ in 0..<1_000 where counter.count == 0 { await Task.yield() }
    #expect(counter.count == 1)
  }
}

// NEXT CANCELLATION STRESS TEST
