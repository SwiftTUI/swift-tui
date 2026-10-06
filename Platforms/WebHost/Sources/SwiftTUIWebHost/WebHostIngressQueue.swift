import Synchronization

/// A single-consumer FIFO with admission limits and no hidden AsyncStream
/// buffer. Overflow is reported to the owning connection, never an eviction.
package final class WebHostIngressQueue<Element: Sendable>: Sendable {
  package static var recordLimit: Int { 256 }
  package static var byteLimit: Int { 4 * 1024 * 1024 }

  package struct Snapshot: Sendable {
    package var records = 0
    package var bytes = 0
    package var highWaterRecords = 0
    package var highWaterBytes = 0
    package var refused = 0
    package var oldestAge: Duration = .zero
    package var maximumConsumedAge: Duration = .zero
  }

  private struct Entry: Sendable {
    var value: Element
    var bytes: Int
    var admitted: ContinuousClock.Instant
  }
  private struct State {
    var entries: [Entry] = []
    var snapshot = Snapshot()
    var waiter: CheckedContinuation<Element?, Never>?
    var finished = false
  }
  private let state = Mutex(State())

  @discardableResult
  package func offer(_ element: Element, bytes: Int) -> Bool {
    let admission = state.withLock { state -> (Bool, CheckedContinuation<Element?, Never>?) in
      guard !state.finished else { return (false, nil) }
      guard bytes >= 0, bytes <= Self.byteLimit - state.snapshot.bytes,
        state.entries.count < Self.recordLimit
      else {
        state.snapshot.refused += 1
        return (false, nil)
      }
      if let waiter = state.waiter {
        state.waiter = nil
        return (true, waiter)
      } else {
        state.entries.append(Entry(value: element, bytes: bytes, admitted: .now))
        state.snapshot.bytes += bytes
        state.snapshot.highWaterBytes = max(state.snapshot.highWaterBytes, state.snapshot.bytes)
        state.snapshot.highWaterRecords = max(state.snapshot.highWaterRecords, state.entries.count)
      }
      return (true, nil)
    }
    admission.1?.resume(returning: element)
    return admission.0
  }

  package var snapshot: Snapshot {
    state.withLock { state in
      var snapshot = state.snapshot
      snapshot.records = state.entries.count
      snapshot.oldestAge = state.entries.first.map { $0.admitted.duration(to: .now) } ?? .zero
      return snapshot
    }
  }

  package func discardBuffered() {
    state.withLock { state in
      state.entries.removeAll(keepingCapacity: true)
      state.snapshot.bytes = 0
    }
  }

  package func finish() {
    let waiter = state.withLock { state in
      state.finished = true
      let waiter = state.waiter
      state.waiter = nil
      return waiter
    }
    // Cancellation invokes its handler under the task's status lock. Resuming
    // while holding our mutex would invert those locks against cancellation.
    waiter?.resume(returning: nil)
  }

  package func stream(onCancel: @escaping @Sendable () -> Void = {}) -> AsyncStream<Element> {
    AsyncStream(
      unfolding: { await self.next() },
      onCancel: {
        self.discardBuffered()
        self.finish()
        onCancel()
      })
  }

  private func next() async -> Element? {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let delivery = state.withLock { state -> (Bool, Element?) in
          guard !Task.isCancelled else {
            return (true, nil)
          }
          if !state.entries.isEmpty {
            let entry = state.entries.removeFirst()
            state.snapshot.bytes -= entry.bytes
            state.snapshot.maximumConsumedAge = max(
              state.snapshot.maximumConsumedAge,
              entry.admitted.duration(to: .now))
            return (true, entry.value)
          } else if state.finished {
            return (true, nil)
          } else {
            precondition(state.waiter == nil, "WebHost ingress has one consumer")
            state.waiter = continuation
            return (false, nil)
          }
        }
        if delivery.0 { continuation.resume(returning: delivery.1) }
      }
    } onCancel: {
      self.finish()
    }
  }
}
