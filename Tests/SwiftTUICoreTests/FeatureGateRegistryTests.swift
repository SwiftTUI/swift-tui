import Testing

@testable import SwiftTUICore

@MainActor
@Suite(.serialized)
struct FeatureGateRegistryTests {
  @Test("feature gate registry owns the gate environment names")
  func registryOwnsGateEnvironmentNames() {
    #expect(
      FeatureGate.allCases.map(\.environmentVariableName) == [
        "SWIFTTUI_SOUNDNESS_PROBE"
      ])
    #expect(
      Set(FeatureGate.allCases.map(\.environmentVariableName)).count == FeatureGate.allCases.count)
  }

  @Test("configuration enums route their enrollment through the registry")
  func configurationEnumsRouteEnrollmentThroughRegistry() {
    #expect(
      SoundnessProbeConfiguration.environmentVariableName
        == FeatureGate.soundnessProbe.environmentVariableName)
  }
}
