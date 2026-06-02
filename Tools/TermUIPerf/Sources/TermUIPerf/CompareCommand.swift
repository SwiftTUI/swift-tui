import Foundation

public enum CompareClassification: String, Codable, Equatable, Sendable {
  case clearWin = "clear win"
  case latencyWinWithCPUCost = "latency win with CPU cost"
  case cpuRegression = "CPU regression"
  case noMeaningfulMovement = "no meaningful movement"
  case inconclusive = "inconclusive due to missing data"
}

public struct SummaryComparison: Equatable, Sendable {
  public var base: PerfSummary
  public var candidate: PerfSummary
  public var classification: CompareClassification
  public var inputLatencyP50Delta: Double?
  public var inputLatencyP95Delta: Double?
  public var totalCPUSecondsDelta: Double
  public var cpuSecondsPerCommittedFrameDelta: Double?
  public var cpuSecondsPerDiagnosticFrameDelta: Double?
  public var mainActorBlockedRatioDelta: Double?
  public var workerLayoutEnqueueP95Delta: Double?
  public var workerLayoutComputeP95Delta: Double?
  public var diagnosticFrameCountDelta: Int
  public var elidedFrameCountDelta: Int
  public var cancelledFrameCountDelta: Int
  public var completedDropCountDelta: Int
  public var customLayoutFallbackCountDelta: Int
  public var layoutDependentMainActorFallbackCountDelta: Int
}

public enum CompareCommand {
  public static func compare(_ config: PerfCompareConfig) throws -> SummaryComparison {
    try compare(
      baseRunDirectory: URL(fileURLWithPath: config.baseRunDirectory, isDirectory: true),
      candidateRunDirectory: URL(fileURLWithPath: config.candidateRunDirectory, isDirectory: true)
    )
  }

  public static func compare(
    baseRunDirectory: URL,
    candidateRunDirectory: URL
  ) throws -> SummaryComparison {
    let base = try loadSummary(from: baseRunDirectory)
    let candidate = try loadSummary(from: candidateRunDirectory)
    return compare(base: base, candidate: candidate)
  }

  public static func compare(base: PerfSummary, candidate: PerfSummary) -> SummaryComparison {
    let latencyP50Delta = delta(
      candidate.inputToPresentLatencyMs.p50,
      base.inputToPresentLatencyMs.p50
    )
    let latencyP95Delta = delta(
      candidate.inputToPresentLatencyMs.p95,
      base.inputToPresentLatencyMs.p95
    )
    let totalCPUDelta = candidate.totalCPUSeconds - base.totalCPUSeconds
    let cpuPerFrameDelta = delta(
      candidate.cpuSecondsPerCommittedFrame,
      base.cpuSecondsPerCommittedFrame
    )
    let cpuPerDiagnosticFrameDelta = delta(
      candidate.cpuSecondsPerDiagnosticFrame,
      base.cpuSecondsPerDiagnosticFrame
    )
    let mainActorBlockedDelta = delta(
      candidate.mainActorBlockedRatio,
      base.mainActorBlockedRatio
    )

    let comparison = SummaryComparison(
      base: base,
      candidate: candidate,
      classification: classify(
        latencyP95Delta: latencyP95Delta,
        totalCPUSecondsDelta: totalCPUDelta
      ),
      inputLatencyP50Delta: latencyP50Delta,
      inputLatencyP95Delta: latencyP95Delta,
      totalCPUSecondsDelta: totalCPUDelta,
      cpuSecondsPerCommittedFrameDelta: cpuPerFrameDelta,
      cpuSecondsPerDiagnosticFrameDelta: cpuPerDiagnosticFrameDelta,
      mainActorBlockedRatioDelta: mainActorBlockedDelta,
      workerLayoutEnqueueP95Delta: delta(
        candidate.workerLayoutEnqueueMs.p95,
        base.workerLayoutEnqueueMs.p95
      ),
      workerLayoutComputeP95Delta: delta(
        candidate.workerLayoutComputeMs.p95,
        base.workerLayoutComputeMs.p95
      ),
      diagnosticFrameCountDelta: candidate.diagnosticFrameCount - base.diagnosticFrameCount,
      elidedFrameCountDelta: candidate.elidedFrameCount - base.elidedFrameCount,
      cancelledFrameCountDelta: candidate.cancelledFrameCount - base.cancelledFrameCount,
      completedDropCountDelta: candidate.completedDropCount - base.completedDropCount,
      customLayoutFallbackCountDelta: candidate.customLayoutFallbackCount
        - base.customLayoutFallbackCount,
      layoutDependentMainActorFallbackCountDelta: candidate.layoutDependentMainActorFallbackCount
        - base.layoutDependentMainActorFallbackCount
    )
    return comparison
  }

  public static func format(_ comparison: SummaryComparison) -> String {
    """
    scenario: \(comparison.base.scenario)
    base mode: \(comparison.base.renderMode)
    candidate mode: \(comparison.candidate.renderMode)
    classification: \(comparison.classification.rawValue)
    input latency p50 ms: \(format(comparison.base.inputToPresentLatencyMs.p50)) -> \(format(comparison.candidate.inputToPresentLatencyMs.p50)) (\(formatDelta(comparison.inputLatencyP50Delta)))
    input latency p95 ms: \(format(comparison.base.inputToPresentLatencyMs.p95)) -> \(format(comparison.candidate.inputToPresentLatencyMs.p95)) (\(formatDelta(comparison.inputLatencyP95Delta)))
    total CPU seconds: \(format(comparison.base.totalCPUSeconds)) -> \(format(comparison.candidate.totalCPUSeconds)) (\(formatDelta(comparison.totalCPUSecondsDelta)))
    CPU seconds/frame: \(format(comparison.base.cpuSecondsPerCommittedFrame)) -> \(format(comparison.candidate.cpuSecondsPerCommittedFrame)) (\(formatDelta(comparison.cpuSecondsPerCommittedFrameDelta)))
    CPU seconds/diagnostic frame: \(format(comparison.base.cpuSecondsPerDiagnosticFrame)) -> \(format(comparison.candidate.cpuSecondsPerDiagnosticFrame)) (\(formatDelta(comparison.cpuSecondsPerDiagnosticFrameDelta)))
    main-actor blocked ratio: \(format(comparison.base.mainActorBlockedRatio)) -> \(format(comparison.candidate.mainActorBlockedRatio)) (\(formatDelta(comparison.mainActorBlockedRatioDelta)))
    worker layout enqueue p95 ms: \(format(comparison.base.workerLayoutEnqueueMs.p95)) -> \(format(comparison.candidate.workerLayoutEnqueueMs.p95)) (\(formatDelta(comparison.workerLayoutEnqueueP95Delta)))
    worker layout compute p95 ms: \(format(comparison.base.workerLayoutComputeMs.p95)) -> \(format(comparison.candidate.workerLayoutComputeMs.p95)) (\(formatDelta(comparison.workerLayoutComputeP95Delta)))
    diagnostic frames: \(comparison.base.diagnosticFrameCount) -> \(comparison.candidate.diagnosticFrameCount) (\(formatSigned(comparison.diagnosticFrameCountDelta)))
    elided frames: \(comparison.base.elidedFrameCount) -> \(comparison.candidate.elidedFrameCount) (\(formatSigned(comparison.elidedFrameCountDelta)))
    cancelled frames: \(comparison.base.cancelledFrameCount) -> \(comparison.candidate.cancelledFrameCount) (\(formatSigned(comparison.cancelledFrameCountDelta)))
    completed drops: \(comparison.base.completedDropCount) -> \(comparison.candidate.completedDropCount) (\(formatSigned(comparison.completedDropCountDelta)))
    custom layout fallbacks: \(comparison.base.customLayoutFallbackCount) -> \(comparison.candidate.customLayoutFallbackCount) (\(formatSigned(comparison.customLayoutFallbackCountDelta)))
    layout-dependent main-actor fallbacks: \(comparison.base.layoutDependentMainActorFallbackCount) -> \(comparison.candidate.layoutDependentMainActorFallbackCount) (\(formatSigned(comparison.layoutDependentMainActorFallbackCountDelta)))
    """
  }

  private static func loadSummary(from runDirectory: URL) throws -> PerfSummary {
    let summaryURL =
      runDirectory.lastPathComponent == "summary.json"
      ? runDirectory
      : runDirectory.appendingPathComponent("summary.json")
    let data = try Data(contentsOf: summaryURL)
    return try JSONDecoder().decode(PerfSummary.self, from: data)
  }

  private static func classify(
    latencyP95Delta: Double?,
    totalCPUSecondsDelta: Double
  ) -> CompareClassification {
    let latencyImproved = latencyP95Delta.map { $0 < -0.5 } ?? false
    let latencyFlat = latencyP95Delta.map { abs($0) <= 0.5 } ?? true
    let cpuRegressed = totalCPUSecondsDelta > 0.01
    let cpuImproved = totalCPUSecondsDelta < -0.01
    let cpuSameOrBetter = totalCPUSecondsDelta <= 0.01

    if latencyP95Delta == nil {
      if cpuImproved {
        return .clearWin
      }
      if cpuRegressed {
        return .cpuRegression
      }
      return .noMeaningfulMovement
    }

    if latencyImproved && cpuSameOrBetter {
      return .clearWin
    }
    if latencyImproved && cpuRegressed {
      return .latencyWinWithCPUCost
    }
    if latencyFlat && cpuRegressed {
      return .cpuRegression
    }
    return .noMeaningfulMovement
  }

  private static func delta(_ candidate: Double?, _ base: Double?) -> Double? {
    guard let candidate, let base else {
      return nil
    }
    return candidate - base
  }

  private static func format(_ value: Double?) -> String {
    guard let value else {
      return "-"
    }
    return format(value)
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.6f", value)
  }

  private static func formatDelta(_ value: Double?) -> String {
    guard let value else {
      return "-"
    }
    return formatSigned(value)
  }

  private static func formatSigned(_ value: Double) -> String {
    let prefix = value >= 0 ? "+" : ""
    return "\(prefix)\(format(value))"
  }

  private static func formatSigned(_ value: Int) -> String {
    value >= 0 ? "+\(value)" : "\(value)"
  }
}
