import SwiftTUICore
import SwiftTUIViews

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
    let routedIdentity = pointerInteraction.activeRouteID.flatMap {
      pairedInteractionRegion(for: $0)?.identity
    }
    for (identity, recognizer) in localGestureRegistry.activeRecognizers() {
      let outcome = recognizer.handleDeadlineClassified(at: instant)
      if outcome != .ignored {
        invalidatedIdentities.insert(identity)
      }
      if identity == routedIdentity {
        pointerInteraction.noteDeadlineDispatchOutcome(outcome)
      }
    }
    if !invalidatedIdentities.isEmpty {
      scheduler.requestInvalidation(of: invalidatedIdentities)
    }
  }
}
