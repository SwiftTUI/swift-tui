import Foundation
import Testing

@testable import TermUIPerf

struct PerfGateTests {
  @Test("a real CPU regression fails the gate")
  func realRegressionFails() {
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpu: [3.0, 3.0, 3.0]),
      candidate: aggregate(cpu: [5.0, 5.0, 5.0]))

    let outcome = CompareCommand.evaluateGate(comparison)

    #expect(!outcome.passed)
    #expect(outcome.failures.contains { $0.metric == "total CPU seconds" })
  }

  @Test("a within-noise CPU change passes the regression gate")
  func withinNoisePasses() {
    // Wide spread makes the noise band swallow the small median move.
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpu: [3.0, 4.0, 5.0]),
      candidate: aggregate(cpu: [3.1, 4.1, 5.1]))

    let outcome = CompareCommand.evaluateGate(comparison)

    #expect(outcome.passed)
  }

  @Test("a real improvement passes the regression gate")
  func realImprovementPasses() {
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpu: [5.0, 5.0, 5.0]),
      candidate: aggregate(cpu: [3.0, 3.0, 3.0]))

    let outcome = CompareCommand.evaluateGate(comparison)

    #expect(outcome.passed)
  }

  @Test("require-improvement is satisfied by a real win")
  func requireImprovementSatisfied() {
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpu: [5.0, 5.0, 5.0]),
      candidate: aggregate(cpu: [3.0, 3.0, 3.0]))

    let outcome = CompareCommand.evaluateGate(
      comparison, requireImprovement: ["total CPU seconds"])

    #expect(outcome.passed)
  }

  @Test("require-improvement fails when the metric only moved within noise")
  func requireImprovementUnmetWithinNoise() {
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpu: [3.0, 4.0, 5.0]),
      candidate: aggregate(cpu: [2.9, 3.9, 4.9]))

    let outcome = CompareCommand.evaluateGate(
      comparison, requireImprovement: ["total CPU seconds"])

    #expect(!outcome.passed)
    #expect(outcome.failures.contains { $0.metric == "total CPU seconds" })
  }

  @Test("require-improvement fails when the metric regressed")
  func requireImprovementUnmetRegression() {
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpu: [3.0, 3.0, 3.0]),
      candidate: aggregate(cpu: [5.0, 5.0, 5.0]))

    let outcome = CompareCommand.evaluateGate(
      comparison, requireImprovement: ["total CPU seconds"])

    #expect(!outcome.passed)
  }

  @Test("an unknown require-improvement metric is itself a failure")
  func requireImprovementUnknownMetricFails() {
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpu: [5.0, 5.0, 5.0]),
      candidate: aggregate(cpu: [3.0, 3.0, 3.0]))

    let outcome = CompareCommand.evaluateGate(
      comparison, requireImprovement: ["does-not-exist"])

    #expect(!outcome.passed)
    #expect(outcome.failures.contains { $0.metric == "does-not-exist" })
  }

  @Test("require-improvement matches metric names punctuation-insensitively")
  func requireImprovementMatchesNormalizedNames() {
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpu: [5.0, 5.0, 5.0]),
      candidate: aggregate(cpu: [3.0, 3.0, 3.0]))

    // "CPU seconds/frame" reached via a differently-cased, punctuated slug.
    let outcome = CompareCommand.evaluateGate(
      comparison, requireImprovement: ["CPU-seconds/frame"])

    #expect(outcome.passed)
  }

  @Test("inconclusive movement neither fails regression nor satisfies improvement")
  func inconclusiveIsNeutralButUnprovable() {
    // Single sample -> inconclusive verdict on every metric.
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpu: [3.0]),
      candidate: aggregate(cpu: [5.0]))

    #expect(CompareCommand.evaluateGate(comparison).passed)
    #expect(
      !CompareCommand.evaluateGate(
        comparison, requireImprovement: ["total CPU seconds"]
      ).passed)
  }

  @Test("loadAggregate reads a file and a single-aggregate directory")
  func loadAggregateFromFileAndDirectory() throws {
    let aggregate = aggregate(cpu: [3.0, 3.0, 3.0])
    let data = try JSONEncoder().encode(aggregate)

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("termuiperf-gate-\(aggregate.committedFrameCount.median)-test")
    try? FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent(
      "aggregate-\(aggregate.scenario)-\(aggregate.renderMode).json")
    try data.write(to: fileURL)

    let fromFile = try CompareCommand.loadAggregate(from: fileURL.path)
    let fromDirectory = try CompareCommand.loadAggregate(from: directory.path)

    #expect(fromFile == aggregate)
    #expect(fromDirectory == aggregate)
  }

  private func aggregate(cpu: [Double]) -> PerfAggregateSummary {
    PerfAggregateSummary(
      scenario: "synthetic-narrow-invalidation",
      renderMode: "async",
      iterationCount: cpu.count,
      totalCPUSeconds: PerfStat(values: cpu),
      committedFrameCount: PerfStat(values: cpu.map { _ in 274 }),
      diagnosticFrameCount: PerfStat(values: cpu.map { _ in 300 }),
      elidedFrameCount: PerfStat(values: cpu.map { _ in 20 }),
      cancelledFrameCount: PerfStat(values: cpu.map { _ in 2 }),
      completedDropCount: PerfStat(values: cpu.map { _ in 4 }),
      cpuSecondsPerCommittedFrame: PerfStat(values: cpu.map { $0 / 274 }),
      cpuSecondsPerDiagnosticFrame: PerfStat(values: cpu.map { $0 / 300 }),
      inputToPresentLatencyP95Ms: PerfStat(values: cpu.map { _ in 22 }),
      frameIntervalP50Ms: PerfStat(values: cpu.map { _ in 36 }))
  }
}
