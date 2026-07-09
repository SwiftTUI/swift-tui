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
      ])
    #expect(
      Set(FeatureGate.allCases.map(\.environmentVariableName)).count == FeatureGate.allCases.count)
  }

  @Test("the behavior toggles default off so the standard build is unaffected")
  func behaviorTogglesDefaultOff() {
    #expect(!FeatureGate.overlayIncrementalDamage.defaultIsEnabled)
    #expect(!FeatureGate.rasterVerifyIncremental.defaultIsEnabled)
    #expect(!FeatureGate.rasterTrustSoundDamage.defaultIsEnabled)
  }

  @Test("the soundness probe defaults on in every configuration")
  func soundnessProbeDefaultsOn() {
    // F34: release builds run the oracles on sampled frames by default so the
    // reconciliation-seam bug class stays observable outside DEBUG.
    #expect(FeatureGate.soundnessProbe.defaultIsEnabled)
  }

  @Test("configuration enums route their enrollment through the registry")
  func configurationEnumsRouteEnrollmentThroughRegistry() {
    #expect(
      SoundnessProbeConfiguration.environmentVariableName
        == FeatureGate.soundnessProbe.environmentVariableName)
  }
}
