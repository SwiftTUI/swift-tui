import Foundation
@_spi(Runners) import SwiftTUIRuntime
import Testing

@Suite
struct HostWireConformanceStreamRecorder {
  static let recordingEnvironment = "SWIFTTUI_REGENERATE_CONFORMANCE_FIXTURES"

  @Test("canonical conformance corpus matches the production encoder recorder")
  func canonicalCorpusMatchesProductionEncoderRecorder() throws {
    let generated = try Self.record()
    let directory = Self.fixtureDirectory
    if ProcessInfo.processInfo.environment[Self.recordingEnvironment] == "1" {
      try generated.manifestData.write(
        to: directory.appendingPathComponent(HostWireConformanceCorpus.manifestFilename),
        options: .atomic
      )
      for (filename, data) in generated.fixtureData {
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
      }
    }

    let checkedInManifest = try Data(
      contentsOf: directory.appendingPathComponent(HostWireConformanceCorpus.manifestFilename))
    #expect(checkedInManifest == generated.manifestData)
    for (filename, expectedData) in generated.fixtureData {
      let checkedIn = try Data(contentsOf: directory.appendingPathComponent(filename))
      #expect(checkedIn == expectedData, "recorded fixture drifted: \(filename)")
    }
    _ = try HostWireConformanceCorpus.load(directory: directory)
  }

  struct GeneratedCorpus {
    var manifestData: Data
    var fixtureData: [String: Data]
  }

  static func record() throws -> GeneratedCorpus {
    let scenarios = try recordedScenarios().sorted { $0.file < $1.file }
    let bodyData = try Dictionary(
      uniqueKeysWithValues: scenarios.map { scenario in
        (scenario.file, try jsonLines(scenario.steps))
      })
    let entries = scenarios.map { scenario -> [String: Any] in
      let bodyHash = HostWireConformanceSHA256.hexDigest(bodyData[scenario.file]!)
      return [
        "file": scenario.file,
        "scenario": scenario.scenario,
        "kind": scenario.kind.rawValue,
        "mutationClass": scenario.mutationClass.rawValue,
        "bodySHA256": bodyHash,
        "requiresStage": scenario.requiresStage.rawValue,
        "runners": scenario.runners.map(\.rawValue),
      ]
    }
    let manifestObject: [String: Any] = [
      "formatVersion": HostWireConformanceCorpus.formatVersion,
      "fixtures": entries,
    ]
    var manifestData = try JSONSerialization.data(
      withJSONObject: manifestObject,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    manifestData.append(0x0A)
    let manifestHash = HostWireConformanceSHA256.hexDigest(manifestData)

    var fixtures: [String: Data] = [:]
    for scenario in scenarios {
      let body = bodyData[scenario.file]!
      let bodyHash = HostWireConformanceSHA256.hexDigest(body)
      let header =
        #"{"formatVersion":1,"manifestSHA256":"\#(manifestHash)","bodySHA256":"\#(bodyHash)"}"#
        + "\n"
      fixtures[scenario.file] = Data(header.utf8) + body
    }
    return GeneratedCorpus(manifestData: manifestData, fixtureData: fixtures)
  }

  struct Scenario {
    var file: String
    var scenario: String
    var kind: HostWireConformanceKind
    var mutationClass: HostWireConformanceMutationClass
    var requiresStage: HostWireConformanceStage
    var runners: [HostWireConformanceRunner]
    var steps: [[String: Any]]
  }

  private static func jsonLines(
    _ steps: [[String: Any]]
  ) throws -> Data {
    var data = Data()
    for step in steps {
      let line = try JSONSerialization.data(
        withJSONObject: step,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
      data.append(line)
      data.append(0x0A)
    }
    return data
  }

  static var fixtureDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures")
      .appendingPathComponent("Transport")
  }
}
