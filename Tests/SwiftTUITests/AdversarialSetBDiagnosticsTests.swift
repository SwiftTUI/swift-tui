import Foundation
@_spi(Testing) import SwiftTUITestSupport
// Adversarial set B, pass 4: diagnostics and profiling sinks (321–330).
//
// The runtime hands every committed, cancelled, dropped or elided frame to one
// frame sink as a raw sample; the profiling product derives the record, formats
// it as TSV or JSONL, reduces it into a stderr summary, and joins the terminal
// writer's completion rows back by frame ordinal. These probes feed the sinks
// the shapes beside their stated contracts: non-committed frames in a summary
// that says "committed", negative durations through a two-digit formatter, the
// JSONL frame line against the record it claims to serialize, an elided
// frame's head time against its total, the bundle manifest against what debug
// mode arms, a runner sink beside a profiling sink, supplemental output
// appended to a pending frame's presents row, sinks on stale or unwritable
// paths, grammar bounds, and the sentinels for absent fields.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIProfiling
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: diagnostics and profiling sinks", .serialized)
struct AdversarialSetBDiagnosticsTests {
  private var header: [String] { FrameDiagnosticsTSVFormatting.headerFields }

  private func columns(_ record: FrameDiagnosticRecord) -> [String: String] {
    Dictionary(
      zip(header, FrameDiagnosticsTSVFormatting.fields(for: record)),
      uniquingKeysWith: { first, _ in first })
  }

  // The summary's frame line counts only committed frames as committed; a
  // cancelled tail and an elided frame are not committed frames.
  @Test func setB321SummaryCountsOnlyCommittedFramesAsCommitted() {
    let sink = SummarySink()
    sink.emit(.frame(FrameRecordDerivation.record(from: .committed(SetBSamples.committed()))))
    sink.emit(
      .frame(
        FrameRecordDerivation.record(
          from: .zeroArtifact(
            SetBSamples.zeroArtifact(
              frameNumber: 2, tailJobState: "cancelled_before_start",
              tailCancelReason: "superseded")))))
    sink.emit(
      .frame(FrameRecordDerivation.record(from: .elided(SetBSamples.elided(frameNumber: 3)))))
    let report = sink.report()
    #expect(report.hasPrefix("=== SwiftTUI profiling summary ===\n"), "\(report)")
    #expect(report.contains("1 elided"), "\(report)")
    do {
      #expect(report.contains("frames: 1 committed, 1 elided"), "\(report)")
    }
  }

  // Duration columns are signed decimals with two truncated fractional digits
  // in both frames.tsv and presents.tsv.
  @Test func setB322NegativeDurationsFormatAsSignedDecimals() throws {
    let index = try #require(header.firstIndex(of: "present_ms"))
    func presentMs(_ duration: Duration) -> String {
      FrameDiagnosticsTSVFormatting.fields(
        for: FrameDiagnosticRecord(
          frameNumber: 1, causeSummary: "input", presentationDuration: duration))[index]
    }
    #expect(presentMs(.microseconds(1_999)) == "1.99")
    #expect(presentMs(.microseconds(5)) == "0.00")
    #expect(presentMs(.milliseconds(1_500)) == "1500.00")
    #expect(presentMs(.milliseconds(-2)) == "-2.00")
    do {
      #expect(presentMs(.microseconds(-2_500)) == "-2.50", "\(presentMs(.microseconds(-2_500)))")
      #expect(presentMs(.microseconds(-250)) == "-0.25", "\(presentMs(.microseconds(-250)))")
    }

    let path = SetBPaths.temporary("presents.tsv")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let sink = try #require(PresentationWriteTSVSink(path: path))
    sink.record(
      PresentationWriteSample(
        frame: 3, submittedAt: MonotonicInstant(offset: .milliseconds(10)),
        writtenAt: MonotonicInstant(offset: .microseconds(7_500)), bytes: 1, outcome: .written))
    let lines = try String(contentsOfFile: path, encoding: .utf8)
      .split(separator: "\n", omittingEmptySubsequences: true)
    let rowText = try #require(lines.dropFirst().first)
    let row = rowText.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    #expect(row.count == PresentationWriteTSVSink.headerFields.count, "\(row)")
    #expect(row[1] == "10.00", "\(row)")
    #expect(row[2] == "7.50", "\(row)")
    do {
      #expect(row[3] == "-2.50", "\(row)")
    }
  }

  // A JSONL frame line serializes the frame record: its total duration and
  // elision reach the file like they reach the TSV columns.
  @Test func setB323JSONLFrameLineCarriesTheFrameRecord() throws {
    let path = SetBPaths.temporary("profile.jsonl")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let sink = try #require(FileProfileSink(path: path, format: .jsonl))
    var record = FrameDiagnosticRecord(
      frameNumber: 1, causeSummary: "input", presentationStrategy: "incremental",
      presentationDuration: .milliseconds(4), totalFrameDuration: .milliseconds(1_234))
    record.elided = true
    sink.emit(.frame(record))
    let line = try #require(
      String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").first.map(String.init))
    #expect(line.hasPrefix("{\"signal\":\"frame\""), "\(line)")
    #expect(line.contains("\"frameNumber\":1"), "\(line)")
    #expect(line.contains("\"causeSummary\":\"input\""), "\(line)")
    #expect(line.contains("\"presentationStrategy\":\"incremental\""), "\(line)")
    do {
      #expect(line.contains("elided"), "\(line)")
      #expect(line.contains("1234"), "\(line)")
    }
  }

  // An elided frame's total includes the head and commit work it did, and the
  // summary's worst frame sees it.
  @Test func setB324ElidedFrameTotalIncludesItsHeadWork() throws {
    let sample = SetBSamples.elided(
      frameNumber: 4,
      timings: ElidedFrameTimings(
        headTotal: .milliseconds(5), animationTick: .milliseconds(2), commit: .milliseconds(1)))
    let record = FrameRecordDerivation.record(from: .elided(sample))
    let row = columns(record)
    #expect(row["elided"] == "1", "\(row)")
    #expect(row["elided_head_total_ms"] == "5.00", "\(row)")
    #expect(row["elided_commit_ms"] == "1.00", "\(row)")
    let summary = SummarySink()
    summary.emit(.frame(record))
    let report = summary.report()
    let totalMs = Double(row["total_ms"] ?? "") ?? -1
    do {
      #expect(record.totalFrameDuration == .milliseconds(8), "\(record.totalFrameDuration)")
      #expect(totalMs >= 5, "\(row["total_ms"] ?? "-")")
      #expect(!report.contains("worst total 0ms"), "\(report)")
    }
  }

  // A debug-armed bundle's manifest records the frame trace that debug mode
  // arms alongside the graph traces.
  @Test func setB325DebugBundleManifestRecordsTheArmedFrameTrace() throws {
    DebugBundle.resetForTesting()
    DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
    defer {
      if let directory = DebugBundle.preparedDirectory,
        DebugLogRouter.environmentDebugDirectory == nil
      {
        try? FileManager.default.removeItem(atPath: directory)
      }
      DebugBundle.resetForTesting()
      DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
    }
    DebugBundle.prepareIfNeeded(configuration: RuntimeConfiguration(debug: true))
    let directory = try #require(DebugBundle.preparedDirectory)
    let trace = EnvFrameTraceSink.fromEnvironment(debug: true)
    #expect(trace != nil, "debug mode arms the bundle's frames.tsv")
    #expect(FileManager.default.fileExists(atPath: directory + "/frames.tsv"))
    let manifest = try String(contentsOfFile: directory + "/manifest.txt", encoding: .utf8)
    #expect(manifest.contains("debug=true"), "\(manifest)")
    let armed = manifest.split(separator: "\n").first { $0.hasPrefix("armed: ") }.map(String.init)
    let armedLine = try #require(armed, "\(manifest)")
    do {
      #expect(armedLine.contains("frames"), "\(manifest)")
    }
  }

  // A runner-supplied frame sink keeps receiving frames when the profiling
  // product installs its own sink in the registry.
  @Test func setB326RunnerFrameSinkSurvivesAProfilingSinkInstall() async throws {
    let runnerSink = SetBCountingFrameSink()
    let profilingSink = SetBCountingFrameSink()
    ProfilingRegistry.shared.frameSink = profilingSink
    defer { ProfilingRegistry.shared.frameSink = nil }
    let exitKey = KeyPress(.character("c"), modifiers: .ctrl)
    let result = try await SetBSceneSessionRunner.run(
      scene: WindowGroup("SetB Sinks") { Text("frames") },
      sessionName: "SetBDiagnostics.Sinks",
      presentationSurface: SetBScenePresentationHost(),
      inputReader: SetBScriptedTerminalInput(events: [.key(exitKey)]),
      frameSink: runnerSink)
    #expect(result.exitReason == .userExit(exitKey), "\(result.exitReason)")
    #expect(result.renderedFrames >= 1)
    #expect(profilingSink.committedFrames >= 1)
    do {
      #expect(runnerSink.committedFrames >= 1)
    }
  }

  // A presents.tsv row's bytes is the submitted emission: supplemental cursor
  // output appended while the frame waits is not that frame's bytes.
  @Test func setB327PresentsRowBytesMatchTheSubmittedEmission() async throws {
    let sink = SetBWriteSampleSink()
    ProfilingRegistry.shared.presentationWriteSink = sink
    defer { ProfilingRegistry.shared.presentationWriteSink = nil }
    let controller = SetBBlockingWriteController()
    let host = TerminalHost(
      inputFileDescriptor: 0, outputFileDescriptor: 1, fallbackSize: .init(width: 80, height: 24),
      controller: controller, capabilityProfile: .previewUnicode, environment: [:])
    func surface(_ line: String) -> RasterSurface {
      RasterSurface(size: .init(width: 8, height: 1), lines: [line])
    }
    let first = try PresentingFrameOrdinal.$current.withValue(910_001) {
      try host.present(surface("alpha"))
    }
    await controller.waitForBlockedWriteToStart()
    let second = try PresentingFrameOrdinal.$current.withValue(910_002) {
      try host.present(surface("alpho"))
    }
    try #require(second.bytesWritten > 0, "\(second)")
    try host.presentAccessibilityCursorFocus(at: CellPoint(x: 1, y: 0))
    controller.unblockWrite()
    try host.drainPendingPresentation()

    let rows = sink.samples.filter { $0.frame == 910_001 || $0.frame == 910_002 }
    let firstRow = try #require(rows.first(where: { $0.frame == 910_001 }), "\(rows)")
    let secondRow = try #require(rows.first(where: { $0.frame == 910_002 }), "\(rows)")
    #expect(rows.count == 2, "\(rows)")
    #expect(firstRow.outcome == .written)
    #expect(firstRow.bytes == first.bytesWritten, "\(firstRow.bytes) vs \(first.bytesWritten)")
    #expect(secondRow.outcome == .written)
    let cursorBytes = TerminalHostEscapeSequences.cursorFocus(to: CellPoint(x: 1, y: 0)).utf8.count
    do {
      #expect(
        secondRow.bytes == second.bytesWritten,
        "\(secondRow.bytes) vs \(second.bytesWritten) (+\(cursorBytes) cursor bytes)")
    }
    #expect(controller.writes.joined().contains("\u{1B}[?25h"))
  }

  // File sinks truncate an existing file and return nil for a directory or an
  // unwritable path (adjacent to STUI-815 and STUI-859, which cover symlinks,
  // FIFOs and private creation).
  @Test func setB328FileSinksTruncateExistingFilesAndRejectUnwritablePaths() throws {
    let base = SetBPaths.temporary("sinks")
    try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: base) }

    let stale = base + "/frames.tsv"
    try "stale line\n".write(toFile: stale, atomically: true, encoding: .utf8)
    let frames = try #require(TSVFileSink(path: stale))
    frames.record(.zeroArtifact(SetBSamples.zeroArtifact(frameNumber: 8)))
    let text = try String(contentsOfFile: stale, encoding: .utf8)
    #expect(text.hasPrefix(header.joined(separator: "\t") + "\n"), "\(text)")
    #expect(!text.contains("stale line"), "\(text)")
    #expect(text.split(separator: "\n").count == 2, "\(text)")

    let presents = base + "/presents.tsv"
    try "stale presents\n".write(toFile: presents, atomically: true, encoding: .utf8)
    let writes = try #require(PresentationWriteTSVSink(path: presents))
    writes.record(
      PresentationWriteSample(
        frame: 1, submittedAt: .zero, writtenAt: nil, bytes: 0, outcome: .superseded))
    let presentsText = try String(contentsOfFile: presents, encoding: .utf8)
    #expect(
      presentsText.hasPrefix(PresentationWriteTSVSink.headerFields.joined(separator: "\t") + "\n"),
      "\(presentsText)")
    #expect(!presentsText.contains("stale presents"), "\(presentsText)")

    #expect(TSVFileSink(path: base) == nil, "a directory is not a sink file")
    #expect(FileProfileSink(path: base, format: .tsv) == nil)
    #expect(PresentationWriteTSVSink(path: base) == nil)
    #expect(FileProfileSink(path: base + "/missing/profile.jsonl", format: .jsonl) == nil)

    let readOnly = base + "/readonly.tsv"
    try "".write(toFile: readOnly, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnly)
    if !FileManager.default.isWritableFile(atPath: readOnly) {
      #expect(TSVFileSink(path: readOnly) == nil)
      #expect(FileProfileSink(path: readOnly, format: .jsonl) == nil)
      #expect(PresentationWriteTSVSink(path: readOnly) == nil)
    }
  }

  // The SWIFTTUI_PROFILE grammar fails closed on zero intervals, sums duration
  // units in any order, and keeps units case-sensitive (overflowing multi
  // component intervals are STUI-801 and are not probed).
  @Test func setB329ProfileGrammarBoundsFailClosedAndSumUnits() {
    #expect(EnvProfileParser.parse("cpu@0ms") == nil)
    #expect(EnvProfileParser.parse("memory@0s") == nil)
    #expect(EnvProfileParser.parse("frames,cpu@0ms;summary") == nil)
    #expect(
      EnvProfileParser.parse("cpu@2s500ms")?.signals == [.cpu(interval: .milliseconds(2_500))])
    #expect(
      EnvProfileParser.parse("cpu@500ms2s")?.signals == [.cpu(interval: .milliseconds(2_500))])
    #expect(EnvProfileParser.parse("memory@1s1s")?.signals == [.memory(interval: .seconds(2))])
    #expect(EnvProfileParser.parse("cpu@1S") == nil)
    #expect(EnvProfileParser.parse("cpu@ 1s") == nil)
    #expect(EnvProfileParser.parse("frames,frames")?.signals == [.frames])
    #expect(EnvProfileParser.parse("memory@1s,memory@2s")?.signals.count == 2)
    #expect(EnvProfileParser.parse("frames;tsv=/a;summary") == nil)
    #expect(EnvProfileParser.parse(" frames ; summary ")?.sinks == [.summary])
    #expect(EnvProfileParser.parseDuration("9223372036854775807s") == .seconds(Int.max))
    #expect(EnvProfileParser.parseDuration("1ms1ms1ms") == .milliseconds(3))
  }

  // Absent fields render their documented sentinels: `-` for disarmed or
  // absent, `0` for armed-and-zero, `full` only when a presentation happened.
  @Test func setB330AbsentFieldsRenderTheirDocumentedSentinels() {
    let committed = columns(
      FrameRecordDerivation.record(
        from: .committed(
          SetBSamples.committed(
            answeredInputs: AnsweredInputs(
              count: 2, first: MonotonicInstant(offset: .milliseconds(10)),
              last: MonotonicInstant(offset: .milliseconds(12))),
            commitInstant: MonotonicInstant(offset: .milliseconds(20)),
            collectionProbes: CollectionProbeSample(realizedRows: 0, listLayoutDerivations: nil)))))
    let zero = columns(
      FrameRecordDerivation.record(from: .zeroArtifact(SetBSamples.zeroArtifact(frameNumber: 2))))
    let elided = columns(
      FrameRecordDerivation.record(from: .elided(SetBSamples.elided(frameNumber: 3))))
    for row in [committed, zero, elided] {
      #expect(row.count == header.count, "\(row.count) columns for \(header.count) headers")
    }
    #expect(committed["answered_inputs"] == "2")
    #expect(committed["input_to_commit_first_ms"] == "10.00")
    #expect(committed["input_to_commit_last_ms"] == "8.00")
    #expect(committed["committed_at_ms"] == "20.00")
    #expect(committed["realized_rows"] == "0")
    #expect(committed["list_layout_derivations"] == "-")
    #expect(committed["animation_time_delta_ms"] == "-")
    #expect(committed["frame_instant_lag_ms"] == "0.00")
    #expect(committed["cache_hit"] == "-")
    #expect(committed["present_strategy"] == "full")
    #expect(committed["damage_rows"] == "full")
    #expect(committed["ingress_oldest_pending_ms"] == "-")
    #expect(zero["answered_inputs"] == "0")
    #expect(zero["input_to_commit_first_ms"] == "-")
    #expect(zero["committed_at_ms"] == "-")
    #expect(zero["realized_rows"] == "-")
    #expect(zero["present_strategy"] == "-")
    #expect(zero["damage_rows"] == "-")
    #expect(zero["ingress_stream_waiting"] == "-")
    #expect(zero["tail_job_state"] == "dropped_completed")
    #expect(elided["elided"] == "1")
    #expect(elided["stale_frame_policy"] == "elided_offscreen")
    #expect(elided["elided_head_total_ms"] == "-")
    #expect(elided["scheduled_animation_request"] == "inherit")
    #expect(elided["present_strategy"] == "-")
  }
}

// MARK: - Samples

private enum SetBSamples {
  static func scheduledFrame() -> ScheduledFrame {
    ScheduledFrame(
      causes: [.input], invalidatedIdentities: [], signalNames: [], externalReasons: [],
      triggeredDeadline: nil, nextDeadline: nil)
  }

  static func committed(
    frameNumber: Int = 1,
    presentationDuration: Duration = .zero,
    answeredInputs: AnsweredInputs? = nil,
    commitInstant: MonotonicInstant = .zero,
    collectionProbes: CollectionProbeSample = .init(realizedRows: nil, listLayoutDerivations: nil)
  ) -> CommittedFrameSample {
    CommittedFrameSample(
      frameNumber: frameNumber, scheduledFrame: scheduledFrame(), diagnostics: FrameDiagnostics(),
      desiredGeneration: 1, coalescedEventBatches: 1, coalescedWakeCauses: [.input],
      intentRequestCount: 1, focusSyncRerenders: 0, animationControllerActiveAnimationCount: 0,
      animationControllerHasPendingWork: false, cancelledRenderCount: 0,
      inputEventsQueuedDuringRenderSuspension: 0, dropEligibilityBlockers: [],
      completedFrameDropDecision: nil, tailJobState: .completed,
      presentationMetrics: PresentationMetrics(), presentationDuration: presentationDuration,
      answeredInputs: answeredInputs, commitInstant: commitInstant,
      collectionProbes: collectionProbes)
  }

  static func zeroArtifact(
    frameNumber: Int,
    tailJobState: String = "dropped_completed",
    tailCancelReason: String = "-"
  ) -> ZeroArtifactFrameSample {
    ZeroArtifactFrameSample(
      frameNumber: frameNumber, scheduledFrame: scheduledFrame(), desiredGeneration: 2,
      coalescedEventBatches: 0, coalescedWakeCauses: [], intentRequestCount: 1,
      renderGeneration: RenderGeneration(2), runtimeIssues: [],
      staleFramePolicy: "drop_completed_visual_only", tailJobState: tailJobState,
      tailCancelReason: tailCancelReason, newestDesiredAtTailResult: 2,
      animationControllerActiveAnimationCount: 0, animationControllerHasPendingWork: false,
      cancelledRenderCount: 0, inputEventsQueuedDuringRenderSuspension: 0,
      dropEligibilityBlockers: [], dropDecision: "-", dropGeneration: nil,
      newestDesiredAtDrop: nil, dropReconciliationMode: "-", dropReconciliationEffects: "-")
  }

  static func elided(frameNumber: Int, timings: ElidedFrameTimings = .empty) -> ElidedFrameSample {
    ElidedFrameSample(
      frameNumber: frameNumber, scheduledFrame: scheduledFrame(), desiredGeneration: 3,
      coalescedEventBatches: 0, coalescedWakeCauses: [], intentRequestCount: 1,
      animationControllerActiveAnimationCount: 0, animationControllerHasPendingWork: false,
      cancelledRenderCount: 0, timings: timings)
  }
}

private enum SetBPaths {
  static func temporary(_ name: String) -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("setb-diagnostics-\(UUID().uuidString)-\(name)").path
  }
}

// MARK: - Sinks

@MainActor
private final class SetBCountingFrameSink: FrameDiagnosticSink {
  private(set) var committedFrames = 0

  func record(_ sample: RuntimeFrameSample) {
    if case .committed = sample {
      committedFrames += 1
    }
  }
}

private final class SetBWriteSampleSink: PresentationWriteSink {
  private let storage = LockedBox<[PresentationWriteSample]>([])

  var samples: [PresentationWriteSample] { storage.value }

  func record(_ sample: PresentationWriteSample) {
    storage.withLock { $0.append(sample) }
  }
}

// MARK: - Terminal controller

private final class SetBBlockingWriteController: TerminalControlling {
  private let gate = BlockingWriteGate()
  private let writesStorage = LockedBox<[String]>([])

  var writes: [String] { writesStorage.value }

  func isATTY(_: Int32) -> Bool { false }

  func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot {
    TerminalModeSnapshot()
  }

  func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {}

  func windowSize(of _: Int32) throws -> CellSize { .init(width: 80, height: 24) }

  func cellPixelSize(of _: Int32) throws -> PixelSize? { nil }

  func write(_ output: String, to _: Int32) throws {
    gate.enterBlockingSection()
    writesStorage.withLock { $0.append(output) }
  }

  func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] {
    []
  }

  func waitForBlockedWriteToStart() async {
    await gate.waitUntilBlocked()
  }

  func unblockWrite() {
    gate.release()
  }
}

// MARK: - Scene session

@MainActor
private enum SetBSceneSessionRunner {
  static func run<S: Scene>(
    scene: S,
    sessionName: String,
    presentationSurface: any PresentationSurface,
    inputReader: any TerminalInputReading,
    frameSink: any FrameDiagnosticSink
  ) async throws -> RunLoopResult<SceneSessionState> {
    var visitor = SetBSceneSelectionVisitor(sessionName: sessionName)
    let found = withFirstWindowSceneConfiguration(in: scene, visitor: &visitor)
    let selection = try #require(found)
    let resources = SceneSessionResources(
      presentationSurface: presentationSurface, terminalInputReader: inputReader,
      signalReader: SetBEmptySignalReader(), frameSink: frameSink, progressProbe: nil)
    return try await selection.run(
      resources,
      StateContainer(
        initialState: SceneSessionState(), invalidationIdentities: [selection.rootIdentity]),
      FocusTracker(invalidationIdentities: [selection.rootIdentity]))
  }
}

@MainActor
private struct SetBSceneSelection {
  let rootIdentity: Identity
  let run:
    (SceneSessionResources, StateContainer<SceneSessionState>, FocusTracker) async throws
      -> RunLoopResult<SceneSessionState>
}

@MainActor
private struct SetBSceneSelectionVisitor: WindowSceneConfigurationVisitor {
  let sessionName: String

  mutating func visit<Content: View>(
    descriptor _: SceneDescriptor,
    configuration: WindowSceneConfiguration<Content>
  ) -> WindowSceneConfigurationVisitResult<SetBSceneSelection> {
    let sessionName = self.sessionName
    return .finish(
      SetBSceneSelection(rootIdentity: configuration.rootIdentity) {
        resources, stateContainer, focusTracker in
        try await SceneSession.run(
          configuration: configuration, sessionName: sessionName, stateContainer: stateContainer,
          focusTracker: focusTracker, resources: resources)
      })
  }
}

private final class SetBScenePresentationHost: PresentationSurface {
  let surfaceSize = CellSize(width: 30, height: 3)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    .fullRepaint(for: surface, capabilityProfile: capabilityProfile)
  }
}

private final class SetBScriptedTerminalInput: TerminalInputReading {
  private let events: [InputEvent]

  init(events: [InputEvent]) {
    self.events = events
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in events {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class SetBEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
