import SwiftTUICore

/// Filters the focus tracker's move notifications before they reach the
/// scheduler.
///
/// A tracker notification invalidates the raw old/new control identities, and
/// its sole purpose is to re-render focus presentation. For a control that
/// declared focus-presentation-inert slots (`TabView`), that recompute is
/// already covered by the retained-reuse suppression scope — whose descendant
/// matching honors the slot declarations — while the raw identity invalidation
/// would conflict-deny the whole content subtree the slots exempt, nullifying
/// the narrowing through the invalidation axis.
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
  private let declaresFocusPresentationInertSlots: @MainActor (Identity) -> Bool

  init(
    base: any Invalidating,
    declaresFocusPresentationInertSlots: @escaping @MainActor (Identity) -> Bool
  ) {
    self.base = base
    self.declaresFocusPresentationInertSlots = declaresFocusPresentationInertSlots
  }

  nonisolated func requestInvalidation(of identities: Set<Identity>) {
    // Tracker notifications are driven from the run loop's main-actor event
    // and focus-sync paths (mirrors the `Environment` read-attribution seam).
    MainActor.assumeIsolated {
      let filtered = identities.filter { identity in
        !declaresFocusPresentationInertSlots(identity)
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
