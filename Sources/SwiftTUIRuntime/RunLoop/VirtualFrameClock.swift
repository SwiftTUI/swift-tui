import SwiftTUICore

/// A steppable stand-in for the run loop's frame clock.
///
/// Install with `runLoop.frameClock = { [clock] in clock.now }` and step `now`
/// by hand: deadline-driven work (animation ticks, scroll-momentum decay) then
/// advances in virtual time with no sleeps and no async loop, and latency
/// arithmetic becomes exact instead of racing the wall clock.
///
/// Only the *frame* clock is virtualized. Real-time waiting — the event pump's
/// sleeps, `waitForPendingFrame`, and pointer-event stamping — deliberately
/// keeps the wall clock, because those are about the real world rather than
/// about the frame in hand; see the `frameClock` documentation on `RunLoop`.
///
/// Perf scenarios deliberately do **not** use this: they measure wall-clock
/// cost on a quiet machine, and a virtual clock would measure nothing.
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
