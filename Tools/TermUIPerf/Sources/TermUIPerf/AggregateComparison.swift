import Foundation

public enum SignificanceVerdict: String, Codable, Equatable, Sendable {
  case real = "real"
  case withinNoise = "within noise"
  case inconclusive = "inconclusive"
}

public struct AggregateMetricComparison: Codable, Equatable, Sendable {
  public var metric: String
  public var baseMedian: Double
  public var candidateMedian: Double
  public var delta: Double
  public var noiseBand: Double
  public var verdict: SignificanceVerdict

  public init(
    metric: String,
    baseMedian: Double,
    candidateMedian: Double,
    delta: Double,
    noiseBand: Double,
    verdict: SignificanceVerdict
  ) {
    self.metric = metric
    self.baseMedian = baseMedian
    self.candidateMedian = candidateMedian
    self.delta = delta
    self.noiseBand = noiseBand
    self.verdict = verdict
  }
}

public struct AggregateComparison: Codable, Equatable, Sendable {
  public var scenario: String
  public var metrics: [AggregateMetricComparison]

  public init(scenario: String, metrics: [AggregateMetricComparison]) {
    self.scenario = scenario
    self.metrics = metrics
  }
}

extension CompareCommand {
  /// Number of standard deviations the median delta must exceed to be "real".
  public static let defaultNoiseSigma = 2.0

  public static func compareAggregates(
    base: PerfAggregateSummary,
    candidate: PerfAggregateSummary,
    sigma: Double = defaultNoiseSigma
  ) -> AggregateComparison {
    let metrics = [
      metricComparison(
        "total CPU seconds", base.totalCPUSeconds, candidate.totalCPUSeconds, sigma),
      metricComparison(
        "committed frames", base.committedFrameCount, candidate.committedFrameCount, sigma),
      metricComparison(
        "CPU seconds/frame", base.cpuSecondsPerCommittedFrame,
        candidate.cpuSecondsPerCommittedFrame, sigma),
      metricComparison(
        "input latency p95 ms", base.inputToPresentLatencyP95Ms,
        candidate.inputToPresentLatencyP95Ms, sigma),
      metricComparison(
        "frame interval p50 ms", base.frameIntervalP50Ms, candidate.frameIntervalP50Ms, sigma),
    ]
    return AggregateComparison(scenario: base.scenario, metrics: metrics)
  }

  private static func metricComparison(
    _ name: String,
    _ base: PerfStat,
    _ candidate: PerfStat,
    _ sigma: Double
  ) -> AggregateMetricComparison {
    let delta = candidate.median - base.median
    let noiseBand = sigma * Swift.max(base.stddev, candidate.stddev)
    let verdict: SignificanceVerdict
    if base.sampleCount < 2 || candidate.sampleCount < 2 {
      verdict = .inconclusive
    } else if abs(delta) > noiseBand {
      verdict = .real
    } else {
      verdict = .withinNoise
    }
    return AggregateMetricComparison(
      metric: name,
      baseMedian: base.median,
      candidateMedian: candidate.median,
      delta: delta,
      noiseBand: noiseBand,
      verdict: verdict)
  }
}
