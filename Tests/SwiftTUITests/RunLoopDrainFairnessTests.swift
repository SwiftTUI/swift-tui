import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite(.serialized)
struct RunLoopDrainFairnessTests {
  @Test(
    "slow frames yield even when periodic state writes keep invalidating", arguments: [false, true])
  func slowFramesYield(synchronous: Bool) async throws {
    let harness = DrainFairnessHarness()
    harness.ticks.isActive = true
    harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
    var frames = 0

    if synchronous {
      try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    } else {
      try await harness.runLoop.renderPendingFramesAsync(renderedFrames: &frames)
    }

    #expect(frames > 0)
    #expect(frames < PeriodicInvalidationSink.safetyLimit)
    #expect(harness.scheduler.hasPendingFrame(at: harness.clock.now))

    // Yielding must preserve the pending write for the next pass.
    harness.ticks.isActive = false
    let framesBeforeResume = frames
    try await harness.runLoop.renderPendingFramesAsync(renderedFrames: &frames)
    #expect(frames > framesBeforeResume)
    #expect(!harness.scheduler.hasPendingFrame(at: harness.clock.now))
  }

  @Test(
    "with an event pump attached and the budget set, a pass yields once it is spent",
    arguments: [
      (renderCost: Duration.milliseconds(40), framesPerPass: 1),
      (renderCost: Duration.milliseconds(5), framesPerPass: 4),
    ]
  )
  func elapsedWorkBudgetBoundsAPass(renderCost: Duration, framesPerPass: Int) async throws {
    // The producer ticks at least once per commit, so every pass has more
    // work than the budget admits.
    let harness = DrainFairnessHarness(renderCost: renderCost, tickInterval: renderCost)
    harness.runLoop.drainPassWorkBudget = .milliseconds(16)
    let pump = harness.runLoop.makeEventPump()
    defer { pump.cancel() }
    harness.ticks.isActive = true
    harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
    var frames = 0

    _ = try await harness.runLoop.renderPendingFramesAsync(
      renderedFrames: &frames, eventPump: pump)

    // 16 ms of frame-clock work per pass: one 40 ms frame overshoots it at
    // once; 5 ms frames fit four acquisitions (0, 5, 10, 15 ms elapsed)
    // before the fifth check trips. The producer still has work pending.
    #expect(frames == framesPerPass, "frames: \(frames)")
    #expect(harness.scheduler.hasPendingFrame(at: harness.clock.now))

    // The synchronous driver applies the same budget when given the pump.
    harness.ticks.isActive = true
    var syncFrames = 0
    try harness.runLoop.renderPendingFrames(renderedFrames: &syncFrames, eventPump: pump)
    #expect(syncFrames == framesPerPass, "sync frames: \(syncFrames)")
  }

  @Test("end of input flushes the input change without draining a periodic producer forever")
  func inputEndBoundsPeriodicFlush() async throws {
    let harness = DrainFairnessHarness()
    harness.input.send(.key(.return))
    harness.input.finish()

    let result = try await harness.runLoop.run()

    #expect(result.exitReason == .inputEnded)
    #expect(result.finalState == 1)
    #expect(harness.surface.frames.last?.contains("value 1") == true)
    #expect(harness.ticks.tickCount > 0)
    #expect(harness.ticks.tickCount < PeriodicInvalidationSink.safetyLimit)
  }

  @Test(
    "cooperative exit presents the resized input frame without draining later producer writes",
    arguments: [false, true])
  func cooperativeExitStopsAfterRequiredPresentation(inputEnds: Bool) async throws {
    let harness = CooperativeExitHarness()
    let runTask = Task { try await harness.runLoop.run() }
    defer {
      runTask.cancel()
      harness.input.finish()
    }
    try await waitUntil {
      harness.surface.frames.last?.contains("input 0") == true && harness.lifetime.taskStarted
    }

    // Resize and queue the handled input and exit without waiting for a frame
    // or stopping the producer. The next input dispatch observes host geometry.
    harness.surface.surfaceSize = CellSize(width: 40, height: 3)
    harness.input.send(.key(.return))
    if inputEnds {
      harness.input.finish()
    } else {
      harness.input.send(.key(.character("c"), modifiers: .ctrl))
    }
    harness.scheduler.requestInvalidation(of: [harness.root])

    let result = try await valueWithTimeout { try await runTask.value }
    try await waitUntil { harness.lifetime.taskCancelled }

    let expectedExit: RunLoopExitReason
    if inputEnds {
      expectedExit = .inputEnded
    } else {
      expectedExit = .userExit(KeyPress(.character("c"), modifiers: .ctrl))
    }
    #expect(result.exitReason == expectedExit)
    #expect(result.finalState.inputValue == 1)
    #expect(harness.surface.frames.last?.contains("input 1 tick 0") == true)
    #expect(harness.surface.frames.last?.contains("stable sibling") == true)
    #expect(harness.surface.frameSizes.last == CellSize(width: 40, height: 3))
    #expect(harness.surface.frames.first?.contains("input 0") == true)
    #expect(harness.producer.committedFrames == 1)
    #expect(harness.producer.acquiredFrames == 1)
    #expect(harness.producer.answeredInputFrames == 1)
    #expect(harness.producer.isActive)
    #expect(harness.scheduler.hasPendingFrame(at: .now()))
    #expect(harness.surface.rawModeEvents == ["enable", "disable"])
    #expect(!harness.runLoop.isSessionActive)
  }

  @Test(
    "cooperative exit settles a synchronous input-driven lifecycle follow-up",
    arguments: [false, true])
  func cooperativeExitPresentsLifecycleFollowUp(inputEnds: Bool) async throws {
    let root = testIdentity("CooperativeExitDerivedInput")
    let surface = CooperativeExitSurface()
    let input = CooperativeExitInputReader()
    let runLoop = RunLoop(
      rootIdentity: root,
      presentationSurface: surface,
      terminalInputReader: input,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      keyHandler: { key, _, state in
        guard key == KeyPress(.return) else { return .ignored }
        state.mutate { $0 += 1 }
        return .handled
      },
      viewBuilder: { value, _ in DerivedInputFixture(value: value) }
    )
    runLoop.renderMode = .async
    let runTask = Task { try await runLoop.run() }
    defer {
      runTask.cancel()
      input.finish()
    }
    try await waitUntil { surface.frames.last?.contains("input 0 derived 0") == true }
    input.send(.key(.return))
    if inputEnds {
      input.finish()
    } else {
      input.send(.key(.character("c"), modifiers: .ctrl))
    }
    runLoop.scheduler.requestInvalidation(of: [root])

    let result = try await valueWithTimeout { try await runTask.value }

    #expect(result.finalState == 1)
    #expect(surface.frames.last?.contains("input 1 derived 1") == true)
    let inputFrame = surface.frames.firstIndex { $0.contains("input 1 derived 0") }
    let followUpFrame = surface.frames.firstIndex { $0.contains("input 1 derived 1") }
    #expect(inputFrame != nil)
    #expect(followUpFrame != nil)
    if let inputFrame, let followUpFrame {
      #expect(inputFrame < followUpFrame)
    }
  }

  @Test(
    "cooperative exit retries a cancelled input acquisition before stopping the producer drain",
    arguments: [false, true])
  func cooperativeExitRetainsInputAcrossCancelledAcquisition(inputEnds: Bool) async throws {
    let harness = CooperativeExitHarness()
    let workerGate = AsyncFrameTailBlockingGate()
    let runTask = Task { try await harness.runLoop.run() }
    defer {
      workerGate.release()
      runTask.cancel()
      harness.input.finish()
    }
    try await waitUntil {
      harness.surface.frames.last?.contains("input 0") == true && harness.lifetime.taskStarted
    }
    let workerTask = Task {
      await harness.runLoop.renderer.runFrameTailLayoutWorkerJobForCancellationTesting {
        workerGate.beforeRaster()
      }
    }
    do {
      await workerGate.waitUntilBlocked()

      harness.input.send(.key(.return))
      if inputEnds {
        harness.input.finish()
      } else {
        harness.input.send(.key(.character("c"), modifiers: .ctrl))
      }
      harness.scheduler.requestInvalidation(of: [harness.root])
      try await waitUntil {
        harness.producer.acquiredFrames > 0
          && harness.runLoop.renderSuspensionDiagnostics.isSuspended
      }
      // Supersede the queued input frame while its tail cannot start. A single
      // acquisition exit budget would abandon the final handled input here.
      harness.runLoop.stateContainer.mutate {
        $0 = CooperativeExitState(inputValue: $0.inputValue, tick: $0.tick + 1)
      }
      try await waitUntil { harness.runLoop.cancelledRenderCount > 0 }
      workerGate.release()

      let result = try await valueWithTimeout { try await runTask.value }
      await workerTask.value
      try await waitUntil { harness.lifetime.taskCancelled }

      let expectedExit: RunLoopExitReason
      if inputEnds {
        expectedExit = .inputEnded
      } else {
        expectedExit = .userExit(KeyPress(.character("c"), modifiers: .ctrl))
      }
      let maxAcquisitions =
        RunLoop<CooperativeExitState, CooperativeExitFixture>.maxFramesPerDrainPass
      #expect(result.exitReason == expectedExit)
      #expect(result.finalState.inputValue == 1)
      #expect(harness.surface.lastFrameContainsLine("input 1 tick 1"))
      #expect(harness.runLoop.cancelledRenderCount > 0)
      #expect(harness.producer.acquiredFrames > 1)
      #expect(harness.producer.acquiredFrames <= maxAcquisitions)
      #expect(harness.producer.committedFrames == 1)
      #expect(harness.producer.answeredInputFrames == 1)
      #expect(harness.producer.isActive)
      #expect(harness.surface.rawModeEvents == ["enable", "disable"])
    } catch {
      workerGate.release()
      await workerTask.value
      throw error
    }
  }

  @Test(
    "cooperative exit retains hover-exit writes across eager focus reconciliation",
    arguments: [false, true], [false, true])
  func cooperativeExitRetainsEagerFocusFollowUp(inputEnds: Bool, synchronous: Bool) async throws {
    let root = testIdentity("CooperativeHoverExit")
    let firstControl = testIdentity("CooperativeHoverExit", "First")
    let secondControl = testIdentity("CooperativeHoverExit", "Second")
    let surface = CooperativeExitSurface()
    surface.surfaceSize = CellSize(width: 30, height: 5)
    let input = CooperativeExitInputReader()
    let scheduler = FrameScheduler()
    let state = StateContainer(
      initialState: HoverExitState(), invalidationIdentities: [root])
    let hover = HoverExitRecorder()
    let producer = HoverExitProducer(state: state)
    let runLoop = RunLoop(
      rootIdentity: root,
      presentationSurface: surface,
      terminalInputReader: input,
      scheduler: scheduler,
      stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      keyHandler: { key, _, state in
        guard key == KeyPress(.character("h")) else { return .ignored }
        producer.isActive = true
        state.mutate {
          $0 = HoverExitState(
            showsFirstControl: false, didExitHover: $0.didExitHover, tick: $0.tick)
        }
        return .handled
      },
      viewBuilder: { value, _ in
        HoverExitFixture(
          state: value, stateContainer: state, hover: hover,
          firstControl: firstControl, secondControl: secondControl)
      }
    )
    if synchronous {
      runLoop.renderMode = .sync
    } else {
      runLoop.renderMode = .async
    }
    runLoop.frameSink = producer
    let runTask = Task { try await runLoop.run() }
    defer {
      runTask.cancel()
      input.finish()
    }
    try await waitUntil { surface.frames.last?.contains("First") == true }
    let firstRegion = try #require(
      runLoop.latestSemanticSnapshot.interactionRegions.first {
        $0.identity == firstControl || $0.identity.isDescendant(of: firstControl)
      })
    let firstFocus = try #require(
      runLoop.latestSemanticSnapshot.focusRegions.first {
        $0.identity == firstControl || $0.identity.isDescendant(of: firstControl)
      })
    let pointer = Point(
      x: Double(firstRegion.rect.origin.x + firstRegion.rect.size.width / 2),
      y: Double(firstRegion.rect.origin.y + firstRegion.rect.size.height / 2))
    input.send(.mouse(MouseEvent(kind: .moved, location: pointer)))
    input.send(.mouse(MouseEvent(kind: .down(.primary), location: pointer)))
    input.send(.mouse(MouseEvent(kind: .up(.primary), location: pointer)))
    scheduler.requestInvalidation(of: [root])
    try await waitUntil {
      hover.didEnter && runLoop.focusTracker.currentFocusIdentity == firstFocus.identity
    }
    #expect(runLoop.hoveredPointerRouteID != nil)
    #expect(!state.state.didExitHover)

    input.send(.key(.character("h")))
    if inputEnds {
      input.finish()
    } else {
      input.send(.key(.character("c"), modifiers: .ctrl))
    }
    scheduler.requestInvalidation(of: [root])
    let result = try await valueWithTimeout { try await runTask.value }

    #expect(!result.finalState.showsFirstControl)
    #expect(result.finalState.didExitHover)
    #expect(hover.exitCount == 1)
    #expect(surface.lastFrameContainsLine("hover exited true"))
    #expect(surface.frames.last?.contains("First") == false)
    #expect(surface.frames.last?.contains("Second") == true)
    #expect(runLoop.focusTracker.currentFocusIdentity != firstFocus.identity)
    #expect(runLoop.focusTracker.currentFocusIdentity != nil)
    #expect(producer.committedFrames == 2)
    #expect(producer.isActive)
  }

  @Test(
    "direct synchronous event-pump exit excludes independent producer writes",
    arguments: [false, true])
  func directSynchronousCooperativeExitStopsAfterRequiredPresentation(inputEnds: Bool) throws {
    let harness = CooperativeExitHarness()
    harness.runLoop.isSessionActive = true
    harness.runLoop.stateContainer.invalidator = harness.scheduler
    harness.runLoop.focusTracker.invalidator = harness.scheduler
    defer {
      harness.runLoop.isSessionActive = false
      harness.runLoop.lifecycleCoordinator.shutdown()
      harness.input.finish()
    }
    var frames = 0
    harness.scheduler.requestInvalidation(of: [harness.root])
    try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    let pump = harness.runLoop.makeEventPump()
    defer { pump.cancel() }
    harness.input.send(.key(.return))
    if inputEnds {
      harness.input.finish()
    } else {
      harness.input.send(.key(.character("c"), modifiers: .ctrl))
    }
    let exit = try harness.runLoop.processPendingEventsSynchronously(
      from: pump, renderedFrames: &frames)

    let expectedExit: RunLoopExitReason
    if inputEnds {
      expectedExit = .inputEnded
    } else {
      expectedExit = .userExit(KeyPress(.character("c"), modifiers: .ctrl))
    }
    #expect(exit == expectedExit)
    #expect(harness.surface.lastFrameContainsLine("input 1 tick 0"))
    #expect(harness.producer.committedFrames == 1)
    #expect(harness.producer.acquiredFrames == 1)
    #expect(harness.producer.answeredInputFrames == 1)
    #expect(harness.producer.isActive)
    #expect(harness.scheduler.hasPendingFrame(at: .now()))
  }

  @Test(
    "lifecycle issue reporting leaves independent sink invalidations pending at exit",
    arguments: [false, true])
  func cooperativeExitExcludesLifecycleIssueSinkWrites(inputEnds: Bool) async throws {
    let harness = CooperativeExitHarness()
    let runTask = Task { try await harness.runLoop.run() }
    defer {
      runTask.cancel()
      harness.input.finish()
    }
    try await waitUntil {
      harness.surface.frames.last?.contains("input 0") == true && harness.lifetime.taskStarted
    }
    let faultIdentity = testIdentity("CooperativeExitProducer", "MissingTask")
    let missingDescriptor = TaskDescriptor(id: "synthetic-unregistered-task", priority: .medium)
    // Explicit fault injection at the existing carry-forward boundary: the
    // lifecycle skip contract must report this unmatched committed start.
    // This is the same missing registration/node failure exercised directly
    // in LifecycleCoordinatorSkipTests, now routed through the real run loop.
    harness.runLoop.deferredLifecycleCarryForward.append(
      LifecycleCommitEntry(identity: faultIdentity, operation: .taskStart(missingDescriptor)))
    let state = harness.runLoop.stateContainer
    var reportedIssues: [RuntimeIssue] = []
    harness.runLoop.runtimeIssueSink = RuntimeIssueSink { issue in
      reportedIssues.append(issue)
      guard issue.code == "lifecycle.taskStartSkipped", issue.identity == faultIdentity else {
        return
      }
      state.mutate {
        $0 = CooperativeExitState(inputValue: $0.inputValue, tick: $0.tick + 1)
      }
    }
    harness.input.send(.key(.return))
    if inputEnds {
      harness.input.finish()
    } else {
      harness.input.send(.key(.character("c"), modifiers: .ctrl))
    }
    harness.scheduler.requestInvalidation(of: [harness.root])

    let result = try await valueWithTimeout { try await runTask.value }
    try await waitUntil { harness.lifetime.taskCancelled }

    #expect(reportedIssues.count == 1)
    #expect(reportedIssues.first?.code == "lifecycle.taskStartSkipped")
    #expect(reportedIssues.first?.identity == faultIdentity)
    #expect(reportedIssues.first?.severity == .warning)
    #expect(reportedIssues.first?.source == "LifecycleCoordinator")
    #expect(result.finalState.inputValue == 1)
    // The issue sink and independent producer both wrote after presentation.
    // Those writes remain pending rather than extending required exit work.
    #expect(result.finalState.tick == 2)
    #expect(harness.surface.lastFrameContainsLine("input 1 tick 0"))
    #expect(harness.producer.committedFrames == 1)
    #expect(harness.producer.acquiredFrames == 1)
    #expect(harness.scheduler.hasPendingFrame(at: .now()))
    #expect(harness.lifetime.taskStartCount == 1)
    #expect(harness.runLoop.lifecycleCoordinator.taskStartSkipCount == 1)
    #expect(harness.runLoop.lifecycleCoordinator.appearHandlerSkipCount == 0)
    #expect(harness.runLoop.lifecycleCoordinator.disappearHandlerSkipCount == 0)
    #expect(harness.runLoop.lifecycleCoordinator.changeHandlerSkipCount == 0)
    #expect(harness.runLoop.lifecycleCoordinator.activeTaskCount == 0)
    #expect(harness.surface.rawModeEvents == ["enable", "disable"])
  }
}

private struct HoverExitState: Equatable, Sendable {
  let showsFirstControl: Bool
  let didExitHover: Bool
  let tick: Int

  init(showsFirstControl: Bool = true, didExitHover: Bool = false, tick: Int = 0) {
    self.showsFirstControl = showsFirstControl
    self.didExitHover = didExitHover
    self.tick = tick
  }
}

@MainActor
private final class HoverExitRecorder {
  var didEnter = false
  var exitCount = 0
}

private struct HoverExitFixture: View {
  let state: HoverExitState
  let stateContainer: StateContainer<HoverExitState>
  let hover: HoverExitRecorder
  let firstControl: Identity
  let secondControl: Identity

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("hover exited \(state.didExitHover)")
      Text("tick \(state.tick)")
      if state.showsFirstControl {
        Button("First") {}
          .id(firstControl)
          .onPointerHover { phase in
            switch phase {
            case .entered:
              hover.didEnter = true
            case .moved:
              break
            case .exited:
              hover.exitCount += 1
              stateContainer.mutate {
                $0 = HoverExitState(
                  showsFirstControl: $0.showsFirstControl, didExitHover: true, tick: $0.tick)
              }
            }
          }
      }
      Button("Second") {}.id(secondControl)
    }
  }
}

@MainActor
private final class HoverExitProducer: FrameDiagnosticSink {
  private let state: StateContainer<HoverExitState>
  var isActive = false
  private(set) var committedFrames = 0

  init(state: StateContainer<HoverExitState>) {
    self.state = state
  }

  func record(_ sample: RuntimeFrameSample) {
    guard case .committed = sample, isActive else { return }
    committedFrames += 1
    if committedFrames < PeriodicInvalidationSink.safetyLimit {
      state.mutate {
        $0 = HoverExitState(
          showsFirstControl: $0.showsFirstControl, didExitHover: $0.didExitHover, tick: $0.tick + 1)
      }
    }
  }
}

private struct CooperativeExitState: Equatable, Sendable {
  let inputValue: Int
  let tick: Int

  init(inputValue: Int = 0, tick: Int = 0) {
    self.inputValue = inputValue
    self.tick = tick
  }
}

/// One source pull forwards the handled key and its following exit together.
/// The test queues the whole batch, then wakes the real run loop's scheduler.
/// This avoids a later stream-copy hop injecting EOF between acquisitions.
@MainActor
private final class CooperativeExitInputReader: SynchronousInputPulling {
  private var queue: [InputEvent] = []
  private var sink: InputPullDeliverySink?
  private var hasFinished = false
  private var hasReportedEnd = false

  func send(_ event: InputEvent) {
    queue.append(event)
  }

  func finish() {
    hasFinished = true
  }

  nonisolated func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }

  func installPullDelivery(_ sink: InputPullDeliverySink) {
    self.sink = sink
  }

  @discardableResult
  func pullPendingInput() -> Int {
    guard let sink else { return 0 }
    let events = queue
    queue.removeAll()
    for event in events {
      sink.deliver(event)
    }
    if hasFinished, !hasReportedEnd {
      hasReportedEnd = true
      sink.inputEnded()
    }
    return events.count
  }

  func uninstallPullDelivery() {
    sink = nil
  }
}

@MainActor
private final class CooperativeExitHarness {
  let root = testIdentity("CooperativeExitProducer")
  let scheduler = FrameScheduler()
  let input = CooperativeExitInputReader()
  let surface = CooperativeExitSurface()
  let lifetime = CooperativeExitLifetime()
  let producer: CooperativeExitProducer
  let runLoop: RunLoop<CooperativeExitState, CooperativeExitFixture>

  init() {
    let state = StateContainer(
      initialState: CooperativeExitState(), invalidationIdentities: [root])
    let producer = CooperativeExitProducer(state: state)
    self.producer = producer
    let lifetime = self.lifetime
    runLoop = RunLoop(
      rootIdentity: root,
      presentationSurface: surface,
      terminalInputReader: input,
      scheduler: scheduler,
      stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      keyHandler: { key, _, state in
        guard key == KeyPress(.return) else { return .ignored }
        producer.isActive = true
        state.mutate {
          $0 = CooperativeExitState(inputValue: $0.inputValue + 1, tick: $0.tick)
        }
        return .handled
      },
      viewBuilder: { state, _ in CooperativeExitFixture(state: state, lifetime: lifetime) }
    )
    runLoop.renderMode = .async
    // Full-loop readiness and acquisition both use the real clock. Producer
    // work is counted deterministically, without mixing virtual deadlines
    // with the outer loop's real-time readiness probes.
    runLoop.frameClockDidAcquire = { _ in
      if producer.isActive { producer.acquiredFrames += 1 }
    }
    runLoop.frameSink = producer
  }
}

@MainActor
private final class CooperativeExitProducer: FrameDiagnosticSink {
  private let state: StateContainer<CooperativeExitState>
  var isActive = false
  var acquiredFrames = 0
  private(set) var committedFrames = 0
  private(set) var answeredInputFrames = 0

  init(state: StateContainer<CooperativeExitState>) {
    self.state = state
  }

  func record(_ sample: RuntimeFrameSample) {
    guard case .committed(let committed) = sample, isActive else { return }
    committedFrames += 1
    if committed.answeredInputs != nil { answeredInputFrames += 1 }
    // Every completed frame encounters another independent producer write.
    // The cap protects an unfixed runner; it is not the exit-work expectation.
    if committedFrames < PeriodicInvalidationSink.safetyLimit {
      state.mutate {
        $0 = CooperativeExitState(inputValue: $0.inputValue, tick: $0.tick + 1)
      }
    }
  }
}

@MainActor
private final class CooperativeExitLifetime {
  private(set) var taskStarted = false
  private(set) var taskCancelled = false
  private(set) var taskStartCount = 0

  func runTask() async {
    taskStarted = true
    taskStartCount += 1
    let stream = AsyncStream<Void> { _ in }
    for await _ in stream {}
    taskCancelled = Task.isCancelled
  }
}

private struct CooperativeExitFixture: View {
  let state: CooperativeExitState
  let lifetime: CooperativeExitLifetime

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("input \(state.inputValue) tick \(state.tick)")
      Text("stable sibling")
    }
    .task { await lifetime.runTask() }
  }
}

private struct DerivedInputFixture: View {
  let value: Int
  @State private var derived = 0

  var body: some View {
    Text("input \(value) derived \(derived)")
      .onChange(of: value) { _, newValue in derived = newValue }
  }
}

private final class CooperativeExitSurface: PresentationSurface {
  var surfaceSize = CellSize(width: 30, height: 3)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  private(set) var frames: [String] = []
  private(set) var frameSizes: [CellSize] = []
  private(set) var rawModeEvents: [String] = []

  func enableRawMode() throws { rawModeEvents.append("enable") }
  func disableRawMode() throws { rawModeEvents.append("disable") }
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  func lastFrameContainsLine(_ line: String) -> Bool {
    guard let frame = frames.last else { return false }
    return frame.split(whereSeparator: \.isNewline).contains { row in
      row.split(separator: " ").joined(separator: " ") == line
    }
  }

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let output = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    frames.append(String(output.filter { $0 != "\r" }))
    frameSizes.append(surface.size)
    return .fullRepaint(for: surface, capabilityProfile: capabilityProfile)
  }
}

@MainActor
private final class DrainFairnessHarness {
  let rootIdentity = testIdentity("DrainFairness")
  let scheduler = FrameScheduler()
  let clock = VirtualFrameClock()
  let input = InjectedTerminalInputReader()
  let surface = RecordingPresentationSurface(surfaceSize: .init(width: 20, height: 2))
  let ticks: PeriodicInvalidationSink
  let runLoop: RunLoop<Int, Text>

  init(renderCost: Duration = .milliseconds(40), tickInterval: Duration = .milliseconds(33)) {
    let ticks = PeriodicInvalidationSink(
      scheduler: scheduler, identity: rootIdentity, clock: clock, renderCost: renderCost,
      tickInterval: tickInterval)
    self.ticks = ticks
    runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: input,
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { key, _, state in
        guard key == KeyPress(.return) else { return .ignored }
        ticks.isActive = true
        state.mutate { $0 += 1 }
        return .handled
      },
      proposal: .init(width: 20, height: 2),
      viewBuilder: { value, _ in Text("value \(value)") }
    )
    runLoop.frameClock = { [clock] in clock.now }
    runLoop.frameSink = ticks
  }
}

/// Models a 33 ms producer on a machine that takes 40 ms to render a frame.
/// Each frame therefore encounters a fresh state invalidation. The safety
/// limit makes the unfixed test fail assertions instead of hanging its runner.
@MainActor
private final class PeriodicInvalidationSink: FrameDiagnosticSink {
  static let safetyLimit = 32
  var isActive = false
  private(set) var tickCount = 0
  private let scheduler: FrameScheduler
  private let identity: Identity
  private let clock: VirtualFrameClock
  private let renderCost: Duration
  private let tickInterval: Duration
  private var nextTick: MonotonicInstant

  init(
    scheduler: FrameScheduler, identity: Identity, clock: VirtualFrameClock,
    renderCost: Duration = .milliseconds(40),
    tickInterval: Duration = .milliseconds(33)
  ) {
    self.scheduler = scheduler
    self.identity = identity
    self.clock = clock
    self.renderCost = renderCost
    self.tickInterval = tickInterval
    nextTick = clock.now.advanced(by: tickInterval)
  }

  func record(_ sample: RuntimeFrameSample) {
    guard case .committed = sample, isActive else { return }
    clock.advance(by: renderCost)
    guard clock.now >= nextTick else { return }
    tickCount += 1
    nextTick = clock.now.advanced(by: tickInterval)
    if tickCount < Self.safetyLimit {
      scheduler.requestInvalidation(of: [identity])
    }
  }
}
