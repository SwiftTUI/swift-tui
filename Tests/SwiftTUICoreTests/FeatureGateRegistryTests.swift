import Testing

@testable import SwiftTUICore

@MainActor
@Suite(.serialized)
struct FeatureGateRegistryTests {
  @Test("feature gate registry owns the performance gate environment names")
  func registryOwnsPerformanceGateEnvironmentNames() {
    #expect(
      FeatureGate.allCases.map(\.environmentVariableName) == [
        "SWIFTTUI_MEMO_REUSE",
        "SWIFTTUI_OBSERVABLE_KEYPATH_INVALIDATION",
        "SWIFTTUI_PRECISE_OBSERVATION_FIRING",
        "SWIFTTUI_READER_ATTRIBUTION",
        "SWIFTTUI_SOUNDNESS_PROBE",
      ])
    #expect(
      Set(FeatureGate.allCases.map(\.environmentVariableName)).count == FeatureGate.allCases.count)
  }

  @Test("configuration enums route their enrollment through the registry")
  func configurationEnumsRouteEnrollmentThroughRegistry() {
    #expect(
      MemoReuseConfiguration.environmentVariableName
        == FeatureGate.memoReuse.environmentVariableName)
    #expect(
      ObservableKeyPathInvalidationConfiguration.environmentVariableName
        == FeatureGate.observableKeyPathInvalidation.environmentVariableName)
    #expect(
      PreciseObservationFiringConfiguration.environmentVariableName
        == FeatureGate.preciseObservationFiring.environmentVariableName)
    #expect(
      ReaderAttributionConfiguration.environmentVariableName
        == FeatureGate.readerAttribution.environmentVariableName)
    #expect(
      SoundnessProbeConfiguration.environmentVariableName
        == FeatureGate.soundnessProbe.environmentVariableName)
  }
}
