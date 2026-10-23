import Dispatch

/// Proves progress on another executor while a synchronous test callback holds
/// its own thread. Use `AsyncEvent` when the waiter may suspend instead.
/// The timeout bounds a broken executor dependency; it never delays success.
package final class BlockingTestSignal: Sendable {
  private let semaphore = DispatchSemaphore(value: 0)

  package init() {}

  package func signal() {
    semaphore.signal()
  }

  package func wait(timeoutNanoseconds: UInt64 = 5_000_000_000) -> Bool {
    let timeout = Int(clamping: AsyncTestTimeouts.scaledNanoseconds(timeoutNanoseconds))
    return semaphore.wait(timeout: .now() + .nanoseconds(timeout)) == .success
  }
}
