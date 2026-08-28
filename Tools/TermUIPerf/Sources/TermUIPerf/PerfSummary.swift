import Foundation

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
  /// Whether this run presented through the emission-visible lane
  /// (`SWIFTTUI_PERF_EMISSION=1`). Lane-on and lane-off runs measure
  /// different pipelines; `compare` refuses to mix them.
  public var emissionLane: Bool
  /// The build configuration the run was compiled with. `compare` refuses to
  /// mix configurations: `-Onone` and `-O` measure different code.
  public var configuration: String
  public var iterationCount: Int
  public var committedFrameCount: Int
  public var diagnosticFrameCount: Int
  public var skippedFrameCount: Int
  public var elidedFrameCount: Int
  public var cancelledFrameCount: Int
  /// Harness-clock latency: this runner's stopwatch from injecting an event to
  /// seeing a marker in a presented frame. Distinct from the runtime's
  /// `inputToCommit*` columns, which are stamped inside the run loop against a
  /// real arrival. Kept because closed-loop scenarios have measured it for a
  /// long time and their history is comparable; it is not the scroll-latency
  /// number.
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
  public var headPrepareMs: PerfDistribution
  public var headGraphCheckpointCreateMs: PerfDistribution
  public var headGraphCheckpointRestoreMs: PerfDistribution
  public var headResolveCheckpointRestoreMs: PerfDistribution
  public var headAnimationProcessResolvedTreeMs: PerfDistribution
  public var headAnimationApplyInterpolationsMs: PerfDistribution
  public var elidedHeadTotalMs: PerfDistribution
  public var elidedGraphCheckpointCreateMs: PerfDistribution
  public var elidedGraphCheckpointRestoreMs: PerfDistribution
  public var elidedResolveCheckpointRestoreMs: PerfDistribution
  public var elidedAnimationTickMs: PerfDistribution
  public var elidedCommitRuntimeRegistrationsMs: PerfDistribution
  public var elidedAnimationCommitMs: PerfDistribution
  public var elidedCommitMs: PerfDistribution
  /// Runtime-stamped arrival→commit for the *oldest* input each frame
  /// answered — the worst latency the frame closed out, and what a user
  /// waiting on a queued notch actually experiences. This is the scroll
  /// latency number, and the one the gate watches.
  public var inputToCommitFirstMs: PerfDistribution
  /// Arrival→commit for the *newest* input each frame answered — the best
  /// latency the frame closed out. Reported beside the first edge because the
  /// two bracket the true per-notch latencies inside a coalesced cluster;
  /// alone it is optimistic, and stays flat while a backlog grows.
  public var inputToCommitLastMs: PerfDistribution
  /// Arrival→write completion, joined through `presents.tsv`. Covers only
  /// frames whose bytes actually reached the terminal.
  public var inputToWriteMs: PerfDistribution
  public var resolveMs: PerfDistribution
  public var measureMs: PerfDistribution
  public var placeMs: PerfDistribution
  public var semanticsMs: PerfDistribution
  public var drawMs: PerfDistribution
  public var rasterMs: PerfDistribution
  public var commitMs: PerfDistribution
  public var pipelineMs: PerfDistribution
  /// Frames that answered input or woke on a deadline — the frames that moved
  /// the scene. Emission and coalescing are reported over these, because
  /// averaging them over settle frames dilutes exactly the cost being hunted.
  public var movingFrameCount: Int
  /// Bytes written per moving frame. The emission number every mitigation tier
  /// in the program is ultimately trying to move.
  public var presentBytesPerMovingFrame: Double?
  /// Inputs answered per moving frame: the coalescing rate. Above 1 the
  /// runtime is merging notches, which lowers per-frame cost and raises
  /// per-notch latency at the same time.
  public var answeredInputsPerMovingFrame: Double?
  /// Moving frames that repainted the whole surface rather than a bounded row
  /// range. For scroll on current HEAD this is expected to be nearly all of
  /// them; the count is the before-side of the translation-aware damage work.
  public var fullRepaintMovingFrameCount: Int
  /// Damaged rows per moving frame, over the frames that reported a bounded
  /// count. Full repaints are excluded here and counted above instead — they
  /// have no row number to average, and substituting one would understate the
  /// damage.
  public var damageRowsPerBoundedMovingFrame: Double?
  /// Rows realized per moving frame, when the run armed
  /// `SWIFTTUI_COLLECTION_PROBES`. `nil` for an unarmed run — the number that
  /// makes `resolve_ms` readable rather than merely observed, so its absence
  /// has to be visible rather than reported as zero work.
  public var realizedRowsPerMovingFrame: Double?
  /// List visible-layout derivations per moving frame, when armed. `nil`
  /// otherwise. One per phase is the D19 target; more means the measured
  /// product is being re-derived instead of consumed.
  public var listLayoutDerivationsPerMovingFrame: Double?
  /// Submissions a newer frame replaced before they reached `write(2)`. Under
  /// open-loop cadence this is the backlog made visible.
  public var supersededPresentCount: Int
  /// Frames that reached the incremental rasterizer. This lane's headline
  /// number: it was structurally zero for every scenario until the damage
  /// producer was rebuilt, which is exactly why it is reported rather than
  /// inferred from timings.
  public var incrementalRasterFrameCount: Int
  /// Frames whose incremental surface diverged from a fresh raster and had to
  /// be repaired. Must be zero; any non-zero value is an under-damage bug that
  /// ships as corruption in release.
  public var repairedIncrementalRasterFrameCount: Int
  /// Frames that took the fresh path, counted by the barrier that forced it.
  public var rasterReuseBarrierCounts: [String: Int]
  public var completedDropCount: Int
  public var customLayoutFallbackCount: Int
  public var layoutDependentMainActorFallbackCount: Int
  /// Run-total deterministic work counters (plan 2026-08-11-005 Stage 0).
  /// `nil` for artifacts recorded before the counters existed.
  public var deterministicCounters: PerfDeterministicCounters?

  public init(
    scenario: String,
    renderMode: String,
    emissionLane: Bool = false,
    configuration: String = PerfBuildConfiguration.detected,
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
    headPrepareMs: PerfDistribution = PerfDistribution(values: []),
    headGraphCheckpointCreateMs: PerfDistribution = PerfDistribution(values: []),
    headGraphCheckpointRestoreMs: PerfDistribution = PerfDistribution(values: []),
    headResolveCheckpointRestoreMs: PerfDistribution = PerfDistribution(values: []),
    headAnimationProcessResolvedTreeMs: PerfDistribution = PerfDistribution(values: []),
    headAnimationApplyInterpolationsMs: PerfDistribution = PerfDistribution(values: []),
    elidedHeadTotalMs: PerfDistribution = PerfDistribution(values: []),
    elidedGraphCheckpointCreateMs: PerfDistribution = PerfDistribution(values: []),
    elidedGraphCheckpointRestoreMs: PerfDistribution = PerfDistribution(values: []),
    elidedResolveCheckpointRestoreMs: PerfDistribution = PerfDistribution(values: []),
    elidedAnimationTickMs: PerfDistribution = PerfDistribution(values: []),
    elidedCommitRuntimeRegistrationsMs: PerfDistribution = PerfDistribution(values: []),
    elidedAnimationCommitMs: PerfDistribution = PerfDistribution(values: []),
    elidedCommitMs: PerfDistribution = PerfDistribution(values: []),
    inputToCommitFirstMs: PerfDistribution = PerfDistribution(values: []),
    inputToCommitLastMs: PerfDistribution = PerfDistribution(values: []),
    inputToWriteMs: PerfDistribution = PerfDistribution(values: []),
    resolveMs: PerfDistribution = PerfDistribution(values: []),
    measureMs: PerfDistribution = PerfDistribution(values: []),
    placeMs: PerfDistribution = PerfDistribution(values: []),
    semanticsMs: PerfDistribution = PerfDistribution(values: []),
    drawMs: PerfDistribution = PerfDistribution(values: []),
    rasterMs: PerfDistribution = PerfDistribution(values: []),
    commitMs: PerfDistribution = PerfDistribution(values: []),
    pipelineMs: PerfDistribution = PerfDistribution(values: []),
    movingFrameCount: Int = 0,
    presentBytesPerMovingFrame: Double? = nil,
    answeredInputsPerMovingFrame: Double? = nil,
    fullRepaintMovingFrameCount: Int = 0,
    damageRowsPerBoundedMovingFrame: Double? = nil,
    realizedRowsPerMovingFrame: Double? = nil,
    listLayoutDerivationsPerMovingFrame: Double? = nil,
    supersededPresentCount: Int = 0,
    incrementalRasterFrameCount: Int = 0,
    repairedIncrementalRasterFrameCount: Int = 0,
    rasterReuseBarrierCounts: [String: Int] = [:],
    completedDropCount: Int,
    customLayoutFallbackCount: Int,
    layoutDependentMainActorFallbackCount: Int,
    deterministicCounters: PerfDeterministicCounters? = nil
  ) {
    self.incrementalRasterFrameCount = incrementalRasterFrameCount
    self.repairedIncrementalRasterFrameCount = repairedIncrementalRasterFrameCount
    self.rasterReuseBarrierCounts = rasterReuseBarrierCounts
    self.scenario = scenario
    self.renderMode = renderMode
    self.emissionLane = emissionLane
    self.configuration = configuration
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
    self.headPrepareMs = headPrepareMs
    self.headGraphCheckpointCreateMs = headGraphCheckpointCreateMs
    self.headGraphCheckpointRestoreMs = headGraphCheckpointRestoreMs
    self.headResolveCheckpointRestoreMs = headResolveCheckpointRestoreMs
    self.headAnimationProcessResolvedTreeMs = headAnimationProcessResolvedTreeMs
    self.headAnimationApplyInterpolationsMs = headAnimationApplyInterpolationsMs
    self.elidedHeadTotalMs = elidedHeadTotalMs
    self.elidedGraphCheckpointCreateMs = elidedGraphCheckpointCreateMs
    self.elidedGraphCheckpointRestoreMs = elidedGraphCheckpointRestoreMs
    self.elidedResolveCheckpointRestoreMs = elidedResolveCheckpointRestoreMs
    self.elidedAnimationTickMs = elidedAnimationTickMs
    self.elidedCommitRuntimeRegistrationsMs = elidedCommitRuntimeRegistrationsMs
    self.elidedAnimationCommitMs = elidedAnimationCommitMs
    self.elidedCommitMs = elidedCommitMs
    self.inputToCommitFirstMs = inputToCommitFirstMs
    self.inputToCommitLastMs = inputToCommitLastMs
    self.inputToWriteMs = inputToWriteMs
    self.resolveMs = resolveMs
    self.measureMs = measureMs
    self.placeMs = placeMs
    self.semanticsMs = semanticsMs
    self.drawMs = drawMs
    self.rasterMs = rasterMs
    self.commitMs = commitMs
    self.pipelineMs = pipelineMs
    self.movingFrameCount = movingFrameCount
    self.presentBytesPerMovingFrame = presentBytesPerMovingFrame
    self.answeredInputsPerMovingFrame = answeredInputsPerMovingFrame
    self.fullRepaintMovingFrameCount = fullRepaintMovingFrameCount
    self.damageRowsPerBoundedMovingFrame = damageRowsPerBoundedMovingFrame
    self.realizedRowsPerMovingFrame = realizedRowsPerMovingFrame
    self.listLayoutDerivationsPerMovingFrame = listLayoutDerivationsPerMovingFrame
    self.supersededPresentCount = supersededPresentCount
    self.completedDropCount = completedDropCount
    self.customLayoutFallbackCount = customLayoutFallbackCount
    self.layoutDependentMainActorFallbackCount = layoutDependentMainActorFallbackCount
    self.deterministicCounters = deterministicCounters
  }

  private enum CodingKeys: String, CodingKey {
    case scenario
    case renderMode = "render_mode"
    case emissionLane = "emission_lane"
    case configuration
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
    case headPrepareMs = "head_prepare_ms"
    case headGraphCheckpointCreateMs = "head_graph_checkpoint_create_ms"
    case headGraphCheckpointRestoreMs = "head_graph_checkpoint_restore_ms"
    case headResolveCheckpointRestoreMs = "head_resolve_checkpoint_restore_ms"
    case headAnimationProcessResolvedTreeMs = "head_animation_process_resolved_tree_ms"
    case headAnimationApplyInterpolationsMs = "head_animation_apply_interpolations_ms"
    case elidedHeadTotalMs = "elided_head_total_ms"
    case elidedGraphCheckpointCreateMs = "elided_graph_checkpoint_create_ms"
    case elidedGraphCheckpointRestoreMs = "elided_graph_checkpoint_restore_ms"
    case elidedResolveCheckpointRestoreMs = "elided_resolve_checkpoint_restore_ms"
    case elidedAnimationTickMs = "elided_animation_tick_ms"
    case elidedCommitRuntimeRegistrationsMs =
      "elided_commit_runtime_registrations_ms"
    case elidedAnimationCommitMs = "elided_animation_commit_ms"
    case elidedCommitMs = "elided_commit_ms"
    case inputToCommitFirstMs = "input_to_commit_first_ms"
    case inputToCommitLastMs = "input_to_commit_last_ms"
    case inputToWriteMs = "input_to_write_ms"
    case resolveMs = "resolve_ms"
    case measureMs = "measure_ms"
    case placeMs = "place_ms"
    case semanticsMs = "semantics_ms"
    case drawMs = "draw_ms"
    case rasterMs = "raster_ms"
    case commitMs = "commit_ms"
    case pipelineMs = "pipeline_ms"
    case movingFrameCount = "moving_frame_count"
    case presentBytesPerMovingFrame = "present_bytes_per_moving_frame"
    case answeredInputsPerMovingFrame = "answered_inputs_per_moving_frame"
    case fullRepaintMovingFrameCount = "full_repaint_moving_frame_count"
    case damageRowsPerBoundedMovingFrame = "damage_rows_per_bounded_moving_frame"
    case realizedRowsPerMovingFrame = "realized_rows_per_moving_frame"
    case listLayoutDerivationsPerMovingFrame = "list_layout_derivations_per_moving_frame"
    case supersededPresentCount = "superseded_present_count"
    case incrementalRasterFrameCount = "incremental_raster_frame_count"
    case repairedIncrementalRasterFrameCount = "repaired_incremental_raster_frame_count"
    case rasterReuseBarrierCounts = "raster_reuse_barrier_counts"
    case completedDropCount = "completed_drop_count"
    case customLayoutFallbackCount = "custom_layout_fallback_count"
    case layoutDependentMainActorFallbackCount = "layout_dependent_main_actor_fallback_count"
    case deterministicCounters = "deterministic_counters"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      scenario: try container.decode(String.self, forKey: .scenario),
      renderMode: try container.decode(String.self, forKey: .renderMode),
      // decodeIfPresent: a summary recorded before the lane existed is a
      // valid lane-off baseline.
      emissionLane: try container.decodeIfPresent(Bool.self, forKey: .emissionLane) ?? false,
      configuration: try container.decodeIfPresent(String.self, forKey: .configuration)
        ?? PerfBuildConfiguration.detected,
      iterationCount: try container.decode(Int.self, forKey: .iterationCount),
      committedFrameCount: try container.decode(Int.self, forKey: .committedFrameCount),
      diagnosticFrameCount: try container.decode(Int.self, forKey: .diagnosticFrameCount),
      skippedFrameCount: try container.decode(Int.self, forKey: .skippedFrameCount),
      elidedFrameCount: try container.decode(Int.self, forKey: .elidedFrameCount),
      cancelledFrameCount: try container.decode(Int.self, forKey: .cancelledFrameCount),
      inputToPresentLatencyMs: try container.decode(
        PerfDistribution.self,
        forKey: .inputToPresentLatencyMs
      ),
      inputToSettledLatencyMs: try container.decode(
        PerfDistribution.self,
        forKey: .inputToSettledLatencyMs
      ),
      frameIntervalMs: try container.decode(PerfDistribution.self, forKey: .frameIntervalMs),
      totalCPUSeconds: try container.decode(Double.self, forKey: .totalCPUSeconds),
      cpuSecondsPerCommittedFrame: try container.decodeIfPresent(
        Double.self,
        forKey: .cpuSecondsPerCommittedFrame
      ),
      cpuSecondsPerDiagnosticFrame: try container.decodeIfPresent(
        Double.self,
        forKey: .cpuSecondsPerDiagnosticFrame
      ),
      cpuSecondsPerInputEvent: try container.decodeIfPresent(
        Double.self,
        forKey: .cpuSecondsPerInputEvent
      ),
      mainActorBlockedRatio: try container.decodeIfPresent(
        Double.self,
        forKey: .mainActorBlockedRatio
      ),
      mainActorSuspendedRatio: try container.decodeIfPresent(
        Double.self,
        forKey: .mainActorSuspendedRatio
      ),
      workerLayoutEnqueueMs: try container.decode(
        PerfDistribution.self,
        forKey: .workerLayoutEnqueueMs
      ),
      workerLayoutComputeMs: try container.decode(
        PerfDistribution.self,
        forKey: .workerLayoutComputeMs
      ),
      workerRasterEnqueueMs: try container.decode(
        PerfDistribution.self,
        forKey: .workerRasterEnqueueMs
      ),
      workerRasterComputeMs: try container.decode(
        PerfDistribution.self,
        forKey: .workerRasterComputeMs
      ),
      presentationDurationMs: try container.decode(
        PerfDistribution.self,
        forKey: .presentationDurationMs
      ),
      headPrepareMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .headPrepareMs
      ) ?? PerfDistribution(values: []),
      headGraphCheckpointCreateMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .headGraphCheckpointCreateMs
      ) ?? PerfDistribution(values: []),
      headGraphCheckpointRestoreMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .headGraphCheckpointRestoreMs
      ) ?? PerfDistribution(values: []),
      headResolveCheckpointRestoreMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .headResolveCheckpointRestoreMs
      ) ?? PerfDistribution(values: []),
      headAnimationProcessResolvedTreeMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .headAnimationProcessResolvedTreeMs
      ) ?? PerfDistribution(values: []),
      headAnimationApplyInterpolationsMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .headAnimationApplyInterpolationsMs
      ) ?? PerfDistribution(values: []),
      elidedHeadTotalMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .elidedHeadTotalMs
      ) ?? PerfDistribution(values: []),
      elidedGraphCheckpointCreateMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .elidedGraphCheckpointCreateMs
      ) ?? PerfDistribution(values: []),
      elidedGraphCheckpointRestoreMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .elidedGraphCheckpointRestoreMs
      ) ?? PerfDistribution(values: []),
      elidedResolveCheckpointRestoreMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .elidedResolveCheckpointRestoreMs
      ) ?? PerfDistribution(values: []),
      elidedAnimationTickMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .elidedAnimationTickMs
      ) ?? PerfDistribution(values: []),
      elidedCommitRuntimeRegistrationsMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .elidedCommitRuntimeRegistrationsMs
      ) ?? PerfDistribution(values: []),
      elidedAnimationCommitMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .elidedAnimationCommitMs
      ) ?? PerfDistribution(values: []),
      elidedCommitMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .elidedCommitMs
      ) ?? PerfDistribution(values: []),
      inputToCommitFirstMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .inputToCommitFirstMs
      ) ?? PerfDistribution(values: []),
      inputToCommitLastMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .inputToCommitLastMs
      ) ?? PerfDistribution(values: []),
      inputToWriteMs: try container.decodeIfPresent(
        PerfDistribution.self,
        forKey: .inputToWriteMs
      ) ?? PerfDistribution(values: []),
      resolveMs: try container.decodeIfPresent(PerfDistribution.self, forKey: .resolveMs)
        ?? PerfDistribution(values: []),
      measureMs: try container.decodeIfPresent(PerfDistribution.self, forKey: .measureMs)
        ?? PerfDistribution(values: []),
      placeMs: try container.decodeIfPresent(PerfDistribution.self, forKey: .placeMs)
        ?? PerfDistribution(values: []),
      semanticsMs: try container.decodeIfPresent(PerfDistribution.self, forKey: .semanticsMs)
        ?? PerfDistribution(values: []),
      drawMs: try container.decodeIfPresent(PerfDistribution.self, forKey: .drawMs)
        ?? PerfDistribution(values: []),
      rasterMs: try container.decodeIfPresent(PerfDistribution.self, forKey: .rasterMs)
        ?? PerfDistribution(values: []),
      commitMs: try container.decodeIfPresent(PerfDistribution.self, forKey: .commitMs)
        ?? PerfDistribution(values: []),
      pipelineMs: try container.decodeIfPresent(PerfDistribution.self, forKey: .pipelineMs)
        ?? PerfDistribution(values: []),
      movingFrameCount: try container.decodeIfPresent(Int.self, forKey: .movingFrameCount) ?? 0,
      presentBytesPerMovingFrame: try container.decodeIfPresent(
        Double.self,
        forKey: .presentBytesPerMovingFrame
      ),
      answeredInputsPerMovingFrame: try container.decodeIfPresent(
        Double.self,
        forKey: .answeredInputsPerMovingFrame
      ),
      fullRepaintMovingFrameCount: try container.decodeIfPresent(
        Int.self,
        forKey: .fullRepaintMovingFrameCount
      ) ?? 0,
      damageRowsPerBoundedMovingFrame: try container.decodeIfPresent(
        Double.self,
        forKey: .damageRowsPerBoundedMovingFrame
      ),
      realizedRowsPerMovingFrame: try container.decodeIfPresent(
        Double.self,
        forKey: .realizedRowsPerMovingFrame
      ),
      listLayoutDerivationsPerMovingFrame: try container.decodeIfPresent(
        Double.self,
        forKey: .listLayoutDerivationsPerMovingFrame
      ),
      supersededPresentCount: try container.decodeIfPresent(
        Int.self,
        forKey: .supersededPresentCount
      ) ?? 0,
      incrementalRasterFrameCount: try container.decodeIfPresent(
        Int.self,
        forKey: .incrementalRasterFrameCount
      ) ?? 0,
      repairedIncrementalRasterFrameCount: try container.decodeIfPresent(
        Int.self,
        forKey: .repairedIncrementalRasterFrameCount
      ) ?? 0,
      rasterReuseBarrierCounts: try container.decodeIfPresent(
        [String: Int].self,
        forKey: .rasterReuseBarrierCounts
      ) ?? [:],
      completedDropCount: try container.decode(Int.self, forKey: .completedDropCount),
      customLayoutFallbackCount: try container.decode(
        Int.self,
        forKey: .customLayoutFallbackCount
      ),
      layoutDependentMainActorFallbackCount: try container.decode(
        Int.self,
        forKey: .layoutDependentMainActorFallbackCount
      ),
      // decodeIfPresent: a summary recorded before the deterministic counters
      // existed is a valid artifact that simply has nothing to say about them.
      deterministicCounters: try container.decodeIfPresent(
        PerfDeterministicCounters.self,
        forKey: .deterministicCounters
      )
    )
  }
}
