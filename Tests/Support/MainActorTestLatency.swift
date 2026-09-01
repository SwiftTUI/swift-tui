import Foundation

/// Deliberate latency injection for tests whose *subject* is a run loop held
/// below its frame cadence.
///
/// This is not synchronisation: callers never wait *for* anything through it —
/// they burn a budgeted slice of wall time between loop turns, the way a
/// loaded host's real per-frame work does (frame-strip predicate scans over a
/// large surface, slow terminal writes). The calling test's actual waits stay
/// signal-based (`MainActorConditionSignal`, `AsyncEvent`).
///
/// It lives in `Tests/Support` because the test-sync ratchet
/// (`Scripts/check_test_sync_policies.sh`) excludes this directory as the
/// sanctioned home of shared primitives; a bare `Thread.sleep` in a test file
/// would trip the ratchet even when it injects load rather than synchronises
/// (see the ratchet's own note on latency injections).
package enum MainActorTestLatency {
  /// Burns `seconds` of wall time on the calling thread.
  package static func inject(seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
  }
}
