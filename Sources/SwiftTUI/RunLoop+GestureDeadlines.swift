import Core
import View

extension RunLoop {
  /// Drains deadline-triggered gesture recognizers when the scheduler fires
  /// a `.deadline` wake cause.
  ///
  /// Each active recognizer whose deadline has arrived transitions to `.ended`
  /// (or stays terminal if already settled). Any identity that transitions
  /// triggers an invalidation so the next render reflects the updated gesture
  /// state via `.onEnded` callbacks.
  package func drainGestureDeadlines(at instant: MonotonicInstant) {
    var invalidatedIdentities: Set<Identity> = []
    for (identity, recognizer) in localGestureRegistry.activeRecognizers() {
      if recognizer.handleDeadline(at: instant) {
        invalidatedIdentities.insert(identity)
      }
    }
    if !invalidatedIdentities.isEmpty {
      scheduler.requestInvalidation(of: invalidatedIdentities)
    }
  }
}
