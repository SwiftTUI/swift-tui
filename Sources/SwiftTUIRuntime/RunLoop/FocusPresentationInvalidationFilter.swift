import SwiftTUICore

/// Filters the focus tracker's move notifications before they reach the
/// scheduler.
///
/// A tracker notification invalidates the raw old/new control identities, and
/// its sole purpose is to re-render focus presentation. Two classes of
/// identity drop out (`scopeCoversMoveInvalidation`): a control that declared
/// focus-presentation-inert slots (`TabView` — its recompute rides the
/// retained-reuse suppression scope, whose descendant matching honors the
/// slot declarations, while the raw invalidation would conflict-deny the
/// exempted content), and an identity with no runtime-focus reader on its
/// root path (a chrome-only member — nothing that resolves on that path can
/// vary with the move, so the invalidation would deny a cone that needs no
/// recompute at all).
///
/// Filtering at the source is what keeps this sound: every other invalidation
/// path keeps its own requests, so a same-identity data write (e.g. a
/// selection `@State` hosted on the control's own node) still recomputes the
/// content. An emptied request still schedules the frame — the scheduler
/// records the invalidation cause and wakes regardless of the identity set —
/// and the frame's focus/press scope legs re-derive the recompute cone from
/// the tracker state itself.
@MainActor
final class FocusPresentationInvalidationFilter: Invalidating {
  private let base: any Invalidating
  private let scopeCoversMoveInvalidation: @MainActor (Identity) -> Bool

  init(
    base: any Invalidating,
    scopeCoversMoveInvalidation: @escaping @MainActor (Identity) -> Bool
  ) {
    self.base = base
    self.scopeCoversMoveInvalidation = scopeCoversMoveInvalidation
  }

  nonisolated func requestInvalidation(of identities: Set<Identity>) {
    // Tracker notifications are driven from the run loop's main-actor event
    // and focus-sync paths (mirrors the `Environment` read-attribution seam).
    MainActor.assumeIsolated {
      let filtered = identities.filter { identity in
        !scopeCoversMoveInvalidation(identity)
      }
      if ReuseDenialTrace.isEnabled, filtered.count != identities.count {
        ReuseDenialTrace.recordSuppressionScopeDescription(
          "focus-inval-filtered(\(identities.count - filtered.count))"
        )
      }
      base.requestInvalidation(of: filtered)
    }
  }
}
