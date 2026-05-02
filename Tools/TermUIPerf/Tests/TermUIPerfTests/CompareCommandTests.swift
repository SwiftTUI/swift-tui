import Foundation
import Testing

@testable import TermUIPerf

struct CompareCommandTests {
  @Test("compare classifies clear win")
  func compareClassifiesClearWin() {
    let comparison = CompareCommand.compare(
      base: summary(latencyValues: [20, 30, 40], cpuSeconds: 1.0, mode: "sync"),
      candidate: summary(latencyValues: [10, 15, 20], cpuSeconds: 0.8, mode: "async")
    )

    #expect(comparison.classification == .clearWin)
    #expect(isApproximately(comparison.inputLatencyP95Delta, -19.5))
    #expect(isApproximately(comparison.totalCPUSecondsDelta, -0.2))
  }

  @Test("compare classifies latency win with CPU cost")
  func compareClassifiesLatencyWinWithCPUCost() {
    let comparison = CompareCommand.compare(
      base: summary(latencyValues: [20, 30, 40], cpuSeconds: 1.0, mode: "sync"),
      candidate: summary(latencyValues: [10, 15, 20], cpuSeconds: 1.2, mode: "async")
    )

    #expect(comparison.classification == .latencyWinWithCPUCost)
  }

  @Test("compare classifies CPU regression")
  func compareClassifiesCPURegression() {
    let comparison = CompareCommand.compare(
      base: summary(latencyValues: [20, 30, 40], cpuSeconds: 1.0, mode: "sync"),
      candidate: summary(latencyValues: [20, 30, 40], cpuSeconds: 1.2, mode: "async")
    )

    #expect(comparison.classification == .cpuRegression)
  }

  @Test("compare formats summary deltas")
  func compareFormatsSummaryDeltas() {
    let comparison = CompareCommand.compare(
      base: summary(latencyValues: [20, 30, 40], cpuSeconds: 1.0, mode: "sync"),
      candidate: summary(latencyValues: [10, 15, 20], cpuSeconds: 1.2, mode: "async")
    )
    let output = CompareCommand.format(comparison)

    #expect(output.contains("classification: latency win with CPU cost"))
    #expect(output.contains("input latency p95 ms:"))
    #expect(output.contains("total CPU seconds:"))
    #expect(output.contains("worker layout compute p95 ms:"))
    #expect(output.contains("layout-dependent main-actor fallbacks:"))
  }

  @Test("compare loads summary files from run directories")
  func compareLoadsSummaryFilesFromRunDirectories() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-perf-compare-\(UUID().uuidString)", isDirectory: true)
    let baseDirectory = root.appendingPathComponent("base", isDirectory: true)
    let candidateDirectory = root.appendingPathComponent("candidate", isDirectory: true)
    try FileManager.default.createDirectory(
      at: baseDirectory,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: candidateDirectory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    try write(
      summary(latencyValues: [20, 30, 40], cpuSeconds: 1.0, mode: "sync"), to: baseDirectory)
    try write(
      summary(latencyValues: [10, 15, 20], cpuSeconds: 1.2, mode: "async"),
      to: candidateDirectory
    )

    let comparison = try CompareCommand.compare(
      baseRunDirectory: baseDirectory,
      candidateRunDirectory: candidateDirectory
    )

    #expect(comparison.classification == .latencyWinWithCPUCost)
  }

  private func summary(
    latencyValues: [Double],
    cpuSeconds: Double,
    mode: String
  ) -> PerfSummary {
    PerfSummary(
      scenario: "gallery-animation-click",
      renderMode: mode,
      iterationCount: 3,
      committedFrameCount: 3,
      skippedFrameCount: 0,
      inputToPresentLatencyMs: PerfDistribution(values: latencyValues),
      inputToSettledLatencyMs: PerfDistribution(values: latencyValues),
      frameIntervalMs: PerfDistribution(values: [10, 12]),
      totalCPUSeconds: cpuSeconds,
      cpuSecondsPerCommittedFrame: cpuSeconds / 3,
      cpuSecondsPerInputEvent: cpuSeconds / 3,
      mainActorBlockedRatio: 0.1,
      mainActorSuspendedRatio: 0.2,
      workerLayoutEnqueueMs: PerfDistribution(values: [1, 2, 3]),
      workerLayoutComputeMs: PerfDistribution(values: [4, 5, 6]),
      workerRasterEnqueueMs: PerfDistribution(values: [1, 1, 2]),
      workerRasterComputeMs: PerfDistribution(values: [2, 3, 4]),
      presentationDurationMs: PerfDistribution(values: [1, 2]),
      cancellationCount: 1,
      completedDropCount: 2,
      customLayoutFallbackCount: 3,
      layoutDependentMainActorFallbackCount: 4
    )
  }

  private func write(_ summary: PerfSummary, to directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(summary).write(to: directory.appendingPathComponent("summary.json"))
  }

  private func isApproximately(_ actual: Double?, _ expected: Double) -> Bool {
    guard let actual else {
      return false
    }
    return abs(actual - expected) < 0.000_001
  }
}
