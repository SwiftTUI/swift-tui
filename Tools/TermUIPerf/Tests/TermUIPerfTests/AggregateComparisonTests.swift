import Foundation
import Testing

@testable import TermUIPerf

struct AggregateComparisonTests {
  @Test("delta beyond the noise band is flagged real")
  func deltaBeyondNoiseBandIsReal() throws {
    // base CPU ~5.4 +/- 0.4; candidate ~3.0 +/- 0.4. 2-sigma band = 0.8.
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpuValues: [5.0, 5.4, 5.8]),
      candidate: aggregate(cpuValues: [2.6, 3.0, 3.4]))

    let cpu = try #require(metric(comparison, "total CPU seconds"))
    #expect(cpu.verdict == .real)
    #expect(approx(cpu.delta, -2.4))
  }

  @Test("delta within the noise band is flagged within noise")
  func deltaWithinNoiseBandIsWithinNoise() throws {
    // base ~5.4 +/- 0.4; candidate ~5.5 +/- 0.4. 2-sigma band = 0.8 > |0.1|.
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpuValues: [5.0, 5.4, 5.8]),
      candidate: aggregate(cpuValues: [5.1, 5.5, 5.9]))

    let cpu = try #require(metric(comparison, "total CPU seconds"))
    #expect(cpu.verdict == .withinNoise)
  }

  @Test("single-sample inputs are inconclusive (no noise estimate)")
  func singleSampleIsInconclusive() throws {
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpuValues: [5.0]),
      candidate: aggregate(cpuValues: [3.0]))

    let cpu = try #require(metric(comparison, "total CPU seconds"))
    #expect(cpu.verdict == .inconclusive)
  }

  @Test("format renders per-metric verdict lines")
  func formatRendersVerdictLines() {
    let comparison = CompareCommand.compareAggregates(
      base: aggregate(cpuValues: [5.0, 5.4, 5.8]),
      candidate: aggregate(cpuValues: [2.6, 3.0, 3.4]))

    let output = CompareCommand.format(comparison)

    #expect(output.contains("scenario: gallery-animation-click"))
    #expect(output.contains("total CPU seconds: 5.4000 -> 3.0000"))
    #expect(output.contains("[real]"))
    #expect(output.contains("(-2.4000, band 0.8000)"))
  }

  private func metric(
    _ comparison: AggregateComparison,
    _ name: String
  ) -> AggregateMetricComparison? {
    comparison.metrics.first { $0.metric == name }
  }

  private func aggregate(cpuValues: [Double]) -> PerfAggregateSummary {
    PerfAggregateSummary(
      scenario: "gallery-animation-click",
      renderMode: "async",
      iterationCount: cpuValues.count,
      totalCPUSeconds: PerfStat(values: cpuValues),
      committedFrameCount: PerfStat(values: cpuValues.map { _ in 274 }),
      cpuSecondsPerCommittedFrame: PerfStat(values: cpuValues.map { $0 / 274 }),
      inputToPresentLatencyP95Ms: PerfStat(values: cpuValues.map { _ in 22 }),
      frameIntervalP50Ms: PerfStat(values: cpuValues.map { _ in 36 }))
  }

  private func approx(_ actual: Double, _ expected: Double) -> Bool {
    abs(actual - expected) < 0.000_001
  }
}
