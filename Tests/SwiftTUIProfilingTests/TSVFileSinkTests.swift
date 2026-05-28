import Foundation
import SwiftTUICore
import Testing

@testable import SwiftTUIProfiling
@testable import SwiftTUIRuntime

@MainActor
@Suite
struct TSVFileSinkTests {
  @Test("TSVFileSink reproduces the legacy logger output byte-for-byte")
  func matchesLegacyLogger() throws {
    let samples: [RuntimeFrameSample] = [makeCommittedSample(), makeZeroArtifactSample()]

    let sinkPath = Self.temporaryPath()
    let loggerPath = Self.temporaryPath()

    let sink = TSVFileSink(path: sinkPath)
    let logger = FrameDiagnosticsLogger(path: loggerPath)
    #expect(sink != nil)
    #expect(logger != nil)

    for sample in samples {
      sink?.record(sample)
      logger?.log(FrameRecordDerivation.record(from: sample))
    }

    let sinkBytes = try Data(contentsOf: URL(fileURLWithPath: sinkPath))
    let loggerBytes = try Data(contentsOf: URL(fileURLWithPath: loggerPath))
    #expect(sinkBytes == loggerBytes)

    // The header is written exactly once, ahead of the data rows.
    let lines = String(decoding: sinkBytes, as: UTF8.self)
      .split(separator: "\n", omittingEmptySubsequences: true)
    #expect(lines.count == samples.count + 1)
    #expect(
      Array(lines.first ?? "")
        == Array(FrameDiagnosticsTSVFormatting.headerFields.joined(separator: "\t")))

    try? FileManager.default.removeItem(atPath: sinkPath)
    try? FileManager.default.removeItem(atPath: loggerPath)
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
