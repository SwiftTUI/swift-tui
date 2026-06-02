import Foundation
import SwiftTUI
import Testing

@testable import TermUIPerf

struct SummaryReducerTests {
  @Test("known samples produce percentile summaries")
  func knownSamplesProducePercentileSummaries() throws {
    let summary = SummaryReducer.reduce(
      metadata: metadata(),
      events: [
        event(id: "a", dispatch: 1.00, present: 1.01),
        event(id: "b", dispatch: 1.00, present: 1.02),
        event(id: "c", dispatch: 1.00, present: 1.03),
        event(id: "d", dispatch: 1.00, present: 1.04),
      ],
      cpuSamples: [],
      frames: [
        frame(number: 1, presentedAt: 2.00),
        frame(number: 2, presentedAt: 2.01),
        frame(number: 3, presentedAt: 2.03),
      ]
    )

    #expect(summary.inputToPresentLatencyMs.count == 4)
    #expect(isApproximately(summary.inputToPresentLatencyMs.p50, 25))
    #expect(isApproximately(summary.inputToPresentLatencyMs.p95, 38.5))
    #expect(isApproximately(summary.frameIntervalMs.p50, 15))
  }

  @Test("CPU seconds per frame comes from sample deltas and committed frames")
  func cpuSecondsPerFrameComesFromSampleDeltasAndCommittedFrames() throws {
    let summary = SummaryReducer.reduce(
      metadata: metadata(),
      events: [event(id: "a", dispatch: 0, present: 0.01)],
      cpuSamples: [
        PerfCPUSample(
          timestampSeconds: 0,
          userCPUSeconds: 0.2,
          systemCPUSeconds: 0.1,
          wallDeltaSeconds: 0.5,
          estimatedCPUPercent: 60
        ),
        PerfCPUSample(
          timestampSeconds: 1,
          userCPUSeconds: 0.2,
          systemCPUSeconds: 0.1,
          wallDeltaSeconds: 0.5,
          estimatedCPUPercent: 60
        ),
      ],
      frames: [
        frame(number: 1),
        frame(number: 2),
        frame(number: 3, tailJobState: "dropped_completed", dropDecision: "drop_visual_only"),
      ]
    )

    #expect(isApproximately(summary.totalCPUSeconds, 0.6))
    #expect(summary.committedFrameCount == 2)
    #expect(summary.diagnosticFrameCount == 3)
    #expect(summary.skippedFrameCount == 1)
    #expect(isApproximately(summary.cpuSecondsPerCommittedFrame, 0.3))
    #expect(isApproximately(summary.cpuSecondsPerDiagnosticFrame, 0.2))
    #expect(summary.completedDropCount == 1)
  }

  @Test("missing optional frame fields do not crash reduction")
  func missingOptionalFrameFieldsDoNotCrashReduction() throws {
    let summary = SummaryReducer.reduce(
      metadata: metadata(),
      events: [],
      cpuSamples: [],
      frames: [
        frame(number: 1, totalMs: nil),
        frame(number: 2, totalMs: nil, tailJobState: "cancelled_before_start"),
      ]
    )

    #expect(summary.mainActorBlockedRatio == nil)
    #expect(summary.workerLayoutComputeMs.count == 0)
    #expect(summary.cancelledFrameCount == 1)
    #expect(summary.skippedFrameCount == 1)
  }

  @Test("presentation duration excludes skipped frames")
  func presentationDurationExcludesSkippedFrames() throws {
    let summary = SummaryReducer.reduce(
      metadata: metadata(),
      events: [],
      cpuSamples: [],
      frames: [
        frame(number: 1),
        frame(
          number: 2,
          totalMs: nil,
          staleFramePolicy: "elided_offscreen",
          tailJobState: "-",
          dropDecision: "-",
          elided: true
        ),
        frame(number: 3, tailJobState: "dropped_completed", dropDecision: "drop_visual_only"),
      ]
    )

    #expect(summary.committedFrameCount == 1)
    #expect(summary.diagnosticFrameCount == 3)
    #expect(summary.skippedFrameCount == 2)
    #expect(summary.elidedFrameCount == 1)
    #expect(summary.presentationDurationMs.count == 1)
    #expect(isApproximately(summary.presentationDurationMs.p50, 3))
  }

  @Test("elided frame spans are summarized")
  func elidedFrameSpansAreSummarized() throws {
    let summary = SummaryReducer.reduce(
      metadata: metadata(),
      events: [],
      cpuSamples: [],
      frames: [
        frame(number: 1),
        frame(
          number: 2,
          totalMs: nil,
          staleFramePolicy: "elided_offscreen",
          tailJobState: "-",
          dropDecision: "-",
          elided: true,
          elidedHeadTotalMs: 2.0,
          elidedGraphCheckpointCreateMs: 0.4,
          elidedGraphCheckpointRestoreMs: 0.5,
          elidedResolveCheckpointRestoreMs: 0.2,
          elidedAnimationTickMs: 0.7,
          elidedCommitRuntimeRegistrationsMs: 0.1,
          elidedAnimationCommitMs: 0.05,
          elidedCommitMs: 0.8
        ),
      ]
    )

    #expect(summary.elidedHeadTotalMs.count == 1)
    #expect(isApproximately(summary.elidedHeadTotalMs.p50, 2.0))
    #expect(isApproximately(summary.elidedGraphCheckpointCreateMs.p50, 0.4))
    #expect(isApproximately(summary.elidedGraphCheckpointRestoreMs.p50, 0.5))
    #expect(isApproximately(summary.elidedResolveCheckpointRestoreMs.p50, 0.2))
    #expect(isApproximately(summary.elidedAnimationTickMs.p50, 0.7))
    #expect(isApproximately(summary.elidedCommitRuntimeRegistrationsMs.p50, 0.1))
    #expect(isApproximately(summary.elidedAnimationCommitMs.p50, 0.05))
    #expect(isApproximately(summary.elidedCommitMs.p50, 0.8))
  }

  @Test("idle events do not contribute latency or input-event CPU ratios")
  func idleEventsDoNotContributeLatencyOrInputRatios() throws {
    let summary = SummaryReducer.reduce(
      metadata: metadata(),
      events: [
        event(id: "idle", eventType: "idle", dispatch: 2.00, present: 1.00),
        event(id: "click", eventType: "mouse_click", dispatch: 3.00, present: 3.02),
      ],
      cpuSamples: [
        PerfCPUSample(
          timestampSeconds: 0,
          userCPUSeconds: 0.2,
          systemCPUSeconds: 0.1,
          wallDeltaSeconds: 0.5,
          estimatedCPUPercent: 60
        )
      ],
      frames: [frame(number: 1)]
    )

    #expect(summary.inputToPresentLatencyMs.count == 1)
    #expect(isApproximately(summary.inputToPresentLatencyMs.p50, 20))
    #expect(isApproximately(summary.cpuSecondsPerInputEvent, 0.3))
  }

  @Test("summary JSON key names are stable")
  func summaryJSONKeyNamesAreStable() throws {
    let summary = SummaryReducer.reduce(
      metadata: metadata(),
      events: [event(id: "a", dispatch: 0, present: 0.01)],
      cpuSamples: [],
      frames: [frame(number: 1)]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(summary)
    let object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    #expect(object.keys.contains("input_to_present_latency_ms"))
    #expect(object.keys.contains("cpu_seconds_per_committed_frame"))
    #expect(object.keys.contains("cpu_seconds_per_diagnostic_frame"))
    #expect(object.keys.contains("main_actor_blocked_ratio"))
    #expect(object.keys.contains("worker_layout_compute_ms"))
    #expect(object.keys.contains("diagnostic_frame_count"))
    #expect(object.keys.contains("elided_frame_count"))
    #expect(object.keys.contains("elided_head_total_ms"))
    #expect(object.keys.contains("elided_commit_ms"))
    #expect(object.keys.contains("cancelled_frame_count"))
    #expect(!object.keys.contains("cancellation_count"))
  }

  @Test("TSV writers keep deterministic headers and nil placeholders")
  func tsvWritersKeepDeterministicHeadersAndNilPlaceholders() throws {
    let eventsTSV = PerfTSVWriter.eventsTSV([
      PerfEventRecord(
        eventID: "event\t1",
        eventType: "click",
        dispatchTimeSeconds: 1,
        expectedVisualMarker: "value\n1"
      )
    ])
    let cpuTSV = PerfTSVWriter.cpuTSV([
      PerfCPUSample(
        timestampSeconds: 1,
        userCPUSeconds: 0.25,
        systemCPUSeconds: 0.75,
        wallDeltaSeconds: 0.5,
        estimatedCPUPercent: 200
      )
    ])

    #expect(eventsTSV.hasPrefix(PerfTSVWriter.eventHeader.joined(separator: "\t")))
    #expect(eventsTSV.contains("event 1\tclick\t1.000000\tvalue 1\t-\t-\t-\t-"))
    #expect(cpuTSV.hasPrefix(PerfTSVWriter.cpuHeader.joined(separator: "\t")))
    #expect(cpuTSV.contains("1.000000\t0.250000\t0.750000\t1.000000\t0.500000\t200.000000"))
  }

  private func metadata() -> PerfRunMetadata {
    PerfRunMetadata(
      gitSHA: "abc123",
      dirty: false,
      renderMode: .async,
      scenario: .galleryAnimationClick,
      iterationCount: 4,
      configuration: "release",
      swiftVersion: "Swift 6.3",
      osVersion: "macOS 15",
      hardwareModel: "Mac",
      processorCount: 10,
      terminalSize: PerfTerminalSize(columns: 100, rows: 32),
      startedAt: "2026-05-02T00:00:00Z",
      endedAt: "2026-05-02T00:00:01Z"
    )
  }

  private func event(
    id: String,
    eventType: String = "input",
    dispatch: Double,
    present: Double
  ) -> PerfEventRecord {
    PerfEventRecord(
      eventID: id,
      eventType: eventType,
      dispatchTimeSeconds: dispatch,
      expectedVisualMarker: id,
      firstMatchingFrame: 1,
      firstMatchingTimeSeconds: present,
      finalSettledFrame: 2,
      finalSettledTimeSeconds: present + 0.01
    )
  }

  private func frame(
    number: Int,
    presentedAt: Double? = nil,
    totalMs: Double? = 10,
    staleFramePolicy: String = "commit_ordered",
    tailJobState: String = "completed",
    dropDecision: String = "commit_ordered",
    elided: Bool = false,
    elidedHeadTotalMs: Double? = nil,
    elidedGraphCheckpointCreateMs: Double? = nil,
    elidedGraphCheckpointRestoreMs: Double? = nil,
    elidedResolveCheckpointRestoreMs: Double? = nil,
    elidedAnimationTickMs: Double? = nil,
    elidedCommitRuntimeRegistrationsMs: Double? = nil,
    elidedAnimationCommitMs: Double? = nil,
    elidedCommitMs: Double? = nil
  ) -> PerfFrameRecord {
    PerfFrameRecord(
      frameNumber: number,
      presentedAtSeconds: presentedAt,
      totalMs: totalMs,
      workerLayoutEnqueueMs: 1,
      workerLayoutComputeMs: totalMs == nil ? nil : 2,
      workerRasterEnqueueMs: 3,
      workerRasterComputeMs: 4,
      mainActorBlockedMs: totalMs == nil ? nil : 1,
      mainActorSuspendedMs: totalMs == nil ? nil : 2,
      presentationDurationMs: 3,
      elidedHeadTotalMs: elidedHeadTotalMs,
      elidedGraphCheckpointCreateMs: elidedGraphCheckpointCreateMs,
      elidedGraphCheckpointRestoreMs: elidedGraphCheckpointRestoreMs,
      elidedResolveCheckpointRestoreMs: elidedResolveCheckpointRestoreMs,
      elidedAnimationTickMs: elidedAnimationTickMs,
      elidedCommitRuntimeRegistrationsMs: elidedCommitRuntimeRegistrationsMs,
      elidedAnimationCommitMs: elidedAnimationCommitMs,
      elidedCommitMs: elidedCommitMs,
      elided: elided,
      customLayoutFallbacks: 1,
      layoutDependentMainActorFallbacks: 2,
      tailJobState: tailJobState,
      staleFramePolicy: staleFramePolicy,
      dropDecision: dropDecision
    )
  }

  private func isApproximately(_ actual: Double?, _ expected: Double) -> Bool {
    guard let actual else {
      return false
    }
    return abs(actual - expected) < 0.000_001
  }

  private func isApproximately(_ actual: Double, _ expected: Double) -> Bool {
    abs(actual - expected) < 0.000_001
  }
}
