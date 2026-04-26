@unsafe @preconcurrency import Dispatch
import Foundation
import Synchronization
import Testing

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

  @Test("worker backlog commits blocked frame before later input batch")
  func workerBacklogCommitsBlockedFrameBeforeLaterInputBatch() async throws {
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
    let value1Index = terminal.frames.firstIndex { $0.contains("value 1") }
    let value3Index = terminal.frames.firstIndex { $0.contains("value 3") }
    #expect(value1Index != nil)
    #expect(value3Index != nil)
    if let value1Index, let value3Index {
      #expect(value1Index < value3Index)
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

    #expect(artifacts.diagnostics.phaseTimings != nil)
    #expect(artifacts.diagnostics.workerTimings != nil)
    #expect(artifacts.diagnostics.mainActorTimings != nil)
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
      return Size(
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
          in: Rect(
            origin: Point(x: bounds.origin.x, y: y),
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
  ) -> Size {
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
    in _: Rect
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
  var surfaceSize: Size {
    size
  }
  let size = Size(width: 32, height: 6)
  let proposal = ProposedSize(width: 32, height: 6)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  private(set) var frames: [String] = []

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

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
