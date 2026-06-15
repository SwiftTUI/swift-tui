import Foundation
import SwiftTUICore
import Testing

@_spi(Runners) @testable import SwiftTUIProfiling
@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite
struct TSVFileSinkTests {
  @Test("TSVFileSink writes a single header then one row per sample")
  func writesHeaderAndRows() throws {
    let samples: [RuntimeFrameSample] = [makeCommittedSample(), makeZeroArtifactSample()]

    let sinkPath = Self.temporaryPath()
    let sink = TSVFileSink(path: sinkPath)
    #expect(sink != nil)
    for sample in samples {
      sink?.record(sample)
    }

    let text = try String(contentsOfFile: sinkPath, encoding: .utf8)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    #expect(lines.count == samples.count + 1)

    let header = FrameDiagnosticsTSVFormatting.headerFields
    #expect(String(lines[0]) == header.joined(separator: "\t"))
    let headerColumns = Dictionary(
      uniqueKeysWithValues: header.enumerated().map { ($1, $0) }
    )
    let firstRow = String(lines[1])
      .split(separator: "\t", omittingEmptySubsequences: false)
      .map(String.init)
    #expect(
      firstRow[headerColumns["runtime_publication_mode"]!] == "subtrees"
    )
    #expect(
      firstRow[headerColumns["runtime_dirty_plan_result"]!] == "formed"
    )
    #expect(
      firstRow[headerColumns["runtime_selective_evaluation_disabled_reasons"]!]
        == "pressed_changed,root_invalidated"
    )
    #expect(
      firstRow[headerColumns["runtime_publication_subtree_roots"]!] == "2"
    )
    #expect(
      firstRow[headerColumns["runtime_publication_restored_nodes"]!] == "4"
    )
    #expect(
      firstRow[headerColumns["runtime_publication_unmapped_invalidated"]!] == "1"
    )
    #expect(
      firstRow[headerColumns["runtime_publication_unmapped_sample"]!] == "Root/Missing"
    )
    #expect(
      firstRow[headerColumns["runtime_publication_portal_root_queued"]!] == "1"
    )
    #expect(
      firstRow[headerColumns["runtime_graph_checkpoint_baseline_nodes"]!] == "8"
    )
    #expect(
      firstRow[headerColumns["runtime_graph_checkpoint_prepared_nodes"]!] == "9"
    )
    #expect(
      firstRow[headerColumns["runtime_non_graph_checkpoints"]!] == "1"
    )
    for row in lines.dropFirst() {
      #expect(row.split(separator: "\t", omittingEmptySubsequences: false).count == header.count)
    }

    try? FileManager.default.removeItem(atPath: sinkPath)
  }

  @Test("init returns nil for an unwritable path")
  func failsForUnwritablePath() {
    #expect(TSVFileSink(path: "/this/path/does/not/exist/run.tsv") == nil)
  }

  private static func temporaryPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("tsv-sink-\(UUID().uuidString).tsv")
      .path
  }

  private func makeScheduledFrame() -> ScheduledFrame {
    ScheduledFrame(
      causes: [],
      invalidatedIdentities: [],
      signalNames: [],
      externalReasons: [],
      triggeredDeadline: nil,
      nextDeadline: nil
    )
  }

  private func makeCommittedSample() -> RuntimeFrameSample {
    var diagnostics = FrameDiagnostics()
    diagnostics.runtime.registrations.publication = .init(
      publicationMode: "subtrees",
      dirtyPlanResult: "formed",
      subtreeRootCount: 2,
      restoredNodeCount: 4,
      invalidatedIdentityCount: 3,
      unmappedInvalidatedIdentityCount: 1,
      unmappedInvalidatedIdentitySample: [Identity(components: ["Root", "Missing"])],
      selectiveEvaluationDisabledReasons: [
        "pressed_changed",
        "root_invalidated",
      ],
      presentationPortalRootQueued: true,
      graphCheckpointBaselineNodeCount: 8,
      graphCheckpointPreparedNodeCount: 9,
      nonGraphCheckpointPresent: true
    )
    return .committed(
      CommittedFrameSample(
        frameNumber: 7,
        scheduledFrame: makeScheduledFrame(),
        diagnostics: diagnostics,
        desiredGeneration: 3,
        coalescedEventBatches: 1,
        coalescedWakeCauses: [],
        intentRequestCount: 2,
        focusSyncRerenders: 0,
        animationControllerActiveAnimationCount: 0,
        animationControllerHasPendingWork: false,
        cancelledRenderCount: 0,
        inputEventsQueuedDuringRenderSuspension: 0,
        dropEligibilityBlockers: [],
        completedFrameDropDecision: nil,
        tailJobState: .completed,
        presentationMetrics: PresentationMetrics(),
        presentationDuration: .zero
      )
    )
  }

  private func makeZeroArtifactSample() -> RuntimeFrameSample {
    .zeroArtifact(
      ZeroArtifactFrameSample(
        frameNumber: 8,
        scheduledFrame: makeScheduledFrame(),
        desiredGeneration: 4,
        coalescedEventBatches: 0,
        coalescedWakeCauses: [],
        intentRequestCount: 1,
        renderGeneration: RenderGeneration(5),
        runtimeIssues: [],
        staleFramePolicy: "drop_completed_visual_only",
        tailJobState: "dropped_completed",
        tailCancelReason: "-",
        newestDesiredAtTailResult: 6,
        animationControllerActiveAnimationCount: 0,
        animationControllerHasPendingWork: false,
        cancelledRenderCount: 0,
        inputEventsQueuedDuringRenderSuspension: 0,
        dropEligibilityBlockers: [],
        dropDecision: "drop_visual_only",
        dropGeneration: 5,
        newestDesiredAtDrop: 6,
        dropReconciliationMode: "-",
        dropReconciliationEffects: "-"
      )
    )
  }
}
