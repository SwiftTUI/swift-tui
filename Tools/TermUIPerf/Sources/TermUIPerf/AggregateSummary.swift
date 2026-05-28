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
  public var iterationCount: Int
  public var totalCPUSeconds: PerfStat
  public var committedFrameCount: PerfStat
  public var cpuSecondsPerCommittedFrame: PerfStat
  public var inputToPresentLatencyP95Ms: PerfStat
  public var frameIntervalP50Ms: PerfStat

  public init(
    scenario: String,
    renderMode: String,
    iterationCount: Int,
    totalCPUSeconds: PerfStat,
    committedFrameCount: PerfStat,
    cpuSecondsPerCommittedFrame: PerfStat,
    inputToPresentLatencyP95Ms: PerfStat,
    frameIntervalP50Ms: PerfStat
  ) {
    self.scenario = scenario
    self.renderMode = renderMode
    self.iterationCount = iterationCount
    self.totalCPUSeconds = totalCPUSeconds
    self.committedFrameCount = committedFrameCount
    self.cpuSecondsPerCommittedFrame = cpuSecondsPerCommittedFrame
    self.inputToPresentLatencyP95Ms = inputToPresentLatencyP95Ms
    self.frameIntervalP50Ms = frameIntervalP50Ms
  }

  private enum CodingKeys: String, CodingKey {
    case scenario
    case renderMode = "render_mode"
    case iterationCount = "iteration_count"
    case totalCPUSeconds = "total_cpu_seconds"
    case committedFrameCount = "committed_frame_count"
    case cpuSecondsPerCommittedFrame = "cpu_seconds_per_committed_frame"
    case inputToPresentLatencyP95Ms = "input_to_present_latency_p95_ms"
    case frameIntervalP50Ms = "frame_interval_p50_ms"
  }
}

public enum AggregateReducer {
  /// Reduces per-iteration summaries into one aggregate. The `summaries` array
  /// must be non-empty; scenario/renderMode are taken from the first element.
  public static func reduce(_ summaries: [PerfSummary]) -> PerfAggregateSummary {
    precondition(!summaries.isEmpty, "AggregateReducer.reduce requires >= 1 summary")
    let first = summaries[0]
    return PerfAggregateSummary(
      scenario: first.scenario,
      renderMode: first.renderMode,
      iterationCount: summaries.count,
      totalCPUSeconds: PerfStat(values: summaries.map(\.totalCPUSeconds)),
      committedFrameCount: PerfStat(values: summaries.map { Double($0.committedFrameCount) }),
      cpuSecondsPerCommittedFrame: PerfStat(
        values: summaries.compactMap(\.cpuSecondsPerCommittedFrame)),
      inputToPresentLatencyP95Ms: PerfStat(
        values: summaries.compactMap(\.inputToPresentLatencyMs.p95)),
      frameIntervalP50Ms: PerfStat(values: summaries.compactMap(\.frameIntervalMs.p50)))
  }
}
