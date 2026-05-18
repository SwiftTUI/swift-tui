import Foundation
import SwiftTUITestSupport
import Testing

@testable import SwiftTUIRuntime

@Suite("AsyncStream teardown")
struct AsyncStreamTeardownTests {
  @Test("managed async stream forwards cancellation termination to cleanup")
  func managedAsyncStreamForwardsCancellationTermination() async throws {
    let probe = AsyncStreamTerminationProbe()
    let stream = makeManagedAsyncStream { (continuation: AsyncStream<Int>.Continuation) in
      continuation.yield(1)
      return { reason in
        Task {
          await probe.record(reason)
        }
      }
    }

    let consumer = Task {
      var iterator = stream.makeAsyncIterator()
      _ = await iterator.next()
      _ = await iterator.next()
    }

    consumer.cancel()
    _ = await consumer.result

    try await valueWithTimeout("managed stream termination", timeoutNanoseconds: 15_000_000_000) {
      await probe.waitForTermination()
    }
  }

  @Test("task-backed async stream cancels its producer task when the consumer terminates")
  func taskBackedAsyncStreamCancelsProducerTask() async throws {
    let probe = AsyncStreamProducerProbe()
    let stream = makeTaskBackedAsyncStream { (continuation: AsyncStream<Int>.Continuation) in
      continuation.yield(1)
      await probe.recordYield()
      while !Task.isCancelled {
        await Task.yield()
      }
      await probe.recordCancellation()
    }

    let consumer = Task {
      var iterator = stream.makeAsyncIterator()
      _ = await iterator.next()
      _ = await iterator.next()
    }

    try await valueWithTimeout(
      "producer yielded the first value", timeoutNanoseconds: 15_000_000_000
    ) {
      await probe.waitForYield()
    }

    consumer.cancel()
    _ = await consumer.result

    try await valueWithTimeout("producer cancellation", timeoutNanoseconds: 15_000_000_000) {
      await probe.waitForCancellation()
    }
  }

  @Test("task-backed async stream preserves normal finish semantics")
  func taskBackedAsyncStreamPreservesNormalFinish() async {
    let stream = makeTaskBackedAsyncStream { (continuation: AsyncStream<Int>.Continuation) in
      continuation.yield(1)
      continuation.finish()
    }

    var iterator = stream.makeAsyncIterator()
    let first = await iterator.next()
    let second = await iterator.next()

    #expect(first == 1)
    #expect(second == nil)
  }
}

private actor AsyncStreamTerminationProbe {
  private(set) var termination: AsyncStream<Int>.Continuation.Termination?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func record(_ termination: AsyncStream<Int>.Continuation.Termination) {
    self.termination = termination
    resumeWaiters()
  }

  func waitForTermination() async {
    guard termination == nil else {
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  private func resumeWaiters() {
    let pendingWaiters = waiters
    waiters.removeAll()
    for waiter in pendingWaiters {
      waiter.resume()
    }
  }
}

private actor AsyncStreamProducerProbe {
  private(set) var yieldCount = 0
  private(set) var cancelled = false
  private var yieldWaiters: [CheckedContinuation<Void, Never>] = []
  private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

  func recordYield() {
    yieldCount += 1
    resumeYieldWaiters()
  }

  func recordCancellation() {
    cancelled = true
    resumeCancellationWaiters()
  }

  func waitForYield() async {
    guard yieldCount == 0 else {
      return
    }
    await withCheckedContinuation { continuation in
      yieldWaiters.append(continuation)
    }
  }

  func waitForCancellation() async {
    guard !cancelled else {
      return
    }
    await withCheckedContinuation { continuation in
      cancellationWaiters.append(continuation)
    }
  }

  private func resumeYieldWaiters() {
    let pendingWaiters = yieldWaiters
    yieldWaiters.removeAll()
    for waiter in pendingWaiters {
      waiter.resume()
    }
  }

  private func resumeCancellationWaiters() {
    let pendingWaiters = cancellationWaiters
    cancellationWaiters.removeAll()
    for waiter in pendingWaiters {
      waiter.resume()
    }
  }
}
