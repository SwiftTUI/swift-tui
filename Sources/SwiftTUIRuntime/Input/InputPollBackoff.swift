/// Geometric idle backoff for cooperative input-poll loops.
///
/// On platforms with an event-driven readable source — `DispatchSource`
/// on Darwin and Linux — an input reader sleeps until the kernel reports
/// the file descriptor readable, so it burns no CPU while idle. WASI has
/// no such primitive and is single-threaded: a blocking `poll_oneoff`
/// would freeze the whole cooperative runtime (animations, timers, the
/// renderer all share the one executor). The only portable option there
/// is to poll a non-blocking descriptor and `Task.sleep` between tries.
///
/// A fixed 1 ms sleep wakes the executor ~1000 times a second even when
/// nobody is typing — pure waste, since a terminal UI spends most of its
/// life idle. This type lets the gap between polls grow geometrically,
/// from a 1 ms floor up to an 8 ms ceiling, while the descriptor keeps
/// reporting "would block". The first byte of real input resets the gap
/// to the floor, so interactive latency stays at the minimum the moment
/// a user is actually typing or dragging.
///
/// The ceiling is deliberately small — 8 ms is roughly half a 60 Hz
/// display frame — so the worst-case wait for the first keystroke after
/// an idle stretch stays imperceptible.
package struct InputPollBackoff {
  /// Shortest gap between polls, used while input is actively arriving.
  package static let floorNanoseconds: UInt64 = 1_000_000

  /// Longest gap between polls, reached after a stretch of idle polls.
  package static let ceilingNanoseconds: UInt64 = 8_000_000

  /// Nanoseconds to sleep before the next poll.
  package private(set) var delayNanoseconds: UInt64 = InputPollBackoff.floorNanoseconds

  package init() {}

  /// Doubles the delay toward the ceiling.
  ///
  /// Call once after a poll that found nothing (the descriptor reported
  /// "would block").
  package mutating func recordIdlePoll() {
    delayNanoseconds = min(delayNanoseconds * 2, Self.ceilingNanoseconds)
  }

  /// Snaps the delay back to the floor.
  ///
  /// Call after a poll that yielded real input, so the next idle stretch
  /// starts over from the most responsive interval.
  package mutating func recordInput() {
    delayNanoseconds = Self.floorNanoseconds
  }
}
