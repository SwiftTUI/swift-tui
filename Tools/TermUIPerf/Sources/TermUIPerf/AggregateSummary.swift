import Foundation

/// Cross-iteration summary statistics for a single scalar metric.
public struct PerfStat: Codable, Equatable, Sendable {
  public var sampleCount: Int
  public var median: Double
  public var mean: Double
  public var stddev: Double
  public var min: Double
  public var max: Double
  public var coefficientOfVariation: Double

  public init(
    sampleCount: Int,
    median: Double,
    mean: Double,
    stddev: Double,
    min: Double,
    max: Double,
    coefficientOfVariation: Double
  ) {
    self.sampleCount = sampleCount
    self.median = median
    self.mean = mean
    self.stddev = stddev
    self.min = min
    self.max = max
    self.coefficientOfVariation = coefficientOfVariation
  }

  /// Builds a stat from raw samples. Sample stddev (Bessel's correction) for
  /// `count > 1`, else `0`. CV is `0` when the mean is `0`.
  public init(values: [Double]) {
    let count = values.count
    guard count > 0 else {
      self.init(
        sampleCount: 0, median: 0, mean: 0, stddev: 0, min: 0, max: 0,
        coefficientOfVariation: 0)
      return
    }
    let sorted = values.sorted()
    let mean = values.reduce(0, +) / Double(count)
    let median: Double
    if count % 2 == 1 {
      median = sorted[count / 2]
    } else {
      median = (sorted[count / 2 - 1] + sorted[count / 2]) / 2
    }
    let stddev: Double
    if count > 1 {
      let sumSquares = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
      stddev = (sumSquares / Double(count - 1)).squareRoot()
    } else {
      stddev = 0
    }
    let cv = mean == 0 ? 0 : stddev / mean
    self.init(
      sampleCount: count,
      median: median,
      mean: mean,
      stddev: stddev,
      min: sorted.first ?? 0,
      max: sorted.last ?? 0,
      coefficientOfVariation: cv)
  }

  private enum CodingKeys: String, CodingKey {
    case sampleCount = "sample_count"
    case median
    case mean
    case stddev
    case min
    case max
    case coefficientOfVariation = "coefficient_of_variation"
  }
}

/// Cross-iteration aggregate over the headline metrics of N `PerfSummary`s.
public struct PerfAggregateSummary: Codable, Equatable, Sendable {
  public var scenario: String
  public var renderMode: String
  /// Whether the aggregated runs presented through the emission-visible lane
  /// (`SWIFTTUI_PERF_EMISSION=1`). The gate refuses to compare a lane-on
  /// aggregate against a lane-off one — they measure different pipelines.
  public var emissionLane: Bool
  /// The build configuration every member run was compiled with.
  public var configuration: String
  public var iterationCount: Int
  /// ISO-8601 instant this aggregate was written. Identity, not measurement:
  /// aggregate filenames are stable and overwrite in place, so without a stamp
  /// inside the file there is no way to tell a fresh aggregate from one a
  /// previous session left behind under the same name.
  ///
  /// `nil` when the aggregate was reduced rather than written by a run, which
  /// keeps `AggregateReducer` deterministic and its tests clock-free.
  public var generatedAt: String?
  public var totalCPUSeconds: PerfStat
  public var committedFrameCount: PerfStat
  public var diagnosticFrameCount: PerfStat
  public var elidedFrameCount: PerfStat
  public var cancelledFrameCount: PerfStat
  public var completedDropCount: PerfStat
  public var cpuSecondsPerCommittedFrame: PerfStat
  public var cpuSecondsPerDiagnosticFrame: PerfStat
  public var inputToPresentLatencyP95Ms: PerfStat
  public var frameIntervalP50Ms: PerfStat
  /// Runtime-stamped arrival→commit for the oldest input each frame answered.
  /// The scroll-latency headline, and the edge the gate watches: it is the
  /// wait a user on a queued notch actually experiences, and unlike the newest
  /// edge it moves when a backlog grows.
  public var inputToCommitP50Ms: PerfStat
  public var inputToCommitP95Ms: PerfStat
  public var inputToCommitP99Ms: PerfStat
  /// Bytes written per frame that moved the scene — the emission number the
  /// program's mitigation tiers exist to reduce.
  public var presentBytesPerMovingFrameMedian: PerfStat
  /// Rows realized per moving frame, over the iterations that armed the
  /// collection probes. Empty when the run did not arm them — which is what
  /// makes a milliseconds-only aggregate legible as such rather than as a
  /// collection that realized nothing.
  public var realizedRowsPerMovingFrameMedian: PerfStat
  /// List visible-layout derivations per moving frame, when armed.
  public var listLayoutDerivationsPerMovingFrameMedian: PerfStat
  public var pipelineP50Ms: PerfStat
  public var headPrepareP50Ms: PerfStat
  public var headGraphCheckpointCreateP50Ms: PerfStat
  public var headGraphCheckpointRestoreP50Ms: PerfStat
  public var headResolveCheckpointRestoreP50Ms: PerfStat
  public var headAnimationProcessResolvedTreeP50Ms: PerfStat
  public var headAnimationApplyInterpolationsP50Ms: PerfStat
  /// Cross-iteration stats for the run-total deterministic work counters
  /// (plan 2026-08-11-005 Stage 0), keyed by counter name (the `frames.tsv`
  /// column vocabulary). A deterministic lane shows `min == max` for every
  /// entry; spread here is itself a finding. `nil` for aggregates recorded
  /// before the counters existed.
  public var deterministicCounters: [String: PerfStat]?

  public init(
    scenario: String,
    renderMode: String,
    emissionLane: Bool = false,
    configuration: String = PerfBuildConfiguration.detected,
    iterationCount: Int,
    generatedAt: String? = nil,
    totalCPUSeconds: PerfStat,
    committedFrameCount: PerfStat,
    diagnosticFrameCount: PerfStat,
    elidedFrameCount: PerfStat,
    cancelledFrameCount: PerfStat,
    completedDropCount: PerfStat,
    cpuSecondsPerCommittedFrame: PerfStat,
    cpuSecondsPerDiagnosticFrame: PerfStat,
    inputToPresentLatencyP95Ms: PerfStat,
    frameIntervalP50Ms: PerfStat,
    inputToCommitP50Ms: PerfStat = PerfStat(values: []),
    inputToCommitP95Ms: PerfStat = PerfStat(values: []),
    inputToCommitP99Ms: PerfStat = PerfStat(values: []),
    presentBytesPerMovingFrameMedian: PerfStat = PerfStat(values: []),
    realizedRowsPerMovingFrameMedian: PerfStat = PerfStat(values: []),
    listLayoutDerivationsPerMovingFrameMedian: PerfStat = PerfStat(values: []),
    pipelineP50Ms: PerfStat = PerfStat(values: []),
    headPrepareP50Ms: PerfStat = PerfStat(values: []),
    headGraphCheckpointCreateP50Ms: PerfStat = PerfStat(values: []),
    headGraphCheckpointRestoreP50Ms: PerfStat = PerfStat(values: []),
    headResolveCheckpointRestoreP50Ms: PerfStat = PerfStat(values: []),
    headAnimationProcessResolvedTreeP50Ms: PerfStat = PerfStat(values: []),
    headAnimationApplyInterpolationsP50Ms: PerfStat = PerfStat(values: []),
    deterministicCounters: [String: PerfStat]? = nil
  ) {
    self.scenario = scenario
    self.renderMode = renderMode
    self.emissionLane = emissionLane
    self.configuration = configuration
    self.iterationCount = iterationCount
    self.generatedAt = generatedAt
    self.totalCPUSeconds = totalCPUSeconds
    self.committedFrameCount = committedFrameCount
    self.diagnosticFrameCount = diagnosticFrameCount
    self.elidedFrameCount = elidedFrameCount
    self.cancelledFrameCount = cancelledFrameCount
    self.completedDropCount = completedDropCount
    self.cpuSecondsPerCommittedFrame = cpuSecondsPerCommittedFrame
    self.cpuSecondsPerDiagnosticFrame = cpuSecondsPerDiagnosticFrame
    self.inputToPresentLatencyP95Ms = inputToPresentLatencyP95Ms
    self.frameIntervalP50Ms = frameIntervalP50Ms
    self.inputToCommitP50Ms = inputToCommitP50Ms
    self.inputToCommitP95Ms = inputToCommitP95Ms
    self.inputToCommitP99Ms = inputToCommitP99Ms
    self.presentBytesPerMovingFrameMedian = presentBytesPerMovingFrameMedian
    self.realizedRowsPerMovingFrameMedian = realizedRowsPerMovingFrameMedian
    self.listLayoutDerivationsPerMovingFrameMedian = listLayoutDerivationsPerMovingFrameMedian
    self.pipelineP50Ms = pipelineP50Ms
    self.headPrepareP50Ms = headPrepareP50Ms
    self.headGraphCheckpointCreateP50Ms = headGraphCheckpointCreateP50Ms
    self.headGraphCheckpointRestoreP50Ms = headGraphCheckpointRestoreP50Ms
    self.headResolveCheckpointRestoreP50Ms = headResolveCheckpointRestoreP50Ms
    self.headAnimationProcessResolvedTreeP50Ms = headAnimationProcessResolvedTreeP50Ms
    self.headAnimationApplyInterpolationsP50Ms = headAnimationApplyInterpolationsP50Ms
    self.deterministicCounters = deterministicCounters
  }

  private enum CodingKeys: String, CodingKey {
    case scenario
    case renderMode = "render_mode"
    case emissionLane = "emission_lane"
    case configuration
    case iterationCount = "iteration_count"
    case generatedAt = "generated_at"
    case totalCPUSeconds = "total_cpu_seconds"
    case committedFrameCount = "committed_frame_count"
    case diagnosticFrameCount = "diagnostic_frame_count"
    case elidedFrameCount = "elided_frame_count"
    case cancelledFrameCount = "cancelled_frame_count"
    case completedDropCount = "completed_drop_count"
    case cpuSecondsPerCommittedFrame = "cpu_seconds_per_committed_frame"
    case cpuSecondsPerDiagnosticFrame = "cpu_seconds_per_diagnostic_frame"
    case inputToPresentLatencyP95Ms = "input_to_present_latency_p95_ms"
    case frameIntervalP50Ms = "frame_interval_p50_ms"
    case inputToCommitP50Ms = "input_to_commit_p50_ms"
    case inputToCommitP95Ms = "input_to_commit_p95_ms"
    case inputToCommitP99Ms = "input_to_commit_p99_ms"
    case presentBytesPerMovingFrameMedian = "present_bytes_per_moving_frame_median"
    case realizedRowsPerMovingFrameMedian = "realized_rows_per_moving_frame_median"
    case listLayoutDerivationsPerMovingFrameMedian =
      "list_layout_derivations_per_moving_frame_median"
    case pipelineP50Ms = "pipeline_p50_ms"
    case headPrepareP50Ms = "head_prepare_p50_ms"
    case headGraphCheckpointCreateP50Ms = "head_graph_checkpoint_create_p50_ms"
    case headGraphCheckpointRestoreP50Ms = "head_graph_checkpoint_restore_p50_ms"
    case headResolveCheckpointRestoreP50Ms = "head_resolve_checkpoint_restore_p50_ms"
    case headAnimationProcessResolvedTreeP50Ms =
      "head_animation_process_resolved_tree_p50_ms"
    case headAnimationApplyInterpolationsP50Ms =
      "head_animation_apply_interpolations_p50_ms"
    case deterministicCounters = "deterministic_counters"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      scenario: try container.decode(String.self, forKey: .scenario),
      renderMode: try container.decode(String.self, forKey: .renderMode),
      // decodeIfPresent: an aggregate recorded before the lane existed is a
      // valid lane-off baseline.
      emissionLane: try container.decodeIfPresent(Bool.self, forKey: .emissionLane) ?? false,
      configuration: try container.decodeIfPresent(String.self, forKey: .configuration)
        ?? PerfBuildConfiguration.detected,
      iterationCount: try container.decode(Int.self, forKey: .iterationCount),
      generatedAt: try container.decodeIfPresent(String.self, forKey: .generatedAt),
      totalCPUSeconds: try container.decode(PerfStat.self, forKey: .totalCPUSeconds),
      committedFrameCount: try container.decode(PerfStat.self, forKey: .committedFrameCount),
      diagnosticFrameCount: try container.decode(
        PerfStat.self,
        forKey: .diagnosticFrameCount
      ),
      elidedFrameCount: try container.decode(PerfStat.self, forKey: .elidedFrameCount),
      cancelledFrameCount: try container.decode(PerfStat.self, forKey: .cancelledFrameCount),
      completedDropCount: try container.decode(PerfStat.self, forKey: .completedDropCount),
      cpuSecondsPerCommittedFrame: try container.decode(
        PerfStat.self,
        forKey: .cpuSecondsPerCommittedFrame
      ),
      cpuSecondsPerDiagnosticFrame: try container.decode(
        PerfStat.self,
        forKey: .cpuSecondsPerDiagnosticFrame
      ),
      inputToPresentLatencyP95Ms: try container.decode(
        PerfStat.self,
        forKey: .inputToPresentLatencyP95Ms
      ),
      frameIntervalP50Ms: try container.decode(PerfStat.self, forKey: .frameIntervalP50Ms),
      // decodeIfPresent, like every metric added after the format shipped: an
      // aggregate recorded before this program existed is still a valid
      // baseline to compare against, it simply has nothing to say about these.
      // `compare` reports such one-sided metrics and never gates them.
      inputToCommitP50Ms: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .inputToCommitP50Ms
      ) ?? PerfStat(values: []),
      inputToCommitP95Ms: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .inputToCommitP95Ms
      ) ?? PerfStat(values: []),
      inputToCommitP99Ms: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .inputToCommitP99Ms
      ) ?? PerfStat(values: []),
      presentBytesPerMovingFrameMedian: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .presentBytesPerMovingFrameMedian
      ) ?? PerfStat(values: []),
      realizedRowsPerMovingFrameMedian: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .realizedRowsPerMovingFrameMedian
      ) ?? PerfStat(values: []),
      listLayoutDerivationsPerMovingFrameMedian: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .listLayoutDerivationsPerMovingFrameMedian
      ) ?? PerfStat(values: []),
      pipelineP50Ms: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .pipelineP50Ms
      ) ?? PerfStat(values: []),
      headPrepareP50Ms: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .headPrepareP50Ms
      ) ?? PerfStat(values: []),
      headGraphCheckpointCreateP50Ms: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .headGraphCheckpointCreateP50Ms
      ) ?? PerfStat(values: []),
      headGraphCheckpointRestoreP50Ms: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .headGraphCheckpointRestoreP50Ms
      ) ?? PerfStat(values: []),
      headResolveCheckpointRestoreP50Ms: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .headResolveCheckpointRestoreP50Ms
      ) ?? PerfStat(values: []),
      headAnimationProcessResolvedTreeP50Ms: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .headAnimationProcessResolvedTreeP50Ms
      ) ?? PerfStat(values: []),
      headAnimationApplyInterpolationsP50Ms: try container.decodeIfPresent(
        PerfStat.self,
        forKey: .headAnimationApplyInterpolationsP50Ms
      ) ?? PerfStat(values: []),
      deterministicCounters: try container.decodeIfPresent(
        [String: PerfStat].self,
        forKey: .deterministicCounters
      )
    )
  }
}

public enum AggregateReducer {
  /// Reduces per-iteration summaries into one aggregate. The `summaries` array
  /// must be non-empty; scenario/renderMode are taken from the first element.
  /// A per-metric `PerfStat.sampleCount` may be less than `iterationCount` when
  /// that optional metric was absent for some iterations (nils are dropped).
  public static func reduce(_ summaries: [PerfSummary]) -> PerfAggregateSummary {
    precondition(!summaries.isEmpty, "AggregateReducer.reduce requires >= 1 summary")
    let first = summaries[0]
    return PerfAggregateSummary(
      scenario: first.scenario,
      renderMode: first.renderMode,
      emissionLane: first.emissionLane,
      configuration: first.configuration,
      iterationCount: summaries.count,
      totalCPUSeconds: PerfStat(values: summaries.map(\.totalCPUSeconds)),
      committedFrameCount: PerfStat(values: summaries.map { Double($0.committedFrameCount) }),
      diagnosticFrameCount: PerfStat(values: summaries.map { Double($0.diagnosticFrameCount) }),
      elidedFrameCount: PerfStat(values: summaries.map { Double($0.elidedFrameCount) }),
      cancelledFrameCount: PerfStat(values: summaries.map { Double($0.cancelledFrameCount) }),
      completedDropCount: PerfStat(values: summaries.map { Double($0.completedDropCount) }),
      cpuSecondsPerCommittedFrame: PerfStat(
        values: summaries.compactMap(\.cpuSecondsPerCommittedFrame)),
      cpuSecondsPerDiagnosticFrame: PerfStat(
        values: summaries.compactMap(\.cpuSecondsPerDiagnosticFrame)),
      inputToPresentLatencyP95Ms: PerfStat(
        values: summaries.compactMap(\.inputToPresentLatencyMs.p95)),
      frameIntervalP50Ms: PerfStat(values: summaries.compactMap(\.frameIntervalMs.p50)),
      inputToCommitP50Ms: PerfStat(values: summaries.compactMap(\.inputToCommitFirstMs.p50)),
      inputToCommitP95Ms: PerfStat(values: summaries.compactMap(\.inputToCommitFirstMs.p95)),
      inputToCommitP99Ms: PerfStat(values: summaries.compactMap(\.inputToCommitFirstMs.p99)),
      presentBytesPerMovingFrameMedian: PerfStat(
        values: summaries.compactMap(\.presentBytesPerMovingFrame)),
      realizedRowsPerMovingFrameMedian: PerfStat(
        values: summaries.compactMap(\.realizedRowsPerMovingFrame)),
      listLayoutDerivationsPerMovingFrameMedian: PerfStat(
        values: summaries.compactMap(\.listLayoutDerivationsPerMovingFrame)),
      pipelineP50Ms: PerfStat(values: summaries.compactMap(\.pipelineMs.p50)),
      headPrepareP50Ms: PerfStat(values: summaries.compactMap(\.headPrepareMs.p50)),
      headGraphCheckpointCreateP50Ms: PerfStat(
        values: summaries.compactMap(\.headGraphCheckpointCreateMs.p50)),
      headGraphCheckpointRestoreP50Ms: PerfStat(
        values: summaries.compactMap(\.headGraphCheckpointRestoreMs.p50)),
      headResolveCheckpointRestoreP50Ms: PerfStat(
        values: summaries.compactMap(\.headResolveCheckpointRestoreMs.p50)),
      headAnimationProcessResolvedTreeP50Ms: PerfStat(
        values: summaries.compactMap(\.headAnimationProcessResolvedTreeMs.p50)),
      headAnimationApplyInterpolationsP50Ms: PerfStat(
        values: summaries.compactMap(\.headAnimationApplyInterpolationsMs.p50)),
      deterministicCounters: reduceDeterministicCounters(summaries))
  }

  /// One `PerfStat` per counter name over the iterations that recorded it.
  /// `nil` when no iteration carried counters at all (pre-counter artifacts).
  private static func reduceDeterministicCounters(
    _ summaries: [PerfSummary]
  ) -> [String: PerfStat]? {
    let perIteration = summaries.compactMap { $0.deterministicCounters?.valuesByName }
    guard !perIteration.isEmpty else {
      return nil
    }
    var stats: [String: PerfStat] = [:]
    for name in Set(perIteration.flatMap(\.keys)) {
      stats[name] = PerfStat(
        values: perIteration.compactMap { $0[name] }.map(Double.init)
      )
    }
    return stats
  }
}

extension AggregateReducer {
  public static func format(_ aggregate: PerfAggregateSummary) -> String {
    let laneSuffix = aggregate.emissionLane ? " [emission lane]" : ""
    var lines = [
      "scenario: \(aggregate.scenario) "
        + "(\(aggregate.renderMode), n=\(aggregate.iterationCount))\(laneSuffix)"
    ]
    lines.append(line("total CPU seconds", aggregate.totalCPUSeconds))
    lines.append(line("committed frames", aggregate.committedFrameCount))
    lines.append(line("diagnostic frames", aggregate.diagnosticFrameCount))
    lines.append(line("elided frames", aggregate.elidedFrameCount))
    lines.append(line("cancelled frames", aggregate.cancelledFrameCount))
    lines.append(line("completed drops", aggregate.completedDropCount))
    lines.append(line("CPU seconds/frame", aggregate.cpuSecondsPerCommittedFrame))
    lines.append(line("CPU seconds/diagnostic frame", aggregate.cpuSecondsPerDiagnosticFrame))
    lines.append(line("input latency p95 ms", aggregate.inputToPresentLatencyP95Ms))
    lines.append(line("frame interval p50 ms", aggregate.frameIntervalP50Ms))
    lines.append(line("input to commit p50 ms", aggregate.inputToCommitP50Ms))
    lines.append(line("input to commit p95 ms", aggregate.inputToCommitP95Ms))
    lines.append(line("input to commit p99 ms", aggregate.inputToCommitP99Ms))
    lines.append(
      line("present bytes/moving frame", aggregate.presentBytesPerMovingFrameMedian)
    )
    lines.append(
      line("realized rows/moving frame", aggregate.realizedRowsPerMovingFrameMedian)
    )
    lines.append(
      line(
        "list layout derivations/moving frame",
        aggregate.listLayoutDerivationsPerMovingFrameMedian
      )
    )
    lines.append(line("pipeline p50 ms", aggregate.pipelineP50Ms))
    lines.append(line("head prepare p50 ms", aggregate.headPrepareP50Ms))
    lines.append(
      line("head graph checkpoint create p50 ms", aggregate.headGraphCheckpointCreateP50Ms)
    )
    lines.append(
      line("head graph checkpoint restore p50 ms", aggregate.headGraphCheckpointRestoreP50Ms)
    )
    lines.append(
      line("head resolve checkpoint restore p50 ms", aggregate.headResolveCheckpointRestoreP50Ms)
    )
    lines.append(
      line(
        "head animation process tree p50 ms",
        aggregate.headAnimationProcessResolvedTreeP50Ms
      )
    )
    lines.append(
      line(
        "head animation apply interpolations p50 ms",
        aggregate.headAnimationApplyInterpolationsP50Ms
      )
    )
    if let counters = aggregate.deterministicCounters, !counters.isEmpty {
      lines.append("deterministic counters (run totals):")
      for name in counters.keys.sorted() {
        guard let stat = counters[name] else {
          continue
        }
        lines.append("  \(name): \(counterLine(stat))")
      }
    }
    return lines.joined(separator: "\n")
  }

  /// `1234 (stable, n=20)` when every iteration agreed, else the spread —
  /// the deterministic lanes read `stable`; anything else is drift worth
  /// seeing before the Stage-3 ratchet formalizes it as a failure.
  private static func counterLine(_ stat: PerfStat) -> String {
    guard stat.sampleCount > 0 else {
      return "n/a (0 samples)"
    }
    if stat.min == stat.max {
      return "\(Int(stat.min)) (stable, n=\(stat.sampleCount))"
    }
    return
      "median \(Int(stat.median)) [\(Int(stat.min))..\(Int(stat.max))] "
      + "(VARIES, n=\(stat.sampleCount))"
  }

  private static func line(_ label: String, _ stat: PerfStat) -> String {
    guard stat.sampleCount > 0 else {
      return "\(label): n/a (0 samples)"
    }
    let median = String(format: "%.4f", stat.median)
    let stddev = String(format: "%.4f", stat.stddev)
    let cv = String(format: "%.1f", stat.coefficientOfVariation * 100)
    return "\(label): \(median) +/- \(stddev) (CV \(cv)%)"
  }
}
