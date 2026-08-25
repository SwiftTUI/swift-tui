import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@MainActor
@Suite(.serialized)
struct FeatureGateRegistryTests {
  @Test("feature gate registry owns the gate environment names")
  func registryOwnsGateEnvironmentNames() {
    #expect(
      FeatureGate.allCases.map(\.environmentVariableName) == [
        "SWIFTTUI_SOUNDNESS_PROBE",
        "SWIFTTUI_OVERLAY_INCREMENTAL_DAMAGE",
        "SWIFTTUI_RASTER_VERIFY_INCREMENTAL",
        "SWIFTTUI_RASTER_TRUST_SOUND_DAMAGE",
        "SWIFTTUI_PRESENTED_PROGRESS_GUARD",
        "SWIFTTUI_COLLECTION_PROBES",
        "SWIFTTUI_COLLECTION_RESOLVE_REUSE",
        "SWIFTTUI_LAZY_IDEAL_ESTIMATE",
        "SWIFTTUI_SCROLL_REGION",
        "SWIFTTUI_SCROLL_BLIT",
        "SWIFTTUI_MEASURE_CUTOFF",
        "SWIFTTUI_PERSISTENT_LAYOUT_CACHE",
        "SWIFTTUI_FOCUS_MOVE_NARROWING",
        "SWIFTTUI_STATE_CAPTURE_BINDING",
        "SWIFTTUI_ANIMATION_VELOCITY",
      ])
    #expect(
      Set(FeatureGate.allCases.map(\.environmentVariableName)).count == FeatureGate.allCases.count)
  }

  @Test("the behavior toggles default off so the standard build is unaffected")
  func behaviorTogglesDefaultOff() {
    #expect(!FeatureGate.overlayIncrementalDamage.defaultIsEnabled)
    #expect(!FeatureGate.rasterVerifyIncremental.defaultIsEnabled)
    #expect(!FeatureGate.rasterTrustSoundDamage.defaultIsEnabled)
    // The presented-progress guard's default flip is gated on its rusage A/B
    // bound (docs/plans/2026-07-20-001 Stage 5, land-only-on-wins).
    #expect(!FeatureGate.presentedProgressGuard.defaultIsEnabled)
  }

  @Test("capture binding defaults on as a diagnostic lever")
  func stateCaptureBindingDefaultsOn() {
    // Flip plan 2026-08-20-001 Stage 4: default-on after the Stage-3 exit
    // criteria (edge coverage, zero seed-fallback/capture-miss oracles).
    // `SWIFTTUI_STATE_CAPTURE_BINDING=0` disables the bind pass for A/B
    // attribution; it does not restore the deleted ambient ladder.
    #expect(FeatureGate.stateCaptureBinding.defaultIsEnabled)
  }

  @Test("focus-move narrowing defaults on as a kill switch")
  func focusMoveNarrowingDefaultsOn() {
    // Flip plan 2026-08-12-004 Stage 3: default-on after the coalesced
    // focus-flip + internal-scroll selective seam fix (Stages 1–2), on the
    // -003 report's A/B (palette close conflicts 177 → 0). The env var is the
    // kill switch and A/B lever (`SWIFTTUI_FOCUS_MOVE_NARROWING=0`).
    #expect(FeatureGate.focusMoveInvalidationNarrowing.defaultIsEnabled)
  }

  @Test("the size-stability measure cutoff defaults on as a kill switch")
  func measureCutoffDefaultsOn() {
    // Plan 2026-08-11-002 Stage 4: promoted on the plan-005
    // committed-benchmark A/B (lazy-vstack-scroll pipeline p50 -54% [real],
    // measure-request counters down [real] suite-wide, narrow-invalidation
    // guard flat) with the layout shadow oracle policing every serve —
    // a kill switch (`SWIFTTUI_MEASURE_CUTOFF=0`), not an opt-in.
    #expect(FeatureGate.measureSizeStabilityCutoff.defaultIsEnabled)
  }

  @Test("the collection probes default on in DEBUG and off in release")
  func collectionProbesDefaultSplitsByConfiguration() {
    // WP-4: the DEBUG suites that assert on these counters read them
    // unconditionally, so DEBUG must stay armed. Release defaults off because
    // the realization counter fires once per realized row — but it stays
    // armable, because debug and release disagree about per-cell work and a
    // release timing can only be explained by a release counter.
    #if DEBUG
      #expect(FeatureGate.collectionProbes.defaultIsEnabled)
    #else
      #expect(!FeatureGate.collectionProbes.defaultIsEnabled)
    #endif
  }

  @Test("the soundness probe defaults on in every configuration")
  func soundnessProbeDefaultsOn() {
    // F34: release builds run the oracles on sampled frames by default so the
    // reconciliation-seam bug class stays observable outside DEBUG.
    #expect(FeatureGate.soundnessProbe.defaultIsEnabled)
  }

  @Test("scroll-region emission defaults on as a kill switch")
  func scrollRegionEmissionDefaultsOn() {
    // R2.3: DECSTBM/SU/SD are VT100-core and every emission is
    // verification-backed, so the gate is a kill switch
    // (`SWIFTTUI_SCROLL_REGION=0`), not an opt-in.
    #expect(FeatureGate.scrollRegionEmission.defaultIsEnabled)
  }

  @Test("the scroll translation blit defaults on as a kill switch")
  func scrollBlitDefaultsOn() {
    // R3.2: every served row is draw-walk verified, flank-verified, and
    // re-proven by the planner's row-buffer identity, with the F13 oracle
    // unchanged on top — so like the scroll-region emission the gate is a
    // kill switch (`SWIFTTUI_SCROLL_BLIT=0`), not an opt-in.
    #expect(FeatureGate.scrollBlit.defaultIsEnabled)
  }

  @Test("configuration enums route their enrollment through the registry")
  func configurationEnumsRouteEnrollmentThroughRegistry() {
    #expect(
      SoundnessProbeConfiguration.environmentVariableName
        == FeatureGate.soundnessProbe.environmentVariableName)
    #expect(
      PresentedProgressGuardConfiguration.environmentVariableName
        == FeatureGate.presentedProgressGuard.environmentVariableName)
  }
}
