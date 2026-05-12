import Foundation
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

    try await waitUntil("managed stream termination") {
      await probe.termination == .cancelled
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

    try await waitUntil("producer yielded the first value") {
      await probe.yieldCount == 1
    }

    consumer.cancel()
    _ = await consumer.result

    try await waitUntil("producer cancellation") {
      await probe.cancelled
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

  func record(_ termination: AsyncStream<Int>.Continuation.Termination) {
    self.termination = termination
  }
}

private actor AsyncStreamProducerProbe {
  private(set) var yieldCount = 0
  private(set) var cancelled = false

  func recordYield() {
    yieldCount += 1
  }

  func recordCancellation() {
    cancelled = true
  }
}

@MainActor
private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  pollNanoseconds: UInt64 = 10_000_000,
  condition: @escaping () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let start = clock.now

  while !(await condition()) {
    if start.duration(to: clock.now) >= .nanoseconds(Int64(timeoutNanoseconds)) {
      throw AsyncStreamTestTimeout(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private struct AsyncStreamTestTimeout: Error, CustomStringConvertible {
  let label: String

  init(_ label: String) {
    self.label = label
  }

  var description: String {
    "Timed out waiting for \(label)"
  }
}
