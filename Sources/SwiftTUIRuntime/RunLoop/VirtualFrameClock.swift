import SwiftTUICore

/// A steppable stand-in for the run loop's frame clock.
///
/// Install the clock with `runLoop.frameClock = { [clock] in clock.now }`.
/// Then step `now` manually.
/// Deadline-driven work (animation ticks and scroll-momentum decay) advances in virtual time.
/// This work uses no sleeps or asynchronous loop.
/// Thus, latency arithmetic is exact and does not race the wall clock.
///
/// Only the *frame* clock is virtual.
/// Real-time waits continue to use the wall clock.
/// These waits include event-pump sleeps, `waitForPendingFrame`, and pointer-event timestamps.
/// They describe the real world, not the current frame.
/// See the `frameClock` documentation on `RunLoop`.
///
/// Performance scenarios do **not** use this clock.
/// They measure wall-clock cost on a quiet machine, and a virtual clock measures nothing.
@MainActor
@_spi(Runners) public final class VirtualFrameClock {
  @_spi(Runners) public var now: MonotonicInstant

  @_spi(Runners) public init(_ now: MonotonicInstant = .zero) {
    self.now = now
  }

  /// Moves the clock forward and returns the new instant.
  @discardableResult
  @_spi(Runners) public func advance(by duration: Duration) -> MonotonicInstant {
    now = now.advanced(by: duration)
    return now
  }
}
