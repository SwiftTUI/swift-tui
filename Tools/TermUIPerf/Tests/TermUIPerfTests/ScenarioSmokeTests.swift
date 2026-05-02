import Foundation
import Testing

@testable import TermUIPerf

struct ScenarioSmokeTests {
  @Test("deterministic scenarios write artifact directories")
  @MainActor
  func deterministicScenariosWriteArtifactDirectories() async throws {
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-perf-scenarios-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: artifactRoot)
    }

    for scenario in PerfScenarioRegistry.all {
      let result = try await scenario.run(
        options: PerfScenarioRunOptions(
          renderMode: .sync,
          iterations: 1,
          artifactRoot: artifactRoot,
          configuration: "debug",
          cpuSampleInterval: .milliseconds(1)
        ))

      #expect(result.presentedFrameCount > 0)
      #expect(result.events.isEmpty == false)
      #expect(fileExists("run.json", in: result.runDirectory))
      #expect(fileExists("frames.tsv", in: result.runDirectory))
      #expect(fileExists("events.tsv", in: result.runDirectory))
      #expect(fileExists("cpu.tsv", in: result.runDirectory))
      #expect(fileExists("summary.json", in: result.runDirectory))
    }
  }

  private func fileExists(_ name: String, in directory: URL) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
  }
}
