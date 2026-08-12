import Foundation

enum PerfFrameDiagnosticsTSVError: Error, Equatable, CustomStringConvertible {
  case missingFrameColumn
  case malformedFrameNumber(String)

  var description: String {
    switch self {
    case .missingFrameColumn:
      return "frames.tsv is missing the frame column."
    case .malformedFrameNumber(let value):
      return "frames.tsv has an invalid frame number '\(value)'."
    }
  }
}

enum PerfFrameDiagnosticsTSVReader {
  /// Reads `frames.tsv`, joining the optional `presents.tsv` sibling that sits
  /// beside it.
  ///
  /// The presents file is looked for in the frames file's own directory under
  /// its fixed name — the same rule the runtime writes it by. Absence is not an
  /// error: a run against the in-process perf host has no asynchronous
  /// presentation writer and legitimately produces none.
  static func read(
    from url: URL,
    presentedFrames: [PerfPresentedFrame]
  ) throws -> [PerfFrameRecord] {
    let text = try String(contentsOf: url, encoding: .utf8)
    let presentedAt = Dictionary(
      uniqueKeysWithValues: presentedFrames.map { ($0.frameNumber, $0.timestampSeconds) }
    )
    let presents = PerfPresentsTSVReader.read(
      from: url.deletingLastPathComponent().appendingPathComponent(presentsFileName)
    )
    return try parse(text, presentedAt: presentedAt, presents: presents)
  }

  /// Fixed, not derived from the frames file's name — matching
  /// `ProfileActivation`, which opens it beside whatever the frames sink was
  /// configured as.
  static let presentsFileName = "presents.tsv"

  static func parse(
    _ text: String,
    presentedAt: [Int: Double] = [:],
    presents: [Int: PerfPresentRecord] = [:]
  ) throws -> [PerfFrameRecord] {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    guard let headerLine = lines.first else {
      return []
    }

    let header = split(headerLine)
    let column = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
    guard let frameColumn = column["frame"] else {
      throw PerfFrameDiagnosticsTSVError.missingFrameColumn
    }

    return try lines.dropFirst().map { line in
      let fields = split(line)
      guard frameColumn < fields.count, let frameNumber = Int(fields[frameColumn]) else {
        throw PerfFrameDiagnosticsTSVError.malformedFrameNumber(
          frameColumn < fields.count ? fields[frameColumn] : ""
        )
      }

      return PerfFrameRecord(
        frameNumber: frameNumber,
        presentedAtSeconds: presentedAt[frameNumber],
        totalMs: double("total_ms", fields, column),
        workerLayoutEnqueueMs: double("worker_layout_enqueue_ms", fields, column),
        workerLayoutComputeMs: double("worker_layout_compute_ms", fields, column),
        workerRasterEnqueueMs: double("worker_raster_enqueue_ms", fields, column),
        workerRasterComputeMs: double("worker_raster_compute_ms", fields, column),
        mainActorBlockedMs: double("main_actor_blocked_ms", fields, column),
        mainActorSuspendedMs: double("main_actor_suspended_ms", fields, column),
        presentationDurationMs: double("present_ms", fields, column),
        headPrepareMs: double("head_prepare_ms", fields, column),
        headGraphCheckpointCreateMs: double("head_graph_checkpoint_create_ms", fields, column),
        headGraphCheckpointRestoreMs: double(
          "head_graph_checkpoint_restore_ms",
          fields,
          column
        ),
        headResolveCheckpointRestoreMs: double(
          "head_resolve_checkpoint_restore_ms",
          fields,
          column
        ),
        headAnimationProcessResolvedTreeMs: double(
          "head_animation_process_resolved_tree_ms",
          fields,
          column
        ),
        headAnimationApplyInterpolationsMs: double(
          "head_animation_apply_interpolations_ms",
          fields,
          column
        ),
        elidedHeadTotalMs: double("elided_head_total_ms", fields, column),
        elidedGraphCheckpointCreateMs: double(
          "elided_graph_checkpoint_create_ms",
          fields,
          column
        ),
        elidedGraphCheckpointRestoreMs: double(
          "elided_graph_checkpoint_restore_ms",
          fields,
          column
        ),
        elidedResolveCheckpointRestoreMs: double(
          "elided_resolve_checkpoint_restore_ms",
          fields,
          column
        ),
        elidedAnimationTickMs: double("elided_animation_tick_ms", fields, column),
        elidedCommitRuntimeRegistrationsMs: double(
          "elided_commit_runtime_registrations_ms",
          fields,
          column
        ),
        elidedAnimationCommitMs: double("elided_animation_commit_ms", fields, column),
        elidedCommitMs: double("elided_commit_ms", fields, column),
        elided: bool("elided", fields, column),
        answeredInputCount: int("answered_inputs", fields, column),
        customLayoutFallbacks: int("custom_layout_fallbacks", fields, column),
        layoutDependentMainActorFallbacks: int(
          "layout_dependent_main_actor_fallbacks",
          fields,
          column
        ),
        // `optionalInt`, not `int`: these columns write `-` when the probes
        // were disarmed, and a disarmed run reported as zero realized rows
        // would read as a perfectly windowed one.
        realizedRows: optionalInt("realized_rows", fields, column),
        listLayoutDerivations: optionalInt("list_layout_derivations", fields, column),
        tailJobState: string("tail_job_state", fields, column, default: "completed"),
        staleFramePolicy: string("stale_frame_policy", fields, column, default: "commit_ordered"),
        dropDecision: string("drop_decision", fields, column, default: "commit_ordered"),
        cancelledRenderCount: int("cancelled_render_count", fields, column),
        rasterPath: string("raster_path", fields, column, default: "-"),
        rasterReuseBarriers: string("raster_reuse_barriers", fields, column, default: "-"),
        causes: string("causes", fields, column, default: ""),
        phases: PerfFramePhaseTimings(
          resolveMs: double("resolve_ms", fields, column),
          measureMs: double("measure_ms", fields, column),
          placeMs: double("place_ms", fields, column),
          semanticsMs: double("semantics_ms", fields, column),
          drawMs: double("draw_ms", fields, column),
          rasterMs: double("raster_ms", fields, column),
          commitMs: double("commit_ms", fields, column),
          pipelineMs: double("pipeline_ms", fields, column)
        ),
        emission: PerfFrameEmission(
          presentBytes: int("present_bytes", fields, column),
          presentCells: int("present_cells", fields, column),
          // Parsed through its own type, not `int`: this column's `full`
          // sentinel would otherwise fall through to 0 and report a
          // whole-surface repaint as the cheapest frame in the trace.
          damageRows: PerfDamageRows(field: rawField("damage_rows", fields, column)),
          damageCells: optionalInt("damage_cells", fields, column),
          coalescedEventBatches: int("coalesced_event_batches", fields, column)
        ),
        workCounters: PerfFrameWorkCounters(
          // Fraction columns (`computed/total`): only the numerator is work.
          resolvedComputed: fractionNumerator("resolved_computed", fields, column),
          resolvedReused: fractionNumerator("resolved_reused", fields, column),
          measuredComputed: fractionNumerator("measured_computed", fields, column),
          drawNodes: optionalInt("draw_nodes", fields, column),
          builtinContainerMeasures: optionalInt(
            "builtin_container_measures", fields, column),
          builtinChildMeasureRequests: optionalInt(
            "builtin_child_measure_requests", fields, column),
          builtinChildMeasureRequestsProbe: optionalInt(
            "builtin_child_measure_requests_probe", fields, column),
          customContainerMeasures: optionalInt(
            "custom_container_measures", fields, column),
          customChildMeasureRequests: optionalInt(
            "custom_child_measure_requests", fields, column),
          customChildMeasureRequestsProbe: optionalInt(
            "custom_child_measure_requests_probe", fields, column),
          customPlacementChildMeasureRequests: optionalInt(
            "custom_placement_child_measure_requests", fields, column)
        ),
        inputToCommitFirstMs: double("input_to_commit_first_ms", fields, column),
        inputToCommitLastMs: double("input_to_commit_last_ms", fields, column),
        committedAtMs: double("committed_at_ms", fields, column),
        present: presents[frameNumber]
      )
    }
  }

  private static func split<S: StringProtocol>(_ line: S) -> [String] {
    String(line).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
  }

  private static func string(
    _ name: String,
    _ fields: [String],
    _ column: [String: Int],
    default defaultValue: String
  ) -> String {
    guard let index = column[name], index < fields.count else {
      return defaultValue
    }
    let value = fields[index]
    return value.isEmpty ? defaultValue : value
  }

  private static func int(
    _ name: String,
    _ fields: [String],
    _ column: [String: Int]
  ) -> Int {
    guard let index = column[name], index < fields.count else {
      return 0
    }
    return Int(fields[index]) ?? 0
  }

  /// The raw column text, or `nil` when the column is absent from this file.
  ///
  /// Needed by columns whose vocabulary is wider than a number — `damage_rows`
  /// carries a `full` sentinel — so the caller can tell "the column said
  /// something I must interpret" from "the column was never written".
  private static func rawField(
    _ name: String,
    _ fields: [String],
    _ column: [String: Int]
  ) -> String? {
    guard let index = column[name], index < fields.count else {
      return nil
    }
    return fields[index]
  }

  /// The numerator of a `computed/total` fraction column, or `nil` when the
  /// column is absent. The whole value is also accepted as a plain integer so
  /// a hand-written test fixture need not fabricate a denominator.
  private static func fractionNumerator(
    _ name: String,
    _ fields: [String],
    _ column: [String: Int]
  ) -> Int? {
    guard let value = rawField(name, fields, column), value != "-", !value.isEmpty else {
      return nil
    }
    guard let slash = value.firstIndex(of: "/") else {
      return Int(value)
    }
    return Int(value[value.startIndex..<slash])
  }

  /// An integer column that distinguishes absent/`-` from zero.
  private static func optionalInt(
    _ name: String,
    _ fields: [String],
    _ column: [String: Int]
  ) -> Int? {
    guard let value = rawField(name, fields, column), value != "-", !value.isEmpty else {
      return nil
    }
    return Int(value)
  }

  private static func bool(
    _ name: String,
    _ fields: [String],
    _ column: [String: Int]
  ) -> Bool {
    guard let index = column[name], index < fields.count else {
      return false
    }
    switch fields[index].lowercased() {
    case "1", "true", "yes":
      return true
    default:
      return false
    }
  }

  private static func double(
    _ name: String,
    _ fields: [String],
    _ column: [String: Int]
  ) -> Double? {
    guard let index = column[name], index < fields.count else {
      return nil
    }
    let value = fields[index]
    guard value != "-", !value.isEmpty else {
      return nil
    }
    return Double(value)
  }
}
