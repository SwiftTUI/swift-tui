import SwiftTUICore

/// Column layout for `frames.tsv`.
///
/// ## Input latency columns
///
/// `answered_inputs` is how many input events the frame answered:
/// inputs dispatched since the previous frame acquisition whose dispatch asked
/// the scheduler for work. A wheel burst that the pump merged into one summed
/// `.scrolled` event still counts once per raw notch. A frame driven only by a
/// deadline (animation, scroll momentum) answers `0`, and its two latency
/// columns are `-`.
///
/// `input_to_commit_first_ms` and `input_to_commit_last_ms` are
/// `commit instant − arrival instant` for the oldest and newest input the
/// frame answered. **Arrival is pump enqueue** — the moment the runtime first
/// saw the event, which is *after* the input reader's 1 ms coalescing flush.
/// That flush is real user-perceived latency, but it happens before the
/// runtime is involved; the PTY rig in the coordination root measures the full
/// wire number. The commit reading comes from `RunLoop.frameClock`, the same
/// clock family as the arrivals, so a virtual-clock test is deterministic.
///
/// These are **envelope semantics, not provenance**: the columns say the frame
/// answered these inputs, not that any particular redraw was caused by any
/// particular one.
///
/// Write completion is not here — it happens after commit, on the presentation
/// writer's queue. It is reported in the sibling `presents.tsv`, joined to this
/// file on the `frame` column.
///
/// ## Collection probe columns
///
/// `realized_rows` and `list_layout_derivations` are magnitude counters for
/// hosted collections, armed by `SWIFTTUI_COLLECTION_PROBES` (always on in
/// DEBUG, opt-in in release). They exist so a millisecond can be *read*: a
/// scrolling collection whose `resolve_ms` doubled either realized twice the
/// rows or paid twice per row, and only the counter separates those.
///
/// **`-` means disarmed, not zero.** A run without the probes armed reports `-`
/// in both columns; a run with them armed that realized nothing reports `0`.
/// Collapsing the two would make an unconfigured run indistinguishable from a
/// perfectly windowed one.
///
/// `realized_rows` is *not* `layout_dependent_realizations` a few columns
/// earlier. That one counts realizations forced by the custom-layout fallback
/// path; this one counts every element an indexed child source resolved a view
/// for, by any route — the number that separates a windowed collection
/// (O(viewport)) from one that collapsed to full-dataset realization.
///
/// Both are scoped to the frame *head attempt*, matching the timing columns
/// they divide into: a retried head re-reports from its retry.
///
/// `committed_at_ms` is the one *absolute* column in a file of durations: the
/// commit instant's offset from the process monotonic origin. It exists to make
/// that join exact. `presents.tsv` stamps submission and completion as offsets
/// on the same origin, so a reducer recovers an input's arrival as
/// `committed_at_ms − input_to_commit_first_ms` and gets arrival→write by
/// subtraction. Without it the two files share no origin and arrival→write
/// could only be bounded. Being process-relative it is meaningless across runs
/// — it is a join coordinate, not a measurement.
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
    "head_prepare_ms",
    "head_graph_checkpoint_create_ms",
    "head_graph_checkpoint_restore_ms",
    "head_resolve_checkpoint_restore_ms",
    "head_animation_process_resolved_tree_ms",
    "head_animation_apply_interpolations_ms",
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
    "builtin_container_measures",
    "builtin_child_measure_requests",
    "builtin_branching_milli",
    "custom_container_measures",
    "custom_child_measure_requests",
    "custom_placement_child_measure_requests",
    "custom_branching_milli",
    "realized_rows",
    "list_layout_derivations",
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
    "runtime_publication_mode",
    "runtime_dirty_plan_result",
    "runtime_selective_evaluation_disabled_reasons",
    "runtime_publication_subtree_roots",
    "runtime_publication_restored_nodes",
    "runtime_publication_invalidated",
    "runtime_publication_unmapped_invalidated",
    "runtime_publication_unmapped_sample",
    "runtime_publication_remapped_invalidated",
    "runtime_publication_dropped_invalidated",
    "runtime_publication_reconciled_invalidated",
    "runtime_publication_portal_root_queued",
    "runtime_publication_portal_root_predicted",
    "runtime_publication_portal_escalated",
    "runtime_graph_checkpoint_baseline_nodes",
    "runtime_graph_checkpoint_prepared_nodes",
    "runtime_graph_checkpoint_dirty_subtree_candidate_nodes",
    "runtime_graph_checkpoint_strategy",
    "runtime_graph_delta_checkpoint_nodes",
    "runtime_graph_delta_checkpoint_created_nodes",
    "runtime_graph_delta_checkpoint_removed_nodes",
    "runtime_graph_delta_checkpoint_epoch_delta",
    "runtime_graph_checkpoint_restore_strategy",
    "runtime_graph_checkpoint_restore_fallback_reason",
    "runtime_graph_checkpoint_delta_restore_count",
    "runtime_graph_checkpoint_fallback_restore_count",
    "runtime_non_graph_checkpoints",
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
    "answered_inputs",
    "input_to_commit_first_ms",
    "input_to_commit_last_ms",
    "committed_at_ms",
    "present_strategy",
    "present_ms",
    "present_bytes",
    "present_lines",
    "present_cells",
    "raster_path",
    "raster_reuse_barriers",
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
    "present_scroll_region",
    "translation_candidate",
    "translation_committed",
    "cache_hit",
    "total_ms",
    "elided",
    "elided_head_total_ms",
    "elided_graph_checkpoint_create_ms",
    "elided_graph_checkpoint_restore_ms",
    "elided_resolve_checkpoint_restore_ms",
    "elided_animation_tick_ms",
    "elided_commit_runtime_registrations_ms",
    "elided_animation_commit_ms",
    "elided_commit_ms",
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
    let headTimings = record.headTimings
    let headPrepareMs = formatMs(headTimings?.prepare)
    let headGraphCheckpointCreateMs = formatMs(headTimings?.graphCheckpointCreate)
    let headGraphCheckpointRestoreMs = formatMs(headTimings?.graphCheckpointRestore)
    let headResolveCheckpointRestoreMs = formatMs(headTimings?.resolveCheckpointRestore)
    let headAnimationProcessResolvedTreeMs = formatMs(
      headTimings?.animationProcessResolvedTree
    )
    let headAnimationApplyInterpolationsMs = formatMs(
      headTimings?.animationApplyInterpolations
    )
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
    let elidedHeadTotalMs = formatMs(record.elidedHeadTotalDuration)
    let elidedGraphCheckpointCreateMs = formatMs(
      record.elidedGraphCheckpointCreateDuration
    )
    let elidedGraphCheckpointRestoreMs = formatMs(
      record.elidedGraphCheckpointRestoreDuration
    )
    let elidedResolveCheckpointRestoreMs = formatMs(
      record.elidedResolveCheckpointRestoreDuration
    )
    let elidedAnimationTickMs = formatMs(record.elidedAnimationTickDuration)
    let elidedCommitRuntimeRegistrationsMs = formatMs(
      record.elidedCommitRuntimeRegistrationsDuration
    )
    let elidedAnimationCommitMs = formatMs(record.elidedAnimationCommitDuration)
    let elidedCommitMs = formatMs(record.elidedCommitDuration)
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
    let publicationUnmappedSample = record.runtimePublicationUnmappedInvalidatedIdentitySample
      .map(\.path)
      .joined(separator: ",")
    let selectiveEvaluationDisabledReasons =
      record.runtimeSelectiveEvaluationDisabledReasons.joined(separator: ",")

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
      headPrepareMs,
      headGraphCheckpointCreateMs,
      headGraphCheckpointRestoreMs,
      headResolveCheckpointRestoreMs,
      headAnimationProcessResolvedTreeMs,
      headAnimationApplyInterpolationsMs,
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
      String(record.layoutBranching.builtinContainerMeasureComputations),
      String(record.layoutBranching.builtinChildMeasureRequests),
      String(record.layoutBranching.builtinBranchingFactorMilli),
      String(record.layoutBranching.customContainerMeasureComputations),
      String(record.layoutBranching.customChildMeasureRequests),
      String(record.layoutBranching.customPlacementChildMeasureRequests),
      String(record.layoutBranching.customBranchingFactorMilli),
      formatOptionalInt(record.realizedRowCount),
      formatOptionalInt(record.listLayoutDerivationCount),
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
      record.runtimePublicationMode,
      record.runtimeDirtyPlanResult,
      selectiveEvaluationDisabledReasons.isEmpty
        ? "-"
        : sanitizeField(selectiveEvaluationDisabledReasons),
      String(record.runtimePublicationSubtreeRootCount),
      formatOptionalInt(record.runtimePublicationRestoredNodeCount),
      String(record.runtimePublicationInvalidatedIdentityCount),
      String(record.runtimePublicationUnmappedInvalidatedIdentityCount),
      publicationUnmappedSample.isEmpty ? "-" : sanitizeField(publicationUnmappedSample),
      String(record.runtimePublicationRemappedInvalidatedIdentityCount),
      String(record.runtimePublicationDroppedInvalidatedIdentityCount),
      String(record.runtimePublicationReconciledInvalidatedNodeCount),
      formatOptionalBool(record.runtimePublicationPresentationPortalRootQueued),
      formatOptionalBool(record.runtimePublicationPresentationPortalRootPredicted),
      formatOptionalBool(record.runtimePublicationPresentationPortalEscalated),
      formatOptionalInt(record.runtimePublicationGraphCheckpointBaselineNodeCount),
      formatOptionalInt(record.runtimePublicationGraphCheckpointPreparedNodeCount),
      formatOptionalInt(
        record.runtimePublicationGraphCheckpointDirtySubtreeCandidateNodeCount
      ),
      record.runtimePublicationGraphCheckpointStrategy ?? "-",
      formatOptionalInt(record.runtimePublicationGraphDeltaCheckpointNodeCount),
      formatOptionalInt(record.runtimePublicationGraphDeltaCheckpointCreatedNodeCount),
      formatOptionalInt(record.runtimePublicationGraphDeltaCheckpointRemovedNodeCount),
      record.runtimePublicationGraphDeltaCheckpointEpochDelta.map(String.init) ?? "-",
      record.runtimePublicationGraphCheckpointRestoreStrategy ?? "-",
      record.runtimePublicationGraphCheckpointRestoreFallbackReason ?? "-",
      String(record.runtimePublicationGraphCheckpointDeltaRestoreCount),
      String(record.runtimePublicationGraphCheckpointFallbackRestoreCount),
      formatOptionalBool(record.runtimePublicationNonGraphCheckpointPresent),
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
      String(record.answeredInputCount),
      formatMs(record.inputToCommitFirst),
      formatMs(record.inputToCommitLast),
      formatMs(record.committedAt),
      record.presentationStrategy,
      presentMs,
      String(record.presentationBytesWritten),
      String(record.presentationLinesTouched),
      String(record.presentationCellsChanged),
      record.rasterPath,
      record.rasterReuseBarriers.isEmpty
        ? "-" : record.rasterReuseBarriers.joined(separator: "+"),
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
      String(record.presentationScrollRegionOperationCount),
      formatTranslationCandidate(record.translationCandidate),
      formatCommittedTranslation(
        record.committedTranslation,
        presentTime: record.translationCandidate
      ),
      cacheHit,
      totalMs,
      record.elided ? "1" : "0",
      elidedHeadTotalMs,
      elidedGraphCheckpointCreateMs,
      elidedGraphCheckpointRestoreMs,
      elidedResolveCheckpointRestoreMs,
      elidedAnimationTickMs,
      elidedCommitRuntimeRegistrationsMs,
      elidedAnimationCommitMs,
      elidedCommitMs,
    ]
  }

  /// `dy=<dy>@rows<minY>..<maxY>` (rows half-open, surface coordinates), or
  /// `-` when the frame produced no candidate. The candidate-free path costs
  /// one nil check and a constant string — no per-frame allocation.
  private static func formatTranslationCandidate(
    _ candidate: ScrollTranslationCandidate?
  ) -> String {
    guard let candidate else {
      return "-"
    }
    return "dy=\(candidate.dy)@rows\(candidate.band.origin.y)..\(candidate.band.maxY)"
  }

  /// The committed-products candidate rendered as an agreement verdict
  /// against the present-time candidate (R3.2a): the column exists to
  /// measure how often the two currencies coincide, so the verdict — not the
  /// raw value — is the primary rendering. Disagreeing rows carry the
  /// committed value so the divergence class can be attributed offline.
  private static func formatCommittedTranslation(
    _ committed: CommittedScrollTranslation?,
    presentTime: ScrollTranslationCandidate?
  ) -> String {
    switch (committed, presentTime) {
    case (nil, nil):
      return "-"
    case (nil, .some):
      return "present_only"
    case (.some(let committed), nil):
      return "committed_only:\(formatted(committed))"
    case (.some(let committed), .some(let presentTime)):
      if committed.band == presentTime.band, committed.dy == presentTime.dy {
        return "agree"
      }
      return "differ:\(formatted(committed))"
    }
  }

  private static func formatted(_ committed: CommittedScrollTranslation) -> String {
    "dy=\(committed.dy)@rows\(committed.band.origin.y)..\(committed.band.maxY)"
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

  private static func formatOptionalInt(_ value: Int?) -> String {
    value.map(String.init) ?? "-"
  }

  private static func formatOptionalBool(_ value: Bool?) -> String {
    guard let value else {
      return "-"
    }
    return value ? "1" : "0"
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
