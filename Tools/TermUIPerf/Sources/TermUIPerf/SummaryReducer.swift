import Foundation

public struct PerfFrameRecord: Equatable, Sendable {
  public var frameNumber: Int
  public var presentedAtSeconds: Double?
  public var totalMs: Double?
  public var workerLayoutEnqueueMs: Double?
  public var workerLayoutComputeMs: Double?
  public var workerRasterEnqueueMs: Double?
  public var workerRasterComputeMs: Double?
  public var mainActorBlockedMs: Double?
  public var mainActorSuspendedMs: Double?
  public var presentationDurationMs: Double?
  public var elided: Bool
  public var customLayoutFallbacks: Int
  public var layoutDependentMainActorFallbacks: Int
  public var tailJobState: String
  public var staleFramePolicy: String
  public var dropDecision: String
  public var cancelledRenderCount: Int

  public init(
    frameNumber: Int,
    presentedAtSeconds: Double? = nil,
    totalMs: Double? = nil,
    workerLayoutEnqueueMs: Double? = nil,
    workerLayoutComputeMs: Double? = nil,
    workerRasterEnqueueMs: Double? = nil,
    workerRasterComputeMs: Double? = nil,
    mainActorBlockedMs: Double? = nil,
    mainActorSuspendedMs: Double? = nil,
    presentationDurationMs: Double? = nil,
    elided: Bool = false,
    customLayoutFallbacks: Int = 0,
    layoutDependentMainActorFallbacks: Int = 0,
    tailJobState: String = "completed",
    staleFramePolicy: String = "commit_ordered",
    dropDecision: String = "commit_ordered",
    cancelledRenderCount: Int = 0
  ) {
    self.frameNumber = frameNumber
    self.presentedAtSeconds = presentedAtSeconds
    self.totalMs = totalMs
    self.workerLayoutEnqueueMs = workerLayoutEnqueueMs
    self.workerLayoutComputeMs = workerLayoutComputeMs
    self.workerRasterEnqueueMs = workerRasterEnqueueMs
    self.workerRasterComputeMs = workerRasterComputeMs
    self.mainActorBlockedMs = mainActorBlockedMs
    self.mainActorSuspendedMs = mainActorSuspendedMs
    self.presentationDurationMs = presentationDurationMs
    self.elided = elided
    self.customLayoutFallbacks = customLayoutFallbacks
    self.layoutDependentMainActorFallbacks = layoutDependentMainActorFallbacks
    self.tailJobState = tailJobState
    self.staleFramePolicy = staleFramePolicy
    self.dropDecision = dropDecision
    self.cancelledRenderCount = cancelledRenderCount
  }
}

public struct PerfDistribution: Codable, Equatable, Sendable {
  public var count: Int
  public var p50: Double?
  public var p95: Double?
  public var p99: Double?

  public init(values: [Double]) {
    let sortedValues = values.sorted()
    count = sortedValues.count
    p50 = Self.percentile(0.50, in: sortedValues)
    p95 = Self.percentile(0.95, in: sortedValues)
    p99 = Self.percentile(0.99, in: sortedValues)
  }

  public init(count: Int, p50: Double?, p95: Double?, p99: Double?) {
    self.count = count
    self.p50 = p50
    self.p95 = p95
    self.p99 = p99
  }

  private static func percentile(_ percentile: Double, in sortedValues: [Double]) -> Double? {
    guard !sortedValues.isEmpty else {
      return nil
    }
    guard sortedValues.count > 1 else {
      return sortedValues[0]
    }

    let position = percentile * Double(sortedValues.count - 1)
    let lowerIndex = Int(position.rounded(.down))
    let upperIndex = Int(position.rounded(.up))
    guard lowerIndex != upperIndex else {
      return sortedValues[lowerIndex]
    }

    let weight = position - Double(lowerIndex)
    return sortedValues[lowerIndex] * (1 - weight) + sortedValues[upperIndex] * weight
  }
}

public struct PerfSummary: Codable, Equatable, Sendable {
  public var scenario: String
  public var renderMode: String
  public var iterationCount: Int
  public var committedFrameCount: Int
  public var diagnosticFrameCount: Int
  public var skippedFrameCount: Int
  public var elidedFrameCount: Int
  public var cancelledFrameCount: Int
  public var inputToPresentLatencyMs: PerfDistribution
  public var inputToSettledLatencyMs: PerfDistribution
  public var frameIntervalMs: PerfDistribution
  public var totalCPUSeconds: Double
  public var cpuSecondsPerCommittedFrame: Double?
  public var cpuSecondsPerDiagnosticFrame: Double?
  public var cpuSecondsPerInputEvent: Double?
  public var mainActorBlockedRatio: Double?
  public var mainActorSuspendedRatio: Double?
  public var workerLayoutEnqueueMs: PerfDistribution
  public var workerLayoutComputeMs: PerfDistribution
  public var workerRasterEnqueueMs: PerfDistribution
  public var workerRasterComputeMs: PerfDistribution
  public var presentationDurationMs: PerfDistribution
  public var completedDropCount: Int
  public var customLayoutFallbackCount: Int
  public var layoutDependentMainActorFallbackCount: Int

  public init(
    scenario: String,
    renderMode: String,
    iterationCount: Int,
    committedFrameCount: Int,
    diagnosticFrameCount: Int,
    skippedFrameCount: Int,
    elidedFrameCount: Int,
    cancelledFrameCount: Int,
    inputToPresentLatencyMs: PerfDistribution,
    inputToSettledLatencyMs: PerfDistribution,
    frameIntervalMs: PerfDistribution,
    totalCPUSeconds: Double,
    cpuSecondsPerCommittedFrame: Double?,
    cpuSecondsPerDiagnosticFrame: Double?,
    cpuSecondsPerInputEvent: Double?,
    mainActorBlockedRatio: Double?,
    mainActorSuspendedRatio: Double?,
    workerLayoutEnqueueMs: PerfDistribution,
    workerLayoutComputeMs: PerfDistribution,
    workerRasterEnqueueMs: PerfDistribution,
    workerRasterComputeMs: PerfDistribution,
    presentationDurationMs: PerfDistribution,
    completedDropCount: Int,
    customLayoutFallbackCount: Int,
    layoutDependentMainActorFallbackCount: Int
  ) {
    self.scenario = scenario
    self.renderMode = renderMode
    self.iterationCount = iterationCount
    self.committedFrameCount = committedFrameCount
    self.diagnosticFrameCount = diagnosticFrameCount
    self.skippedFrameCount = skippedFrameCount
    self.elidedFrameCount = elidedFrameCount
    self.cancelledFrameCount = cancelledFrameCount
    self.inputToPresentLatencyMs = inputToPresentLatencyMs
    self.inputToSettledLatencyMs = inputToSettledLatencyMs
    self.frameIntervalMs = frameIntervalMs
    self.totalCPUSeconds = totalCPUSeconds
    self.cpuSecondsPerCommittedFrame = cpuSecondsPerCommittedFrame
    self.cpuSecondsPerDiagnosticFrame = cpuSecondsPerDiagnosticFrame
    self.cpuSecondsPerInputEvent = cpuSecondsPerInputEvent
    self.mainActorBlockedRatio = mainActorBlockedRatio
    self.mainActorSuspendedRatio = mainActorSuspendedRatio
    self.workerLayoutEnqueueMs = workerLayoutEnqueueMs
    self.workerLayoutComputeMs = workerLayoutComputeMs
    self.workerRasterEnqueueMs = workerRasterEnqueueMs
    self.workerRasterComputeMs = workerRasterComputeMs
    self.presentationDurationMs = presentationDurationMs
    self.completedDropCount = completedDropCount
    self.customLayoutFallbackCount = customLayoutFallbackCount
    self.layoutDependentMainActorFallbackCount = layoutDependentMainActorFallbackCount
  }

  private enum CodingKeys: String, CodingKey {
    case scenario
    case renderMode = "render_mode"
    case iterationCount = "iteration_count"
    case committedFrameCount = "committed_frame_count"
    case diagnosticFrameCount = "diagnostic_frame_count"
    case skippedFrameCount = "skipped_frame_count"
    case elidedFrameCount = "elided_frame_count"
    case cancelledFrameCount = "cancelled_frame_count"
    case inputToPresentLatencyMs = "input_to_present_latency_ms"
    case inputToSettledLatencyMs = "input_to_settled_latency_ms"
    case frameIntervalMs = "frame_interval_ms"
    case totalCPUSeconds = "total_cpu_seconds"
    case cpuSecondsPerCommittedFrame = "cpu_seconds_per_committed_frame"
    case cpuSecondsPerDiagnosticFrame = "cpu_seconds_per_diagnostic_frame"
    case cpuSecondsPerInputEvent = "cpu_seconds_per_input_event"
    case mainActorBlockedRatio = "main_actor_blocked_ratio"
    case mainActorSuspendedRatio = "main_actor_suspended_ratio"
    case workerLayoutEnqueueMs = "worker_layout_enqueue_ms"
    case workerLayoutComputeMs = "worker_layout_compute_ms"
    case workerRasterEnqueueMs = "worker_raster_enqueue_ms"
    case workerRasterComputeMs = "worker_raster_compute_ms"
    case presentationDurationMs = "presentation_duration_ms"
    case completedDropCount = "completed_drop_count"
    case customLayoutFallbackCount = "custom_layout_fallback_count"
    case layoutDependentMainActorFallbackCount = "layout_dependent_main_actor_fallback_count"
  }
}

public enum SummaryReducer {
  public static func reduce(
    metadata: PerfRunMetadata,
    events: [PerfEventRecord],
    cpuSamples: [PerfCPUSample],
    frames: [PerfFrameRecord]
  ) -> PerfSummary {
    let committedFrames = frames.filter(\.isCommitted)
    let diagnosticFrameCount = frames.count
    let skippedFrames = frames.count - committedFrames.count
    let totalCPUSeconds = cpuSeconds(from: cpuSamples)
    let committedFrameCount = committedFrames.count
    let inputEvents = events.filter(\.isLatencyBearing)
    let cancelledFrameCount = cancelledFrameCount(frames)

    return PerfSummary(
      scenario: metadata.scenario,
      renderMode: metadata.renderMode,
      iterationCount: metadata.iterationCount,
      committedFrameCount: committedFrameCount,
      diagnosticFrameCount: diagnosticFrameCount,
      skippedFrameCount: skippedFrames,
      elidedFrameCount: frames.filter(\.isElided).count,
      cancelledFrameCount: cancelledFrameCount,
      inputToPresentLatencyMs: PerfDistribution(values: inputToPresentLatencies(events)),
      inputToSettledLatencyMs: PerfDistribution(values: inputToSettledLatencies(events)),
      frameIntervalMs: PerfDistribution(values: frameIntervals(frames)),
      totalCPUSeconds: totalCPUSeconds,
      cpuSecondsPerCommittedFrame: ratio(totalCPUSeconds, Double(committedFrameCount)),
      cpuSecondsPerDiagnosticFrame: ratio(totalCPUSeconds, Double(diagnosticFrameCount)),
      cpuSecondsPerInputEvent: ratio(totalCPUSeconds, Double(inputEvents.count)),
      mainActorBlockedRatio: timeRatio(
        frames.compactMap(\.mainActorBlockedMs),
        frames.compactMap(\.totalMs)
      ),
      mainActorSuspendedRatio: timeRatio(
        frames.compactMap(\.mainActorSuspendedMs),
        frames.compactMap(\.totalMs)
      ),
      workerLayoutEnqueueMs: PerfDistribution(values: frames.compactMap(\.workerLayoutEnqueueMs)),
      workerLayoutComputeMs: PerfDistribution(values: frames.compactMap(\.workerLayoutComputeMs)),
      workerRasterEnqueueMs: PerfDistribution(values: frames.compactMap(\.workerRasterEnqueueMs)),
      workerRasterComputeMs: PerfDistribution(values: frames.compactMap(\.workerRasterComputeMs)),
      presentationDurationMs: PerfDistribution(
        values: committedFrames.compactMap(\.presentationDurationMs)
      ),
      completedDropCount: completedDropCount(frames),
      customLayoutFallbackCount: frames.reduce(0) { $0 + $1.customLayoutFallbacks },
      layoutDependentMainActorFallbackCount: frames.reduce(0) {
        $0 + $1.layoutDependentMainActorFallbacks
      }
    )
  }

  private static func inputToPresentLatencies(_ events: [PerfEventRecord]) -> [Double] {
    events.filter(\.isLatencyBearing).compactMap { event in
      guard let firstMatchingTimeSeconds = event.firstMatchingTimeSeconds else {
        return nil
      }
      return (firstMatchingTimeSeconds - event.dispatchTimeSeconds) * 1000
    }
  }

  private static func inputToSettledLatencies(_ events: [PerfEventRecord]) -> [Double] {
    events.filter(\.isLatencyBearing).compactMap { event in
      guard let finalSettledTimeSeconds = event.finalSettledTimeSeconds else {
        return nil
      }
      return (finalSettledTimeSeconds - event.dispatchTimeSeconds) * 1000
    }
  }

  private static func frameIntervals(_ frames: [PerfFrameRecord]) -> [Double] {
    let timestamps = frames.compactMap(\.presentedAtSeconds).sorted()
    guard timestamps.count > 1 else {
      return []
    }
    return zip(timestamps, timestamps.dropFirst()).map { previous, current in
      (current - previous) * 1000
    }
  }

  private static func cpuSeconds(from samples: [PerfCPUSample]) -> Double {
    samples.reduce(0) { $0 + max(0, $1.totalCPUSeconds) }
  }

  private static func ratio(_ numerator: Double, _ denominator: Double) -> Double? {
    guard denominator > 0 else {
      return nil
    }
    return numerator / denominator
  }

  private static func timeRatio(_ numerators: [Double], _ denominators: [Double]) -> Double? {
    ratio(numerators.reduce(0, +), denominators.reduce(0, +))
  }

  private static func cancelledFrameCount(_ frames: [PerfFrameRecord]) -> Int {
    max(
      frames.filter { $0.tailJobState == "cancelled_before_start" }.count,
      frames.map(\.cancelledRenderCount).max() ?? 0
    )
  }

  private static func completedDropCount(_ frames: [PerfFrameRecord]) -> Int {
    frames.filter { frame in
      frame.tailJobState == "dropped_completed"
        || frame.staleFramePolicy == "drop_completed_visual_only"
        || frame.dropDecision.hasPrefix("drop")
    }
    .count
  }
}

extension PerfFrameRecord {
  fileprivate var isCommitted: Bool {
    tailJobState == "completed" && !dropDecision.hasPrefix("drop") && !isElided
  }

  fileprivate var isElided: Bool {
    elided || staleFramePolicy == "elided_offscreen"
  }
}

extension PerfEventRecord {
  fileprivate var isLatencyBearing: Bool {
    eventType.lowercased() != "idle"
  }
}
