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
    .committed(
      CommittedFrameSample(
        frameNumber: 7,
        scheduledFrame: makeScheduledFrame(),
        diagnostics: FrameDiagnostics(),
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
