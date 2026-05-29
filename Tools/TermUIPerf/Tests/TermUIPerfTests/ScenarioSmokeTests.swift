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

  @Test("RunCommand runs N iterations and writes one aggregate per mode")
  @MainActor
  func runCommandRunsIterationsAndWritesAggregate() async throws {
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-perf-iterate-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: artifactRoot) }

    let config = PerfRunConfig(
      scenario: .galleryAnimationClick,
      modes: [.sync],
      iterations: 2,
      artifactsRoot: artifactRoot.path,
      configuration: "debug")

    let outcome = try await RunCommand.run(config)

    #expect(outcome.perIteration.count == 2)
    #expect(outcome.aggregates.count == 1)
    #expect(outcome.aggregates[0].iterationCount == 2)
    #expect(outcome.aggregates[0].totalCPUSeconds.sampleCount == 2)

    let aggregateFile = artifactRoot.appendingPathComponent(
      "aggregate-\(outcome.aggregates[0].scenario)-\(outcome.aggregates[0].renderMode).json")
    #expect(FileManager.default.fileExists(atPath: aggregateFile.path))
  }

  @Test("run writes memory_growth.tsv and honors the memory sample interval")
  @MainActor
  func runWritesMemoryGrowthArtifact() async throws {
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-perf-memgrowth-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: artifactRoot) }

    let result = try await GalleryAnimationClickScenario().run(
      options: PerfScenarioRunOptions(
        renderMode: .sync,
        iterations: 1,
        artifactRoot: artifactRoot,
        configuration: "debug",
        cpuSampleInterval: .milliseconds(5),
        memorySampleInterval: .milliseconds(20),
        memoryIdleWindow: .milliseconds(200)))

    let growthURL = result.runDirectory.appendingPathComponent("memory_growth.tsv")
    #expect(FileManager.default.fileExists(atPath: growthURL.path))
    let growth = try String(contentsOf: growthURL, encoding: .utf8)
    #expect(growth.hasPrefix("provider\tsamples\t"))

    let memory = try String(
      contentsOf: result.runDirectory.appendingPathComponent("memory.tsv"), encoding: .utf8)
    let distinctElapsed = Set(
      memory.split(separator: "\n").dropFirst().compactMap { $0.split(separator: "\t").first })
    #expect(distinctElapsed.count >= 2)
  }

  private func fileExists(_ name: String, in directory: URL) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
  }
}
