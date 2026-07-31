import Foundation

/// The `damage_rows` column, which is not a plain integer.
///
/// A whole-surface repaint prints the literal `full` rather than a count, so a
/// parse that folds it into `0` reports the most expensive frame in a trace as
/// the cheapest. Scroll is the workload where that matters most: today a
/// one-line scroll damages the entire viewport, and a baseline that recorded
/// those frames as zero-damage would flatter every mitigation measured against
/// it.
public enum PerfDamageRows: Equatable, Sendable {
  /// A bounded repaint of `count` rows.
  case rows(Int)
  /// The whole surface was repainted — the column's `full` sentinel.
  case fullRepaint
  /// The column was absent, i.e. an artifact written before this column
  /// existed. Distinct from `fullRepaint`: unknown is not a measurement.
  case unknown

  /// The row count when the frame reported one. `nil` for a full repaint or an
  /// absent column, so a caller must decide what those mean rather than
  /// inheriting a silent zero.
  public var count: Int? {
    switch self {
    case .rows(let count):
      return count
    case .fullRepaint, .unknown:
      return nil
    }
  }

  public var isFullRepaint: Bool {
    self == .fullRepaint
  }

  /// Parses the column value. `full` is the sentinel; anything unparseable is
  /// `.unknown` rather than a fabricated count.
  public init(field: String?) {
    guard let field, !field.isEmpty, field != "-" else {
      self = .unknown
      return
    }
    if field == "full" {
      self = .fullRepaint
    } else if let count = Int(field) {
      self = .rows(count)
    } else {
      self = .unknown
    }
  }
}

/// The seven typed pipeline phases plus their total, as reduced from
/// `frames.tsv`.
///
/// These columns have been written for every frame since long before this
/// program, and never parsed — the gate could see a frame's total cost but not
/// which phase spent it. Scroll work is distributed across resolve, measure,
/// place and raster in different proportions depending on which mitigation tier
/// is in play, so the breakdown is the difference between "scrolling got
/// faster" and knowing why.
public struct PerfFramePhaseTimings: Equatable, Sendable {
  public var resolveMs: Double?
  public var measureMs: Double?
  public var placeMs: Double?
  public var semanticsMs: Double?
  public var drawMs: Double?
  public var rasterMs: Double?
  public var commitMs: Double?
  /// The pipeline total the runtime computed, not a sum of the above: the
  /// phases can overlap on worker threads.
  public var pipelineMs: Double?

  public init(
    resolveMs: Double? = nil,
    measureMs: Double? = nil,
    placeMs: Double? = nil,
    semanticsMs: Double? = nil,
    drawMs: Double? = nil,
    rasterMs: Double? = nil,
    commitMs: Double? = nil,
    pipelineMs: Double? = nil
  ) {
    self.resolveMs = resolveMs
    self.measureMs = measureMs
    self.placeMs = placeMs
    self.semanticsMs = semanticsMs
    self.drawMs = drawMs
    self.rasterMs = rasterMs
    self.commitMs = commitMs
    self.pipelineMs = pipelineMs
  }
}

/// What the frame put on the wire, and how much of the surface it had to
/// consider putting there.
public struct PerfFrameEmission: Equatable, Sendable {
  /// UTF-8 bytes the presentation wrote for this frame.
  public var presentBytes: Int
  /// Cells the presentation changed.
  public var presentCells: Int
  public var damageRows: PerfDamageRows
  /// Damaged text cells; `nil` when the column reported no bounded count.
  public var damageCells: Int?
  /// How many input batches the render-intent coalescer merged into this
  /// frame. The coalescing rate is this over the frames that moved.
  public var coalescedEventBatches: Int

  public init(
    presentBytes: Int = 0,
    presentCells: Int = 0,
    damageRows: PerfDamageRows = .unknown,
    damageCells: Int? = nil,
    coalescedEventBatches: Int = 0
  ) {
    self.presentBytes = presentBytes
    self.presentCells = presentCells
    self.damageRows = damageRows
    self.damageCells = damageCells
    self.coalescedEventBatches = coalescedEventBatches
  }
}

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
  public var headPrepareMs: Double?
  public var headGraphCheckpointCreateMs: Double?
  public var headGraphCheckpointRestoreMs: Double?
  public var headResolveCheckpointRestoreMs: Double?
  public var headAnimationProcessResolvedTreeMs: Double?
  public var headAnimationApplyInterpolationsMs: Double?
  public var elidedHeadTotalMs: Double?
  public var elidedGraphCheckpointCreateMs: Double?
  public var elidedGraphCheckpointRestoreMs: Double?
  public var elidedResolveCheckpointRestoreMs: Double?
  public var elidedAnimationTickMs: Double?
  public var elidedCommitRuntimeRegistrationsMs: Double?
  public var elidedAnimationCommitMs: Double?
  public var elidedCommitMs: Double?
  public var elided: Bool
  /// How many input events this frame answered (WP-1). `0` for a frame driven
  /// by a deadline alone.
  public var answeredInputCount: Int
  public var customLayoutFallbacks: Int
  public var layoutDependentMainActorFallbacks: Int
  public var tailJobState: String
  public var staleFramePolicy: String
  public var dropDecision: String
  public var cancelledRenderCount: Int
  /// Which rasterizer path the frame took: `fresh`, `incremental`, or
  /// `incrementalRepaired`. `-` for frames with no committed raster.
  public var rasterPath: String
  /// Why raster-reuse damage production barriered, `+`-joined; `-` when damage
  /// was produced.
  public var rasterReuseBarriers: String
  /// The frame's wake causes, `+`-joined. A deadline cause is how a momentum
  /// tick is told apart from an idle frame when neither answered input.
  public var causes: String
  public var phases: PerfFramePhaseTimings
  public var emission: PerfFrameEmission
  /// Commit minus the *oldest* answered input's arrival: the worst latency the
  /// frame closed out, and the one the aggregate gates on.
  public var inputToCommitFirstMs: Double?
  /// Commit minus the *newest* answered input's arrival: the best latency the
  /// frame closed out.
  public var inputToCommitLastMs: Double?
  /// The commit instant as an offset from the process monotonic origin — the
  /// join coordinate for `presents.tsv`, not a measurement. Meaningless across
  /// runs.
  public var committedAtMs: Double?
  /// The `presents.tsv` row for this frame, joined on frame ordinal. `nil`
  /// when the run produced no presents file (an in-process host writes
  /// synchronously and has no write latency to report) or when the writer
  /// never saw this frame.
  public var present: PerfPresentRecord?

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
    headPrepareMs: Double? = nil,
    headGraphCheckpointCreateMs: Double? = nil,
    headGraphCheckpointRestoreMs: Double? = nil,
    headResolveCheckpointRestoreMs: Double? = nil,
    headAnimationProcessResolvedTreeMs: Double? = nil,
    headAnimationApplyInterpolationsMs: Double? = nil,
    elidedHeadTotalMs: Double? = nil,
    elidedGraphCheckpointCreateMs: Double? = nil,
    elidedGraphCheckpointRestoreMs: Double? = nil,
    elidedResolveCheckpointRestoreMs: Double? = nil,
    elidedAnimationTickMs: Double? = nil,
    elidedCommitRuntimeRegistrationsMs: Double? = nil,
    elidedAnimationCommitMs: Double? = nil,
    elidedCommitMs: Double? = nil,
    elided: Bool = false,
    answeredInputCount: Int = 0,
    customLayoutFallbacks: Int = 0,
    layoutDependentMainActorFallbacks: Int = 0,
    tailJobState: String = "completed",
    staleFramePolicy: String = "commit_ordered",
    dropDecision: String = "commit_ordered",
    cancelledRenderCount: Int = 0,
    rasterPath: String = "-",
    rasterReuseBarriers: String = "-",
    causes: String = "",
    phases: PerfFramePhaseTimings = PerfFramePhaseTimings(),
    emission: PerfFrameEmission = PerfFrameEmission(),
    inputToCommitFirstMs: Double? = nil,
    inputToCommitLastMs: Double? = nil,
    committedAtMs: Double? = nil,
    present: PerfPresentRecord? = nil
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
    self.elided = elided
    self.answeredInputCount = answeredInputCount
    self.customLayoutFallbacks = customLayoutFallbacks
    self.layoutDependentMainActorFallbacks = layoutDependentMainActorFallbacks
    self.tailJobState = tailJobState
    self.staleFramePolicy = staleFramePolicy
    self.dropDecision = dropDecision
    self.cancelledRenderCount = cancelledRenderCount
    self.rasterPath = rasterPath
    self.rasterReuseBarriers = rasterReuseBarriers
    self.causes = causes
    self.phases = phases
    self.emission = emission
    self.inputToCommitFirstMs = inputToCommitFirstMs
    self.inputToCommitLastMs = inputToCommitLastMs
    self.committedAtMs = committedAtMs
    self.present = present
  }
}

extension PerfFrameRecord {
  /// When the oldest input this frame answered arrived, on the same origin as
  /// `presents.tsv`'s offsets. `nil` unless the frame answered input *and* the
  /// artifact carries the join coordinate.
  ///
  /// This is the whole reason `committed_at_ms` exists: it converts a duration
  /// back into a coordinate the write-completion file can be subtracted from.
  public var firstInputArrivalMs: Double? {
    guard let committedAtMs, let inputToCommitFirstMs else {
      return nil
    }
    return committedAtMs - inputToCommitFirstMs
  }

  /// Arrival of the oldest answered input to the moment its frame's bytes
  /// finished being written to the terminal.
  ///
  /// `nil` when the frame answered nothing, when no presents row joined, or
  /// when the submission was superseded — superseded bytes never reached the
  /// terminal, so there is no write to measure and reporting one would invent
  /// a latency for a frame the user never saw.
  public var inputToWriteMs: Double? {
    guard
      let arrival = firstInputArrivalMs,
      let present, present.wasWritten,
      let writtenMs = present.writtenMs
    else {
      return nil
    }
    return writtenMs - arrival
  }

  /// A frame that moved the scene: it answered input, or a deadline woke it
  /// (the momentum cadence). Settle frames and idle repaints are neither.
  ///
  /// Reducer-side by design — the runtime cannot know a scenario's intent, and
  /// both inputs to the decision are already columns.
  public var isMoving: Bool {
    // Exact cause match, not a substring test: `causes` is a `+`-joined set of
    // `WakeCause` raw values, and a future cause spelled `deadline_missed`
    // would silently reclassify every frame that carried it.
    answeredInputCount > 0 || causes.split(separator: "+").contains("deadline")
  }
}
