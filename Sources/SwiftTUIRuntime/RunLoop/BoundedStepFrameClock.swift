import SwiftTUICore

/// A frame clock that follows the wall clock but never advances more than
/// `maximumStep` per successful frame acquisition.
///
/// Install `now` as `runLoop.frameClock` and `recordAcquisition` as
/// `runLoop.frameClockDidAcquire`. Reads alone never consume another step.
///
/// Since STUI-618 every frame animates to the clock reading it was consumed
/// at, so a starved test runner that takes a second per frame legitimately
/// skips every intermediate pose of a short animation — the behavior the
/// production run loop wants under overload, and the wrong thing for a test
/// that asserts a cross-fade dimmed or a digit rolled through `8`. This clock
/// keeps such tests deterministic without weakening their assertions: on a
/// machine that keeps cadence it *is* the wall clock, and on a starved one it
/// degrades to one bounded animation step per rendered frame, which is
/// exactly the pacing the old deadline rule guaranteed. The bounded step is
/// also monotonic by construction.
///
/// Readiness probes that read the real clock (`run()`'s `hasPendingFrame(at:)`
/// and wake computation) see deadlines armed in this lagging domain as due,
/// so a lagging loop renders back to back until it catches up rather than
/// sleeping; the frame drivers consume at this clock, so each of those
/// frames still advances by at most one step.
@MainActor
@_spi(Runners) public final class BoundedStepFrameClock {
  private let maximumStep: Duration
  private var last: MonotonicInstant?
  private let wallClock: () -> MonotonicInstant

  /// - Parameter maximumStep: the most an acquisition may advance past the
  ///   previous one. Defaults to the 33 ms animation cadence.
  @_spi(Runners) public init(maximumStep: Duration = .milliseconds(33)) {
    self.maximumStep = maximumStep
    wallClock = { .now() }
  }

  package init(maximumStep: Duration, wallClock: @escaping () -> MonotonicInstant) {
    self.maximumStep = maximumStep
    self.wallClock = wallClock
  }

  package func recordAcquisition(_ instant: MonotonicInstant) {
    last = last.map { max($0, instant) } ?? instant
  }

  /// The next reading: the wall clock, clamped to `previous + maximumStep`.
  @_spi(Runners) public func now() -> MonotonicInstant {
    let wall = wallClock()
    guard let last else {
      self.last = wall
      return wall
    }
    let bounded = last.advanced(by: maximumStep)
    let reading = wall < bounded ? wall : bounded
    let monotonic = reading < last ? last : reading
    return monotonic
  }
}
