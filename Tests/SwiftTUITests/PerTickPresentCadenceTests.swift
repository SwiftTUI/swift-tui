import Foundation
import SwiftTUICore
@_spi(Runners) import SwiftTUIProfiling
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Per-tick present cadence under completed-frame disposal policies.
///
/// The browser 0.1.9 incident: a steady autonomous tick (the Life scene) on a
/// slow drive coalesced to ~1 present per 3 completed frames because every
/// completed visual-only frame had a newer intent pending at its drop
/// decision (`dropped_completed`, bounded by the `progress_starvation`
/// guard), with pre-start cancels (`cancelled_before_start`) interleaved.
/// `renderMode = .asyncNoCancel` removes both disposal arms
/// (`completedFramePolicy: .orderedCommitOnly` + no pre-start cancellation),
/// so present-count equals commit-count equals consumed-intent-count.
///
/// The two composed-runtime tests here are an identical-harness A/B pair: the
/// same autonomous 5 ms tick workload with the same one-shot raster block
/// holding a started tail while the test injects a newer intent (the
/// deterministic supersession recipe from `AsyncFrameTailRenderingTests` —
/// a raced tick alone is probabilistic on fast native tails). Under
/// `.asyncNoCancel` the released frame must commit (zero skips); under
/// `.async` the released frame is the suppression witness (`frameSkipped`
/// with the disposal reason string) — the red-proof that this suite can
/// actually see the defect layer. Every wait is signal-native (`AsyncEvent`,
/// `PendingFrameAwaiting`, `frameSignal`, probe events) per the test-sync
/// ratchet; the suite time limit is the hang bound.
// The time limit is a HANG bound, not a performance assertion (see
// PreStartCancelForwardProgressTests: probe-event hops contend for the main
// actor under the full parallel run).
@Suite(.serialized, .timeLimit(.minutes(5)))
struct PerTickPresentCadenceTests {
  // MARK: Disposal-policy units

  @Test(
    "ordered-commit-only never drops a superseded frame, for any counter",
    arguments: [0, 1, CompletedFramePolicy.maxConsecutiveVisualOnlyDrops - 1,
      CompletedFramePolicy.maxConsecutiveVisualOnlyDrops,
      CompletedFramePolicy.maxConsecutiveVisualOnlyDrops + 7, Int.max]
  )
  func orderedCommitOnlyNeverDrops(consecutiveDrops: Int) {
    let decision = CompletedFramePolicy.orderedCommitOnly.decide(
      candidateGeneration: RenderGeneration(1),
      newestDesiredGeneration: RenderGeneration(2),
      eligibility: FrameDropEligibility(blockers: []),
      consecutiveVisualOnlyDrops: consecutiveDrops
    )
    #expect(decision.action == .commitOrdered)
    #expect(decision.reconciliation.blockReason == .orderedCommitPolicy)
  }

  @Test("unknown render-mode values parse to the platform default")
  func unknownRenderModeValuesParseToDefault() {
    #expect(RuntimeRenderMode.parse(nil) == RuntimeRenderMode.defaultMode)
    #expect(RuntimeRenderMode.parse("") == RuntimeRenderMode.defaultMode)
    #expect(RuntimeRenderMode.parse("garbage") == RuntimeRenderMode.defaultMode)
    #expect(RuntimeRenderMode.parse("ASYNC-NO-CANCEL") == RuntimeRenderMode.defaultMode)
    #expect(RuntimeRenderMode.parse("async-no-cancel") == .asyncNoCancel)
    #expect(RuntimeRenderMode.parse("async-no-drop") == .asyncNoDrop)
    #expect(RuntimeRenderMode.parse("async") == .async)
    #expect(RuntimeRenderMode.parse("sync") == .sync)
  }

  // MARK: Composed-runtime A/B pair

  @MainActor
  @Test("async-no-cancel presents every completed frame under an autonomous tick")
  func asyncNoCancelPresentsEveryCompletedFrame() async throws {
    let harness = PerTickCadenceHarness(rootName: "PerTickCadenceNoCancelRoot")
    defer { harness.removeDiagnostics() }
    harness.runLoop.renderMode = .asyncNoCancel

    let runTask = Task {
      try await harness.runLoop.run()
    }

    // Hold a steady tick frame's started tail mid-raster, inject a newer
    // intent while it is held, then release: the disposal decision sees a
    // newer desired generation, and under ordered-commit-only the frame must
    // still commit. The phase breadcrumbs exist for CI: when a slow runner
    // exceeds the suite time limit, the last printed phase names the wait
    // that starved (the amd64 lane's frame latency has defeated two rounds
    // of workload sizing).
    print("[per-tick-cadence] no-cancel: awaiting held tail")
    await harness.gate.waitUntilBlocked()
    harness.stateContainer.replace(with: 1)
    print("[per-tick-cadence] no-cancel: awaiting injected pending intent")
    await harness.scheduler.waitForPendingFrame(at: .now())
    harness.gate.release()

    // Steady window, signal-synchronised on presents: at least 8 distinct
    // tick values must reach the surface.
    print("[per-tick-cadence] no-cancel: awaiting 8 distinct presented ticks")
    await harness.terminal.frameSignal.wait {
      distinctTickValues(in: harness.terminal.frames).count >= 8
    }

    harness.requestExit()
    print("[per-tick-cadence] no-cancel: awaiting run-loop exit")
    let result = try await runTask.value

    let skips = harness.probe.events.filter { $0.kind == .frameSkipped }
    #expect(skips.isEmpty)
    let acquired = harness.probe.events.filter { $0.kind == .frameAcquired }.count
    let committed = harness.probe.events.filter { $0.kind == .frameCommitted }.count
    #expect(acquired == committed)
    #expect(committed >= distinctTickValues(in: harness.terminal.frames).count)
    #expect(harness.runLoop.cancelledRenderCount == 0)
    #expect(result.renderedFrames == committed)
  }

  @MainActor
  @Test(
    "async disposal suppresses the held frame — the red-proof witness",
    // Non-lean only: stack-lean frames carry drop blockers on every frame, so
    // the visual-only disposal arm structurally never engages under the lean
    // profile (Stage-0 live capture: 172/172 lean decisions `blocked`, zero
    // drops/cancels — lean's only losses are scheduler intent fusion).
    .enabled(
      if: ProcessInfo.processInfo.environment["SWIFTTUI_STACK_LEAN_PROFILE"] != "1",
      "lean-profile frames are never drop-eligible; the disposal arm under test is unreachable"
    ),
    // A guard-on process soak (SWIFTTUI_PRESENTED_PROGRESS_GUARD=1) makes the
    // awaited drop structurally impossible — that inverse is exactly what
    // `presentedProgressGuardClosesDisposalArm` verifies.
    .enabled(
      if: {
        let raw = ProcessInfo.processInfo.environment["SWIFTTUI_PRESENTED_PROGRESS_GUARD"]
        return raw == nil || raw!.isEmpty || raw == "0"
      }(),
      "the presented-progress guard blocks the disposal arm under test"
    )
  )
  func asyncDisposalSuppressesHeldFrame() async throws {
    let harness = PerTickCadenceHarness(rootName: "PerTickCadenceAsyncRoot")
    defer { harness.removeDiagnostics() }
    harness.runLoop.renderMode = .async

    let runTask = Task {
      try await harness.runLoop.run()
    }

    // Identical hold and injected supersession. Under `.async` the released
    // completed visual-only frame must be disposed, and the disposal layer
    // must record the skip with its reason string. The probe event wait is
    // signal-native — it resumes exactly when the skip records.
    print("[per-tick-cadence] red-proof: awaiting held tail")
    await harness.gate.waitUntilBlocked()
    harness.stateContainer.replace(with: 1)
    print("[per-tick-cadence] red-proof: awaiting injected pending intent")
    await harness.scheduler.waitForPendingFrame(at: .now())
    harness.gate.release()

    print("[per-tick-cadence] red-proof: awaiting disposal skip")
    _ = await harness.probe.event { $0.kind == .frameSkipped }

    harness.requestExit()
    print("[per-tick-cadence] red-proof: awaiting run-loop exit")
    _ = try await runTask.value

    let skips = harness.probe.events.filter { $0.kind == .frameSkipped }
    #expect(!skips.isEmpty)
    // The held frame had already started, so its disposal is specifically the
    // completed-frame drop arm; later tick frames may hit either arm.
    #expect(skips.first?.tailJobState == FrameTailJobState.droppedCompleted.rawValue)
    let disposalReasons = [
      FrameTailJobState.droppedCompleted.rawValue,
      FrameTailJobState.cancelledBeforeStart.rawValue,
    ]
    #expect(
      skips.allSatisfy { event in
        event.tailJobState.map { disposalReasons.contains($0) } ?? false
      }
    )
    // The frame-pipeline trace identifies the biting layer, not just the
    // fact of suppression: the dropped row must name the completed-frame
    // disposal policy (two-layer masking has fooled red-proofs before).
    let rows = diagnosticRows(harness.diagnosticsText())
    #expect(
      rows.contains { row in
        row["tail_job_state"] == "dropped_completed"
          && row["stale_frame_policy"] == "drop_completed_visual_only"
          && row["drop_decision"] == "drop_visual_only"
      }
    )
  }

  @MainActor
  @Test(
    "the presented-progress guard closes the disposal arm under plain async",
    // Non-lean only, like the red-proof: this is its guard-on inverse on the
    // identical harness — the same held superseded frame that `.async` drops
    // must commit when undelivered pixels block disposal.
    .enabled(
      if: ProcessInfo.processInfo.environment["SWIFTTUI_STACK_LEAN_PROFILE"] != "1",
      "lean-profile frames are never drop-eligible; the guard has nothing to close"
    )
  )
  func presentedProgressGuardClosesDisposalArm() async throws {
    let wasEnabled = PresentedProgressGuardConfiguration.isEnabled
    PresentedProgressGuardConfiguration.isEnabled = true
    defer { PresentedProgressGuardConfiguration.isEnabled = wasEnabled }

    let harness = PerTickCadenceHarness(rootName: "PerTickCadenceGuardRoot")
    defer { harness.removeDiagnostics() }
    harness.runLoop.renderMode = .async

    let runTask = Task {
      try await harness.runLoop.run()
    }

    print("[per-tick-cadence] guard: awaiting held tail")
    await harness.gate.waitUntilBlocked()
    harness.stateContainer.replace(with: 1)
    print("[per-tick-cadence] guard: awaiting injected pending intent")
    await harness.scheduler.waitForPendingFrame(at: .now())
    harness.gate.release()

    // The guard's commit is observable as the held tick value presenting:
    // under plain `.async` this exact scenario records `dropped_completed`
    // (the red-proof above); with the guard on the frame must reach the
    // surface instead.
    print("[per-tick-cadence] guard: awaiting 4 distinct presented ticks")
    await harness.terminal.frameSignal.wait {
      distinctTickValues(in: harness.terminal.frames).count >= 4
    }

    harness.requestExit()
    print("[per-tick-cadence] guard: awaiting run-loop exit")
    _ = try await runTask.value

    // The guard closes the completed-frame drop arm only; a legitimate
    // pre-start cancel+replay (G2) is explicitly outside its scope
    // (the plan pre-registers `.asyncNoCancel` as the escalation for that
    // residual), so only `dropped_completed` skips are a failure here.
    let skips = harness.probe.events.filter { $0.kind == .frameSkipped }
    #expect(
      skips.allSatisfy {
        $0.tailJobState == FrameTailJobState.cancelledBeforeStart.rawValue
      }
    )
    // The trace names the guard as the biting layer: the superseded frame's
    // decision is `blocked` with the guard blocker, never `drop_visual_only`.
    let rows = diagnosticRows(harness.diagnosticsText())
    #expect(rows.allSatisfy { $0["drop_decision"] != "drop_visual_only" })
    #expect(
      rows.contains { row in
        (row["drop_blockers"] ?? "").contains("undeliveredPresentationDamage")
      }
    )
  }
}

// MARK: - Harness

/// One composition shared by both A/B legs: autonomous 5 ms tick probe view,
/// recording surface, progress probe, and a one-shot raster block at the
/// second tail (the first is the bootstrap frame).
@MainActor
private final class PerTickCadenceHarness {
  let terminal: RecordingPresentationSurface
  let inputReader: InjectedTerminalInputReader
  let gate: AsyncFrameTailBlockingGate
  let probe: RunLoopProgressProbe
  let scheduler: FrameScheduler
  let stateContainer: StateContainer<Int>
  let model: PerTickProbeModel
  let runLoop: SwiftTUIRuntime.RunLoop<Int, PerTickAutonomousProbeView>
  let diagnosticsURL: URL

  func diagnosticsText() -> String {
    (try? String(contentsOf: diagnosticsURL, encoding: .utf8)) ?? ""
  }

  func removeDiagnostics() {
    try? FileManager.default.removeItem(at: diagnosticsURL)
  }

  init(rootName: String) {
    let model = PerTickProbeModel()
    let rootIdentity = testIdentity(rootName)
    let terminal = RecordingPresentationSurface(
      surfaceSize: CellSize(width: 32, height: 6)
    )
    let inputReader = InjectedTerminalInputReader()
    // Entry 6 holds a mid-steady tick frame: the first post-bootstrap frames
    // carry first-registration deltas (taskStart, observation intake) that
    // classify must-commit, so they cannot witness the visual-only drop arm.
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 6)
    let probe = RunLoopProgressProbe()
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, _ in
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: ProposedSize(width: 32, height: 6),
      viewBuilder: { _, _ in
        PerTickAutonomousProbeView(model: model)
      }
    )
    runLoop.progressProbe = probe
    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-per-tick-cadence-\(UUID().uuidString).tsv")
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    self.diagnosticsURL = diagnosticsURL

    self.terminal = terminal
    self.inputReader = inputReader
    self.gate = gate
    self.probe = probe
    self.scheduler = scheduler
    self.stateContainer = stateContainer
    self.model = model
    self.runLoop = runLoop
  }

  func requestExit() {
    // Stop the workload first so the cooperative-exit drain has no live
    // tick producer left to replay (the logo-tab flush-before-exit shape).
    model.stopped = true
    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()
  }
}

private func diagnosticRows(_ text: String) -> [[String: String]] {
  let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
  guard let headerLine = lines.first else {
    return []
  }
  let headers = headerLine.components(separatedBy: "\t")
  return lines.dropFirst().map { line in
    let fields = line.components(separatedBy: "\t")
    var row: [String: String] = [:]
    for (index, header) in headers.enumerated() where index < fields.count {
      row[header] = fields[index]
    }
    return row
  }
}

private func distinctTickValues(in frames: [String]) -> Set<Int> {
  var values: Set<Int> = []
  for frame in frames {
    var search = frame[...]
    while let range = search.range(of: "tick ") {
      let digits = search[range.upperBound...].prefix { $0.isNumber }
      if let value = Int(digits) {
        values.insert(value)
      }
      search = search[range.upperBound...]
    }
  }
  return values
}
