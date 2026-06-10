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
  static func read(
    from url: URL,
    presentedFrames: [PerfPresentedFrame]
  ) throws -> [PerfFrameRecord] {
    let text = try String(contentsOf: url, encoding: .utf8)
    let presentedAt = Dictionary(
      uniqueKeysWithValues: presentedFrames.map { ($0.frameNumber, $0.timestampSeconds) }
    )
    return try parse(text, presentedAt: presentedAt)
  }

  static func parse(
    _ text: String,
    presentedAt: [Int: Double] = [:]
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
        customLayoutFallbacks: int("custom_layout_fallbacks", fields, column),
        layoutDependentMainActorFallbacks: int(
          "layout_dependent_main_actor_fallbacks",
          fields,
          column
        ),
        tailJobState: string("tail_job_state", fields, column, default: "completed"),
        staleFramePolicy: string("stale_frame_policy", fields, column, default: "commit_ordered"),
        dropDecision: string("drop_decision", fields, column, default: "commit_ordered"),
        cancelledRenderCount: int("cancelled_render_count", fields, column)
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
