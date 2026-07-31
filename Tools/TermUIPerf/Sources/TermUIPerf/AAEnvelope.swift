import Foundation

/// What this machine's noise looks like: the per-metric spread observed between
/// two identical, back-to-back runs of the same scenario.
///
/// An A/B verdict without one of these is an opinion. `compareAggregates`
/// already reports a `noiseBand` from cross-iteration stddev, but that is the
/// spread *within* a run — it says nothing about the drift between two runs
/// minutes apart, which is where this repo has repeatedly been fooled (a
/// text-input p95 that moved ±40 ms between sessions and read as a real
/// regression until it was paired tightly).
///
/// The honest form of the house's "±2–4 % is noise" rule of thumb is to record
/// the number rather than encode it: the envelope is machine-, configuration-
/// and scenario-dependent, and a constant baked into `PerfGate` would be right
/// on the machine it was measured on and wrong everywhere else.
public struct PerfAAEnvelope: Codable, Equatable, Sendable {
  public var scenario: String
  public var renderMode: String
  /// Iterations in *each* of the two passes.
  public var iterations: Int
  public var generatedAt: String?
  /// Metric name → the relative delta observed between the two identical runs,
  /// as a non-negative fraction (`0.021` = 2.1 %). Keys match the metric names
  /// ``CompareCommand/compareAggregates(base:candidate:sigma:)`` produces,
  /// because that is exactly where they come from.
  public var relativeDeltas: [String: Double]

  public init(
    scenario: String,
    renderMode: String,
    iterations: Int,
    generatedAt: String? = nil,
    relativeDeltas: [String: Double]
  ) {
    self.scenario = scenario
    self.renderMode = renderMode
    self.iterations = iterations
    self.generatedAt = generatedAt
    self.relativeDeltas = relativeDeltas
  }

  /// The recorded envelope for one metric, or `nil` when this A/A pair could
  /// not express one.
  public func envelope(for metric: String) -> Double? {
    relativeDeltas[metric]
  }

  /// Records the envelope from two aggregates of the same scenario and mode.
  ///
  /// Built by running the real comparator over the pair, so the metric names
  /// are the comparator's own rather than a parallel list that could drift out
  /// of step with it — the annotation later looks metrics up by name, and a
  /// name that does not match reads as "no envelope recorded", which is the
  /// one failure this design should not be able to produce silently.
  ///
  /// Two metrics are deliberately dropped:
  ///
  /// - `oneSided` metrics, where one run measured something the other did not.
  ///   Their delta is an artifact of format history, not of noise.
  /// - metrics whose base median is `0` and whose delta is not, because a
  ///   relative envelope around zero is not expressible. Absolute-only metrics
  ///   are better read from the aggregate itself than annotated with a ratio.
  public static func record(
    runA: PerfAggregateSummary,
    runB: PerfAggregateSummary,
    iterations: Int,
    generatedAt: String? = nil
  ) -> PerfAAEnvelope {
    let comparison = CompareCommand.compareAggregates(base: runA, candidate: runB)
    var relativeDeltas: [String: Double] = [:]
    for metric in comparison.metrics where !metric.oneSided {
      guard metric.baseMedian != 0 else {
        if metric.delta == 0 {
          relativeDeltas[metric.metric] = 0
        }
        continue
      }
      relativeDeltas[metric.metric] = abs(metric.delta) / abs(metric.baseMedian)
    }
    return PerfAAEnvelope(
      scenario: runA.scenario,
      renderMode: runA.renderMode,
      iterations: iterations,
      generatedAt: generatedAt,
      relativeDeltas: relativeDeltas
    )
  }

  /// The filename an envelope is written to and looked up by, beside the
  /// aggregates it describes.
  public static func fileName(scenario: String, renderMode: String) -> String {
    "aa-envelope-\(scenario)-\(renderMode).json"
  }

  private enum CodingKeys: String, CodingKey {
    case scenario
    case renderMode = "render_mode"
    case iterations
    case generatedAt = "generated_at"
    case relativeDeltas = "relative_deltas"
  }
}
