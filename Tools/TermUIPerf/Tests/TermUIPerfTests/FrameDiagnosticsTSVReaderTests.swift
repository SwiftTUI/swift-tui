import Testing

@testable import TermUIPerf

struct FrameDiagnosticsTSVReaderTests {
  @Test("reader parses diagnostic timing fields and presentation timestamps")
  func readerParsesDiagnosticFieldsAndPresentationTimestamps() throws {
    let records = try PerfFrameDiagnosticsTSVReader.parse(
      """
      frame\ttotal_ms\tworker_layout_enqueue_ms\tworker_layout_compute_ms\tworker_raster_enqueue_ms\tworker_raster_compute_ms\tmain_actor_blocked_ms\tmain_actor_suspended_ms\thead_prepare_ms\thead_graph_checkpoint_create_ms\thead_graph_checkpoint_restore_ms\thead_resolve_checkpoint_restore_ms\thead_animation_process_resolved_tree_ms\thead_animation_apply_interpolations_ms\tcustom_layout_fallbacks\tlayout_dependent_main_actor_fallbacks\tstale_frame_policy\ttail_job_state\tcancelled_render_count\tdrop_decision\tpresent_ms\telided\telided_head_total_ms\telided_graph_checkpoint_create_ms\telided_graph_checkpoint_restore_ms\telided_resolve_checkpoint_restore_ms\telided_animation_tick_ms\telided_commit_runtime_registrations_ms\telided_animation_commit_ms\telided_commit_ms
      1\t10.50\t1.25\t2.50\t0.75\t3.00\t0.50\t1.00\t4.50\t0.30\t0.40\t0.20\t1.10\t0.60\t2\t3\tcommit_ordered\tcompleted\t4\tcommit_ordered\t0.12\t0\t-\t-\t-\t-\t-\t-\t-\t-
      2\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t0\t0\telided_offscreen\t-\t4\t-\t-\t1\t2.10\t0.30\t0.40\t0.20\t0.50\t0.10\t0.05\t0.60
      """,
      presentedAt: [1: 20.0]
    )

    #expect(records.count == 2)
    #expect(records[0].frameNumber == 1)
    #expect(records[0].presentedAtSeconds == 20.0)
    #expect(records[0].totalMs == 10.50)
    #expect(records[0].workerLayoutEnqueueMs == 1.25)
    #expect(records[0].workerLayoutComputeMs == 2.50)
    #expect(records[0].workerRasterEnqueueMs == 0.75)
    #expect(records[0].workerRasterComputeMs == 3.00)
    #expect(records[0].mainActorBlockedMs == 0.50)
    #expect(records[0].mainActorSuspendedMs == 1.00)
    #expect(records[0].headPrepareMs == 4.50)
    #expect(records[0].headGraphCheckpointCreateMs == 0.30)
    #expect(records[0].headGraphCheckpointRestoreMs == 0.40)
    #expect(records[0].headResolveCheckpointRestoreMs == 0.20)
    #expect(records[0].headAnimationProcessResolvedTreeMs == 1.10)
    #expect(records[0].headAnimationApplyInterpolationsMs == 0.60)
    #expect(records[0].presentationDurationMs == 0.12)
    #expect(records[0].elided == false)
    #expect(records[0].customLayoutFallbacks == 2)
    #expect(records[0].layoutDependentMainActorFallbacks == 3)
    #expect(records[0].tailJobState == "completed")
    #expect(records[0].staleFramePolicy == "commit_ordered")
    #expect(records[0].dropDecision == "commit_ordered")
    #expect(records[0].cancelledRenderCount == 4)

    #expect(records[1].frameNumber == 2)
    #expect(records[1].presentedAtSeconds == nil)
    #expect(records[1].totalMs == nil)
    #expect(records[1].elided == true)
    #expect(records[1].elidedHeadTotalMs == 2.10)
    #expect(records[1].elidedGraphCheckpointCreateMs == 0.30)
    #expect(records[1].elidedGraphCheckpointRestoreMs == 0.40)
    #expect(records[1].elidedResolveCheckpointRestoreMs == 0.20)
    #expect(records[1].elidedAnimationTickMs == 0.50)
    #expect(records[1].elidedCommitRuntimeRegistrationsMs == 0.10)
    #expect(records[1].elidedAnimationCommitMs == 0.05)
    #expect(records[1].elidedCommitMs == 0.60)
    #expect(records[1].tailJobState == "-")
    #expect(records[1].staleFramePolicy == "elided_offscreen")
    #expect(records[1].dropDecision == "-")
  }

  @Test("parsed elided rows contribute to skipped-frame summaries")
  func parsedElidedRowsContributeToSkippedFrameSummaries() throws {
    let records = try PerfFrameDiagnosticsTSVReader.parse(
      """
      frame\ttotal_ms\ttail_job_state\tstale_frame_policy\tdrop_decision\telided
      1\t10.0\tcompleted\tcommit_ordered\tcommit_ordered\t0
      2\t-\t-\telided_offscreen\t-\t1
      """,
      presentedAt: [1: 10.0]
    )

    let summary = SummaryReducer.reduce(
      metadata: metadata(),
      events: [],
      cpuSamples: [],
      frames: records
    )

    #expect(summary.committedFrameCount == 1)
    #expect(summary.diagnosticFrameCount == 2)
    #expect(summary.skippedFrameCount == 1)
    #expect(summary.elidedFrameCount == 1)
    #expect(summary.frameIntervalMs.count == 0)
  }

  @Test("reader rejects missing frame column")
  func readerRejectsMissingFrameColumn() throws {
    #expect(throws: PerfFrameDiagnosticsTSVError.missingFrameColumn) {
      _ = try PerfFrameDiagnosticsTSVReader.parse(
        """
        total_ms\ttail_job_state
        10.0\tcompleted
        """
      )
    }
  }

  private func metadata() -> PerfRunMetadata {
    PerfRunMetadata(
      gitSHA: "abc123",
      dirty: false,
      renderMode: .async,
      scenario: .syntheticOffscreenPhaseAnimator,
      iterationCount: 1,
      configuration: "release",
      swiftVersion: "Swift 6.3",
      osVersion: "macOS 15",
      terminalSize: PerfTerminalSize(columns: 80, rows: 24),
      startedAt: "2026-06-02T00:00:00Z"
    )
  }
}
