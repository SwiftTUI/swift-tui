import Foundation

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
    // Moving frames are classified over committed frames only: an elided or
    // dropped frame emitted nothing, so folding it into a per-moving-frame
    // emission average would divide real bytes by phantom frames.
    let movingFrames = committedFrames.filter(\.isMoving)
    // Hoisted rather than inlined into the initializer call below: that call
    // takes enough arguments that leaving these as inline closure expressions
    // pushes the type checker past its budget and fails the build with a
    // "unable to type-check in reasonable time" error rather than a real
    // diagnostic.
    let latency = InputLatencyDistributions(committedFrames)
    let phases = PhaseDistributions(committedFrames)
    let emission = EmissionAggregates(movingFrames: movingFrames, allFrames: frames)

    return PerfSummary(
      scenario: metadata.scenario,
      renderMode: metadata.renderMode,
      emissionLane: metadata.emissionLane,
      configuration: metadata.configuration,
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
      headPrepareMs: PerfDistribution(values: committedFrames.compactMap(\.headPrepareMs)),
      headGraphCheckpointCreateMs: PerfDistribution(
        values: committedFrames.compactMap(\.headGraphCheckpointCreateMs)
      ),
      headGraphCheckpointRestoreMs: PerfDistribution(
        values: committedFrames.compactMap(\.headGraphCheckpointRestoreMs)
      ),
      headResolveCheckpointRestoreMs: PerfDistribution(
        values: committedFrames.compactMap(\.headResolveCheckpointRestoreMs)
      ),
      headAnimationProcessResolvedTreeMs: PerfDistribution(
        values: committedFrames.compactMap(\.headAnimationProcessResolvedTreeMs)
      ),
      headAnimationApplyInterpolationsMs: PerfDistribution(
        values: committedFrames.compactMap(\.headAnimationApplyInterpolationsMs)
      ),
      elidedHeadTotalMs: PerfDistribution(values: frames.compactMap(\.elidedHeadTotalMs)),
      elidedGraphCheckpointCreateMs: PerfDistribution(
        values: frames.compactMap(\.elidedGraphCheckpointCreateMs)
      ),
      elidedGraphCheckpointRestoreMs: PerfDistribution(
        values: frames.compactMap(\.elidedGraphCheckpointRestoreMs)
      ),
      elidedResolveCheckpointRestoreMs: PerfDistribution(
        values: frames.compactMap(\.elidedResolveCheckpointRestoreMs)
      ),
      elidedAnimationTickMs: PerfDistribution(
        values: frames.compactMap(\.elidedAnimationTickMs)
      ),
      elidedCommitRuntimeRegistrationsMs: PerfDistribution(
        values: frames.compactMap(\.elidedCommitRuntimeRegistrationsMs)
      ),
      elidedAnimationCommitMs: PerfDistribution(
        values: frames.compactMap(\.elidedAnimationCommitMs)
      ),
      elidedCommitMs: PerfDistribution(values: frames.compactMap(\.elidedCommitMs)),
      inputToCommitFirstMs: latency.commitFirst,
      inputToCommitLastMs: latency.commitLast,
      inputToWriteMs: latency.write,
      resolveMs: phases.resolve,
      measureMs: phases.measure,
      placeMs: phases.place,
      semanticsMs: phases.semantics,
      drawMs: phases.draw,
      rasterMs: phases.raster,
      commitMs: phases.commit,
      pipelineMs: phases.pipeline,
      movingFrameCount: movingFrames.count,
      presentBytesPerMovingFrame: emission.bytesPerMovingFrame,
      answeredInputsPerMovingFrame: emission.answeredInputsPerMovingFrame,
      fullRepaintMovingFrameCount: emission.fullRepaintMovingFrameCount,
      damageRowsPerBoundedMovingFrame: emission.damageRowsPerBoundedMovingFrame,
      realizedRowsPerMovingFrame: emission.realizedRowsPerMovingFrame,
      listLayoutDerivationsPerMovingFrame: emission.listLayoutDerivationsPerMovingFrame,
      supersededPresentCount: emission.supersededPresentCount,
      incrementalRasterFrameCount: frames.count {
        // The R3.2b translation blit is the incremental path plus served
        // band rows; both count as incremental frames for the reuse metric.
        $0.rasterPath == "incremental" || $0.rasterPath == "incrementalTranslated"
      },
      repairedIncrementalRasterFrameCount: frames.count {
        $0.rasterPath == "incrementalRepaired"
      },
      rasterReuseBarrierCounts: rasterReuseBarrierCounts(frames),
      completedDropCount: completedDropCount(frames),
      customLayoutFallbackCount: frames.reduce(0) { $0 + $1.customLayoutFallbacks },
      layoutDependentMainActorFallbackCount: frames.reduce(0) {
        $0 + $1.layoutDependentMainActorFallbacks
      },
      deterministicCounters: PerfDeterministicCounters.reduce(
        frames: frames,
        committedFrameCount: committedFrameCount
      )
    )
  }

  /// The runtime-stamped latency distributions, over committed frames.
  private struct InputLatencyDistributions {
    var commitFirst: PerfDistribution
    var commitLast: PerfDistribution
    var write: PerfDistribution

    init(_ frames: [PerfFrameRecord]) {
      commitFirst = PerfDistribution(values: frames.compactMap(\.inputToCommitFirstMs))
      commitLast = PerfDistribution(values: frames.compactMap(\.inputToCommitLastMs))
      write = PerfDistribution(values: frames.compactMap(\.inputToWriteMs))
    }
  }

  /// The seven typed phases plus the pipeline total, over committed frames.
  private struct PhaseDistributions {
    var resolve: PerfDistribution
    var measure: PerfDistribution
    var place: PerfDistribution
    var semantics: PerfDistribution
    var draw: PerfDistribution
    var raster: PerfDistribution
    var commit: PerfDistribution
    var pipeline: PerfDistribution

    init(_ frames: [PerfFrameRecord]) {
      resolve = PerfDistribution(values: frames.compactMap(\.phases.resolveMs))
      measure = PerfDistribution(values: frames.compactMap(\.phases.measureMs))
      place = PerfDistribution(values: frames.compactMap(\.phases.placeMs))
      semantics = PerfDistribution(values: frames.compactMap(\.phases.semanticsMs))
      draw = PerfDistribution(values: frames.compactMap(\.phases.drawMs))
      raster = PerfDistribution(values: frames.compactMap(\.phases.rasterMs))
      commit = PerfDistribution(values: frames.compactMap(\.phases.commitMs))
      pipeline = PerfDistribution(values: frames.compactMap(\.phases.pipelineMs))
    }
  }

  /// What the moving frames put on the wire, and what the writer did with it.
  private struct EmissionAggregates {
    var bytesPerMovingFrame: Double?
    var answeredInputsPerMovingFrame: Double?
    var fullRepaintMovingFrameCount: Int
    var damageRowsPerBoundedMovingFrame: Double?
    var realizedRowsPerMovingFrame: Double?
    var listLayoutDerivationsPerMovingFrame: Double?
    var supersededPresentCount: Int

    init(movingFrames: [PerfFrameRecord], allFrames: [PerfFrameRecord]) {
      let movingCount = Double(movingFrames.count)
      bytesPerMovingFrame = SummaryReducer.ratio(
        Double(movingFrames.reduce(0) { $0 + $1.emission.presentBytes }),
        movingCount
      )
      answeredInputsPerMovingFrame = SummaryReducer.ratio(
        Double(movingFrames.reduce(0) { $0 + $1.answeredInputCount }),
        movingCount
      )
      fullRepaintMovingFrameCount = movingFrames.count {
        $0.emission.damageRows.isFullRepaint
      }
      damageRowsPerBoundedMovingFrame = SummaryReducer.mean(
        movingFrames.compactMap { $0.emission.damageRows.count }.map(Double.init)
      )
      // `compactMap` over an optional column, so a run with the collection
      // probes disarmed contributes no samples and the metric stays `nil`
      // rather than averaging to zero rows realized.
      realizedRowsPerMovingFrame = SummaryReducer.mean(
        movingFrames.compactMap(\.realizedRows).map(Double.init)
      )
      listLayoutDerivationsPerMovingFrame = SummaryReducer.mean(
        movingFrames.compactMap(\.listLayoutDerivations).map(Double.init)
      )
      // Counted over every frame, not just moving ones: a supersede is the
      // writer dropping a frame, and a settle frame superseded by the next
      // notch is exactly the backlog this metric exists to expose.
      supersededPresentCount = allFrames.count { $0.present?.wasWritten == false }
    }
  }

  private static func rasterReuseBarrierCounts(
    _ frames: [PerfFrameRecord]
  ) -> [String: Int] {
    var counts: [String: Int] = [:]
    for frame in frames where frame.rasterReuseBarriers != "-" {
      for barrier in frame.rasterReuseBarriers.split(separator: "+") {
        counts[String(barrier), default: 0] += 1
      }
    }
    return counts
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

  /// `nil` rather than `0` for an empty set: no samples is not an average of
  /// zero, and a gate that cannot tell them apart certifies silence as a win.
  private static func mean(_ values: [Double]) -> Double? {
    ratio(values.reduce(0, +), Double(values.count))
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
