/// Process-level switch for the Presented-Progress Guard
/// (`SWIFTTUI_PRESENTED_PROGRESS_GUARD`, opt-in).
///
/// With the guard on, a completed frame whose presentation diff against the
/// last presented surface is non-empty is never drop-eligible
/// (``FrameDropBlocker/undeliveredPresentationDamage``): the bounded
/// completed-frame starvation backstop becomes the invariant "undelivered
/// pixels are never droppable", uniformly for every host. This is the Tier-2
/// insurance from docs/plans/2026-07-20-001 — the browser 0.1.9 coalescing
/// class cannot be re-entered through host configuration alone while the
/// guard is on. The default flip is gated on the plan's pre-committed rusage
/// A/B bound (commit-instead-of-drop runs the full commit path).
///
/// The environment read latches on first access; tests set ``isEnabled``
/// directly (serialized suites, restored in `defer`).
@MainActor
package enum PresentedProgressGuardConfiguration {
  package static let environmentVariableName =
    FeatureGate.presentedProgressGuard.environmentVariableName

  package static var isEnabled: Bool =
    FeatureGate.presentedProgressGuard.initialIsEnabled()
}
