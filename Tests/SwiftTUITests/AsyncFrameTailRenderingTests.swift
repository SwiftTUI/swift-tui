@unsafe @preconcurrency import Dispatch
import Foundation
@_spi(Runners) import SwiftTUIProfiling
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private enum AsyncFrameTailRaisedCenterAlignmentID: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int {
    context[VerticalAlignment.center]
  }
}

extension VerticalAlignment {
  fileprivate static let asyncFrameTailRaisedCenter =
    Self(AsyncFrameTailRaisedCenterAlignmentID.self)
}

@MainActor
@Suite(.serialized)
struct AsyncFrameTailRenderingTests {
  @Test("blocked async frame tail queues input without committing ahead")
  func blockedFrameTailQueuesInputWithoutCommittingAhead() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailRoot")
    let gate = AsyncFrameTailBlockingGate()
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let lifecycleRecorder = AsyncFrameTailLifecycleRecorder()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        if keyPress == KeyPress(.character("i")) {
          stateContainer.mutate { value in
            value += 1
          }
          return .handled
        }
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailStressView(
          value: value,
          lifecycleRecorder: lifecycleRecorder
        )
      }
    )

    let runTask = Task {
      try await runLoop.run()
    }

    await gate.waitUntilBlocked()
    #expect(terminal.frames.isEmpty)

    inputReader.send(.key(.character("i")))
    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()

    #expect(terminal.frames.isEmpty)
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.finalState == 1)
    #expect(gate.rasterEntryCount >= 3)
    #expect(terminal.frames.count >= 2)
    #expect(terminal.frames.first?.contains("value 0") == true)
    #expect(terminal.frames.last?.contains("value 1") == true)
    #expect(lifecycleRecorder.events == ["appear 0", "disappear 0", "appear 1"])
  }

  @Test("internal @State mutations during suspended async frame tail survive commit")
  func internalStateMutationDuringSuspendedAsyncTailSurvivesCommit() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailInternalStateRoot")
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let terminal = AsyncFrameTailTerminalHost()
    let trigger = AsyncFrameTailInternalStateTrigger()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { phase, _ in
        AsyncFrameTailInternalStateMutationView(
          phase: phase,
          trigger: trigger
        )
      }
    )
    let eventPump = runLoop.makeEventPump()
    defer {
      eventPump.cancel()
    }

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    _ = try await runLoop.renderPendingFramesAsync(
      renderedFrames: &initialFrames,
      eventPump: eventPump
    )
    #expect(terminal.frames.last?.contains("phase 0 count 0") == true)

    runLoop.stateContainer.mutate { phase in
      phase = 1
    }
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])

    let renderTask = Task { @MainActor in
      var renderedFrames = 0
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: eventPump
      )
      return renderedFrames
    }

    await gate.waitUntilBlocked()
    trigger.fire()
    gate.release()

    _ = try await valueWithTimeout {
      try await renderTask.value
    }

    #expect(
      terminal.frames.last?.contains("phase 1 count 1") == true,
      "frames: \(terminal.frames)"
    )
  }

  @Test("authored @FocusState write during suspended async frame tail survives commit")
  func focusStateWriteDuringSuspendedAsyncTailSurvivesCommit() async throws {
    // F10 slice 4 deciding test. @FocusState bypasses the @State
    // checkpoint-restore mirror (`stateMutationKeys`), so a mid-suspension
    // authored focus write relies on `FocusStateStorage` being a shared
    // class instance that suspend/materialize never rolls back, plus
    // focus-sync re-deriving bindings from the tracker. This pins that
    // contract: the write lands while the phase-1 frame's tail is
    // suspended-to-baseline, and the committed run must still relocate
    // focus to the requested field. (The narrower first-frame-slot residue
    // is not constructible through production paths: tasks start at
    // commit, input cannot target uncommitted regions, and resolve-time
    // seeds land in the prepared state that materialize restores.)
    let rootIdentity = testIdentity("AsyncFrameTailFocusMutationRoot")
    // Unlike the internal-@State sibling above, the blocking hooks install
    // only after the initial render: resolve-time `.defaultFocus` seeding
    // gives the first frame a focus-sync pass-2 rerender (two raster
    // entries), so counting entries from renderer construction would stall
    // the initial `renderPendingFramesAsync` await with nothing able to
    // release the gate.
    let gate = AsyncFrameTailBlockingGate()
    let renderer = DefaultRenderer()
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let terminal = AsyncFrameTailTerminalHost()
    let trigger = AsyncFrameTailInternalStateTrigger()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: terminal.proposal,
      viewBuilder: { phase, _ in
        AsyncFrameTailFocusMutationView(
          phase: phase,
          trigger: trigger
        )
      }
    )
    focusTracker.invalidator = runLoop.scheduler
    let eventPump = runLoop.makeEventPump()
    defer {
      eventPump.cancel()
    }

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    _ = try await runLoop.renderPendingFramesAsync(
      renderedFrames: &initialFrames,
      eventPump: eventPump
    )
    #expect(terminal.frames.last?.contains("phase 0 field first") == true)

    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    runLoop.stateContainer.mutate { phase in
      phase = 1
    }
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])

    let renderTask = Task { @MainActor in
      var renderedFrames = 0
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: eventPump
      )
      return renderedFrames
    }

    await gate.waitUntilBlocked()
    trigger.fire()
    gate.release()

    _ = try await valueWithTimeout {
      try await renderTask.value
    }

    // Drain any follow-up frame the authored request scheduled (the request
    // is consumed by a re-resolve's registration snapshot, not by the
    // resumed frame itself).
    var followUpFrames = 0
    _ = try await runLoop.renderPendingFramesAsync(
      renderedFrames: &followUpFrames,
      eventPump: eventPump
    )

    // The authored request lands on the live shared storage while the
    // phase-1 frame's tail is suspended; the resumed frame's focus-sync
    // re-derives bindings via `applyRuntimeValue`, whose request-generation
    // guard refuses to consume a request its resolve-time registrations
    // predate (they observed the pre-write generation). The request's own
    // invalidation stays pending in the scheduler — the eager rerender only
    // peeks — so the follow-up frame re-resolves with the surviving request,
    // applies `.focus(Second)`, and consumes it with matching generations.
    #expect(
      terminal.frames.last?.contains("phase 1 field second") == true,
      "frames: \(terminal.frames)"
    )
    #expect(
      focusTracker.currentFocusIdentity
        == testIdentity("AsyncFrameTailFocusMutation", "Second")
    )
  }

  @Test("blocked built-in layout queues input without committing ahead")
  func blockedBuiltInLayoutQueuesInputWithoutCommittingAhead() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailLayoutRoot")
    let gate = AsyncFrameTailBlockingGate()
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeLayout: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let lifecycleRecorder = AsyncFrameTailLifecycleRecorder()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        if keyPress == KeyPress(.character("i")) {
          stateContainer.mutate { value in
            value += 1
          }
          return .handled
        }
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailStressView(
          value: value,
          lifecycleRecorder: lifecycleRecorder
        )
      }
    )

    let runTask = Task {
      try await runLoop.run()
    }

    await gate.waitUntilBlocked()
    #expect(terminal.frames.isEmpty)

    inputReader.send(.key(.character("i")))
    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()

    #expect(terminal.frames.isEmpty)
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.finalState == 1)
    #expect(gate.rasterEntryCount >= 1)
    #expect(terminal.frames.count >= 2)
    #expect(terminal.frames.first?.contains("value 0") == true)
    #expect(terminal.frames.last?.contains("value 1") == true)
    #expect(lifecycleRecorder.events == ["appear 0", "disappear 0", "appear 1"])
  }

  @Test("diagnostics count input queued during async render suspension")
  func diagnosticsCountInputQueuedDuringAsyncRenderSuspension() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailDiagnosticsRoot")
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-async-tail-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let lifecycleRecorder = AsyncFrameTailLifecycleRecorder()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        if keyPress == KeyPress(.character("i")) {
          stateContainer.mutate { value in
            value += 1
          }
          return .handled
        }
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailStressView(
          value: value,
          lifecycleRecorder: lifecycleRecorder
        )
      }
    )
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      terminal.frames.contains { $0.contains("value 0") }
    }

    inputReader.send(.key(.character("i")))
    await gate.waitUntilBlocked()
    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    runLoop.renderSuspensionDiagnostics.recordInputEventQueuedIfSuspended()
    inputReader.finish()
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }
    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(
      rows.contains { row in
        (Int(row["input_events_during_render_suspension"] ?? "") ?? 0) >= 1
      })
    #expect(
      rows.allSatisfy { row in
        row["main_actor_blocked_ms"] != nil
          && row["main_actor_suspended_ms"] != nil
          && row["custom_layout_fallbacks"] == "0"
          && row["first_custom_layout_fallback"] == "-"
          && row["geometry_anchor_resolution_misses"] == "0"
          && row["first_geometry_anchor_resolution_miss"] == "-"
          && row["geometry_missing_named_coordinate_spaces"] == "0"
          && row["first_geometry_missing_named_coordinate_space"] == "-"
          && row["geometry_duplicate_named_coordinate_spaces"] == "0"
          && row["first_geometry_duplicate_named_coordinate_space"] == "-"
          && row["layout_dependent_realizations"] == "0"
          && row["layout_dependent_cache_hits"] == "0"
          && row["layout_dependent_main_actor_fallbacks"] == "0"
          && row["stale_frame_policy"] == "commit_ordered"
          && row["tail_job_state"] != nil
          && row["tail_cancel_reason"] != nil
          && row["cancelled_render_count"] != nil
          && row["newest_desired_at_tail_start"] != nil
          && row["newest_desired_at_tail_result"] != nil
          && !(row["drop_blockers"] ?? "").contains("diagnosticsFullRecord")
          && !(row["drop_blockers"] ?? "").contains("retainedLayoutBaseline")
          && !(row["drop_blockers"] ?? "").contains("retainedRasterBaseline")
          && row["desired_generation"] != nil
          && row["render_generation"] != nil
          && row["layout_input_generation"] == row["render_generation"]
          && row["layout_output_generation"] == row["render_generation"]
          && row["raster_input_generation"] == row["render_generation"]
          && row["raster_output_generation"] == row["render_generation"]
          && row["coalesced_event_batches"] != nil
          && row["coalesced_wake_causes"] != nil
          && row["scheduled_animation_request"] != nil
          && row["scheduled_animation_batch"] != nil
          && row["animation_controller_active_animations"] != nil
          && row["animation_controller_pending_work"] != nil
      })
  }

  @Test("interactive render drain yields to queued input before new invalidations")
  func interactiveRenderDrainYieldsToQueuedInputBeforeNewInvalidations() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailRenderDrainInputFairnessRoot")
    let scheduler = FrameScheduler()
    let valueBox = AsyncFrameTailValueBox(value: 0)
    let terminal = AsyncFrameTailInvalidatingTerminalHost(
      valueBox: valueBox,
      scheduler: scheduler,
      invalidationIdentity: rootIdentity
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { _, _ in
        AsyncFrameTailCounterView(value: valueBox.value)
      }
    )
    var renderedFrames = 0

    scheduler.requestInvalidation(of: [rootIdentity])
    try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    #expect(terminal.frames.contains { $0.contains("value 0") })

    valueBox.value = 1
    scheduler.requestInvalidation(of: [rootIdentity])
    let queuedInputPump = RunLoop<Int, AsyncFrameTailCounterView>.EventPump(
      stream: AsyncStream { continuation in
        continuation.finish()
      },
      drainEvents: { [] },
      hasPendingEvents: { true },
      cancel: {},
      scheduleDeadlineWake: { _ in }
    )

    _ = try await runLoop.renderPendingFramesAsync(
      renderedFrames: &renderedFrames,
      eventPump: queuedInputPump
    )

    #expect(terminal.frames.contains { $0.contains("value 1") })
    #expect(!terminal.frames.contains { $0.contains("value 2") })
  }

  @Test("runtime diagnostics logger records geometry resolution diagnostics")
  func runtimeDiagnosticsLoggerRecordsGeometryResolutionDiagnostics() async throws {
    let rootIdentity = testIdentity("RuntimeGeometryDiagnosticsRoot")
    let missingAnchor = Anchor<Rect>(
      identity: testIdentity("LoggedMissingAnchor"),
      kind: .bounds
    )
    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-geometry-diagnostics-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: DefaultRenderer(),
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, _ in
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { _, _ in
        VStack(alignment: .leading, spacing: 0) {
          Text("First")
            .frame(width: 10, height: 1)
            .coordinateSpace(name: "board")
          Text("Second")
            .frame(width: 10, height: 1)
            .coordinateSpace(name: "board")
          GeometryReader { proxy in
            let missingFrame = proxy.frame(in: .named("missing-space"))
            let missingRect = proxy[missingAnchor]
            Text(
              "geometry \(Int(missingFrame.origin.x)) "
                + "\(Int(missingRect.size.width))"
            )
          }
          .frame(width: 20, height: 1)
        }
      }
    )
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      terminal.frames.contains { $0.contains("geometry") }
    }

    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()

    let result = try await valueWithTimeout {
      try await runTask.value
    }
    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(
      rows.contains { row in
        row["geometry_anchor_resolution_misses"] == "1"
          && row["first_geometry_anchor_resolution_miss"] == "LoggedMissingAnchor"
          && row["geometry_missing_named_coordinate_spaces"] == "1"
          && row["first_geometry_missing_named_coordinate_space"] == "missing-space"
          && row["geometry_duplicate_named_coordinate_spaces"] == "2"
          && row["first_geometry_duplicate_named_coordinate_space"] == "board"
          && row["layout_dependent_realizations"] == "1"
          && row["layout_dependent_cache_hits"] == "0"
          && row["layout_dependent_main_actor_fallbacks"] == "1"
      })
  }

  @Test("plain custom layout runs layout on the frame-tail worker")
  func plainCustomLayoutRunsLayoutOnFrameTailWorker() async throws {
    let rootIdentity = testIdentity("AsyncCustomLayoutFallbackRoot")
    let gate = AsyncFrameTailBlockingGate()
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let renderTask = Task {
      await renderer.renderAsync(
        AsyncFrameTailCustomLayout {
          Text("custom")
          Text("layout")
        },
        context: .init(identity: rootIdentity)
      )
    }

    await gate.waitUntilBlocked()
    gate.release()
    let artifacts = await renderTask.value
    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    let mainActorTimings = try #require(artifacts.diagnostics.timing.mainActorTimings)

    #expect(artifacts.diagnostics.work.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.work.firstCustomLayoutFallbackIdentity == nil)
    guard case .custom(let customLayoutHandle) = artifacts.resolvedTree.layoutBehavior else {
      Issue.record("expected custom layout root")
      return
    }
    #expect(customLayoutHandle.executionCapability == .worker)
    #expect(customLayoutHandle.canRunOnWorker)
    #expect(customLayoutHandle.workerProxy != nil)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(mainActorTimings.suspended != .zero)
  }

  @Test("open popover keeps frame-tail layout on the worker")
  func openPopoverKeepsFrameTailLayoutOnWorker() async throws {
    let artifacts = await DefaultRenderer().renderAsync(
      Text("Anchor")
        .popover(
          isPresented: .constant(true),
          arrowEdge: .trailing
        ) {
          Text("Details")
        }
        .frame(width: 36, height: 8, alignment: .topLeading),
      context: .init(
        identity: testIdentity("AsyncPopoverOffloadRoot"),
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 36, height: 8)
    )

    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    let raster = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(artifacts.diagnostics.work.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.work.firstCustomLayoutFallbackIdentity == nil)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(raster.contains("Details"))
  }

  @Test("worker-safe custom layout snapshot runs layout on the frame-tail worker")
  func workerSafeCustomLayoutSnapshotRunsLayoutOnFrameTailWorker() async throws {
    let rootIdentity = testIdentity("AsyncWorkerCustomLayoutRoot")
    let recorder = AsyncFrameTailWorkerCustomLayoutRecorder()

    let artifacts = await DefaultRenderer().renderAsync(
      AsyncFrameTailWorkerCustomLayout(recorder: recorder) {
        Text("worker")
        Text("layout")
      },
      context: .init(identity: rootIdentity),
      proposal: .init(width: 32, height: 6)
    )

    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    let mainActorTimings = try #require(artifacts.diagnostics.timing.mainActorTimings)
    let workerLayoutState = recorder.state

    #expect(artifacts.diagnostics.work.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.work.firstCustomLayoutFallbackIdentity == nil)
    guard case .custom(let customLayoutHandle) = artifacts.resolvedTree.layoutBehavior else {
      Issue.record("expected custom layout root")
      return
    }
    #expect(customLayoutHandle.executionCapability == .worker)
    #expect(customLayoutHandle.canRunOnWorker)
    #expect(customLayoutHandle.workerProxy != nil)
    #expect(workerLayoutState.measureCount >= 1)
    #expect(workerLayoutState.placeCount >= 1)
    #expect(workerLayoutState.measureRanOnMainThread == false)
    #expect(workerLayoutState.placeRanOnMainThread == false)
    #expect(workerLayoutState.cacheApplyCount == 1)
    // `recordCacheApply` is `@MainActor`-isolated. The recorder uses
    // `currentlyOnMainActor()` which derives the answer from the caller's
    // `#isolation` rather than `Thread.isMainThread`, so this assertion is
    // portable across Darwin and Linux despite the Linux Foundation gap
    // documented in LINUX_ISSUES.md issue #2.
    #expect(workerLayoutState.cacheApplyRanOnMainThread == true)
    #expect(workerLayoutState.cacheApplyIdentity == rootIdentity)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(mainActorTimings.suspended != .zero)
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("worker"))
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("layout"))
  }

  @Test("layout-realized content relayouts worker-safe snapshots on the frame-tail worker")
  func layoutRealizedContentRelayoutsWorkerSafeSnapshotOnFrameTailWorker() async throws {
    let artifacts = await DefaultRenderer().renderAsync(
      GeometryReader { proxy in
        Text("geometry \(proxy.size.width)x\(proxy.size.height)")
      },
      context: .init(identity: testIdentity("AsyncGeometryRoot")),
      proposal: .init(width: 24, height: 5)
    )

    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    #expect(artifacts.diagnostics.work.layoutDependentRealizations == 1)
    #expect(artifacts.diagnostics.work.layoutDependentMainActorFallbacks == 1)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(artifacts.rasterSurface.lines.contains { $0.contains("geometry 24x5") })
  }

  @Test("layout-realized content realizes on the main actor then relayouts on the worker")
  func layoutRealizedContentWithCustomLayoutRelayoutsOnWorker() async throws {
    let artifacts = await DefaultRenderer().renderAsync(
      GeometryReader { _ in
        AsyncFrameTailCustomLayout {
          Text("geometry custom")
        }
      },
      context: .init(identity: testIdentity("AsyncGeometryCustomLayoutRoot")),
      proposal: .init(width: 24, height: 5)
    )

    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    let raster = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(artifacts.diagnostics.work.layoutDependentRealizations == 1)
    #expect(artifacts.diagnostics.work.layoutDependentMainActorFallbacks == 1)
    #expect(artifacts.diagnostics.work.customLayoutFallbackCount == 0)
    // Realization itself is main-actor-only, but the realized snapshot's
    // relayout offloads now that the custom layout is worker-capable —
    // pre-F11 the plain `Layout` disqualified offload and this stayed zero.
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(raster.contains("geometry custom"))
  }

  @Test("layout-realized async commits publish realized action registrations")
  func layoutDependentAsyncCommitsPublishRealizedActionRegistrations() async throws {
    let actionRegistry = LocalActionRegistry()
    var didTap = false

    let artifacts = await DefaultRenderer().renderAsync(
      GeometryReader { _ in
        Button("Hit") {
          didTap = true
        }
      },
      context: .init(
        identity: testIdentity("AsyncGeometryActionRoot"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: false
      ),
      proposal: .init(width: 24, height: 5)
    )

    let actionIdentity = try #require(artifacts.semanticSnapshot.focusRegions.first?.identity)
    #expect(actionRegistry.hasHandler(identity: actionIdentity))
    #expect(actionRegistry.dispatch(identity: actionIdentity))
    #expect(didTap)
  }

  @Test("late toolbar diagnostics are preserved on the async renderer")
  func lateToolbarDiagnosticsArePreservedOnAsyncRenderer() async throws {
    let artifacts = await DefaultRenderer().renderAsync(
      GeometryReader { _ in
        Text("content").toolbarItem(
          .init(
            title: "Late Save",
            icon: nil,
            position: .bottom,
            isEnabled: true,
            action: {}
          )
        )
      },
      context: .init(identity: testIdentity("AsyncLateToolbarRoot")),
      proposal: .init(width: 24, height: 4)
    )
    let issue = artifacts.diagnostics.runtime.issues.first

    #expect(artifacts.diagnostics.runtime.issues.count == 1)
    #expect(issue?.code == "toolbar.unhostedItems")
    #expect(issue?.severity == .warning)
  }

  @Test("custom layout compatibility depth issues are preserved on the async renderer")
  func customLayoutCompatibilityDepthIssuesArePreservedOnAsyncRenderer() async throws {
    let artifacts = await DefaultRenderer().renderAsync(
      AsyncFrameTailRecursiveCustomLayout(depth: 80),
      context: .init(identity: testIdentity("AsyncRecursiveCustomLayoutRoot")),
      proposal: .init(width: 24, height: 4)
    )
    let issues = artifacts.diagnostics.runtime.issues.filter {
      $0.code == "layout.customLayoutDepthLimitExceeded"
    }

    #expect(!issues.isEmpty)
    #expect(issues.contains { $0.message.contains("measurement") })
    #expect(issues.contains { $0.message.contains("placement") })
    #expect(issues.first?.severity == .error)
  }

  @Test("public SendableLayout opt-in runs layout on the frame-tail worker")
  func publicSendableLayoutOptInRunsLayoutOnFrameTailWorker() async throws {
    let rootIdentity = testIdentity("AsyncSendableLayoutRoot")
    let recorder = AsyncFrameTailSendableLayoutRecorder()

    let artifacts = await DefaultRenderer().renderAsync(
      AsyncFrameTailSendableLayout(recorder: recorder) {
        Text("sendable")
        Text("layout")
      },
      context: .init(identity: rootIdentity),
      proposal: .init(width: 32, height: 6)
    )

    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    let mainActorTimings = try #require(artifacts.diagnostics.timing.mainActorTimings)
    let layoutState = recorder.state

    #expect(artifacts.diagnostics.work.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.work.firstCustomLayoutFallbackIdentity == nil)
    guard case .custom(let customLayoutHandle) = artifacts.resolvedTree.layoutBehavior else {
      Issue.record("expected custom layout root")
      return
    }
    #expect(customLayoutHandle.executionCapability == .worker)
    #expect(customLayoutHandle.canRunOnWorker)
    #expect(customLayoutHandle.workerProxy != nil)
    #expect(layoutState.makeCacheCount == 1)
    #expect(layoutState.measuredCache == 1)
    #expect(layoutState.placedCache == 1)
    #expect(layoutState.measureRanOnMainThread == false)
    #expect(layoutState.placeRanOnMainThread == false)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(mainActorTimings.suspended != .zero)
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("sendable"))
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("layout"))
  }

  @Test("public SendableLayout cache is pass-local across async layout passes")
  func publicSendableLayoutCacheIsPassLocalAcrossAsyncLayoutPasses() async throws {
    let rootIdentity = testIdentity("AsyncSendableLayoutPassLocalCacheRoot")
    let recorder = AsyncFrameTailSendableLayoutRecorder()
    let renderer = DefaultRenderer()

    @MainActor
    func root(_ text: String) -> some View {
      AsyncFrameTailSendableLayout(recorder: recorder) {
        Text(text)
      }
    }

    _ = await renderer.renderAsync(
      root("A"),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 32, height: 6)
    )
    var layoutState = recorder.state
    #expect(layoutState.makeCacheCount == 1)
    #expect(layoutState.measuredCache == 1)
    #expect(layoutState.placedCache == 1)

    _ = await renderer.renderAsync(
      root("AB"),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 32, height: 6)
    )
    layoutState = recorder.state
    #expect(layoutState.makeCacheCount == 2)
    #expect(layoutState.measuredCache == 2)
    #expect(layoutState.placedCache == 2)
  }

  @Test("public SendableLayout cache is recreated after async proposal and structure changes")
  func publicSendableLayoutCacheIsRecreatedAfterAsyncProposalAndStructureChanges() async throws {
    let rootIdentity = testIdentity("AsyncSendableLayoutProposalStructureCacheRoot")
    let recorder = AsyncFrameTailSendableLayoutRecorder()
    let renderer = DefaultRenderer()

    @MainActor
    func root(includeSecond: Bool) -> some View {
      AsyncFrameTailSendableLayout(recorder: recorder) {
        Text("A")
        if includeSecond {
          Text("B")
        }
      }
    }

    _ = await renderer.renderAsync(
      root(includeSecond: false),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 32, height: 6)
    )
    var layoutState = recorder.state
    #expect(layoutState.makeCacheCount == 1)
    #expect(layoutState.measuredCache == 1)
    #expect(layoutState.placedCache == 1)

    _ = await renderer.renderAsync(
      root(includeSecond: false),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 24, height: 6)
    )
    layoutState = recorder.state
    #expect(layoutState.makeCacheCount == 2)
    #expect(layoutState.measuredCache == 2)
    #expect(layoutState.placedCache == 2)

    _ = await renderer.renderAsync(
      root(includeSecond: true),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 24, height: 6)
    )
    layoutState = recorder.state
    #expect(layoutState.makeCacheCount == 3)
    #expect(layoutState.measuredCache == 3)
    #expect(layoutState.placedCache == 3)
    #expect(layoutState.measureRanOnMainThread == false)
    #expect(layoutState.placeRanOnMainThread == false)
  }

  @Test("public SendableLayout reads dimensions and alignment guides on the worker")
  func publicSendableLayoutReadsDimensionsAndAlignmentGuidesOnWorker() async throws {
    let rootIdentity = testIdentity("AsyncSendableGuideLayoutRoot")
    let recorder = AsyncFrameTailSendableLayoutRecorder()

    let artifacts = await DefaultRenderer().renderAsync(
      AsyncFrameTailSendableGuideLayout(recorder: recorder) {
        Text("AB").alignmentGuide(.asyncFrameTailRaisedCenter) { dimensions in
          dimensions[.trailing]
        }
        Text("C")
      },
      context: .init(identity: rootIdentity),
      proposal: .init(width: 32, height: 6)
    )

    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    let layoutState = recorder.state

    #expect(artifacts.diagnostics.work.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.work.firstCustomLayoutFallbackIdentity == nil)
    #expect(layoutState.measureRanOnMainThread == false)
    #expect(layoutState.placeRanOnMainThread == false)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(artifacts.rasterSurface.lines.filter { !$0.isEmpty } == ["ABC"])
    #expect(
      artifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 2, y: 0),
      ])
  }

  @Test("public SendableLayout reuses retained layout across draw-only async frames")
  func publicSendableLayoutReusesRetainedLayoutAcrossDrawOnlyAsyncFrames() async throws {
    let rootIdentity = testIdentity("AsyncSendableLayoutReuseRoot")
    let recorder = AsyncFrameTailSendableLayoutRecorder()
    let renderer = DefaultRenderer()
    let blend = BorderBlend([.red, .yellow, .green, .cyan, .blue, .magenta, .red])

    @MainActor
    func root(phase: Double) -> some View {
      AsyncFrameTailSendableLayout(recorder: recorder) {
        Text("tick")
          .padding(1)
          .border(
            blend: blend,
            set: .rounded,
            phase: phase
          )
      }
    }

    let first = await renderer.renderAsync(
      root(phase: 0),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 24, height: 6)
    )
    let second = await renderer.renderAsync(
      root(phase: 0.5),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 24, height: 6)
    )

    #expect(first.diagnostics.work.measuredNodesComputed > 0)
    #expect(first.diagnostics.work.placedNodesComputed > 0)
    #expect(second.diagnostics.work.customLayoutFallbackCount == 0)
    #expect(second.diagnostics.work.measuredNodesComputed == 0)
    #expect(second.diagnostics.work.placedNodesComputed == 0)
  }

  @Test("public SendableLayout focus sync rerender converges on the runtime path")
  func publicSendableLayoutFocusSyncRerenderConvergesOnRuntimePath() async throws {
    let rootIdentity = testIdentity("AsyncSendableLayoutFocusRoot")
    let recorder = AsyncFrameTailSendableLayoutRecorder()
    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: DefaultRenderer(),
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, _ in
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { _, _ in
        AsyncFrameTailSendableFocusView(recorder: recorder)
      }
    )

    let runTask = Task {
      try await runLoop.run()
    }
    defer {
      inputReader.finish()
      runTask.cancel()
    }

    try await waitUntil {
      terminal.frames.contains {
        $0.contains("Field: first")
          && $0.contains("Focus: AsyncFrameTailSendableFocus/First")
      }
    }

    inputReader.send(.key(.tab))

    try await waitUntil {
      terminal.frames.contains {
        $0.contains("Field: second")
          && $0.contains("Focus: AsyncFrameTailSendableFocus/Second")
      }
    }

    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    let result = try await valueWithTimeout {
      try await runTask.value
    }
    let layoutState = recorder.state

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(layoutState.measureRanOnMainThread == false)
    #expect(layoutState.placeRanOnMainThread == false)
  }

  @Test("framework-owned WindowHostLayout runs on the frame-tail worker")
  func frameworkOwnedWindowHostLayoutRunsOnFrameTailWorker() async throws {
    try await assertFrameworkOwnedLayoutWorker(
      WindowHostLayout {
        Text("window content")
      },
      identity: testIdentity("AsyncFrameworkWindowHostLayoutRoot"),
      proposal: .init(width: 24, height: 4),
      marker: "window content"
    )
  }

  private func assertFrameworkOwnedLayoutWorker<V: View>(
    _ view: V,
    identity: Identity,
    proposal: ProposedSize,
    marker: String
  ) async throws {
    let artifacts = await DefaultRenderer().renderAsync(
      view,
      context: .init(identity: identity),
      proposal: proposal
    )
    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    let raster = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(
      artifacts.diagnostics.work.customLayoutFallbackCount == 0,
      """
      expected \(identity.path) to avoid custom-layout fallback; \
      first fallback was \(artifacts.diagnostics.work.firstCustomLayoutFallbackIdentity?.path ?? "nil")
      \(raster)
      """
    )
    #expect(artifacts.diagnostics.work.firstCustomLayoutFallbackIdentity == nil)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(raster.contains(marker))
  }

  @Test("framework-owned ScrollView layout runs on the frame-tail worker")
  func frameworkOwnedScrollViewLayoutRunsOnFrameTailWorker() async throws {
    try await assertFrameworkOwnedLayoutWorker(
      ScrollView([.vertical], showsIndicators: true) {
        VStack(alignment: .leading, spacing: 0) {
          Text("scroll row 0")
          Text("scroll row 1")
          Text("scroll row 2")
        }
      },
      identity: testIdentity("AsyncFrameworkScrollViewLayoutRoot"),
      proposal: .init(width: 24, height: 4),
      marker: "scroll row 0"
    )
  }

  @Test("lazy indexed ScrollView content snapshots before worker layout")
  func lazyIndexedScrollViewContentSnapshotsBeforeWorkerLayout() async throws {
    let artifacts = await DefaultRenderer().renderAsync(
      ScrollView([.vertical], showsIndicators: true) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<12) { index in
            Text("lazy row \(index)")
          }
        }
      },
      context: .init(identity: testIdentity("AsyncLazyIndexedScrollViewLayoutRoot")),
      proposal: .init(width: 24, height: 4)
    )
    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    let raster = artifacts.rasterSurface.lines.joined(separator: "\n")

    let lazyStack = try #require(artifacts.resolvedTree.children.first)
    let source = try #require(lazyStack.indexedChildSource)

    #expect(source.canRunOnWorker)
    #expect(source.workerResolvedChildren?.count == 12)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(raster.contains("lazy row 0"))
  }

  @Test("lazy indexed child with plain custom layout keeps layout on the worker")
  func lazyIndexedChildWithPlainCustomLayoutKeepsLayoutOnWorker() async throws {
    let artifacts = await DefaultRenderer().renderAsync(
      ScrollView([.vertical], showsIndicators: true) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<1) { _ in
            AsyncFrameTailCustomLayout {
              Text("custom lazy")
            }
          }
        }
      },
      context: .init(identity: testIdentity("AsyncLazyIndexedCustomLayoutRoot")),
      proposal: .init(width: 24, height: 4)
    )
    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    let raster = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(artifacts.diagnostics.work.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.work.firstCustomLayoutFallbackIdentity == nil)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(raster.contains("custom lazy"))
  }

  @Test("framework-owned TabView container layout runs on the frame-tail worker")
  func frameworkOwnedTabViewContainerLayoutRunsOnFrameTailWorker() async throws {
    try await assertFrameworkOwnedLayoutWorker(
      TabView(selection: .constant("home")) {
        Tab("Home", value: "home") {
          Text("Home content")
        }

        Tab("Logs", value: "logs") {
          Text("Logs content")
        }
      },
      identity: testIdentity("AsyncFrameworkTabViewLayoutRoot"),
      proposal: .init(width: 40, height: 4),
      marker: "Home content"
    )
  }

  @Test("computed async frames commit in order even when newer input is queued")
  func computedAsyncFramesCommitInOrderEvenWhenNewerInputIsQueued() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailBacklogRoot")
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-async-tail-coalescing-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        if keyPress == KeyPress(.character("i")) {
          stateContainer.mutate { value in
            value += 1
          }
          return .handled
        }
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailCounterView(value: value)
      }
    )
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      terminal.frames.contains { $0.contains("value 0") }
    }

    inputReader.send(.key(.character("i")))
    await gate.waitUntilBlocked()
    #expect(terminal.frames.contains { $0.contains("value 1") } == false)

    inputReader.send(.key(.character("i")))
    inputReader.send(.key(.character("i")))
    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.finalState == 3)
    #expect((3...4).contains(result.renderedFrames))
    let value1Index = terminal.frames.firstIndex { $0.contains("value 1") }
    let value2Index = terminal.frames.firstIndex { $0.contains("value 2") }
    let value3Index = terminal.frames.firstIndex { $0.contains("value 3") }
    #expect(value1Index != nil)
    #expect(value3Index != nil)
    if let value1Index, let value2Index {
      #expect(value1Index < value2Index)
    }
    if let value2Index, let value3Index {
      #expect(value2Index < value3Index)
    }
    if let value1Index, let value3Index {
      #expect(value1Index < value3Index)
    }

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(
      rows.contains { row in
        (Int(row["coalesced_event_batches"] ?? "") ?? 0) >= 1
          && (row["coalesced_wake_causes"] ?? "").contains("input")
          && row["stale_frame_policy"] == "commit_ordered"
      })
    #expect(rows.allSatisfy { $0["tail_job_state"] != "cancelled_before_start" })
  }

  @Test("queued frame tail cancels before worker layout starts")
  func queuedFrameTailCancelsBeforeWorkerLayoutStarts() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailQueuedCancellationRoot")
    let workerGate = AsyncFrameTailBlockingGate()
    let renderer = DefaultRenderer()
    defer {
      workerGate.release()
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-async-tail-cancellation-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        if keyPress == KeyPress(.character("i")) {
          stateContainer.mutate { value in
            value += 1
          }
          return .handled
        }
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailCounterView(value: value)
      }
    )
    runLoop.renderMode = .async
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      terminal.frames.contains { $0.contains("value 0") }
    }

    let workerBlockTask = Task {
      await renderer.runFrameTailLayoutWorkerJobForCancellationTesting {
        workerGate.beforeRaster()
      }
    }
    await workerGate.waitUntilBlocked()

    stateContainer.replace(with: 1)
    try await waitUntil {
      runLoop.renderSuspensionDiagnostics.isSuspended
    }
    #expect(terminal.frames.contains { $0.contains("value 1") } == false)

    stateContainer.replace(with: 2)
    try await waitUntil {
      runLoop.cancelledRenderCount >= 1
    }
    workerGate.release()

    try await waitUntil {
      terminal.frames.last?.contains("value 2") == true
    }
    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()

    let result = try await valueWithTimeout {
      try await runTask.value
    }
    await workerBlockTask.value

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.finalState == 2)
    #expect(result.renderedFrames == 2)
    #expect(terminal.frames.contains { $0.contains("value 1") } == false)
    #expect(terminal.frames.last?.contains("value 2") == true)

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(
      rows.contains { row in
        row["tail_job_state"] == "cancelled_before_start"
          && row["tail_cancel_reason"] == "newer_render_intent"
          && row["stale_frame_policy"] == "cancel_pending_before_start"
          && (Int(row["cancelled_render_count"] ?? "") ?? 0) >= 1
      })
  }

  @Test("runtime render mode sync bypasses async cancellation")
  func runtimeRenderModeSyncBypassesAsyncCancellation() async throws {
    let rootIdentity = testIdentity("RuntimeRenderModeSyncRoot")
    let workerGate = AsyncFrameTailBlockingGate()
    let renderer = DefaultRenderer()
    defer {
      workerGate.release()
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-render-mode-sync-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailCounterView(value: value)
      }
    )
    runLoop.renderMode = .sync
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)

    #expect(terminal.frames.contains { $0.contains("value 0") })

    let workerBlockTask = Task {
      await renderer.runFrameTailLayoutWorkerJobForCancellationTesting {
        workerGate.beforeRaster()
      }
    }
    await workerGate.waitUntilBlocked()

    stateContainer.replace(with: 1)
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
    workerGate.release()
    await workerBlockTask.value

    #expect(renderedFrames == 2)
    #expect(runLoop.cancelledRenderCount == 0)
    #expect(terminal.frames.last?.contains("value 1") == true)

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(rows.allSatisfy { $0["tail_job_state"] != "cancelled_before_start" })
    #expect(rows.allSatisfy { $0["stale_frame_policy"] != "cancel_pending_before_start" })
  }

  @Test("runtime render mode async-no-cancel commits queued work in order")
  func runtimeRenderModeAsyncNoCancelCommitsQueuedWorkInOrder() async throws {
    let rootIdentity = testIdentity("RuntimeRenderModeAsyncNoCancelRoot")
    let workerGate = AsyncFrameTailBlockingGate()
    let renderer = DefaultRenderer()
    defer {
      workerGate.release()
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-render-mode-async-no-cancel-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, _ in
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailHandledCounterView(value: value)
      }
    )
    runLoop.renderMode = .asyncNoCancel
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      terminal.frames.contains { $0.contains("value 0") }
    }

    let workerBlockTask = Task {
      await renderer.runFrameTailLayoutWorkerJobForCancellationTesting {
        workerGate.beforeRaster()
      }
    }
    await workerGate.waitUntilBlocked()

    stateContainer.replace(with: 1)
    try await waitUntil {
      runLoop.renderSuspensionDiagnostics.isSuspended
    }
    #expect(terminal.frames.contains { $0.contains("value 1") } == false)

    stateContainer.replace(with: 2)
    try await waitUntil {
      runLoop.scheduler.hasPendingFrame(at: .now())
    }
    workerGate.release()

    try await waitUntil {
      terminal.frames.last?.contains("value 2") == true
    }
    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()

    let result = try await valueWithTimeout {
      try await runTask.value
    }
    await workerBlockTask.value

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.finalState == 2)
    #expect(result.renderedFrames == 3)
    #expect(runLoop.cancelledRenderCount == 0)
    let value1Index = terminal.frames.firstIndex { $0.contains("value 1") }
    let value2Index = terminal.frames.firstIndex { $0.contains("value 2") }
    #expect(value1Index != nil)
    #expect(value2Index != nil)
    if let value1Index, let value2Index {
      #expect(value1Index < value2Index)
    }

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(rows.allSatisfy { $0["tail_job_state"] != "cancelled_before_start" })
    #expect(rows.allSatisfy { $0["tail_job_state"] != "dropped_completed" })
    #expect(rows.allSatisfy { $0["stale_frame_policy"] != "cancel_pending_before_start" })
  }

  @Test("stale completed visual-only frame drops before commit")
  func staleCompletedVisualOnlyFrameDropsBeforeCommit() async throws {
    let rootIdentity = testIdentity("AsyncCompletedVisualOnlyDropRoot")
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-async-completed-drop-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        if keyPress == KeyPress(.character("i")) {
          stateContainer.mutate { value in
            value += 1
          }
          return .handled
        }
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncSkippedVisualOnlyView(value: value)
      }
    )
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)

    #expect(terminal.frames.contains { $0.contains("visual 0") })

    stateContainer.replace(with: 1)
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    let eventPump = RunLoop<Int, AsyncSkippedVisualOnlyView>.EventPump(
      stream: AsyncStream { continuation in
        continuation.finish()
      },
      drainEvents: { [] },
      hasPendingEvents: { false },
      cancel: {},
      scheduleDeadlineWake: { _ in }
    )
    let renderTask = Task { @MainActor in
      var renderedFrames = initialFrames
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: eventPump
      )
      return renderedFrames
    }
    try await valueWithTimeout {
      await gate.waitUntilBlocked()
    }
    #expect(terminal.frames.contains { $0.contains("visual 1") } == false)

    stateContainer.replace(with: 2)
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try await waitUntil {
      runLoop.scheduler.hasPendingFrame(at: .now())
    }
    gate.release()
    let renderedFrames = try await valueWithTimeout {
      try await renderTask.value
    }

    #expect(renderedFrames == 2)
    #expect(stateContainer.state == 2)
    #expect(terminal.frames.contains { $0.contains("visual 1") } == false)
    #expect(terminal.frames.last?.contains("visual 2") == true)

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(
      rows.contains { row in
        row["tail_job_state"] == "dropped_completed"
          && row["stale_frame_policy"] == "drop_completed_visual_only"
          && row["drop_decision"] == "drop_visual_only"
          && row["drop_generation"] != nil
          && row["newest_desired_at_drop"] != nil
          && row["drop_reconciliation_mode"] == "empty_visual_only"
          && row["drop_reconciliation_effects"] == "-"
          && row["presentation_recovery_after_drop"] == "0"
      })
  }

  @Test("stale completed visual-only frame with stable interaction chrome drops before commit")
  func staleCompletedVisualOnlyFrameWithStableInteractionChromeDropsBeforeCommit() async throws {
    let rootIdentity = testIdentity("AsyncCompletedStableChromeVisualOnlyDropRoot")
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-async-stable-chrome-drop-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, stateContainer in
        if keyPress == KeyPress(.character("i")) {
          stateContainer.mutate { value in
            value += 1
          }
          return .handled
        }
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncSkippedStableInteractionVisualOnlyView(value: value)
      }
    )
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)

    #expect(terminal.frames.contains { $0.contains("visual 0") })

    stateContainer.replace(with: 1)
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    let eventPump = RunLoop<Int, AsyncSkippedStableInteractionVisualOnlyView>.EventPump(
      stream: AsyncStream { continuation in
        continuation.finish()
      },
      drainEvents: { [] },
      hasPendingEvents: { false },
      cancel: {},
      scheduleDeadlineWake: { _ in }
    )
    let renderTask = Task { @MainActor in
      var renderedFrames = initialFrames
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: eventPump
      )
      return renderedFrames
    }
    try await valueWithTimeout {
      await gate.waitUntilBlocked()
    }
    #expect(terminal.frames.contains { $0.contains("visual 1") } == false)

    stateContainer.replace(with: 2)
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try await waitUntil {
      runLoop.scheduler.hasPendingFrame(at: .now())
    }
    gate.release()
    let renderedFrames = try await valueWithTimeout {
      try await renderTask.value
    }

    #expect(renderedFrames == 2)
    #expect(stateContainer.state == 2)
    #expect(terminal.frames.contains { $0.contains("visual 1") } == false)
    #expect(terminal.frames.last?.contains("visual 2") == true)

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(
      rows.contains { row in
        row["tail_job_state"] == "dropped_completed"
          && row["stale_frame_policy"] == "drop_completed_visual_only"
          && row["drop_decision"] == "drop_visual_only"
      })
  }

  @Test("runtime render mode async-no-drop commits stale visual-only frames")
  func runtimeRenderModeAsyncNoDropCommitsStaleVisualOnlyFrames() async throws {
    let rootIdentity = testIdentity("RuntimeRenderModeAsyncNoDropRoot")
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-render-mode-async-no-drop-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncSkippedVisualOnlyView(value: value)
      }
    )
    runLoop.renderMode = .asyncNoDrop
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)

    #expect(terminal.frames.contains { $0.contains("visual 0") })

    stateContainer.replace(with: 1)
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    let eventPump = RunLoop<Int, AsyncSkippedVisualOnlyView>.EventPump(
      stream: AsyncStream { continuation in
        continuation.finish()
      },
      drainEvents: { [] },
      hasPendingEvents: { false },
      cancel: {},
      scheduleDeadlineWake: { _ in }
    )
    let renderTask = Task { @MainActor in
      var renderedFrames = initialFrames
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: eventPump
      )
      return renderedFrames
    }
    try await valueWithTimeout {
      await gate.waitUntilBlocked()
    }
    #expect(terminal.frames.contains { $0.contains("visual 1") } == false)

    stateContainer.replace(with: 2)
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try await waitUntil {
      runLoop.scheduler.hasPendingFrame(at: .now())
    }
    gate.release()
    let renderedFrames = try await valueWithTimeout {
      try await renderTask.value
    }

    #expect(renderedFrames == 3)
    #expect(stateContainer.state == 2)
    let value1Index = terminal.frames.firstIndex { $0.contains("visual 1") }
    let value2Index = terminal.frames.firstIndex { $0.contains("visual 2") }
    #expect(value1Index != nil)
    #expect(value2Index != nil)
    if let value1Index, let value2Index {
      #expect(value1Index < value2Index)
    }

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(rows.allSatisfy { $0["tail_job_state"] != "dropped_completed" })
    #expect(rows.allSatisfy { $0["stale_frame_policy"] != "drop_completed_visual_only" })
    #expect(rows.allSatisfy { $0["drop_decision"] != "drop_visual_only" })
    #expect(
      rows.contains { row in
        row["tail_job_state"] == "completed"
          && row["stale_frame_policy"] == "commit_ordered"
          && row["drop_decision"] == "commit_ordered"
          && row["drop_reconciliation_mode"] == "blocked"
      })
  }

  @Test("cancelled animation intent is replayed into replacement frame diagnostics")
  func cancelledAnimationIntentIsReplayedIntoReplacementFrameDiagnostics() async throws {
    let rootIdentity = testIdentity("AsyncFrameTailAnimationIntentReplayRoot")
    let workerGate = AsyncFrameTailBlockingGate()
    let renderer = DefaultRenderer()
    defer {
      workerGate.release()
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
      AnimationCompletionStorage.currentSink = nil
    }

    let inputReader = InjectedTerminalInputReader()
    let terminal = AsyncFrameTailTerminalHost()
    let diagnosticsURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-async-animation-replay-\(UUID().uuidString).tsv")
    defer {
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailAnimatedOffsetView(value: value)
      }
    )
    runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)
    #expect(runLoop.frameSink != nil)

    let animationController = renderer.internalAnimationController
    AnimationRegistrationStorage.currentSink = animationController
    TransitionRegistrationStorage.currentSink = animationController
    AnimationCompletionStorage.currentSink = animationController

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      terminal.frames.contains { $0.contains("value 0") }
    }

    let workerBlockTask = Task {
      await renderer.runFrameTailLayoutWorkerJobForCancellationTesting {
        workerGate.beforeRaster()
      }
    }
    await workerGate.waitUntilBlocked()

    withAnimation(.linear(duration: .milliseconds(400))) {
      stateContainer.replace(with: 1)
    }
    try await waitUntil {
      runLoop.renderSuspensionDiagnostics.isSuspended
    }
    #expect(terminal.frames.contains { $0.contains("value 1") } == false)

    stateContainer.replace(with: 2)
    try await waitUntil {
      runLoop.cancelledRenderCount >= 1
    }
    workerGate.release()

    try await waitUntil {
      terminal.frames.last?.contains("value 2") == true
    }
    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()

    let result = try await valueWithTimeout {
      try await runTask.value
    }
    await workerBlockTask.value

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(result.finalState == 2)
    #expect(terminal.frames.contains { $0.contains("value 1") } == false)
    #expect(terminal.frames.last?.contains("value 2") == true)

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    let cancelledAnimationIndex = rows.firstIndex { row in
      row["tail_job_state"] == "cancelled_before_start"
        && row["tail_cancel_reason"] == "newer_render_intent"
        && row["stale_frame_policy"] == "cancel_pending_before_start"
        && row["scheduled_animation_request"] == "animate"
    }
    #expect(
      cancelledAnimationIndex != nil,
      "expected the cancelled pre-start frame to carry explicit animation intent; rows=\(rows)"
    )
    if let cancelledAnimationIndex {
      let replayedCommit = rows.suffix(from: rows.index(after: cancelledAnimationIndex))
        .contains { row in
          row["tail_job_state"] == "completed"
            && row["stale_frame_policy"] == "commit_ordered"
            && row["scheduled_animation_request"] == "animate"
            && (row["drop_blockers"] ?? "").contains("animationTransaction")
            && (Int(row["animation_controller_active_animations"] ?? "") ?? 0) > 0
        }
      #expect(
        replayedCommit,
        """
        expected the replacement frame after cancellation to commit with the \
        cancelled frame's animation intent replayed; rows=\(rows)
        """
      )
    }
  }

  @Test("async renderer records worker timing diagnostics")
  func asyncRendererRecordsWorkerTimingDiagnostics() async {
    let artifacts = await DefaultRenderer().renderAsync(
      VStack(alignment: .leading, spacing: 1) {
        Text("Async")
        Text("Diagnostics")
      },
      context: .init(identity: testIdentity("AsyncTimingRoot"))
    )

    #expect(artifacts.diagnostics.timing.phaseTimings != nil)
    #expect(artifacts.diagnostics.timing.workerTimings != nil)
    #expect(artifacts.diagnostics.timing.mainActorTimings != nil)
  }

  @Test("sync and async renderer artifacts stay equivalent")
  func syncAndAsyncRendererArtifactsStayEquivalent() async {
    let rootIdentity = testIdentity("AsyncFrameTailParityRoot")
    let commandRootIdentity = testIdentity("AsyncFrameTailCommandParityRoot")
    let proposal = ProposedSize(width: 24, height: 5)
    let commandRecorder = AsyncFrameHeadAbortEffectRecorder()

    @MainActor
    func root() -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text("Parity")
        HStack(spacing: 1) {
          Text("A")
          Text("B")
        }
      }
    }

    @MainActor
    func commandRoot() -> some View {
      AsyncFrameHeadDraftKeyCommandView(
        value: 1,
        recorder: commandRecorder
      )
    }

    let syncArtifacts = DefaultRenderer().render(
      root(),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )
    let asyncArtifacts = await DefaultRenderer().renderAsync(
      root(),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    #expect(syncArtifacts == asyncArtifacts)

    let syncCommandArtifacts = DefaultRenderer().render(
      commandRoot(),
      context: .init(identity: commandRootIdentity),
      proposal: proposal
    )
    let asyncCommandArtifacts = await DefaultRenderer().renderAsync(
      commandRoot(),
      context: .init(identity: commandRootIdentity),
      proposal: proposal
    )

    #expect(syncCommandArtifacts == asyncCommandArtifacts)
  }

  @Test("sync renderer commits draft key command registrations")
  func syncRendererCommitsDraftKeyCommandRegistrations() throws {
    let rootIdentity = testIdentity("SyncFrameHeadDraftKeyCommandRoot")
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let commandRegistry = CommandRegistry()
    let initialBinding = KeyBinding(key: .character("i"), modifiers: .ctrl)
    let draftBinding = KeyBinding(key: .character("d"), modifiers: .ctrl)
    var context = ResolveContext(identity: rootIdentity)
    context.commandRegistry = commandRegistry

    _ = renderer.render(
      AsyncFrameHeadDraftKeyCommandView(
        value: 0,
        recorder: recorder
      ),
      context: context,
      proposal: .init(width: 24, height: 5)
    )
    let commandScope = try #require(
      commandRegistry.snapshot().keyCommandsByScope.first {
        $0.value[initialBinding] != nil
      }?.key
    )
    #expect(
      commandRegistry.keyCommand(at: commandScope, matching: draftBinding)?.isEnabled == false)

    var updateContext = context
    updateContext.invalidatedIdentities = [rootIdentity]
    _ = renderer.render(
      AsyncFrameHeadDraftKeyCommandView(
        value: 1,
        recorder: recorder
      ),
      context: updateContext,
      proposal: .init(width: 24, height: 5)
    )

    #expect(commandRegistry.keyCommand(at: commandScope, matching: draftBinding)?.isEnabled == true)
  }

  @Test("frame-head abort scaffold records normal committed effects")
  func frameHeadAbortScaffoldRecordsNormalCommittedEffects() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadAbortScaffoldRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let inputReader = InjectedTerminalInputReader()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: DefaultRenderer(),
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: AsyncFrameHeadAbortScaffoldState(),
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: terminal.proposal,
      viewBuilder: { state, _ in
        AsyncFrameHeadAbortScaffoldView(
          state: state,
          recorder: recorder
        )
      }
    )
    focusTracker.invalidator = runLoop.scheduler

    try await withAsyncFrameHeadAbortAnimationSinks(runLoop.renderer) {
      try renderAsyncFrameHeadAbortScaffoldFrame(runLoop)
      runLoop.renderer.enableSelectiveEvaluation()

      #expect(recorder.events.contains("preference:pref-0"))
      #expect(runLoop.focusTracker.currentFocusIdentity != nil)
      #expect(!runLoop.latestSemanticSnapshot.scrollRoutes.isEmpty)

      focusLeafmostAsyncFrameHeadAbortScaffoldRegion(in: runLoop)
      _ = runLoop.handleKeyPress(KeyPress(.space, modifiers: []))
      try renderAsyncFrameHeadAbortScaffoldFrame(runLoop)

      #expect(recorder.events.contains("action"))
      #expect(recorder.events.contains("change:true"))
      #expect(recorder.events.contains("animation-completion"))
      try await waitUntil {
        recorder.events.contains("task:revealed")
      }
      #expect(recorder.events.contains("appear:revealed"))

      _ = runLoop.handleKeyPress(KeyPress(.space, modifiers: []))
      try renderAsyncFrameHeadAbortScaffoldFrame(runLoop)

      #expect(recorder.events.contains("change:false"))

      _ = runLoop.handleKeyPress(KeyPress(.character("a"), modifiers: .ctrl))
      runLoop.handlePaste(PasteEvent(content: "/tmp/frame-head-abort.txt"))

      #expect(recorder.events.contains("key-command"))
      #expect(recorder.events.contains("drop:1"))
    }
  }

  @Test("RunLoop.run dispatches frame-head scaffold registrations")
  func runLoopRunDispatchesFrameHeadScaffoldRegistrations() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadRunLoopScaffoldRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let inputReader = InjectedTerminalInputReader()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: DefaultRenderer(),
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: AsyncFrameHeadAbortScaffoldState(),
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: terminal.proposal,
      viewBuilder: { state, _ in
        AsyncFrameHeadAbortScaffoldView(
          state: state,
          recorder: recorder
        )
      }
    )

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      !terminal.frames.isEmpty
        && runLoop.focusTracker.currentFocusIdentity != nil
    }

    inputReader.send(.key(.space))
    inputReader.send(.key(.character("a"), modifiers: .ctrl))
    inputReader.send(.paste(PasteEvent(content: "/tmp/frame-head-run-loop.txt")))
    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()

    let result = try await valueWithTimeout {
      try await runTask.value
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(recorder.events.contains("action"))
    #expect(recorder.events.contains("change:true"))
    #expect(recorder.events.contains("key-command"))
    #expect(recorder.events.contains("drop:1"))
  }

  @Test("blocked async frame head defers animation completion until commit")
  func blockedAsyncFrameHeadDefersAnimationCompletionUntilCommit() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadAnimationCompletionRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: AsyncFrameHeadAbortScaffoldState(),
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: terminal.proposal,
      viewBuilder: { state, _ in
        AsyncFrameHeadAbortScaffoldView(
          state: state,
          recorder: recorder
        )
      }
    )
    focusTracker.invalidator = runLoop.scheduler

    try await withAsyncFrameHeadAbortAnimationSinks(runLoop.renderer) {
      runLoop.scheduler.requestInvalidation(of: [rootIdentity])
      var initialFrames = 0
      try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)
      focusLeafmostAsyncFrameHeadAbortScaffoldRegion(in: runLoop)

      let gate = AsyncFrameTailBlockingGate()
      renderer.setFrameTailRenderHooks(
        .init(beforeRaster: {
          gate.beforeRaster()
        })
      )
      defer {
        renderer.setFrameTailRenderHooks(nil)
        gate.release()
      }

      recorder.reset()
      _ = runLoop.handleKeyPress(KeyPress(.space, modifiers: []))
      let renderTask = Task { @MainActor in
        var renderedFrames = 0
        try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
        return renderedFrames
      }

      await gate.waitUntilBlocked()
      #expect(recorder.events.contains("action"))
      #expect(!recorder.events.contains("animation-completion"))

      gate.release()
      _ = try await valueWithTimeout {
        try await renderTask.value
      }

      #expect(recorder.events.contains("animation-completion"))
    }
  }

  @Test("blocked async frame head keeps draft key commands out of live dispatch")
  func blockedAsyncFrameHeadKeepsDraftKeyCommandsOutOfLiveDispatch() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadDraftKeyCommandRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let inputReader = InjectedTerminalInputReader()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameHeadDraftKeyCommandView(
          value: value,
          recorder: recorder
        )
      }
    )

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)
    #expect(terminal.frames.contains { $0.contains("value 0") })
    #expect(runLoop.focusTracker.currentFocusIdentity != nil)
    let initialBinding = KeyBinding(key: .character("i"), modifiers: .ctrl)
    let draftBinding = KeyBinding(key: .character("d"), modifiers: .ctrl)
    let commandScope = try #require(
      runLoop.currentFocusScopePath().first {
        runLoop.commandRegistry.keyCommand(at: $0, matching: initialBinding) != nil
      }
    )

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    runLoop.stateContainer.mutate { value in
      value = 1
    }
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])

    let renderTask = Task { @MainActor in
      var renderedFrames = 0
      try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
      return renderedFrames
    }

    await gate.waitUntilBlocked()

    #expect(
      runLoop.commandRegistry.keyCommand(at: commandScope, matching: draftBinding)?
        .isEnabled == false
    )

    gate.release()
    _ = try await valueWithTimeout {
      try await renderTask.value
    }

    #expect(
      runLoop.commandRegistry.keyCommand(at: commandScope, matching: draftBinding)?
        .isEnabled == true
    )
    _ = runLoop.handleKeyPress(KeyPress(.character("d"), modifiers: .ctrl))
    #expect(recorder.events.contains("draft"))
  }

  @Test("blocked async frame head preserves untouched sibling commands during selective dirty")
  func blockedAsyncFrameHeadPreservesUntouchedSiblingCommandsDuringSelectiveDirty() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadSelectiveDraftRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { _, _ in
        AsyncFrameHeadSelectiveDraftRegistrationView(recorder: recorder)
      }
    )

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)
    renderer.enableSelectiveEvaluation()

    let siblingABinding = KeyBinding(key: .character("a"), modifiers: .ctrl)
    let siblingBBinding = KeyBinding(key: .character("b"), modifiers: .ctrl)
    let siblingAScope = try #require(
      runLoop.commandRegistry.snapshot().keyCommandsByScope.first {
        $0.value[siblingABinding] != nil
      }?.key
    )
    let siblingBScope = try #require(
      runLoop.commandRegistry.snapshot().keyCommandsByScope.first {
        $0.value[siblingBBinding] != nil
      }?.key
    )

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    _ = runLoop.handleKeyPress(KeyPress(.character("e"), modifiers: .ctrl))
    #expect(recorder.events.contains("toggle"))

    let renderTask = Task { @MainActor in
      var renderedFrames = 0
      try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
      return renderedFrames
    }

    await gate.waitUntilBlocked()

    #expect(
      runLoop.commandRegistry.dispatch(
        key: siblingABinding,
        along: [siblingAScope]
      )
    )
    #expect(recorder.events.contains("sibling-a"))
    #expect(
      runLoop.commandRegistry.keyCommand(at: siblingBScope, matching: siblingBBinding)?
        .isEnabled == false
    )

    gate.release()
    _ = try await valueWithTimeout {
      try await renderTask.value
    }

    #expect(
      runLoop.commandRegistry.keyCommand(at: siblingBScope, matching: siblingBBinding)?
        .isEnabled == true
    )
    #expect(
      runLoop.commandRegistry.dispatch(
        key: siblingBBinding,
        along: [siblingBScope]
      )
    )
    #expect(recorder.events.contains("sibling-b-new"))
  }

  @Test("blocked async frame head keeps draft drop destinations out of live dispatch")
  func blockedAsyncFrameHeadKeepsDraftDropDestinationsOutOfLiveDispatch() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadDraftDropRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameHeadDraftDropDestinationView(
          value: value,
          recorder: recorder
        )
      }
    )

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)
    #expect(runLoop.focusTracker.currentFocusIdentity != nil)

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    runLoop.stateContainer.mutate { value in
      value = 1
    }
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])

    let renderTask = Task { @MainActor in
      var renderedFrames = 0
      try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
      return renderedFrames
    }

    await gate.waitUntilBlocked()

    runLoop.handlePaste(PasteEvent(content: "/tmp/draft-drop.txt"))
    #expect(!recorder.events.contains("drop:1"))

    gate.release()
    _ = try await valueWithTimeout {
      try await renderTask.value
    }

    runLoop.handlePaste(PasteEvent(content: "/tmp/draft-drop.txt"))
    #expect(recorder.events.contains("drop:1"))
  }

  @Test("blocked async frame head keeps committed scroll route live for scroll bursts")
  func blockedAsyncFrameHeadKeepsCommittedScrollRouteLiveForScrollBursts() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadScrollBurstRoot")
    let scrollIdentity = testIdentity("AsyncFrameHeadScrollBurstRoot", "Scroll")
    let terminal = AsyncFrameTailTerminalHost()
    let positionBox = AsyncFrameHeadScrollPositionBox()
    let renderer = DefaultRenderer()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameHeadScrollableDraftView(
          value: value,
          scrollIdentity: scrollIdentity,
          positionBox: positionBox
        )
      }
    )

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)
    let scrollRoute = try #require(
      runLoop.latestSemanticSnapshot.scrollRoutes.first { route in
        route.identity == scrollIdentity
      }
    )
    let scrollLocation = asyncFrameHeadCenterPoint(of: scrollRoute.viewportRect)
    let initialFrameCount = terminal.frames.count

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    runLoop.stateContainer.mutate { value in
      value = 1
    }
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])

    let renderTask = Task { @MainActor in
      var renderedFrames = 0
      try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
      return renderedFrames
    }

    await gate.waitUntilBlocked()

    for _ in 0..<3 {
      _ = runLoop.handle(
        .input(
          .mouse(
            .init(
              kind: .scrolled(deltaX: 0, deltaY: 1),
              location: scrollLocation
            )
          )
        )
      )
    }

    #expect(positionBox.position.y == 3)
    #expect(terminal.frames.count == initialFrameCount)

    gate.release()
    _ = try await valueWithTimeout {
      try await renderTask.value
    }

    #expect(positionBox.position.y == 3)
    #expect(terminal.frames.last?.contains("scroll 1-3") == true)
  }

  @Test("blocked async frame head keeps committed click action live until commit")
  func blockedAsyncFrameHeadKeepsCommittedClickActionLiveUntilCommit() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadClickRoot")
    let buttonIdentity = testIdentity("AsyncFrameHeadClickRoot", "Button")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameHeadDraftButtonActionView(
          value: value,
          buttonIdentity: buttonIdentity,
          recorder: recorder
        )
      }
    )

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)
    let buttonRect = try #require(
      runLoop.latestSemanticSnapshot.interactionRegions.first { region in
        // Pairing (not exact) match: the snapshot's region carries the minting
        // node's `ownerNodeID`; the test addresses it by identity + kind.
        region.routeID.pairsIgnoringOwner(with: primaryRouteID(for: buttonIdentity))
      }?.rect
    )
    let clickLocation = asyncFrameHeadCenterPoint(of: buttonRect)

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    recorder.reset()
    runLoop.stateContainer.mutate { value in
      value = 1
    }
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])

    let renderTask = Task { @MainActor in
      var renderedFrames = 0
      try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
      return renderedFrames
    }

    await gate.waitUntilBlocked()

    _ = runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: clickLocation))))
    _ = runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: clickLocation))))
    #expect(recorder.events.contains("click:0"))
    #expect(!recorder.events.contains("click:1"))

    gate.release()
    _ = try await valueWithTimeout {
      try await renderTask.value
    }

    recorder.reset()
    _ = runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: clickLocation))))
    _ = runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: clickLocation))))
    #expect(recorder.events == ["click:1"])
  }

  @Test("blocked async frame head keeps active committed drag recognizer live")
  func blockedAsyncFrameHeadKeepsActiveCommittedDragRecognizerLive() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadDragRoot")
    let dragIdentity = testIdentity("AsyncFrameHeadDragRoot", "Drag")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameHeadDraftDragView(
          value: value,
          dragIdentity: dragIdentity,
          recorder: recorder
        )
      }
    )

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)
    let dragRect = try #require(
      runLoop.latestSemanticSnapshot.interactionRegions.first { region in
        region.identity == dragIdentity
      }?.rect
        ?? runLoop.latestSemanticSnapshot.interactionRegions.first?.rect
    )
    let startLocation = asyncFrameHeadCenterPoint(of: dragRect)
    let dragLocation = Point(
      x: startLocation.x + 2,
      y: startLocation.y
    )

    _ = runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: startLocation))))

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    recorder.reset()
    runLoop.stateContainer.mutate { value in
      value = 1
    }
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])

    let renderTask = Task { @MainActor in
      var renderedFrames = 0
      try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
      return renderedFrames
    }

    await gate.waitUntilBlocked()

    _ = runLoop.handle(.input(.mouse(.init(kind: .dragged(.primary), location: dragLocation))))
    _ = runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: dragLocation))))
    #expect(recorder.events.contains("drag:0"))
    #expect(recorder.events.contains("drag-ended:0"))
    #expect(!recorder.events.contains("drag:1"))
    #expect(!recorder.events.contains("drag-ended:1"))

    gate.release()
    _ = try await valueWithTimeout {
      try await renderTask.value
    }

    recorder.reset()
    _ = runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: startLocation))))
    _ = runLoop.handle(.input(.mouse(.init(kind: .dragged(.primary), location: dragLocation))))
    _ = runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: dragLocation))))
    #expect(recorder.events.contains("drag:1"))
    #expect(recorder.events.contains("drag-ended:1"))
  }

  @Test("blocked async frame head keeps draft sheet out of Escape dismissal")
  func blockedAsyncFrameHeadKeepsDraftSheetOutOfEscapeDismissal() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadDraftSheetRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameHeadDraftSheetView(
          value: value,
          recorder: recorder
        )
      }
    )

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)
    #expect(terminal.frames.last?.contains("Draft Sheet") == false)

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    recorder.reset()
    runLoop.stateContainer.mutate { value in
      value = 1
    }
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])

    let renderTask = Task { @MainActor in
      var renderedFrames = 0
      try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
      return renderedFrames
    }

    await gate.waitUntilBlocked()

    _ = runLoop.handle(.input(.key(KeyPress(.escape))))
    #expect(recorder.events.isEmpty)
    #expect(terminal.frames.last?.contains("Draft Sheet") == false)

    gate.release()
    _ = try await valueWithTimeout {
      try await renderTask.value
    }

    #expect(terminal.frames.last?.contains("Draft Sheet") == true)
    _ = runLoop.handle(.input(.key(KeyPress(.escape))))
    #expect(recorder.events == ["sheet-dismiss:1:false"])
  }

  @Test("prepared frame-head abort restores broad reset state")
  func preparedFrameHeadAbortRestoresBroadResetState() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadAbortBroadResetRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameHeadAbortDraftEffectsView(
          value: value,
          recorder: recorder
        )
      }
    )
    focusTracker.invalidator = runLoop.scheduler

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &initialFrames)
    #expect(terminal.frames.last?.contains("value 0") == true)
    #expect(runLoop.focusTracker.currentFocusIdentity != nil)

    recorder.reset()
    runLoop.stateContainer.mutate { value in
      value = 1
    }
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      runLoop.currentView(),
      context: runLoop.resolveContext(
        for: scheduledFrame(invalidatedIdentities: [rootIdentity])
      ),
      proposal: runLoop.proposal()
    )

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)

    _ = runLoop.handleKeyPress(KeyPress(.character("d"), modifiers: .ctrl))
    runLoop.handlePaste(PasteEvent(content: "/tmp/aborted-draft-drop.txt"))
    #expect(!recorder.events.contains("key-command"))
    #expect(!recorder.events.contains("drop:1"))
    #expect(!recorder.events.contains("appear:revealed"))
    #expect(!recorder.events.contains("task:revealed"))
    #expect(
      !renderer.liveIdentitySnapshot().contains(
        testIdentity("AsyncFrameHeadAbortDraftRevealed")
      )
    )

    runLoop.stateContainer.mutate { value in
      value = 0
    }
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var restoredFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &restoredFrames)
    #expect(terminal.frames.last?.contains("value 0") == true)
    #expect(!recorder.events.contains("appear:revealed"))
    #expect(!recorder.events.contains("task:revealed"))

    recorder.reset()
    runLoop.stateContainer.mutate { value in
      value = 1
    }
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var committedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &committedFrames)
    _ = runLoop.handleKeyPress(KeyPress(.character("d"), modifiers: .ctrl))
    runLoop.handlePaste(PasteEvent(content: "/tmp/committed-draft-drop.txt"))

    #expect(recorder.events.contains("key-command"))
    #expect(recorder.events.contains("drop:1"))
    #expect(recorder.events.contains("appear:revealed"))
    try await waitUntil {
      recorder.events.contains("task:revealed")
    }
  }

  @Test("prepared frame-head abort restores selective dirty registrations")
  func preparedFrameHeadAbortRestoresSelectiveDirtyRegistrations() throws {
    let rootIdentity = testIdentity("AsyncFrameHeadAbortSelectiveRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { _, _ in
        AsyncFrameHeadSelectiveDraftRegistrationView(recorder: recorder)
      }
    )

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &initialFrames)
    renderer.enableSelectiveEvaluation()

    let siblingABinding = KeyBinding(key: .character("a"), modifiers: .ctrl)
    let siblingBBinding = KeyBinding(key: .character("b"), modifiers: .ctrl)
    let enableBinding = KeyBinding(key: .character("e"), modifiers: .ctrl)
    let siblingAScope = try #require(
      runLoop.commandRegistry.snapshot().keyCommandsByScope.first {
        $0.value[siblingABinding] != nil
      }?.key
    )
    let siblingBScope = try #require(
      runLoop.commandRegistry.snapshot().keyCommandsByScope.first {
        $0.value[siblingBBinding] != nil
      }?.key
    )
    let enableScope = try #require(
      runLoop.commandRegistry.snapshot().keyCommandsByScope.first {
        $0.value[enableBinding] != nil
      }?.key
    )

    #expect(
      runLoop.commandRegistry.dispatch(
        key: enableBinding,
        along: [enableScope]
      )
    )
    #expect(recorder.events.contains("toggle"))
    let scheduledFrame = try #require(runLoop.scheduler.consumeReadyFrame(at: .now()))
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      runLoop.currentView(),
      context: runLoop.resolveContext(for: scheduledFrame),
      proposal: runLoop.proposal()
    )

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)

    recorder.reset()
    #expect(
      runLoop.commandRegistry.dispatch(
        key: siblingABinding,
        along: [siblingAScope]
      )
    )
    #expect(recorder.events.contains("sibling-a"))
    _ = runLoop.commandRegistry.dispatch(
      key: siblingBBinding,
      along: [siblingBScope]
    )
    #expect(!recorder.events.contains("sibling-b-new"))
    #expect(
      runLoop.commandRegistry.keyCommand(at: siblingBScope, matching: siblingBBinding)?
        .isEnabled == false
    )

    runLoop.scheduler.requestInvalidation(of: [])
    var committedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &committedFrames)

    #expect(
      runLoop.commandRegistry.keyCommand(at: siblingBScope, matching: siblingBBinding)?
        .isEnabled == true
    )
    #expect(
      runLoop.commandRegistry.dispatch(
        key: siblingBBinding,
        along: [siblingBScope]
      )
    )
    #expect(recorder.events.contains("sibling-b-new"))
  }

  @Test("prepared frame-head abort keeps animation completions uncommitted")
  func preparedFrameHeadAbortKeepsAnimationCompletionsUncommitted() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadAbortAnimationRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: AsyncFrameHeadAbortScaffoldState(),
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: terminal.proposal,
      viewBuilder: { state, _ in
        AsyncFrameHeadAbortScaffoldView(
          state: state,
          recorder: recorder
        )
      }
    )
    focusTracker.invalidator = runLoop.scheduler

    try await withAsyncFrameHeadAbortAnimationSinks(renderer) {
      runLoop.scheduler.requestInvalidation(of: [rootIdentity])
      var initialFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &initialFrames)
      focusLeafmostAsyncFrameHeadAbortScaffoldRegion(in: runLoop)

      recorder.reset()
      _ = runLoop.handleKeyPress(KeyPress(.space, modifiers: []))
      #expect(recorder.events.contains("action"))
      let scheduledFrame = try #require(runLoop.scheduler.consumeReadyFrame(at: .now()))
      let draft = renderer.prepareFrameHeadForCancellationTesting(
        runLoop.currentView(),
        context: runLoop.resolveContext(for: scheduledFrame),
        proposal: runLoop.proposal()
      )

      renderer.abortPreparedFrameHeadForCancellationTesting(draft)

      #expect(!recorder.events.contains("animation-completion"))
      runLoop.scheduler.requestInvalidation(of: [])
      var committedFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &committedFrames)
      #expect(!recorder.events.contains("animation-completion"))
    }
  }

  @Test("prepared frame-head keeps transition animations draft-owned until commit")
  func preparedFrameHeadKeepsTransitionAnimationsDraftOwnedUntilCommit() throws {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("AsyncFrameHeadTransitionDraftRoot")
    let proposal = ProposedSize(width: 30, height: 4)
    let animation = Animation.linear(duration: .milliseconds(1_000_000))
    let box = renderer.internalAnimationController.register(animation)
    let batchID = AnimationBatchID(44_001)

    _ = renderer.render(
      AsyncFrameHeadTransitionDraftView(show: false),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )
    #expect(renderer.internalAnimationController.activeInsertionOffsetCount == 0)

    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(box)
    transaction.animationBatchID = batchID
    let animatedContext = ResolveContext(
      identity: rootIdentity,
      transaction: transaction,
      invalidatedIdentities: [rootIdentity]
    )
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      AsyncFrameHeadTransitionDraftView(show: true),
      context: animatedContext,
      proposal: proposal
    )

    #expect(draft.animationDraft.controller.activeInsertionOffsetCount > 0)
    #expect(renderer.internalAnimationController.activeInsertionOffsetCount == 0)
    #expect(
      !renderer.internalAnimationController.frameDropEligibilityBlockers
        .contains(.animationTransition)
    )

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    #expect(renderer.internalAnimationController.activeInsertionOffsetCount == 0)

    _ = renderer.render(
      AsyncFrameHeadTransitionDraftView(show: true),
      context: animatedContext,
      proposal: proposal
    )
    #expect(renderer.internalAnimationController.activeInsertionOffsetCount > 0)
  }

  @Test("prepared frame-tail abort keeps worker custom layout cache updates uncommitted")
  func preparedFrameTailAbortKeepsWorkerCustomLayoutCacheUpdatesUncommitted() async {
    let rootIdentity = testIdentity("AsyncFrameHeadAbortWorkerCacheRoot")
    let recorder = AsyncFrameTailWorkerCustomLayoutRecorder()
    let renderer = DefaultRenderer()
    let proposal = ProposedSize(width: 32, height: 6)

    @MainActor
    func root() -> some View {
      AsyncFrameTailWorkerCustomLayout(recorder: recorder) {
        Text("worker")
        Text("cache")
      }
    }

    let draft = renderer.prepareFrameHeadForCancellationTesting(
      root(),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )
    await renderer.renderPreparedFrameTailForCancellationTesting(draft)

    let preparedState = recorder.state
    #expect(preparedState.measureCount >= 1)
    #expect(preparedState.placeCount >= 1)
    #expect(preparedState.cacheApplyCount == 0)

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    #expect(recorder.state.cacheApplyCount == 0)

    _ = await renderer.renderAsync(
      root(),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    #expect(recorder.state.cacheApplyCount == 1)
  }

  @Test("completed frame drop decisions carry reconciliation policy")
  func completedFrameDropDecisionsCarryReconciliationPolicy() {
    let visualOnlyEligibility = FrameDropEligibility(decision: .canDropVisualOnly)
    let visualOnlyDecision = CompletedFrameDropDecision.dropVisualOnly(
      eligibility: visualOnlyEligibility
    )
    #expect(visualOnlyDecision.action == .dropVisualOnly)
    #expect(visualOnlyDecision.reconciliation == .emptyVisualOnly)
    #expect(visualOnlyDecision.canSkipCompletedFrame)

    let blockedEligibility = FrameDropEligibility(blockers: [.lifecycleAppear])
    let blockedDecision = CompletedFrameDropDecision.dropVisualOnly(
      eligibility: blockedEligibility
    )
    #expect(blockedDecision.action == .blocked)
    #expect(blockedDecision.reconciliation.mode == .blocked)
    #expect(!blockedDecision.canSkipCompletedFrame)

    let appliedSideEffects = SkippedFrameReconciliation.appliedSideEffects(
      effectSummary: "lifecycle"
    )
    #expect(appliedSideEffects.mode == .appliedSideEffects)
    #expect(!appliedSideEffects.isAvailableToRuntimePolicy)
  }

  @Test("completed frame policy compares candidate and newest desired generations")
  func completedFramePolicyComparesGenerations() {
    let orderedPolicy = CompletedFramePolicy.orderedCommitOnly
    let dropPolicy = CompletedFramePolicy(mode: .dropCompletedVisualOnly)
    let visualOnlyEligibility = FrameDropEligibility(decision: .canDropVisualOnly)
    let blockedEligibility = FrameDropEligibility(blockers: [.handlerInstallations])

    let staleVisualOnly = dropPolicy.decide(
      candidateGeneration: RenderGeneration(1),
      newestDesiredGeneration: RenderGeneration(2),
      eligibility: visualOnlyEligibility
    )
    #expect(staleVisualOnly.action == .dropVisualOnly)
    #expect(staleVisualOnly.reconciliation == .emptyVisualOnly)

    let currentVisualOnly = dropPolicy.decide(
      candidateGeneration: RenderGeneration(2),
      newestDesiredGeneration: RenderGeneration(2),
      eligibility: visualOnlyEligibility
    )
    #expect(currentVisualOnly.action == .commitOrdered)

    let staleBlocked = dropPolicy.decide(
      candidateGeneration: RenderGeneration(1),
      newestDesiredGeneration: RenderGeneration(2),
      eligibility: blockedEligibility
    )
    #expect(staleBlocked.action == .blocked)
    #expect(staleBlocked.reconciliation.blockReason == .dropEligibilityBlockers)

    let orderedStale = orderedPolicy.decide(
      candidateGeneration: RenderGeneration(1),
      newestDesiredGeneration: RenderGeneration(2),
      eligibility: visualOnlyEligibility
    )
    #expect(orderedStale.action == .commitOrdered)
  }

  @Test("cancellable completed frame reports ordered reconciliation decision")
  func cancellableCompletedFrameReportsOrderedReconciliationDecision() async throws {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("AsyncCompletedFrameDropDecisionRoot")
    let outcome = await renderer.renderAsyncCancellable(
      Text("ordered"),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 16, height: 3),
      shouldCancelQueued: { false }
    )

    let decision = try #require(outcome.completedFrameDropDecision)
    #expect(outcome.artifacts != nil)
    #expect(outcome.tailJobState == .completed)
    #expect(decision.action == .commitOrdered)
    #expect(decision.reconciliation.mode == .blocked)
    #expect(decision.reconciliation.blockReason == .orderedCommitPolicy)
    #expect(!decision.canSkipCompletedFrame)
  }

  @Test("completed frame candidate creation does not commit draft registrations")
  func completedFrameCandidateCreationDoesNotCommitDraftRegistrations() async throws {
    let rootIdentity = testIdentity("AsyncCompletedFrameCandidateBoundaryRoot")
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let commandRegistry = CommandRegistry()
    let initialBinding = KeyBinding(key: .character("i"), modifiers: .ctrl)
    let draftBinding = KeyBinding(key: .character("d"), modifiers: .ctrl)
    var context = ResolveContext(identity: rootIdentity)
    context.commandRegistry = commandRegistry

    _ = renderer.render(
      AsyncFrameHeadDraftKeyCommandView(
        value: 0,
        recorder: recorder
      ),
      context: context,
      proposal: .init(width: 24, height: 5)
    )
    let commandScope = try #require(
      commandRegistry.snapshot().keyCommandsByScope.first {
        $0.value[initialBinding] != nil
      }?.key
    )
    #expect(
      commandRegistry.keyCommand(at: commandScope, matching: draftBinding)?.isEnabled == false)

    var updateContext = context
    updateContext.invalidatedIdentities = [rootIdentity]
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      AsyncFrameHeadDraftKeyCommandView(
        value: 1,
        recorder: recorder
      ),
      context: updateContext,
      proposal: .init(width: 24, height: 5)
    )

    let decision = await renderer.previewCompletedFrameCandidateForTesting(draft)

    #expect(decision.action == .commitOrdered)
    #expect(
      commandRegistry.keyCommand(at: commandScope, matching: draftBinding)?.isEnabled == false)

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    #expect(
      commandRegistry.keyCommand(at: commandScope, matching: draftBinding)?.isEnabled == false)
  }

  @Test("previewed commit plan equals the committed plan for a completed async frame")
  func previewCommitEqualsRealCommit() async {
    let rootIdentity = testIdentity("AsyncPreviewCommitEquivalenceRoot")
    let proposal = ProposedSize(width: 32, height: 6)
    let renderer = DefaultRenderer()
    let recorder = AsyncFrameTailLifecycleRecorder()

    _ = renderer.render(
      AsyncFrameTailStressView(
        value: 0,
        lifecycleRecorder: recorder
      ),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    let draft = renderer.prepareFrameHeadForCancellationTesting(
      AsyncFrameTailStressView(
        value: 1,
        lifecycleRecorder: recorder
      ),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: proposal
    )

    let comparison = await renderer.commitCompletedFrameCandidateForTesting(draft)

    #expect(!comparison.committedCommit.lifecycle.isEmpty)
    #expect(comparison.previewCommit == comparison.committedCommit)
    #expect(comparison.committedArtifacts.commitPlan == comparison.committedCommit)
  }

  @Test("empty visual-only reconciliation discards completed tail without commit")
  func emptyVisualOnlyReconciliationDiscardsCompletedTailWithoutCommit() async throws {
    let rootIdentity = testIdentity("AsyncSkippedVisualOnlyRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let renderer = DefaultRenderer()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncSkippedVisualOnlyView(value: value)
      }
    )

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &initialFrames)
    let initialTerminalFrameCount = terminal.frames.count
    let initialLiveIdentities = renderer.liveIdentitySnapshot()

    runLoop.stateContainer.mutate { value in
      value = 1
    }
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      runLoop.currentView(),
      context: runLoop.resolveContext(
        for: scheduledFrame(invalidatedIdentities: [rootIdentity])
      ),
      proposal: runLoop.proposal()
    )
    let decision = CompletedFrameDropDecision.dropVisualOnly(
      eligibility: FrameDropEligibility(decision: .canDropVisualOnly)
    )

    let discarded = await renderer.discardPreparedFrameTailForReconciliationTesting(
      draft,
      decision: decision
    )

    #expect(discarded)
    #expect(terminal.frames.count == initialTerminalFrameCount)
    #expect(renderer.liveIdentitySnapshot() == initialLiveIdentities)
    #expect(terminal.frames.last?.contains("visual 1") == false)
  }

  @Test("async renderer tags monotonically increasing render generations")
  func asyncRendererTagsMonotonicallyIncreasingRenderGenerations() async {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("AsyncRenderGenerationRoot")

    let first = await renderer.renderAsync(
      VStack(alignment: .leading, spacing: 0) {
        Text("generation 1")
      },
      context: .init(identity: rootIdentity),
      proposal: .init(width: 24, height: 3)
    )
    let second = await renderer.renderAsync(
      VStack(alignment: .leading, spacing: 0) {
        Text("generation 2")
      },
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: .init(width: 24, height: 3)
    )

    let firstGenerations = first.diagnostics.timing.renderGenerations
    let secondGenerations = second.diagnostics.timing.renderGenerations

    #expect(firstGenerations.render.rawValue == 1)
    #expect(secondGenerations.render.rawValue == 2)
    #expect(secondGenerations.render > firstGenerations.render)
    #expect(firstGenerations.layoutInput == firstGenerations.render)
    #expect(firstGenerations.layoutOutput == firstGenerations.render)
    #expect(firstGenerations.rasterInput == firstGenerations.render)
    #expect(firstGenerations.rasterOutput == firstGenerations.render)
    #expect(secondGenerations.layoutInput == secondGenerations.render)
    #expect(secondGenerations.layoutOutput == secondGenerations.render)
    #expect(secondGenerations.rasterInput == secondGenerations.render)
    #expect(secondGenerations.rasterOutput == secondGenerations.render)
  }
}

private struct AsyncFrameTailCounterView: View {
  var value: Int

  var body: some View {
    Text("value \(value)")
      .id(testIdentity("AsyncFrameTailCounterValue", "\(value)"))
  }
}

private final class AsyncFrameTailValueBox: Sendable {
  private let storage: Mutex<Int>

  init(value: Int) {
    storage = Mutex(value)
  }

  var value: Int {
    get {
      storage.withLock { $0 }
    }
    set {
      storage.withLock { $0 = newValue }
    }
  }
}

private struct AsyncFrameTailHandledCounterView: View {
  var value: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Action") {}
        .id(testIdentity("AsyncFrameTailHandledCounterAction"))
      Text("value \(value)")
        .id(testIdentity("AsyncFrameTailHandledCounterValue", "\(value)"))
    }
  }
}

private struct AsyncFrameTailAnimatedOffsetView: View {
  var value: Int

  var body: some View {
    Text("value \(value)")
      .id(testIdentity("AsyncFrameTailAnimatedOffsetValue"))
      .offset(x: value * 4, y: 0)
  }
}

private struct AsyncSkippedVisualOnlyView: View {
  var value: Int

  var body: some View {
    Text("visual \(value)")
      .id(testIdentity("AsyncSkippedVisualOnlyValue", "\(value)"))
  }
}

private struct AsyncSkippedStableInteractionVisualOnlyView: View {
  var value: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Stable") {}
        .id(testIdentity("AsyncSkippedStableInteractionButton"))
      Text("visual \(value)")
        .id(testIdentity("AsyncSkippedStableInteractionValue", "\(value)"))
    }
  }
}

private struct AsyncFrameTailStressView: View {
  @FocusState private var focusedField: AsyncFrameTailFocusField?

  var value: Int
  var lifecycleRecorder: AsyncFrameTailLifecycleRecorder

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Focusable") {}
        .id(testIdentity("AsyncFrameTailFocus"))
        .focused($focusedField, equals: .button)
      if value == 0 {
        Text("value 0")
          .id(testIdentity("AsyncFrameTailValue", "zero"))
          .onAppear {
            lifecycleRecorder.record("appear 0")
          }
          .onDisappear {
            lifecycleRecorder.record("disappear 0")
          }
      } else {
        Text("value 1")
          .id(testIdentity("AsyncFrameTailValue", "one"))
          .onAppear {
            lifecycleRecorder.record("appear 1")
          }
          .onDisappear {
            lifecycleRecorder.record("disappear 1")
          }
      }
    }
    .defaultFocus($focusedField, .button)
  }
}

private final class AsyncFrameTailInternalStateTrigger {
  private let event = AsyncEvent()

  func fire() {
    event.fire()
  }

  func wait() async {
    await event.wait()
  }
}

private struct AsyncFrameTailInternalStateMutationView: View {
  var phase: Int
  var trigger: AsyncFrameTailInternalStateTrigger

  @State private var count = 0

  var body: some View {
    Text("phase \(phase) count \(count)")
      .task {
        await trigger.wait()
        count = 1
      }
  }
}

private struct AsyncFrameTailFocusMutationView: View {
  var phase: Int
  var trigger: AsyncFrameTailInternalStateTrigger

  @FocusState private var focusedField: AsyncFrameTailSendableFocusField?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("phase \(phase) field \(focusedField?.rawValue ?? "none")")
      Button("first") {}
        .id(testIdentity("AsyncFrameTailFocusMutation", "First"))
        .focused($focusedField, equals: .first)
      Button("second") {}
        .id(testIdentity("AsyncFrameTailFocusMutation", "Second"))
        .focused($focusedField, equals: .second)
    }
    .defaultFocus($focusedField, .first)
    .task {
      await trigger.wait()
      focusedField = .second
    }
  }
}

private struct AsyncFrameTailSendableFocusView: View {
  @FocusState private var focusedField: AsyncFrameTailSendableFocusField?

  let recorder: AsyncFrameTailSendableLayoutRecorder

  var body: some View {
    AsyncFrameTailSendableLayout(recorder: recorder) {
      EnvironmentReader(\.focusedIdentity) { focusedIdentity in
        Text("Focus: \(focusedIdentity.map(\.description) ?? "none")")
      }
      Text("Field: \(focusedField?.rawValue ?? "none")")
      Button("First") {}
        .id(testIdentity("AsyncFrameTailSendableFocus", "First"))
        .focused($focusedField, equals: .first)
      Button("Second") {}
        .id(testIdentity("AsyncFrameTailSendableFocus", "Second"))
        .focused($focusedField, equals: .second)
    }
    .defaultFocus($focusedField, .first)
  }
}

private struct AsyncFrameHeadAbortScaffoldState: Equatable, Sendable {
  var value = 0
}

private enum AsyncFrameHeadAbortPreferenceKey: PreferenceKey {
  static var defaultValue: [String] { [] }

  static func reduce(value: inout [String], nextValue: () -> [String]) {
    value.append(contentsOf: nextValue())
  }
}

private enum AsyncFrameHeadAbortFocusField: Hashable {
  case action
}

private struct AsyncFrameHeadAbortScaffoldView: View {
  @FocusState private var focusedField: AsyncFrameHeadAbortFocusField?
  @State private var animated = false

  var state: AsyncFrameHeadAbortScaffoldState
  var recorder: AsyncFrameHeadAbortEffectRecorder

  var body: some View {
    Panel(id: "abort-scaffold") {
      ScrollView([.vertical], showsIndicators: true) {
        VStack(alignment: .leading, spacing: 0) {
          Button("Animated action") {
            withAnimation(nil) {
              animated.toggle()
              recorder.record("action")
            } completion: {
              recorder.record("animation-completion")
            }
          }
          .id(testIdentity("AsyncFrameHeadAbortAction"))
          .focused($focusedField, equals: .action)

          Text("value \(state.value)")
            .id(testIdentity("AsyncFrameHeadAbortValue", "\(state.value)"))
            .preference(
              key: AsyncFrameHeadAbortPreferenceKey.self,
              value: ["pref-\(state.value)"]
            )
            .onChange(of: animated) { _, value in
              recorder.record("change:\(value)")
            }

          Text("filler")
          Text("filler")
          Text("filler")
          Text("filler")
          Text("filler")

          if animated {
            Text("revealed")
              .id(testIdentity("AsyncFrameHeadAbortRevealed"))
              .onAppear {
                recorder.record("appear:revealed")
              }
              .onDisappear {
                recorder.record("disappear:revealed")
              }
              .task {
                recorder.record("task:revealed")
              }
          }
        }
      }
      .frame(height: 3)
      .onPreferenceChange(AsyncFrameHeadAbortPreferenceKey.self) { value in
        recorder.record("preference:\(value.joined(separator: "+"))")
      }
    }
    .keyCommand("Abort scaffold", key: .character("a"), modifiers: .ctrl) {
      recorder.record("key-command")
    }
    .dropDestination { paths in
      recorder.record("drop:\(paths.count)")
      return true
    }
    .defaultFocus($focusedField, .action)
  }
}

private struct AsyncFrameHeadDraftKeyCommandView: View {
  var value: Int
  var recorder: AsyncFrameHeadAbortEffectRecorder

  var body: some View {
    Panel(id: "draft-key-command") {
      Text("value \(value)")
        .focusable(true)
    }
    .keyCommand("Initial", key: .character("i"), modifiers: .ctrl) {
      recorder.record("initial")
    }
    .keyCommand(
      "Draft",
      key: .character("d"),
      modifiers: .ctrl,
      isEnabled: value != 0
    ) {
      recorder.record("draft")
    }
  }
}

private struct AsyncFrameHeadTransitionDraftView: View {
  var show: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("anchor")
      if show {
        Text("draft transition")
          .id(testIdentity("AsyncFrameHeadTransitionDraftLeaf"))
          .transition(.move(edge: .leading))
      }
    }
  }
}

private struct AsyncFrameHeadSelectiveDraftRegistrationView: View {
  @State private var draftEnabled = false

  var recorder: AsyncFrameHeadAbortEffectRecorder

  var body: some View {
    Panel(id: "selective-root") {
      VStack(alignment: .leading, spacing: 0) {
        Panel(id: "sibling-a") {
          Text("A")
            .focusable(true)
        }
        .keyCommand("Sibling A", key: .character("a"), modifiers: .ctrl) {
          recorder.record("sibling-a")
        }

        Panel(id: "sibling-b") {
          Text(draftEnabled ? "B1" : "B0")
            .focusable(true)
        }
        .keyCommand(
          "Sibling B",
          key: .character("b"),
          modifiers: .ctrl,
          isEnabled: draftEnabled
        ) {
          recorder.record("sibling-b-new")
        }
      }
    }
    .keyCommand("Enable B", key: .character("e"), modifiers: .ctrl) {
      draftEnabled = true
      recorder.record("toggle")
    }
  }
}

private enum AsyncFrameHeadAbortDraftFocusField: Hashable {
  case primary
}

private struct AsyncFrameHeadAbortDraftEffectsView: View {
  @FocusState private var focusedField: AsyncFrameHeadAbortDraftFocusField?

  var value: Int
  var recorder: AsyncFrameHeadAbortEffectRecorder

  var body: some View {
    Panel(id: "abort-draft-effects") {
      VStack(alignment: .leading, spacing: 0) {
        Text("value \(value)")
          .focusable(true)
          .focused($focusedField, equals: .primary)

        if value != 0 {
          Text("revealed")
            .id(testIdentity("AsyncFrameHeadAbortDraftRevealed"))
            .onAppear {
              recorder.record("appear:revealed")
            }
            .task {
              recorder.record("task:revealed")
            }
        }
      }
    }
    .keyCommand(
      "Draft",
      key: .character("d"),
      modifiers: .ctrl,
      isEnabled: value != 0
    ) {
      recorder.record("key-command")
    }
    .dropDestination { paths in
      guard value != 0 else {
        return false
      }
      recorder.record("drop:\(paths.count)")
      return true
    }
    .defaultFocus($focusedField, .primary)
  }
}

private struct AsyncFrameHeadDraftDropDestinationView: View {
  var value: Int
  var recorder: AsyncFrameHeadAbortEffectRecorder

  var body: some View {
    Panel(id: "draft-drop") {
      Text("drop \(value)")
        .focusable(true)
    }
    .dropDestination { paths in
      guard value != 0 else {
        return false
      }
      recorder.record("drop:\(paths.count)")
      return true
    }
  }
}

private final class AsyncFrameHeadScrollPositionBox: Sendable {
  private let storage = LockedBox(ScrollPosition.zero)

  var position: ScrollPosition {
    get { storage.value }
    set { storage.value = newValue }
  }
}

private struct AsyncFrameHeadScrollableDraftView: View {
  var value: Int
  var scrollIdentity: Identity
  var positionBox: AsyncFrameHeadScrollPositionBox

  var body: some View {
    ScrollView(
      .vertical,
      position: Binding(
        get: { positionBox.position },
        set: { positionBox.position = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<20) { index in
          Text("scroll \(value)-\(index)")
        }
      }
    }
    .id(scrollIdentity)
    .frame(width: 14, height: 3, alignment: .topLeading)
  }
}

private struct AsyncFrameHeadDraftButtonActionView: View {
  var value: Int
  var buttonIdentity: Identity
  var recorder: AsyncFrameHeadAbortEffectRecorder

  var body: some View {
    Button("Click \(value)") {
      recorder.record("click:\(value)")
    }
    .id(buttonIdentity)
    .frame(width: 10, height: 1, alignment: .topLeading)
  }
}

private struct AsyncFrameHeadDraftDragView: View {
  var value: Int
  var dragIdentity: Identity
  var recorder: AsyncFrameHeadAbortEffectRecorder

  var body: some View {
    Text("Drag \(value)")
      .id(dragIdentity)
      .frame(width: 8, height: 1, alignment: .topLeading)
      .gesture(
        DragGesture()
          .onChanged { _ in
            recorder.record("drag:\(value)")
          }
          .onEnded { _ in
            recorder.record("drag-ended:\(value)")
          }
      )
  }
}

private struct AsyncFrameHeadDraftSheetView: View {
  var value: Int
  var recorder: AsyncFrameHeadAbortEffectRecorder

  var body: some View {
    Text("base \(value)")
      .sheet(
        "Draft Sheet",
        isPresented: Binding(
          get: { value != 0 },
          set: { isPresented in
            recorder.record("sheet-dismiss:\(value):\(isPresented)")
          }
        )
      ) {
        Text("Draft Sheet \(value)")
      }
  }
}

private struct AsyncFrameTailCustomLayout: Layout {
  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    return .init(
      width: sizes.map(\.width).max() ?? 0,
      height: sizes.reduce(0) { $0 + $1.height }
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    var y = bounds.origin.y
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      subview.place(
        at: .init(x: bounds.origin.x, y: y),
        anchor: .topLeading,
        proposal: .init(width: size.width, height: size.height)
      )
      y += size.height
    }
  }
}

private struct AsyncFrameTailRecursiveCustomLayout: PrimitiveView, ResolvableView {
  var depth: Int

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [makeAsyncRecursiveCustomLayoutNode(identity: context.identity, depth: depth)]
  }
}

private let asyncRecursiveCustomLayoutProxy = AsyncRecursiveCustomLayoutProxy()

private func makeAsyncRecursiveCustomLayoutNode(
  identity: Identity,
  depth: Int
) -> ResolvedNode {
  var node = ResolvedNode(
    identity: identity.child("leaf"),
    kind: .view("Leaf"),
    intrinsicSize: .init(width: 1, height: 1)
  )

  for index in stride(from: depth - 1, through: 0, by: -1) {
    node = ResolvedNode(
      identity: index == 0 ? identity : identity.child("recursive-\(index)"),
      kind: .view("AsyncRecursiveCustomLayout"),
      children: [node],
      layoutBehavior: .custom(CustomLayoutHandle(asyncRecursiveCustomLayoutProxy))
    )
  }

  return node
}

private final class AsyncRecursiveCustomLayoutProxy: LayoutPassContextCustomLayoutProxy {
  var debugName: String {
    "AsyncRecursiveCustomLayoutProxy"
  }

  func measureContainer(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    proposal _: ProposedSize
  ) -> CellSize {
    .init(width: 1, height: 1)
  }

  func measureContainer(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    proposal _: ProposedSize,
    passContext _: LayoutPassContext?
  ) -> CellSize {
    .init(width: 1, height: 1)
  }

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> [PlacedNode] {
    placeSubviews(
      engine: engine,
      node: node,
      measured: measured,
      in: bounds,
      passContext: nil
    )
  }

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    node.children.map { child in
      let childMeasurement = engine.measure(
        child,
        proposal: measured.proposal,
        passContext: passContext
      )
      return engine.place(
        child,
        measured: childMeasurement,
        in: CellRect(origin: bounds.origin, size: childMeasurement.measuredSize),
        passContext: passContext
      )
    }
  }
}

private struct AsyncFrameTailSendableLayout: Layout {
  let recorder: AsyncFrameTailSendableLayoutRecorder

  var measurementReuseSignature: String? {
    "AsyncFrameTailSendableLayout.measure"
  }

  var placementReuseSignature: String? {
    "AsyncFrameTailSendableLayout.place"
  }

  func makeCache(subviews _: LayoutSubviews) -> Int {
    recorder.nextCache()
  }

  func updateCache(
    _ cache: inout Int,
    subviews _: LayoutSubviews
  ) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Int
  ) -> LayoutSize {
    recorder.recordMeasure(cache: cache)
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    return .init(
      width: sizes.map(\.width).max() ?? 0,
      height: sizes.reduce(0) { $0 + $1.height }
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Int
  ) {
    recorder.recordPlace(cache: cache)
    var y = bounds.origin.y
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      subview.place(
        at: .init(x: bounds.origin.x, y: y),
        anchor: .topLeading,
        proposal: .init(width: size.width, height: size.height)
      )
      y += size.height
    }
  }
}

private struct AsyncFrameTailSendableGuideLayout: Layout {
  let recorder: AsyncFrameTailSendableLayoutRecorder

  var measurementReuseSignature: String? {
    "AsyncFrameTailSendableGuideLayout.measure"
  }

  var placementReuseSignature: String? {
    "AsyncFrameTailSendableGuideLayout.place"
  }

  func makeCache(subviews _: LayoutSubviews) -> Int {
    recorder.nextCache()
  }

  func updateCache(
    _ cache: inout Int,
    subviews _: LayoutSubviews
  ) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Int
  ) -> LayoutSize {
    recorder.recordMeasure(cache: cache)
    guard subviews.count == 2 else {
      return .zero
    }

    let first = subviews[0].dimensions(in: .unspecified)
    let second = subviews[1].sizeThatFits(.unspecified)
    return .init(
      width: max(first.width, first[.asyncFrameTailRaisedCenter] + second.width),
      height: max(first.height, second.height)
    )
  }

  func placeSubviews(
    in _: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Int
  ) {
    recorder.recordPlace(cache: cache)
    guard subviews.count == 2 else {
      return
    }

    let firstSize = subviews[0].sizeThatFits(.unspecified)
    let firstDimensions = subviews[0].dimensions(in: .unspecified)
    let secondSize = subviews[1].sizeThatFits(.unspecified)

    subviews[0].place(
      at: .init(x: 0, y: 0),
      anchor: .topLeading,
      proposal: .init(width: firstSize.width, height: firstSize.height)
    )
    subviews[1].place(
      at: .init(x: firstDimensions[.asyncFrameTailRaisedCenter], y: 0),
      anchor: .topLeading,
      proposal: .init(width: secondSize.width, height: secondSize.height)
    )
  }
}

private struct AsyncFrameTailWorkerCustomLayout<Content: View>: PrimitiveView, ResolvableView {
  var recorder: AsyncFrameTailWorkerCustomLayoutRecorder
  var content: Content

  init(
    recorder: AsyncFrameTailWorkerCustomLayoutRecorder,
    @ViewBuilder content: () -> Content
  ) {
    self.recorder = recorder
    self.content = content()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let handle = CustomLayoutHandle(
      AsyncFrameTailMainActorOnlyCustomLayoutProxy(),
      measurementReuseSignature: "AsyncFrameTailWorkerCustomLayout.measure",
      placementReuseSignature: "AsyncFrameTailWorkerCustomLayout.place",
      workerProxy: asyncFrameTailWorkerCustomLayoutSnapshot(recorder: recorder)
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("AsyncFrameTailWorkerCustomLayout"),
        children: resolveDeclaredChildren(
          content,
          in: context,
          kindName: "AsyncFrameTailWorkerCustomLayout"
        ),
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .custom(handle)
      )
    ]
  }
}

private func asyncFrameTailWorkerCustomLayoutSnapshot(
  recorder: AsyncFrameTailWorkerCustomLayoutRecorder
) -> WorkerCustomLayoutSnapshot {
  WorkerCustomLayoutSnapshot(
    debugName: "AsyncFrameTailWorkerCustomLayout",
    measureContainer: { engine, node, _, passContext in
      recorder.recordMeasure()
      let sizes = node.children.map { child in
        engine.measure(
          child,
          proposal: .unspecified,
          passContext: passContext
        ).measuredSize
      }
      return CellSize(
        width: sizes.map(\.width).max() ?? 0,
        height: sizes.reduce(0) { $0 + $1.height }
      )
    },
    placeSubviews: { engine, node, _, bounds, passContext in
      recorder.recordPlace()
      let identity = node.identity
      passContext?.recordWorkerCustomLayoutCacheUpdate(
        .init(identity: identity) {
          recorder.recordCacheApply(identity: identity)
        }
      )
      var y = bounds.origin.y
      return node.children.map { child in
        let childMeasurement = engine.measure(
          child,
          proposal: .unspecified,
          passContext: passContext
        )
        defer {
          y += childMeasurement.measuredSize.height
        }
        return engine.place(
          child,
          measured: childMeasurement,
          in: CellRect(
            origin: CellPoint(x: bounds.origin.x, y: y),
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      }
    }
  )
}

private final class AsyncFrameTailMainActorOnlyCustomLayoutProxy: CustomLayoutProxy {
  var debugName: String {
    "AsyncFrameTailWorkerCustomLayout"
  }

  func measureContainer(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    proposal _: ProposedSize
  ) -> CellSize {
    preconditionFailure("worker custom layout must use its worker proxy for measurement")
  }

  func measureChildren(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    proposal _: ProposedSize
  ) -> [MeasuredNode] {
    preconditionFailure("worker custom layout must use its worker proxy for child measurement")
  }

  func placeSubviews(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    measured _: MeasuredNode,
    in _: CellRect
  ) -> [PlacedNode] {
    preconditionFailure("worker custom layout must use its worker proxy for placement")
  }
}

private final class AsyncFrameTailWorkerCustomLayoutRecorder: Sendable {
  struct State: Sendable {
    var measureCount = 0
    var placeCount = 0
    var measureRanOnMainThread: Bool?
    var placeRanOnMainThread: Bool?
    var cacheApplyCount = 0
    var cacheApplyRanOnMainThread: Bool?
    var cacheApplyIdentity: Identity?
  }

  private let stateStorage = Mutex(State())

  var state: State {
    stateStorage.withLock { $0 }
  }

  func recordMeasure() {
    let onMain = currentlyOnMainActor()
    stateStorage.withLock { state in
      state.measureCount += 1
      state.measureRanOnMainThread = onMain
    }
  }

  func recordPlace() {
    let onMain = currentlyOnMainActor()
    stateStorage.withLock { state in
      state.placeCount += 1
      state.placeRanOnMainThread = onMain
    }
  }

  @MainActor
  func recordCacheApply(identity: Identity) {
    let onMain = currentlyOnMainActor()
    stateStorage.withLock { state in
      state.cacheApplyCount += 1
      state.cacheApplyRanOnMainThread = onMain
      state.cacheApplyIdentity = identity
    }
  }
}

private final class AsyncFrameTailSendableLayoutRecorder: Sendable {
  struct State: Sendable {
    var makeCacheCount = 0
    var measuredCache: Int?
    var placedCache: Int?
    var measureRanOnMainThread: Bool?
    var placeRanOnMainThread: Bool?
  }

  private let stateStorage = Mutex(State())

  var state: State {
    stateStorage.withLock { $0 }
  }

  func nextCache() -> Int {
    stateStorage.withLock { state in
      state.makeCacheCount += 1
      return state.makeCacheCount
    }
  }

  func recordMeasure(cache: Int) {
    let onMain = currentlyOnMainActor()
    stateStorage.withLock { state in
      state.measuredCache = cache
      state.measureRanOnMainThread = onMain
    }
  }

  func recordPlace(cache: Int) {
    let onMain = currentlyOnMainActor()
    stateStorage.withLock { state in
      state.placedCache = cache
      state.placeRanOnMainThread = onMain
    }
  }
}

private enum AsyncFrameTailFocusField: Hashable {
  case button
}

private enum AsyncFrameTailSendableFocusField: String, Hashable {
  case first
  case second
}

extension SwiftTUIRuntime.RunLoop {
  @MainActor
  fileprivate func currentView() -> ScopedBuilder<Content> {
    viewBuilder(
      (
        state: stateContainer.state,
        focusedIdentity: focusTracker.currentFocusIdentity
      )
    )
  }
}

private func scheduledFrame(
  invalidatedIdentities: Set<Identity>
) -> ScheduledFrame {
  ScheduledFrame(
    causes: [.invalidation],
    invalidatedIdentities: invalidatedIdentities,
    signalNames: [],
    externalReasons: [],
    triggeredDeadline: nil,
    nextDeadline: nil
  )
}

@MainActor
private final class AsyncFrameTailLifecycleRecorder {
  var events: [String] = []

  func record(_ event: String) {
    events.append(event)
  }
}

private final class AsyncFrameHeadAbortEffectRecorder: Sendable {
  private struct State: Sendable {
    var events: [String] = []
  }

  private let state = Mutex(State())

  var events: [String] {
    state.withLock(\.events)
  }

  func record(_ event: String) {
    state.withLock { state in
      state.events.append(event)
    }
  }

  func reset() {
    state.withLock { state in
      state.events.removeAll(keepingCapacity: true)
    }
  }
}

@MainActor
private func renderAsyncFrameHeadAbortScaffoldFrame<State, V: View>(
  _ runLoop: SwiftTUIRuntime.RunLoop<State, V>
) throws {
  runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
}

@MainActor
private func focusLeafmostAsyncFrameHeadAbortScaffoldRegion<State, V: View>(
  in runLoop: SwiftTUIRuntime.RunLoop<State, V>
) {
  guard
    let leafmost = runLoop.latestSemanticSnapshot.focusRegions.filter({
      runLoop.localActionRegistry.hasHandler(identity: $0.identity)
    }).max(
      by: { $0.scopePath.count < $1.scopePath.count }
    )
  else {
    return
  }
  _ = runLoop.focusTracker.setFocus(to: leafmost.identity)
}

private func asyncFrameHeadCenterPoint(
  of rect: CellRect
) -> Point {
  Point(
    CellPoint(
      x: rect.origin.x + max(0, rect.size.width / 2),
      y: rect.origin.y + max(0, rect.size.height / 2)
    ))
}

@MainActor
private func withAsyncFrameHeadAbortAnimationSinks<Value>(
  _ renderer: DefaultRenderer,
  operation: () async throws -> Value
) async throws -> Value {
  let animationController = renderer.internalAnimationController
  return try await AnimationRegistrationStorage.withSink(animationController) {
    try await TransitionRegistrationStorage.withSink(animationController) {
      try await AnimationCompletionStorage.withSink(animationController) {
        try await operation()
      }
    }
  }
}

private final class AsyncFrameTailTerminalHost: PresentationSurface {
  var surfaceSize: CellSize {
    size
  }
  let size = CellSize(width: 32, height: 6)
  let proposal = ProposedSize(width: 32, height: 6)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  private(set) var frames: [String] = []

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
  }

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )
    .render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    return .fullRepaint(
      for: surface,
      capabilityProfile: capabilityProfile
    )
  }
}

private final class AsyncFrameTailInvalidatingTerminalHost: PresentationSurface {
  var surfaceSize: CellSize {
    size
  }
  let size = CellSize(width: 32, height: 6)
  let proposal = ProposedSize(width: 32, height: 6)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  private(set) var frames: [String] = []

  private let valueBox: AsyncFrameTailValueBox
  private let scheduler: FrameScheduler
  private let invalidationIdentity: Identity
  private var didQueueFollowUpInvalidation = false

  init(
    valueBox: AsyncFrameTailValueBox,
    scheduler: FrameScheduler,
    invalidationIdentity: Identity
  ) {
    self.valueBox = valueBox
    self.scheduler = scheduler
    self.invalidationIdentity = invalidationIdentity
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
  }

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )
    .render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))

    if !didQueueFollowUpInvalidation, rendered.contains("value 1") {
      didQueueFollowUpInvalidation = true
      valueBox.value = 2
      scheduler.requestInvalidation(of: [invalidationIdentity])
    }

    return .fullRepaint(
      for: surface,
      capabilityProfile: capabilityProfile
    )
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
