import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIProfiling
@testable import SwiftTUIRuntime

@MainActor
@Suite
struct ProfileActivationTests {
  @Test("Activating the frames signal installs a registry frame sink")
  func framesInstallsBridge() {
    ProfilingRegistry.shared.frameSink = nil
    let activation = ProfileActivation()
    activation.activate(signals: [.frames], sinks: [HandlerSink { _ in }])
    #expect(ProfilingRegistry.shared.frameSink != nil)
    ProfilingRegistry.shared.frameSink = nil
  }

  @Test("collectMemory emits a memory record to the sinks")
  func collectMemoryEmits() {
    _ = TextLayoutCache.shared
    let captured = CapturedRecords()
    let activation = ProfileActivation()
    activation.activate(signals: [], sinks: [HandlerSink { captured.records.append($0) }])
    activation.collectMemory()
    #expect(
      captured.records.contains {
        if case .memory = $0 { true } else { false }
      })
  }

  @Test("The frame bridge derives a record and fans it to every sink")
  func frameBridgeFansOut() {
    let captured = CapturedRecords()
    let bridge = ProfileFrameBridge(sinks: [HandlerSink { captured.records.append($0) }])
    bridge.record(Self.zeroArtifactSample())
    #expect(
      captured.records.contains {
        if case .frame = $0 { true } else { false }
      })
  }

  @Test("FileProfileSink jsonl writes a memory line")
  func jsonlMemory() throws {
    let path = Self.temporaryPath()
    let sink = FileProfileSink(path: path, format: .jsonl)
    #expect(sink != nil)
    sink?.emit(.memory([MemoryMetricSnapshot(name: "Cache", count: 7, approxBytes: 100)]))
    let text = try String(contentsOfFile: path, encoding: .utf8)
    #expect(text.contains("\"signal\":\"memory\""))
    #expect(text.contains("\"name\":\"Cache\""))
    #expect(text.contains("\"count\":7"))
    try? FileManager.default.removeItem(atPath: path)
  }

  @Test("FileProfileSink tsv writes a frame header and row")
  func tsvFrame() throws {
    let path = Self.temporaryPath()
    let sink = FileProfileSink(path: path, format: .tsv)
    sink?.emit(.frame(FrameDiagnosticRecord(frameNumber: 1, causeSummary: "test")))
    let text = try String(contentsOfFile: path, encoding: .utf8)
    #expect(text.split(separator: "\n").count == 2)
    try? FileManager.default.removeItem(atPath: path)
  }

  private static func temporaryPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("profile-\(UUID().uuidString)").path
  }

  private static func zeroArtifactSample() -> RuntimeFrameSample {
    .zeroArtifact(
      ZeroArtifactFrameSample(
        frameNumber: 1,
        scheduledFrame: ScheduledFrame(
          causes: [],
          invalidatedIdentities: [],
          signalNames: [],
          externalReasons: [],
          triggeredDeadline: nil,
          nextDeadline: nil
        ),
        desiredGeneration: 1,
        coalescedEventBatches: 0,
        coalescedWakeCauses: [],
        intentRequestCount: 0,
        renderGeneration: RenderGeneration(1),
        runtimeIssues: [],
        staleFramePolicy: "drop_completed_visual_only",
        tailJobState: "dropped_completed",
        tailCancelReason: "-",
        newestDesiredAtTailResult: 1,
        animationControllerActiveAnimationCount: 0,
        animationControllerHasPendingWork: false,
        cancelledRenderCount: 0,
        inputEventsQueuedDuringRenderSuspension: 0,
        dropEligibilityBlockers: [],
        dropDecision: "-",
        dropGeneration: nil,
        newestDesiredAtDrop: nil,
        dropReconciliationMode: "-",
        dropReconciliationEffects: "-"
      )
    )
  }
}

@MainActor
private final class CapturedRecords {
  var records: [ProfileRecord] = []
}
