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
  /// One side measured this metric and the other did not — an aggregate
  /// recorded before the metric existed compared against one recorded after.
  ///
  /// The absent side's median is `0` because there is nothing to report, which
  /// makes `delta` an artifact of the format's history rather than of the code
  /// under test. Such a metric is *reported* so the gap is visible, and never
  /// gated: failing a build because a metric was invented is not a regression.
  public var oneSided: Bool

  public init(
    metric: String,
    baseMedian: Double,
    candidateMedian: Double,
    delta: Double,
    noiseBand: Double,
    verdict: SignificanceVerdict,
    oneSided: Bool = false
  ) {
    self.metric = metric
    self.baseMedian = baseMedian
    self.candidateMedian = candidateMedian
    self.delta = delta
    self.noiseBand = noiseBand
    self.verdict = verdict
    self.oneSided = oneSided
  }

  private enum CodingKeys: String, CodingKey {
    case metric
    case baseMedian = "base_median"
    case candidateMedian = "candidate_median"
    case delta
    case noiseBand = "noise_band"
    case verdict
    case oneSided = "one_sided"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      metric: try container.decode(String.self, forKey: .metric),
      baseMedian: try container.decode(Double.self, forKey: .baseMedian),
      candidateMedian: try container.decode(Double.self, forKey: .candidateMedian),
      delta: try container.decode(Double.self, forKey: .delta),
      noiseBand: try container.decode(Double.self, forKey: .noiseBand),
      verdict: try container.decode(SignificanceVerdict.self, forKey: .verdict),
      oneSided: try container.decodeIfPresent(Bool.self, forKey: .oneSided) ?? false
    )
  }
}

public struct AggregateComparison: Codable, Equatable, Sendable {
  public var scenario: String
  public var metrics: [AggregateMetricComparison]

  public init(scenario: String, metrics: [AggregateMetricComparison]) {
    self.scenario = scenario
    self.metrics = metrics
  }

  private enum CodingKeys: String, CodingKey {
    case scenario
    case metrics
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
        "diagnostic frames", base.diagnosticFrameCount, candidate.diagnosticFrameCount, sigma),
      metricComparison(
        "elided frames", base.elidedFrameCount, candidate.elidedFrameCount, sigma),
      metricComparison(
        "cancelled frames", base.cancelledFrameCount, candidate.cancelledFrameCount, sigma),
      metricComparison(
        "completed drops", base.completedDropCount, candidate.completedDropCount, sigma),
      metricComparison(
        "CPU seconds/frame", base.cpuSecondsPerCommittedFrame,
        candidate.cpuSecondsPerCommittedFrame, sigma),
      metricComparison(
        "CPU seconds/diagnostic frame", base.cpuSecondsPerDiagnosticFrame,
        candidate.cpuSecondsPerDiagnosticFrame, sigma),
      metricComparison(
        "input latency p95 ms", base.inputToPresentLatencyP95Ms,
        candidate.inputToPresentLatencyP95Ms, sigma),
      metricComparison(
        "frame interval p50 ms", base.frameIntervalP50Ms, candidate.frameIntervalP50Ms, sigma),
      metricComparison(
        "input to commit p50 ms", base.inputToCommitP50Ms, candidate.inputToCommitP50Ms, sigma),
      metricComparison(
        "input to commit p95 ms", base.inputToCommitP95Ms, candidate.inputToCommitP95Ms, sigma),
      metricComparison(
        "input to commit p99 ms", base.inputToCommitP99Ms, candidate.inputToCommitP99Ms, sigma),
      metricComparison(
        "present bytes/moving frame", base.presentBytesPerMovingFrameMedian,
        candidate.presentBytesPerMovingFrameMedian, sigma),
      metricComparison(
        "pipeline p50 ms", base.pipelineP50Ms, candidate.pipelineP50Ms, sigma),
    ]
    return AggregateComparison(scenario: base.scenario, metrics: metrics)
  }

  public static func format(_ comparison: AggregateComparison) -> String {
    var lines = ["scenario: \(comparison.scenario)"]
    for metric in comparison.metrics {
      let base = String(format: "%.4f", metric.baseMedian)
      let candidate = String(format: "%.4f", metric.candidateMedian)
      let delta = String(format: "%+.4f", metric.delta)
      let band = String(format: "%.4f", metric.noiseBand)
      let annotation = metric.oneSided ? " [one-sided: metric missing on one run]" : ""
      lines.append(
        "\(metric.metric): \(base) -> \(candidate) (\(delta), band \(band)) "
          + "[\(metric.verdict.rawValue)]\(annotation)")
    }
    return lines.joined(separator: "\n")
  }

  /// Compares one metric. The noise band is `sigma * max(base.stddev,
  /// candidate.stddev)`; when both stddevs are 0 (perfectly consistent runs)
  /// the band is 0, so any nonzero median delta is reported `.real`. A metric
  /// with fewer than 2 samples on either side is `.inconclusive`.
  ///
  /// A metric present on exactly one side is additionally marked `oneSided`.
  /// Sample-count alone already keeps it out of the gate, but the flag is what
  /// stops a reader from taking `0.0000 -> 5.2000` at face value when the zero
  /// only means "this run predates the metric".
  private static func metricComparison(
    _ name: String,
    _ base: PerfStat,
    _ candidate: PerfStat,
    _ sigma: Double
  ) -> AggregateMetricComparison {
    let delta = candidate.median - base.median
    let noiseBand = sigma * Swift.max(base.stddev, candidate.stddev)
    let oneSided =
      (base.sampleCount == 0) != (candidate.sampleCount == 0)
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
      verdict: verdict,
      oneSided: oneSided)
  }
}
