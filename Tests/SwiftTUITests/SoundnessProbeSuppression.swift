import SwiftTUICore

/// Suppresses the soundness probe for one test's renders — the intentional
/// oracle-reduction shape from `docs/SOUNDNESS-ORACLES.md`'s enforcement
/// model.
///
/// The layout shadow oracle re-runs measure and place on every sampled DEBUG
/// frame, which re-invokes author custom layouts (`sizeThatFits`,
/// `placeSubviews`, `makeCache`) a second time. That is sound — the `Layout`
/// contract requires those to be pure functions of their inputs — but tests
/// that pin per-pass invocation economy (cache made once per pass,
/// layout derived once and carried) measure the production pass, not the
/// oracle, and must pin the probe off for their renders:
///
/// ```swift
/// let probe = SoundnessProbeSuppression()
/// defer { probe.restore() }
/// ```
@MainActor
struct SoundnessProbeSuppression {
  private let wasEnabled: Bool
  private let wasSampledFrame: Bool

  init() {
    wasEnabled = SoundnessProbeConfiguration.isEnabled
    wasSampledFrame = SoundnessProbeConfiguration.isSampledFrame
    SoundnessProbeConfiguration.isEnabled = false
    SoundnessProbeConfiguration.isSampledFrame = false
  }

  func restore() {
    SoundnessProbeConfiguration.isEnabled = wasEnabled
    SoundnessProbeConfiguration.isSampledFrame = wasSampledFrame
  }
}
