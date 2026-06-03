import Foundation

/// One reason the gate rejected a comparison.
public struct GateFailure: Equatable, Sendable {
  public var metric: String
  public var reason: String

  public init(metric: String, reason: String) {
    self.metric = metric
    self.reason = reason
  }
}

/// The pass/fail result of evaluating a `compare` gate.
public struct GateOutcome: Equatable, Sendable {
  public var passed: Bool
  public var failures: [GateFailure]

  public init(passed: Bool, failures: [GateFailure]) {
    self.passed = passed
    self.failures = failures
  }
}

extension CompareCommand {
  /// Lower-is-better cost metrics the regression gate watches. A `.real`
  /// positive (worse) median delta on one of these fails the gate. The
  /// workload-shape metrics (committed/diagnostic/elided frame counts) are
  /// deliberately excluded — they describe how much work the scenario did, not
  /// its cost, so they should not auto-fail a comparison. (Resolve-time cost,
  /// which has no aggregate metric of its own, is proxied here by
  /// `CPU seconds/frame`: resolve is the dominant per-frame phase.)
  public static let regressionWatchedMetrics: Set<String> = [
    "total CPU seconds",
    "CPU seconds/frame",
    "CPU seconds/diagnostic frame",
    "input latency p95 ms",
    "frame interval p50 ms",
    "completed drops",
    "cancelled frames",
  ]

  /// Punctuation/case-insensitive key so `--require-improvement` can name a
  /// metric as `cpu-seconds-per-frame`, `cpuSecondsPerFrame`, or
  /// `"CPU seconds/frame"` and still match.
  static func normalizedMetricName(_ name: String) -> String {
    String(name.lowercased().filter { $0.isLetter || $0.isNumber })
  }

  /// Evaluates the pass/fail gate over a variance-aware aggregate comparison.
  ///
  /// - A watched lower-is-better metric whose delta is a *real* regression
  ///   (verdict `.real` and a positive median delta beyond the noise band)
  ///   fails the gate.
  /// - Every metric named in `requireImprovement` must show a *real*
  ///   improvement (verdict `.real` and a negative median delta); otherwise the
  ///   gate fails. An unknown metric name is itself a failure, so a typo cannot
  ///   silently certify a non-existent win.
  ///
  /// `.withinNoise` and `.inconclusive` movements never fail the regression
  /// gate (the change is not a trustworthy regression) but also never satisfy a
  /// required improvement (the win is not trustworthy either).
  public static func evaluateGate(
    _ comparison: AggregateComparison,
    requireImprovement: [String] = []
  ) -> GateOutcome {
    var failures: [GateFailure] = []

    for metric in comparison.metrics where regressionWatchedMetrics.contains(metric.metric) {
      if metric.verdict == .real, metric.delta > 0 {
        failures.append(
          GateFailure(
            metric: metric.metric,
            reason:
              "real regression \(formatSignedValue(metric.delta)) "
              + "beyond noise band \(formatValue(metric.noiseBand))"
          )
        )
      }
    }

    for requested in requireImprovement {
      let target = normalizedMetricName(requested)
      guard
        let metric = comparison.metrics.first(where: {
          normalizedMetricName($0.metric) == target
        })
      else {
        failures.append(
          GateFailure(
            metric: requested,
            reason: "unknown metric — cannot certify an improvement"
          )
        )
        continue
      }
      if metric.verdict != .real || metric.delta >= 0 {
        failures.append(
          GateFailure(
            metric: metric.metric,
            reason:
              "required a real improvement, got \(metric.verdict.rawValue) "
              + "delta \(formatSignedValue(metric.delta))"
          )
        )
      }
    }

    return GateOutcome(passed: failures.isEmpty, failures: failures)
  }

  public static func formatGate(_ outcome: GateOutcome) -> String {
    guard !outcome.passed else {
      return "gate: PASS"
    }
    var lines = ["gate: FAIL"]
    for failure in outcome.failures {
      lines.append("  - \(failure.metric): \(failure.reason)")
    }
    return lines.joined(separator: "\n")
  }

  /// Loads a `PerfAggregateSummary` for the gate. The path may be the
  /// `aggregate-<scenario>-<mode>.json` file itself, or a directory containing
  /// exactly one such file (the artifact-root layout `run` writes).
  public static func loadAggregate(from path: String) throws -> PerfAggregateSummary {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
    guard exists else {
      throw PerfGateError.aggregateNotFound(path)
    }

    let aggregateURL: URL
    if isDirectory.boolValue {
      let entries = try fileManager.contentsOfDirectory(atPath: path)
      let aggregates =
        entries
        .filter { $0.hasPrefix("aggregate-") && $0.hasSuffix(".json") }
        .sorted()
      guard aggregates.count == 1, let only = aggregates.first else {
        throw PerfGateError.aggregateSelectionAmbiguous(path: path, found: aggregates.count)
      }
      aggregateURL = URL(fileURLWithPath: path, isDirectory: true)
        .appendingPathComponent(only)
    } else {
      aggregateURL = URL(fileURLWithPath: path)
    }

    let data = try Data(contentsOf: aggregateURL)
    return try JSONDecoder().decode(PerfAggregateSummary.self, from: data)
  }

  private static func formatValue(_ value: Double) -> String {
    String(format: "%.4f", value)
  }

  private static func formatSignedValue(_ value: Double) -> String {
    String(format: "%+.4f", value)
  }
}

public enum PerfGateError: Error, Equatable, CustomStringConvertible {
  case aggregateNotFound(String)
  case aggregateSelectionAmbiguous(path: String, found: Int)

  public var description: String {
    switch self {
    case .aggregateNotFound(let path):
      return "no aggregate summary at '\(path)'."
    case .aggregateSelectionAmbiguous(let path, let found):
      return
        "expected exactly one aggregate-*.json in '\(path)', found \(found). "
        + "Pass the aggregate file directly."
    }
  }
}
