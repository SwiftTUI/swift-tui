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
  /// The relative spread this metric showed between two identical runs on this
  /// machine, when an A/A envelope was recorded beside either aggregate.
  ///
  /// Annotation only — never gated. The envelope says how much of a delta this
  /// machine produces from nothing; it does not say whether a delta is
  /// acceptable, and turning a recorded observation into a pass/fail threshold
  /// would smuggle a policy in under a measurement's name.
  public var aaEnvelope: Double?

  /// Whether this metric's relative delta falls inside the recorded A/A
  /// envelope. `nil` when no envelope was recorded, when the base median is `0`
  /// and a relative delta is not expressible, or when the recorded envelope is
  /// itself `0`.
  ///
  /// A zero envelope means the two A/A passes produced identical medians. That
  /// is not evidence of a metric with no spread — it is two samples agreeing,
  /// which happens routinely for coarse-grained medians that land on the same
  /// discretized value. Treating it as a zero-width band would label every
  /// later delta "outside recorded A/A", including ones well inside the noise
  /// band, so the honest reading is that this pair did not resolve an envelope
  /// for this metric. The recorded `0` stays in the envelope file, where it is
  /// visible as what it is.
  public var withinRecordedAA: Bool? {
    guard let aaEnvelope, aaEnvelope > 0, baseMedian != 0 else {
      return nil
    }
    return abs(delta) / abs(baseMedian) <= aaEnvelope
  }

  public init(
    metric: String,
    baseMedian: Double,
    candidateMedian: Double,
    delta: Double,
    noiseBand: Double,
    verdict: SignificanceVerdict,
    oneSided: Bool = false,
    aaEnvelope: Double? = nil
  ) {
    self.metric = metric
    self.baseMedian = baseMedian
    self.candidateMedian = candidateMedian
    self.delta = delta
    self.noiseBand = noiseBand
    self.verdict = verdict
    self.oneSided = oneSided
    self.aaEnvelope = aaEnvelope
  }

  private enum CodingKeys: String, CodingKey {
    case metric
    case baseMedian = "base_median"
    case candidateMedian = "candidate_median"
    case delta
    case noiseBand = "noise_band"
    case verdict
    case oneSided = "one_sided"
    case aaEnvelope = "aa_envelope"
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
      oneSided: try container.decodeIfPresent(Bool.self, forKey: .oneSided) ?? false,
      aaEnvelope: try container.decodeIfPresent(Double.self, forKey: .aaEnvelope)
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

  /// Compares two aggregates, optionally annotating each metric with the A/A
  /// envelope recorded on this machine.
  ///
  /// The envelope only ever *labels* a verdict. `evaluateGate` does not read
  /// it, deliberately: a recorded observation about how noisy a machine is
  /// answers a different question from whether a change is acceptable, and
  /// letting the first decide the second would turn a measurement into an
  /// unreviewed policy.
  public static func compareAggregates(
    base: PerfAggregateSummary,
    candidate: PerfAggregateSummary,
    sigma: Double = defaultNoiseSigma,
    aaEnvelope: PerfAAEnvelope? = nil
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
      // Explanatory, not a target: these two say whether a milliseconds delta
      // came from doing more work or from the same work costing more. A run
      // that armed the probes on only one side surfaces as `oneSided`, which
      // is the honest reading — not a regression.
      metricComparison(
        "realized rows/moving frame", base.realizedRowsPerMovingFrameMedian,
        candidate.realizedRowsPerMovingFrameMedian, sigma),
      metricComparison(
        "list layout derivations/moving frame",
        base.listLayoutDerivationsPerMovingFrameMedian,
        candidate.listLayoutDerivationsPerMovingFrameMedian, sigma),
      metricComparison(
        "pipeline p50 ms", base.pipelineP50Ms, candidate.pipelineP50Ms, sigma),
    ]
    guard let aaEnvelope else {
      return AggregateComparison(scenario: base.scenario, metrics: metrics)
    }
    let annotated = metrics.map { metric -> AggregateMetricComparison in
      guard !metric.oneSided, let recorded = aaEnvelope.envelope(for: metric.metric) else {
        return metric
      }
      var annotated = metric
      annotated.aaEnvelope = recorded
      return annotated
    }
    return AggregateComparison(scenario: base.scenario, metrics: annotated)
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
          + "[\(metric.verdict.rawValue)]\(annotation)\(aaAnnotation(metric))")
    }
    return lines.joined(separator: "\n")
  }

  /// `" [inside recorded A/A ±2.10%]"`, or the `OUTSIDE` form, or empty when
  /// no envelope covers this metric.
  private static func aaAnnotation(_ metric: AggregateMetricComparison) -> String {
    guard let envelope = metric.aaEnvelope, let within = metric.withinRecordedAA else {
      return ""
    }
    let percent = String(format: "%.2f", envelope * 100)
    return within
      ? " [inside recorded A/A ±\(percent)%]"
      : " [OUTSIDE recorded A/A ±\(percent)%]"
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
