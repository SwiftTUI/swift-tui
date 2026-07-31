import Foundation
import Testing

@testable import TermUIPerf

@Suite(.serialized)
struct ScenarioSmokeTests {
  /// Comma-separated `PerfScenarioName` raw values quarantined from the smoke
  /// sweep. Only CI lanes with a registered flake set this — see
  /// docs/KNOWN-TEST-FLAKES.md for the active entries; every skip must map to
  /// a register entry with its reproduction evidence.
  private static var quarantinedScenarioNames: Set<String> {
    guard let raw = ProcessInfo.processInfo.environment["SWIFTTUI_PERF_SMOKE_SKIP"] else {
      return []
    }
    return Set(
      raw.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces)
      })
  }

  @Test("deterministic scenarios write artifact directories")
  @MainActor
  func deterministicScenariosWriteArtifactDirectories() async throws {
    // The collection baselines default to their measurement scale (1k rows —
    // seconds per frame in debug by design); pin the smoke sweep to a small
    // tree so this test stays a wiring check, not a benchmark.
    setenv("SWIFTTUI_PERF_LAZY_LIST_ROWS", "120", 1)
    setenv("SWIFTTUI_PERF_TABLE_ROWS", "120", 1)
    setenv("SWIFTTUI_PERF_LAZY_VSTACK_ROWS", "200", 1)
    setenv("SWIFTTUI_PERF_SCROLL_NOTCHES", "6", 1)
    setenv("SWIFTTUI_PERF_SCROLL_CADENCE_NOTCHES", "12", 1)
    setenv("SWIFTTUI_PERF_SCROLL_DOCUMENT_BLOCKS", "24", 1)
    defer {
      unsetenv("SWIFTTUI_PERF_LAZY_LIST_ROWS")
      unsetenv("SWIFTTUI_PERF_TABLE_ROWS")
      unsetenv("SWIFTTUI_PERF_LAZY_VSTACK_ROWS")
      unsetenv("SWIFTTUI_PERF_SCROLL_NOTCHES")
      unsetenv("SWIFTTUI_PERF_SCROLL_CADENCE_NOTCHES")
      unsetenv("SWIFTTUI_PERF_SCROLL_DOCUMENT_BLOCKS")
    }
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-perf-scenarios-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: artifactRoot)
    }

    for scenario in PerfScenarioRegistry.all {
      if Self.quarantinedScenarioNames.contains(scenario.name.rawValue) {
        print("[scenario-smoke] skipping quarantined scenario \(scenario.name.rawValue)")
        continue
      }
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

  // MARK: - T-12

  @Test("Open-loop 60 Hz accounts for every notch, and records coalescing when it happens")
  @MainActor
  func openLoopCadenceAccountsForEveryNotch() async throws {
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-perf-cadence-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: artifactRoot) }

    setenv("SWIFTTUI_PERF_LAZY_LIST_ROWS", "160", 1)
    setenv("SWIFTTUI_PERF_SCROLL_CADENCE_NOTCHES", "24", 1)
    defer {
      unsetenv("SWIFTTUI_PERF_LAZY_LIST_ROWS")
      unsetenv("SWIFTTUI_PERF_SCROLL_CADENCE_NOTCHES")
    }

    // Async on purpose: under `.sync` the frame driver drains inside the
    // injection's suspension points, so the drive is not a race and the
    // scenario measures something else entirely (see the scenario's doc).
    let result = try await ScrollCadence60HzScenario().run(
      options: PerfScenarioRunOptions(
        renderMode: .async,
        iterations: 1,
        artifactRoot: artifactRoot,
        configuration: "debug",
        cpuSampleInterval: .milliseconds(5),
        memoryIdleWindow: .milliseconds(200)
      ))

    let frames = try PerfFrameDiagnosticsTSVReader.read(
      from: result.runDirectory.appendingPathComponent("frames.tsv"),
      presentedFrames: []
    )
    #expect(!frames.isEmpty)

    // The instrument's totality property, which holds whether or not HEAD
    // absorbs the cadence: every injected notch is answered by exactly one
    // frame, so the answered counts sum to the notches injected. If this ever
    // drifts, the coalescing rate downstream is measuring nothing.
    let answered = frames.map(\.answeredInputCount)
    #expect(answered.reduce(0, +) == 24)

    // Whether a backlog forms is a property of HEAD, not of the harness, so
    // this is recorded rather than demanded. At the time of writing HEAD does
    // NOT absorb 60 Hz — 60 notches collapsed to 22 frames with input→commit
    // p50 at 453 ms — but a faster HEAD legitimately answers one per frame.
    let coalescedFrames = answered.filter { $0 > 1 }.count
    if coalescedFrames > 0 {
      #expect(frames.count < 24)
    }
  }

  private func fileExists(_ name: String, in directory: URL) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
  }
}
