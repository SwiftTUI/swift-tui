import Dispatch
import Synchronization

/// Blocks the frame-tail worker at a chosen raster entry until released, so a
/// test can hold a queued tail in its pre-start window (or hold a completed
/// raster mid-flight) deterministically.
@_spi(Testing) public final class AsyncFrameTailBlockingGate: Sendable {
  private struct State: Sendable {
    var rasterEntryCount = 0
  }

  private let blockingEntry: Int
  private let state = Mutex(State())
  /// Fired (synchronously, from the blocking raster path) once the gate has
  /// entered its blocked state, so `waitUntilBlocked` can await it directly
  /// instead of parking a global-queue thread on a semaphore.
  private let enteredEvent = AsyncEvent()
  // A genuine *synchronous* thread block: `beforeRaster` is a sync method on
  // the raster path and must stall its own thread until `release()`. A
  // semaphore is the correct primitive — this is not the async-bridge
  // anti-pattern the test-sync ratchet targets, which is why this helper
  // lives in Tests/Support, the sanctioned (regex-excluded) home of the
  // shared synchronisation primitives.
  private let releaseSemaphore = DispatchSemaphore(value: 0)

  @_spi(Testing) public init(blockingEntry: Int = 1) {
    self.blockingEntry = blockingEntry
  }

  @_spi(Testing) public var rasterEntryCount: Int {
    state.withLock(\.rasterEntryCount)
  }

  @_spi(Testing) public func beforeRaster() {
    let shouldBlock = state.withLock { state in
      state.rasterEntryCount += 1
      return state.rasterEntryCount == blockingEntry
    }
    guard shouldBlock else {
      return
    }

    enteredEvent.fire()
    releaseSemaphore.wait()
  }

  @_spi(Testing) public func waitUntilBlocked() async {
    await enteredEvent.wait()
  }

  @_spi(Testing) public func release() {
    releaseSemaphore.signal()
  }
}
