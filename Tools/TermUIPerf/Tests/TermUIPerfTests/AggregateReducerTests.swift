import Foundation
import Testing

@testable import TermUIPerf

struct AggregateReducerTests {
  @Test("PerfStat computes median, mean, sample stddev, min/max, CV")
  func perfStatComputesSummaryStatistics() {
    let stat = PerfStat(values: [2, 4, 4, 4, 5, 5, 7, 9])

    #expect(stat.sampleCount == 8)
    #expect(approx(stat.mean, 5.0))
    #expect(approx(stat.median, 4.5))
    #expect(approx(stat.stddev, 2.138_089_935))  // sample stddev (n-1)
    #expect(approx(stat.min, 2.0))
    #expect(approx(stat.max, 9.0))
    #expect(approx(stat.coefficientOfVariation, 0.427_617_987))
  }

  @Test("PerfStat with one value has zero stddev and zero CV")
  func perfStatSingleValueIsZeroSpread() {
    let stat = PerfStat(values: [3.5])

    #expect(stat.sampleCount == 1)
    #expect(approx(stat.median, 3.5))
    #expect(approx(stat.mean, 3.5))
    #expect(approx(stat.stddev, 0.0))
    #expect(approx(stat.coefficientOfVariation, 0.0))
  }

  @Test("PerfStat with zero mean reports zero CV, not NaN")
  func perfStatZeroMeanReportsZeroCV() {
    let stat = PerfStat(values: [0, 0, 0])

    #expect(approx(stat.mean, 0.0))
    #expect(approx(stat.stddev, 0.0))
    #expect(approx(stat.coefficientOfVariation, 0.0))
  }

  @Test("PerfStat with no values is all zeros")
  func perfStatEmptyInputIsAllZeros() {
    let stat = PerfStat(values: [])

    #expect(stat.sampleCount == 0)
    #expect(approx(stat.median, 0.0))
    #expect(approx(stat.mean, 0.0))
    #expect(approx(stat.stddev, 0.0))
    #expect(approx(stat.min, 0.0))
    #expect(approx(stat.max, 0.0))
    #expect(approx(stat.coefficientOfVariation, 0.0))
  }

  @Test("AggregateReducer reduces per-iteration summaries into per-metric stats")
  func aggregateReducerReducesSummaries() {
    let aggregate = AggregateReducer.reduce([
      summary(cpuSeconds: 5.0, committed: 270, latencyP95: 22.0, intervalP50: 36.0),
      summary(cpuSeconds: 5.4, committed: 274, latencyP95: 24.0, intervalP50: 36.0),
      summary(cpuSeconds: 5.8, committed: 278, latencyP95: 26.0, intervalP50: 36.0),
    ])

    #expect(aggregate.scenario == "gallery-animation-click")
    #expect(aggregate.renderMode == "async")
    #expect(aggregate.iterationCount == 3)
    #expect(approx(aggregate.totalCPUSeconds.median, 5.4))
    #expect(approx(aggregate.totalCPUSeconds.mean, 5.4))
    #expect(aggregate.committedFrameCount.sampleCount == 3)
    #expect(approx(aggregate.committedFrameCount.median, 274))
    #expect(approx(aggregate.inputToPresentLatencyP95Ms.median, 24.0))
    #expect(approx(aggregate.frameIntervalP50Ms.stddev, 0.0))
  }

  @Test("AggregateReducer drops nil optional metrics before aggregating")
  func aggregateReducerSkipsNilMetrics() {
    let aggregate = AggregateReducer.reduce([
      summary(cpuSeconds: 5.0, committed: 270, latencyP95: nil, intervalP50: 36.0),
      summary(cpuSeconds: 5.4, committed: 274, latencyP95: 24.0, intervalP50: 36.0),
    ])

    // Only one summary had a non-nil latency p95, so the stat has one sample.
    #expect(aggregate.inputToPresentLatencyP95Ms.sampleCount == 1)
    #expect(approx(aggregate.inputToPresentLatencyP95Ms.median, 24.0))
    #expect(aggregate.totalCPUSeconds.sampleCount == 2)
  }

  @Test("AggregateReducer.format renders median +/- stddev and CV percent")
  func aggregateReducerFormatsHumanReadableSummary() {
    let aggregate = AggregateReducer.reduce([
      summary(cpuSeconds: 5.0, committed: 270, latencyP95: 22.0, intervalP50: 36.0),
      summary(cpuSeconds: 5.4, committed: 274, latencyP95: 24.0, intervalP50: 36.0),
      summary(cpuSeconds: 5.8, committed: 278, latencyP95: 26.0, intervalP50: 36.0),
    ])

    let output = AggregateReducer.format(aggregate)

    #expect(output.contains("scenario: gallery-animation-click (async, n=3)"))
    #expect(output.contains("total CPU seconds: 5.4000 +/- 0.4000"))
    #expect(output.contains("CV 7.4%"))
    #expect(output.contains("committed frames:"))
  }

  private func approx(_ actual: Double, _ expected: Double) -> Bool {
    abs(actual - expected) < 0.000_001
  }

  private func summary(
    cpuSeconds: Double,
    committed: Int,
    latencyP95: Double?,
    intervalP50: Double?
  ) -> PerfSummary {
    PerfSummary(
      scenario: "gallery-animation-click",
      renderMode: "async",
      iterationCount: 1,
      committedFrameCount: committed,
      skippedFrameCount: 0,
      inputToPresentLatencyMs: PerfDistribution(count: 1, p50: nil, p95: latencyP95, p99: nil),
      inputToSettledLatencyMs: PerfDistribution(count: 0, p50: nil, p95: nil, p99: nil),
      frameIntervalMs: PerfDistribution(count: 1, p50: intervalP50, p95: nil, p99: nil),
      totalCPUSeconds: cpuSeconds,
      cpuSecondsPerCommittedFrame: cpuSeconds / Double(committed),
      cpuSecondsPerInputEvent: nil,
      mainActorBlockedRatio: nil,
      mainActorSuspendedRatio: nil,
      workerLayoutEnqueueMs: PerfDistribution(count: 0, p50: nil, p95: nil, p99: nil),
      workerLayoutComputeMs: PerfDistribution(count: 0, p50: nil, p95: nil, p99: nil),
      workerRasterEnqueueMs: PerfDistribution(count: 0, p50: nil, p95: nil, p99: nil),
      workerRasterComputeMs: PerfDistribution(count: 0, p50: nil, p95: nil, p99: nil),
      presentationDurationMs: PerfDistribution(count: 0, p50: nil, p95: nil, p99: nil),
      cancellationCount: 0,
      completedDropCount: 0,
      customLayoutFallbackCount: 0,
      layoutDependentMainActorFallbackCount: 0)
  }
}
