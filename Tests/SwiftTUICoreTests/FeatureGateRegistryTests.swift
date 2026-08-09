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
