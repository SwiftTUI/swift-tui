@unsafe @preconcurrency import Dispatch
import Foundation
import Synchronization
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

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
      terminalHost: terminal,
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
        if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
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
    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    inputReader.finish()

    #expect(terminal.frames.isEmpty)
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(result.finalState == 1)
    #expect(gate.rasterEntryCount >= 3)
    #expect(terminal.frames.count >= 2)
    #expect(terminal.frames.first?.contains("value 0") == true)
    #expect(terminal.frames.last?.contains("value 1") == true)
    #expect(lifecycleRecorder.events == ["appear 0", "appear 1"])
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
      terminalHost: terminal,
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
        if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
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
    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    inputReader.finish()

    #expect(terminal.frames.isEmpty)
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(result.finalState == 1)
    #expect(gate.rasterEntryCount >= 1)
    #expect(terminal.frames.count >= 2)
    #expect(terminal.frames.first?.contains("value 0") == true)
    #expect(terminal.frames.last?.contains("value 1") == true)
    #expect(lifecycleRecorder.events == ["appear 0", "appear 1"])
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
      terminalHost: terminal,
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
        if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
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
    runLoop.diagnosticsLogger = FrameDiagnosticsLogger(path: diagnosticsURL.path)
    #expect(runLoop.diagnosticsLogger != nil)

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      terminal.frames.contains { $0.contains("value 0") }
    }

    inputReader.send(.key(.character("i")))
    await gate.waitUntilBlocked()
    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    runLoop.renderSuspensionDiagnostics.recordInputEventQueuedIfSuspended()
    inputReader.finish()
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }
    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))

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
          && row["desired_generation"] != nil
          && row["render_generation"] != nil
          && row["layout_input_generation"] == row["render_generation"]
          && row["layout_output_generation"] == row["render_generation"]
          && row["raster_input_generation"] == row["render_generation"]
          && row["raster_output_generation"] == row["render_generation"]
          && row["coalesced_event_batches"] != nil
          && row["coalesced_wake_causes"] != nil
      })
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
      terminalHost: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, _ in
        if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
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
    runLoop.diagnosticsLogger = FrameDiagnosticsLogger(path: diagnosticsURL.path)
    #expect(runLoop.diagnosticsLogger != nil)

    let runTask = Task {
      try await runLoop.run()
    }

    try await waitUntil {
      terminal.frames.contains { $0.contains("geometry") }
    }

    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    inputReader.finish()

    let result = try await valueWithTimeout {
      try await runTask.value
    }
    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))

    let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
    let rows = diagnosticRows(diagnostics)
    #expect(
      rows.contains { row in
        row["geometry_anchor_resolution_misses"] == "1"
          && row["first_geometry_anchor_resolution_miss"] == "LoggedMissingAnchor"
          && row["geometry_missing_named_coordinate_spaces"] == "1"
          && row["first_geometry_missing_named_coordinate_space"] == "missing-space"
          && row["geometry_duplicate_named_coordinate_spaces"] == "1"
          && row["first_geometry_duplicate_named_coordinate_space"] == "board"
          && row["layout_dependent_realizations"] == "1"
          && row["layout_dependent_cache_hits"] == "0"
          && row["layout_dependent_main_actor_fallbacks"] == "1"
      })
  }

  @Test("custom layout falls back for layout while raster still suspends")
  func customLayoutFallbackKeepsLayoutInlineButSuspendsRaster() async throws {
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
    let workerTimings = try #require(artifacts.diagnostics.workerTimings)
    let mainActorTimings = try #require(artifacts.diagnostics.mainActorTimings)

    #expect(artifacts.diagnostics.customLayoutFallbackCount == 1)
    #expect(artifacts.diagnostics.firstCustomLayoutFallbackIdentity == rootIdentity)
    guard case .custom(let customLayoutHandle) = artifacts.resolvedTree.layoutBehavior else {
      Issue.record("expected custom layout root")
      return
    }
    #expect(customLayoutHandle.executionCapability == .mainActorOnly)
    #expect(!customLayoutHandle.canRunOnWorker)
    #expect(customLayoutHandle.workerProxy == nil)
    #expect(workerTimings.layoutEnqueueToStart == .zero)
    #expect(workerTimings.layoutCompute == .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(mainActorTimings.suspended != .zero)
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

    let workerTimings = try #require(artifacts.diagnostics.workerTimings)
    let mainActorTimings = try #require(artifacts.diagnostics.mainActorTimings)
    let workerLayoutState = recorder.state

    #expect(artifacts.diagnostics.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.firstCustomLayoutFallbackIdentity == nil)
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
    #expect(workerLayoutState.cacheApplyRanOnMainThread == true)
    #expect(workerLayoutState.cacheApplyIdentity == rootIdentity)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(mainActorTimings.suspended != .zero)
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("worker"))
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("layout"))
  }

  @Test("layout-dependent content forces async layout onto the main actor")
  func layoutDependentContentForcesAsyncLayoutOntoMainActor() async throws {
    let artifacts = await DefaultRenderer().renderAsync(
      GeometryReader { proxy in
        Text("geometry \(proxy.size.width)x\(proxy.size.height)")
      },
      context: .init(identity: testIdentity("AsyncGeometryRoot")),
      proposal: .init(width: 24, height: 5)
    )

    let workerTimings = try #require(artifacts.diagnostics.workerTimings)
    #expect(artifacts.diagnostics.layoutDependentRealizations == 1)
    #expect(artifacts.diagnostics.layoutDependentMainActorFallbacks == 1)
    #expect(workerTimings.layoutCompute == .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(artifacts.rasterSurface.lines.contains { $0.contains("geometry 24x5") })
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

    let workerTimings = try #require(artifacts.diagnostics.workerTimings)
    let mainActorTimings = try #require(artifacts.diagnostics.mainActorTimings)
    let layoutState = recorder.state

    #expect(artifacts.diagnostics.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.firstCustomLayoutFallbackIdentity == nil)
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

    let workerTimings = try #require(artifacts.diagnostics.workerTimings)
    let layoutState = recorder.state

    #expect(artifacts.diagnostics.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.firstCustomLayoutFallbackIdentity == nil)
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

    #expect(first.diagnostics.measuredNodesComputed > 0)
    #expect(first.diagnostics.placedNodesComputed > 0)
    #expect(second.diagnostics.customLayoutFallbackCount == 0)
    #expect(second.diagnostics.measuredNodesComputed == 0)
    #expect(second.diagnostics.placedNodesComputed == 0)
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
      terminalHost: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, _ in
        if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
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

    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    let result = try await valueWithTimeout {
      try await runTask.value
    }
    let layoutState = recorder.state

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
    let workerTimings = try #require(artifacts.diagnostics.workerTimings)
    let raster = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(
      artifacts.diagnostics.customLayoutFallbackCount == 0,
      """
      expected \(identity.path) to avoid custom-layout fallback; \
      first fallback was \(artifacts.diagnostics.firstCustomLayoutFallbackIdentity?.path ?? "nil")
      \(raster)
      """
    )
    #expect(artifacts.diagnostics.firstCustomLayoutFallbackIdentity == nil)
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
    let workerTimings = try #require(artifacts.diagnostics.workerTimings)
    let raster = artifacts.rasterSurface.lines.joined(separator: "\n")

    let lazyStack = try #require(artifacts.resolvedTree.children.first)
    let source = try #require(lazyStack.indexedChildSource)

    #expect(source.canRunOnWorker)
    #expect(source.workerResolvedChildren?.count == 12)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(raster.contains("lazy row 0"))
  }

  @Test("lazy indexed child with main-actor custom layout still blocks worker layout")
  func lazyIndexedChildWithMainActorCustomLayoutStillBlocksWorkerLayout() async throws {
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
    let workerTimings = try #require(artifacts.diagnostics.workerTimings)
    let raster = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(artifacts.diagnostics.customLayoutFallbackCount == 1)
    #expect(artifacts.diagnostics.firstCustomLayoutFallbackIdentity != nil)
    #expect(workerTimings.layoutCompute == .zero)
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
      terminalHost: terminal,
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
        if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        AsyncFrameTailCounterView(value: value)
      }
    )
    runLoop.diagnosticsLogger = FrameDiagnosticsLogger(path: diagnosticsURL.path)
    #expect(runLoop.diagnosticsLogger != nil)

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
    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    inputReader.finish()
    gate.release()

    let result = try await valueWithTimeout {
      try await runTask.value
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(result.finalState == 3)
    #expect(result.renderedFrames == 3)
    let value1Index = terminal.frames.firstIndex { $0.contains("value 1") }
    let value2Index = terminal.frames.firstIndex { $0.contains("value 2") }
    let value3Index = terminal.frames.firstIndex { $0.contains("value 3") }
    #expect(value1Index != nil)
    #expect(value2Index == nil)
    #expect(value3Index != nil)
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

    #expect(artifacts.diagnostics.phaseTimings != nil)
    #expect(artifacts.diagnostics.workerTimings != nil)
    #expect(artifacts.diagnostics.mainActorTimings != nil)
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
      proposal: proposal,
      collectsDiagnostics: false
    )
    let asyncArtifacts = await DefaultRenderer().renderAsync(
      root(),
      context: .init(identity: rootIdentity),
      proposal: proposal,
      collectsDiagnostics: false
    )

    #expect(syncArtifacts == asyncArtifacts)

    let syncCommandArtifacts = DefaultRenderer().render(
      commandRoot(),
      context: .init(identity: commandRootIdentity),
      proposal: proposal,
      collectsDiagnostics: false
    )
    let asyncCommandArtifacts = await DefaultRenderer().renderAsync(
      commandRoot(),
      context: .init(identity: commandRootIdentity),
      proposal: proposal,
      collectsDiagnostics: false
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
      proposal: .init(width: 24, height: 5),
      collectsDiagnostics: false
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
      proposal: .init(width: 24, height: 5),
      collectsDiagnostics: false
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
      terminalHost: terminal,
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
      terminalHost: terminal,
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
    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    inputReader.finish()

    let result = try await valueWithTimeout {
      try await runTask.value
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
      terminalHost: terminal,
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
      terminalHost: terminal,
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

    let firstGenerations = first.diagnostics.renderGenerations
    let secondGenerations = second.diagnostics.renderGenerations

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

private struct AsyncFrameTailSendableLayout: SendableLayout {
  let recorder: AsyncFrameTailSendableLayoutRecorder

  var measurementReuseSignature: String {
    "AsyncFrameTailSendableLayout.measure"
  }

  var placementReuseSignature: String {
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

private struct AsyncFrameTailSendableGuideLayout: SendableLayout {
  let recorder: AsyncFrameTailSendableLayoutRecorder

  var measurementReuseSignature: String {
    "AsyncFrameTailSendableGuideLayout.measure"
  }

  var placementReuseSignature: String {
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

private struct AsyncFrameTailWorkerCustomLayout<Content: View>: View, ResolvableView {
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
    stateStorage.withLock { state in
      state.measureCount += 1
      state.measureRanOnMainThread = Thread.isMainThread
    }
  }

  func recordPlace() {
    stateStorage.withLock { state in
      state.placeCount += 1
      state.placeRanOnMainThread = Thread.isMainThread
    }
  }

  @MainActor
  func recordCacheApply(identity: Identity) {
    stateStorage.withLock { state in
      state.cacheApplyCount += 1
      state.cacheApplyRanOnMainThread = Thread.isMainThread
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
    stateStorage.withLock { state in
      state.measuredCache = cache
      state.measureRanOnMainThread = Thread.isMainThread
    }
  }

  func recordPlace(cache: Int) {
    stateStorage.withLock { state in
      state.placedCache = cache
      state.placeRanOnMainThread = Thread.isMainThread
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
  _ runLoop: TerminalUI.RunLoop<State, V>
) throws {
  runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
}

@MainActor
private func focusLeafmostAsyncFrameHeadAbortScaffoldRegion<State, V: View>(
  in runLoop: TerminalUI.RunLoop<State, V>
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

private final class AsyncFrameTailBlockingGate: Sendable {
  private struct State: Sendable {
    var rasterEntryCount = 0
  }

  private let blockingEntry: Int
  private let state = Mutex(State())
  private let entered = DispatchSemaphore(value: 0)
  private let releaseSemaphore = DispatchSemaphore(value: 0)

  init(blockingEntry: Int = 1) {
    self.blockingEntry = blockingEntry
  }

  var rasterEntryCount: Int {
    state.withLock(\.rasterEntryCount)
  }

  func beforeRaster() {
    let shouldBlock = state.withLock { state in
      state.rasterEntryCount += 1
      return state.rasterEntryCount == blockingEntry
    }
    guard shouldBlock else {
      return
    }

    entered.signal()
    releaseSemaphore.wait()
  }

  func waitUntilBlocked() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        self.entered.wait()
        continuation.resume()
      }
    }
  }

  func release() {
    releaseSemaphore.signal()
  }
}

private final class AsyncFrameTailTerminalHost: TerminalHosting {
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

private struct AsyncFrameTailTimeout: Error {}

@MainActor
private func waitUntil(
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  _ condition: () -> Bool
) async throws {
  let started = ContinuousClock().now
  while !condition() {
    if started.duration(to: ContinuousClock().now) > .nanoseconds(Int64(timeoutNanoseconds)) {
      throw AsyncFrameTailTimeout()
    }
    try await Task.sleep(nanoseconds: 1_000_000)
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

private func valueWithTimeout<Value: Sendable>(
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
  try await withThrowingTaskGroup(of: Value.self) { group in
    group.addTask {
      try await operation()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: timeoutNanoseconds)
      throw AsyncFrameTailTimeout()
    }

    let value = try await group.next()!
    group.cancelAll()
    return value
  }
}
