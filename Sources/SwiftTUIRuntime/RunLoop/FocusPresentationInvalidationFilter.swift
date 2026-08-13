import SwiftTUICore

/// Frame-time translation of focus-tracker move notifications
/// (plan 2026-08-12-001 Stage 2), gated by `SWIFTTUI_FOCUS_MOVE_NARROWING`.
///
/// When enabled, ``FocusPresentationInvalidationFilter`` defers a move's
/// endpoint identities instead of enqueuing them: the run loop re-derives each
/// resolve pass's focus contribution from the pending endpoints against the
/// *current* reader registries (``RunLoop/focusNarrowedInvalidationIdentities(for:)``).
/// An endpoint that departed between the notification and the pass — the
/// palette's close-button leaf, click-focused an instant before its overlay
/// tore down — then contributes nothing, where the event-time enqueue carried
/// its unmappable identity into the dismissal frame and the reuse door's
/// conservative remap conflict-denied the entire background (the measured
/// palette-close cone).
@MainActor
package enum FocusMoveInvalidationNarrowing {
  /// Latched from the environment once; settable for tests.
  package static var isEnabled: Bool =
    FeatureGate.focusMoveInvalidationNarrowing.initialIsEnabled()
}

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
///
/// Under ``FocusMoveInvalidationNarrowing`` the event-time classification is
/// deferred wholesale: the raw endpoints are recorded on
/// ``pendingMoveEndpointsSinceLastCommit`` and the request is forwarded
/// emptied (scheduling the frame, contributing no identities). Provenance
/// stays exact — the scheduler's identity sets then hold only non-focus
/// sources, so the frame-time re-validation can never drop a state write's
/// cone.
@MainActor
final class FocusPresentationInvalidationFilter: Invalidating {
  private let base: any Invalidating
  private let scopeCoversMoveInvalidation: @MainActor (Identity) -> Bool

  /// Raw focus-move endpoints notified since the last *committed* frame
  /// (narrowing mode only). Not consumed per pass: a superseded async frame
  /// replays its intent, and the replay must re-derive the same contribution.
  /// Cleared by the run loop at the committed-frame boundary, beside
  /// `previousFrameFocusIdentity`.
  private(set) var pendingMoveEndpointsSinceLastCommit: Set<Identity> = []

  init(
    base: any Invalidating,
    scopeCoversMoveInvalidation: @escaping @MainActor (Identity) -> Bool
  ) {
    self.base = base
    self.scopeCoversMoveInvalidation = scopeCoversMoveInvalidation
  }

  func clearPendingMoveEndpoints() {
    pendingMoveEndpointsSinceLastCommit.removeAll(keepingCapacity: true)
  }

  /// Records focus/press move endpoints deferred by a run-loop site that
  /// invalidates outside the tracker-notification path (the pressed-identity
  /// twin in `setPressedIdentity`).
  func recordDeferredMoveEndpoints(_ identities: Set<Identity>) {
    pendingMoveEndpointsSinceLastCommit.formUnion(identities)
    if ReuseDenialTrace.isEnabled, !identities.isEmpty {
      ReuseDenialTrace.recordSuppressionScopeDescription(
        "press-inval-deferred(\(identities.count))"
      )
    }
  }

  nonisolated func requestInvalidation(of identities: Set<Identity>) {
    // Tracker notifications are driven from the run loop's main-actor event
    // and focus-sync paths (mirrors the `Environment` read-attribution seam).
    MainActor.assumeIsolated {
      if FocusMoveInvalidationNarrowing.isEnabled {
        pendingMoveEndpointsSinceLastCommit.formUnion(identities)
        if ReuseDenialTrace.isEnabled, !identities.isEmpty {
          ReuseDenialTrace.recordSuppressionScopeDescription(
            "focus-inval-deferred(\(identities.count))"
          )
        }
        base.requestInvalidation(of: [])
        return
      }
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
