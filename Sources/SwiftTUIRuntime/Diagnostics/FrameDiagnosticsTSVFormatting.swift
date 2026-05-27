import SwiftTUICore

package enum FrameDiagnosticsTSVFormatting {
  package static let headerFields = [
    "frame",
    "causes",
    "focus_syncs",
    "invalidated",
    "resolved_computed",
    "resolved_reused",
    "measured_computed",
    "draw_nodes",
    "interactions",
    "focus_regions",
    "resolve_ms",
    "measure_ms",
    "place_ms",
    "semantics_ms",
    "draw_ms",
    "raster_ms",
    "commit_ms",
    "pipeline_ms",
    "desired_generation",
    "render_generation",
    "layout_input_generation",
    "layout_output_generation",
    "raster_input_generation",
    "raster_output_generation",
    "coalesced_event_batches",
    "coalesced_wake_causes",
    "coalesced_intent_requests",
    "scheduled_animation_request",
    "scheduled_animation_batch",
    "animation_controller_active_animations",
    "animation_controller_pending_work",
    "worker_layout_enqueue_ms",
    "worker_layout_compute_ms",
    "worker_raster_enqueue_ms",
    "worker_raster_compute_ms",
    "worker_completion_to_commit_ms",
    "main_actor_blocked_ms",
    "main_actor_suspended_ms",
    "custom_layout_fallbacks",
    "first_custom_layout_fallback",
    "layout_dependent_realizations",
    "layout_dependent_cache_hits",
    "layout_dependent_main_actor_fallbacks",
    "geometry_anchor_resolution_misses",
    "first_geometry_anchor_resolution_miss",
    "geometry_missing_named_coordinate_spaces",
    "first_geometry_missing_named_coordinate_space",
    "geometry_duplicate_named_coordinate_spaces",
    "first_geometry_duplicate_named_coordinate_space",
    "runtime_pointer_handlers",
    "runtime_pointer_hover_handlers",
    "runtime_gesture_recognizers",
    "runtime_gesture_state_bindings",
    "runtime_issue_count",
    "runtime_issues",
    "stale_frame_policy",
    "tail_job_state",
    "tail_cancel_reason",
    "cancelled_render_count",
    "newest_desired_at_tail_start",
    "newest_desired_at_tail_result",
    "drop_blockers",
    "drop_decision",
    "drop_generation",
    "newest_desired_at_drop",
    "drop_reconciliation_mode",
    "drop_reconciliation_effects",
    "presentation_recovery_after_drop",
    "input_events_during_render_suspension",
    "present_strategy",
    "present_ms",
    "present_bytes",
    "present_lines",
    "present_cells",
    "damage_rows",
    "damage_range_rows",
    "damage_spans",
    "damage_cells",
    "damage_graphics",
    "damage_full_text",
    "damage_full_graphics",
    "present_sync",
    "present_graphics_scope",
    "present_graphics_attachments",
    "present_edit_op",
    "present_edit_ops",
    "cache_hit",
    "total_ms",
  ]

  package static func fields(
    for record: FrameDiagnosticRecord
  ) -> [String] {
    let timings = record.phaseTimings
    let resolveMs = formatMs(timings?.resolve)
    let measureMs = formatMs(timings?.measure)
    let placeMs = formatMs(timings?.place)
    let semanticsMs = formatMs(timings?.semantics)
    let drawMs = formatMs(timings?.draw)
    let rasterMs = formatMs(timings?.raster)
    let commitMs = formatMs(timings?.commit)
    let pipelineMs = formatMs(timings?.total)
    let workerTimings = record.workerTimings
    let renderGenerations = record.renderGenerations
    let layoutEnqueueMs = formatMs(workerTimings?.layoutEnqueueToStart)
    let layoutComputeMs = formatMs(workerTimings?.layoutCompute)
    let rasterEnqueueMs = formatMs(workerTimings?.rasterEnqueueToStart)
    let rasterComputeMs = formatMs(workerTimings?.rasterCompute)
    let workerCompletionToCommitMs = formatMs(workerTimings?.completionToMainCommit)
    let mainActorTimings = record.mainActorTimings
    let mainActorBlockedMs = formatMs(mainActorTimings?.blocked)
    let mainActorSuspendedMs = formatMs(mainActorTimings?.suspended)
    let presentMs = formatMs(record.presentationDuration)
    let totalMs = formatMs(record.totalFrameDuration)
    let cacheHit =
      record.measurementCacheHitRate.map { rate in
        let pct = Int(rate * 1000)
        return "\(pct / 10).\(pct % 10)%"
      } ?? "-"
    let damageRows = record.damageRowCount.map(String.init) ?? "full"
    let damageRangeAwareRows = record.damageRangeAwareRowCount.map(String.init) ?? "-"
    let damageSpans = record.damageTextSpanCount.map(String.init) ?? "-"
    let damageCells = record.damageTextCellCount.map(String.init) ?? "-"
    let damageGraphics = record.damageGraphicsInvalidationCount.map(String.init) ?? "-"
    let scheduledAnimationBatch = record.scheduledAnimationBatchID.map(String.init) ?? "-"

    return [
      String(record.frameNumber),
      record.causeSummary,
      String(record.focusSyncRerenders),
      String(record.invalidatedIdentityCount),
      "\(record.resolvedNodesComputed)/\(record.resolvedNodeCount)",
      "\(record.resolvedNodesReused)/\(record.resolvedNodeCount)",
      "\(record.measuredNodesComputed)/\(record.measuredNodeCount)",
      "\(record.drawNodeCount)",
      "\(record.interactionRegionCount)",
      "\(record.focusRegionCount)",
      resolveMs,
      measureMs,
      placeMs,
      semanticsMs,
      drawMs,
      rasterMs,
      commitMs,
      pipelineMs,
      String(record.desiredGeneration),
      String(renderGenerations.render.rawValue),
      formatGeneration(renderGenerations.layoutInput),
      formatGeneration(renderGenerations.layoutOutput),
      formatGeneration(renderGenerations.rasterInput),
      formatGeneration(renderGenerations.rasterOutput),
      String(record.coalescedEventBatches),
      record.coalescedWakeCauses,
      String(record.coalescedIntentRequests),
      record.scheduledAnimationRequest,
      scheduledAnimationBatch,
      String(record.animationControllerActiveAnimationCount),
      record.animationControllerHasPendingWork ? "1" : "0",
      layoutEnqueueMs,
      layoutComputeMs,
      rasterEnqueueMs,
      rasterComputeMs,
      workerCompletionToCommitMs,
      mainActorBlockedMs,
      mainActorSuspendedMs,
      String(record.customLayoutFallbackCount),
      record.firstCustomLayoutFallbackIdentity ?? "-",
      String(record.layoutDependentRealizations),
      String(record.layoutDependentRealizationCacheHits),
      String(record.layoutDependentMainActorFallbacks),
      String(record.geometryAnchorResolutionMissCount),
      record.firstGeometryAnchorResolutionMissIdentity ?? "-",
      String(record.geometryMissingNamedCoordinateSpaceCount),
      record.firstGeometryMissingNamedCoordinateSpaceName ?? "-",
      String(record.geometryDuplicateNamedCoordinateSpaceCount),
      record.firstGeometryDuplicateNamedCoordinateSpaceName ?? "-",
      String(record.runtimePointerHandlerCount),
      String(record.runtimePointerHoverHandlerCount),
      String(record.runtimeGestureRecognizerCount),
      String(record.runtimeGestureStateBindingCount),
      String(record.runtimeIssues.count),
      formatRuntimeIssues(record.runtimeIssues),
      record.staleFramePolicy,
      record.tailJobState,
      record.tailCancelReason,
      String(record.cancelledRenderCount),
      record.newestDesiredAtTailStart.map(String.init) ?? "-",
      record.newestDesiredAtTailResult.map(String.init) ?? "-",
      formatDropBlockers(record.dropEligibilityBlockers),
      record.dropDecision,
      record.dropGeneration.map(String.init) ?? "-",
      record.newestDesiredAtDrop.map(String.init) ?? "-",
      record.dropReconciliationMode,
      record.dropReconciliationEffects,
      record.presentationRecoveryAfterDrop ? "1" : "0",
      String(record.inputEventsQueuedDuringRenderSuspension),
      record.presentationStrategy,
      presentMs,
      String(record.presentationBytesWritten),
      String(record.presentationLinesTouched),
      String(record.presentationCellsChanged),
      damageRows,
      damageRangeAwareRows,
      damageSpans,
      damageCells,
      damageGraphics,
      record.damageRequiresFullTextRepaint ? "1" : "0",
      record.damageRequiresFullGraphicsReplay ? "1" : "0",
      record.presentationUsedSynchronizedOutput ? "1" : "0",
      record.presentationGraphicsReplayScope,
      String(record.presentationGraphicsAttachmentsReplayed),
      record.presentationEditOperationLowering,
      String(record.presentationEditOperationCount),
      cacheHit,
      totalMs,
    ]
  }

  private static func formatMs(_ duration: Duration?) -> String {
    guard let duration else {
      return "-"
    }
    let totalMicroseconds =
      duration.components.seconds * 1_000_000
      + duration.components.attoseconds / 1_000_000_000_000
    let ms = totalMicroseconds / 1000
    let frac = (totalMicroseconds % 1000) / 10
    return "\(ms).\(frac < 10 ? "0" : "")\(frac)"
  }

  private static func formatGeneration(_ generation: RenderGeneration?) -> String {
    generation.map { String($0.rawValue) } ?? "-"
  }

  private static func formatDropBlockers(
    _ blockers: Set<FrameDropEligibility.Blocker>
  ) -> String {
    guard !blockers.isEmpty else {
      return "-"
    }
    return blockers.map(\.rawValue).sorted().joined(separator: "+")
  }

  private static func formatRuntimeIssues(
    _ issues: [RuntimeIssue]
  ) -> String {
    guard !issues.isEmpty else {
      return "-"
    }
    return
      issues
      .map { sanitizeField($0.description) }
      .joined(separator: " | ")
  }

  private static func sanitizeField(
    _ value: String
  ) -> String {
    String(
      value.map { character in
        switch character {
        case "\t", "\n", "\r":
          " "
        default:
          character
        }
      }
    )
  }
}
