import Synchronization

/// Serializes a polling read with suspension of its input ownership.
/// A successful suspension acquires the same lock as the synchronous read,
/// so it acknowledges completion of any read already in flight. No lock is
/// held while the handoff's asynchronous operation runs.
package final class TerminalInputPollGate: Sendable {
  private let suspensionDepth = Mutex<Int>(0)

  package init() {}

  package func read<T>(_ body: () -> T) -> T? {
    suspensionDepth.withLock { depth in
      guard depth == 0 else { return nil }
      return body()
    }
  }

  package func suspend() {
    suspensionDepth.withLock { $0 += 1 }
  }

  package func resume() {
    suspensionDepth.withLock {
      precondition($0 > 0)
      $0 -= 1
    }
  }
}
