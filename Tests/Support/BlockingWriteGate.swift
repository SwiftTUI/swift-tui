import Dispatch
import Synchronization

/// Holds the first synchronous write inside a terminal-controller double until
/// released, so a test can park one frame in flight and deterministically
/// supersede the frames queued behind it.
///
/// The presentation writer's `write` is a *synchronous* method running on the
/// writer's own dispatch queue; to keep a frame in flight, that thread must
/// genuinely stall. A semaphore is the correct primitive for that — this is not
/// the async-bridge anti-pattern the test-sync ratchet targets, which is why
/// this helper lives in `Tests/Support`, the sanctioned (regex-excluded) home
/// of the shared synchronisation primitives. The *waiter* side is still a
/// direct signal: ``waitUntilBlocked()`` awaits an ``AsyncEvent`` fired from
/// inside the blocked write, never a poll under a timeout.
///
/// Same shape and rationale as ``AsyncFrameTailBlockingGate``, one layer down.
@_spi(Testing) public final class BlockingWriteGate: Sendable {
  private let armed: Mutex<Bool>
  /// Fired synchronously from inside the blocked write, so a waiter learns the
  /// gate is holding the instant it starts holding.
  private let enteredEvent = AsyncEvent()
  private let releaseSemaphore = DispatchSemaphore(value: 0)

  /// - Parameter arms: when `false` the gate never blocks, so the same double
  ///   can serve tests that just want writes to run straight through.
  @_spi(Testing) public init(arms: Bool = true) {
    armed = Mutex(arms)
  }

  /// Call from the synchronous write path. The first call blocks its own
  /// thread until ``release()``; every later call returns immediately.
  @_spi(Testing) public func enterBlockingSection() {
    let shouldBlock = armed.withLock { armed in
      let shouldBlock = armed
      armed = false
      return shouldBlock
    }
    guard shouldBlock else {
      return
    }
    enteredEvent.fire()
    releaseSemaphore.wait()
  }

  /// Suspends until the gate is actually holding a write.
  @_spi(Testing) public func waitUntilBlocked() async {
    await enteredEvent.wait()
  }

  @_spi(Testing) public func release() {
    releaseSemaphore.signal()
  }
}
