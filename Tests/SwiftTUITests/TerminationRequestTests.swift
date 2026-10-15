@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Termination requests")
struct TerminationRequestTests {
  @Test(
    "termination raised by exit-flush callbacks is dispatched in both pumps",
    arguments: [false, true], [false, true])
  func terminationDuringExitFlush(synchronous: Bool, cancelProgrammatic: Bool) async throws {
    let recorder = TerminationRecorder()
    let root = testIdentity("LateExitFlush")
    let exitKey = KeyPress(.character("c"), modifiers: .ctrl)
    let input = CooperativeExitInputReader()
    input.send(.key(.return))
    input.send(.key(exitKey))
    defer { input.finish() }
    let scheduler = FrameScheduler()
    let state = StateContainer(initialState: 0, invalidationIdentities: [root])
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: TerminationTestTerminalHost(),
      terminalInputReader: input, scheduler: scheduler, stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      keyHandler: { key, _, state in
        guard key == KeyPress(.return) else { return .ignored }
        state.mutate { $0 += 1 }
        return .handled
      },
      viewBuilder: { value, _ in
        ExitFlushTerminationFixture(value: value)
          .onTerminationRequest { request in
            recorder.requests.append(request)
            return request == .programmatic && cancelProgrammatic ? .cancel : .allow
          }
      })
    let exit: RunLoopExitReason?
    if synchronous {
      loop.isSessionActive = true
      state.invalidator = scheduler
      defer {
        loop.isSessionActive = false
        loop.lifecycleCoordinator.shutdown()
      }
      var frames = 0
      scheduler.requestInvalidation(of: [root])
      try loop.renderPendingFrames(renderedFrames: &frames)
      let buffer = EventPumpBuffer()
      _ = buffer.enqueue(.input(.key(.return)))
      _ = buffer.enqueue(.input(.key(exitKey)))
      exit = try loop.processPendingEventsSynchronously(
        from: .init(
          stream: AsyncStream { $0.finish() }, drainEvents: { buffer.drain() },
          hasPendingEvents: { buffer.hasPendingEvents() }, cancel: {},
          scheduleDeadlineWake: { _ in }),
        renderedFrames: &frames)
    } else {
      exit = try await loop.run().exitReason
    }
    // A veto of the late request does not revoke the earlier accepted exit.
    #expect(exit == (cancelProgrammatic ? .userExit(exitKey) : .programmatic))
    #expect(recorder.requests == [.userExit(exitKey), .programmatic])
    #expect(!loop.hasPendingProgrammaticTermination)
  }

  @Test("signal exit acquires at most one pending frame", arguments: [false, true])
  func synchronousSignalFlushIsBounded(synchronous: Bool) async throws {
    let root = testIdentity("SyncSignalFlush")
    let scheduler = FrameScheduler()
    let surface = TerminationTestTerminalHost()
    var framesAtDisposition = 0
    let runLoop = RunLoop(
      rootIdentity: root, presentationSurface: surface,
      terminalInputReader: TerminationTestInputReader(events: [], finishAfterEvents: false),
      signalReader: TerminationTestSignalReader(signals: synchronous ? [] : ["SIGTERM"]),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      viewBuilder: { _, _ in
        Text("pending").onTerminationRequest { _ in
          framesAtDisposition = surface.frames.count
          return .allow
        }
      })
    runLoop.isSessionActive = true
    defer {
      runLoop.isSessionActive = false
      runLoop.lifecycleCoordinator.shutdown()
    }
    runLoop.frameSink = SignalExitFrameSink(scheduler: scheduler, root: root)
    scheduler.requestInvalidation(of: [root])
    if !synchronous {
      let result = try await runLoop.run()
      #expect(result.exitReason == .signal("SIGTERM"))
      #expect(surface.frames.count - framesAtDisposition == 1)
      return
    }
    let buffer = EventPumpBuffer()
    _ = buffer.enqueue(.signal("SIGTERM"))
    var frames = 0
    let exit = try runLoop.processPendingEventsSynchronously(
      from: .init(
        stream: AsyncStream { $0.finish() }, drainEvents: { buffer.drain() },
        hasPendingEvents: { buffer.hasPendingEvents() }, cancel: {}, scheduleDeadlineWake: { _ in }),
      renderedFrames: &frames)
    #expect(exit == .signal("SIGTERM"))
    #expect(frames == 1)
  }

  @Test("Ctrl exit letters ignore case without folding bare characters or modifiers")
  func controlExitLetterCase() {
    let bindings = ExitKeyBindings([KeyPress(.character("Q"), modifiers: .ctrl)])
    #expect(bindings.contains(KeyPress(.character("q"), modifiers: .ctrl)))
    #expect(!bindings.contains(KeyPress(.character("q"))))
    #expect(!bindings.contains(KeyPress(.character("q"), modifiers: [.ctrl, .shift])))
    #expect(!ExitKeyBindings([KeyPress(.character("Q"))]).contains(KeyPress(.character("q"))))
  }

  @Test(
    "programmatic termination from a drained action precedes a later exit key",
    arguments: [false, true], [false, true])
  func programmaticRequestPrecedesBatchedExit(cancelProgrammatic: Bool, synchronous: Bool)
    async throws
  {
    let recorder = TerminationRecorder()
    let exitKey = KeyPress(.character("c"), modifiers: .ctrl)
    let input = CooperativeExitInputReader()
    input.send(.key(.space))
    input.send(.key(exitKey))
    defer { input.finish() }
    let root = testIdentity("BatchedProgrammaticTermination")
    let surface = TerminationTestTerminalHost()
    let state = StateContainer(initialState: 0, invalidationIdentities: [root])
    let runLoop = RunLoop(
      rootIdentity: root,
      presentationSurface: surface,
      terminalInputReader: input,
      signalReader: TerminationTestSignalReader(signals: []),
      scheduler: FrameScheduler(),
      stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      viewBuilder: { value, _ in
        VStack {
          Text("decision \(value)")
          ButtonTerminationFixture()
        }
        .onTerminationRequest { request in
          recorder.requests.append(request)
          state.mutate { $0 += 1 }
          return cancelProgrammatic && request == .programmatic ? .cancel : .allow
        }
      }
    )
    let exitReason: RunLoopExitReason?
    if synchronous {
      runLoop.isSessionActive = true
      state.invalidator = runLoop.scheduler
      defer {
        runLoop.isSessionActive = false
        runLoop.lifecycleCoordinator.shutdown()
      }
      var frames = 0
      runLoop.scheduler.requestInvalidation(of: [root])
      try runLoop.renderPendingFrames(renderedFrames: &frames)
      let buffer = EventPumpBuffer()
      _ = buffer.enqueue(.input(.key(KeyPress(.space))))
      _ = buffer.enqueue(.input(.key(exitKey)))
      exitReason = try runLoop.processPendingEventsSynchronously(
        from: .init(
          stream: AsyncStream { $0.finish() },
          drainEvents: { buffer.drain() }, hasPendingEvents: { buffer.hasPendingEvents() },
          cancel: {}, scheduleDeadlineWake: { _ in }),
        renderedFrames: &frames)
    } else {
      exitReason = try await runLoop.run().exitReason
    }
    #expect(surface.frames.last?.contains("decision \(cancelProgrammatic ? 2 : 1)") == true)
    #expect(exitReason == (cancelProgrammatic ? .userExit(exitKey) : .programmatic))
    #expect(
      recorder.requests
        == (cancelProgrammatic ? [.programmatic, .userExit(exitKey)] : [.programmatic]))
  }

  @Test(
    "onTerminationRequest can cancel without flushing or stopping owned tasks",
    arguments: [false, true])
  func terminationRequestCanCancelExitKey(synchronous: Bool) async throws {
    let recorder = TerminationRecorder()
    let exitKey = KeyPress(.character("c"), modifiers: .ctrl)
    let input = CooperativeExitInputReader()
    for event: InputEvent in [
      .key(.init(.return)), .key(exitKey), .key(.init(.character("v"))), .key(exitKey),
    ] { input.send(event) }
    defer { input.finish() }
    let root = testIdentity("VetoBeforeFlush")
    let surface = TerminationTestTerminalHost()
    let state = StateContainer(initialState: 0, invalidationIdentities: [root])
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: root, presentationSurface: surface,
      terminalInputReader: input, scheduler: scheduler, stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      keyHandler: { key, _, state in
        if key == KeyPress(.return) {
          state.mutate { $0 = 1 }
          return .handled
        }
        if key == KeyPress(.character("v")) {
          #expect(surface.frames.count == 1)
          #expect(recorder.activeTasks?() == 1)
          recorder.checkedVeto = true
          return .handled
        }
        return .ignored
      },
      viewBuilder: { value, _ in
        Text("value \(value)")
          .task { await suspendUntilCancelled() }
          .onTerminationRequest { request in
            recorder.requests.append(request)
            if recorder.requests.count == 1 { return .cancel }
            state.mutate { $0 = 2 }
            return .allow
          }
      })
    recorder.activeTasks = { [weak runLoop] in runLoop?.lifecycleCoordinator.activeTaskCount ?? 0 }
    if synchronous {
      runLoop.isSessionActive = true
      state.invalidator = scheduler
      defer {
        runLoop.isSessionActive = false
        runLoop.lifecycleCoordinator.shutdown()
      }
      var frames = 0
      scheduler.requestInvalidation(of: [root])
      try runLoop.renderPendingFrames(renderedFrames: &frames)
      let buffer = EventPumpBuffer()
      _ = buffer.enqueue(.input(.key(.init(.return))))
      _ = buffer.enqueue(.input(.key(exitKey)))
      _ = buffer.enqueue(.input(.key(.init(.character("v")))))
      #expect(
        try runLoop.processPendingEventsSynchronously(
          from: .init(
            stream: AsyncStream { $0.finish() }, drainEvents: { buffer.drain() },
            hasPendingEvents: { buffer.hasPendingEvents() }, cancel: {},
            scheduleDeadlineWake: { _ in }), renderedFrames: &frames) == nil)
      #expect(surface.frames.last?.contains("value 1") == true)
      #expect(runLoop.lifecycleCoordinator.activeTaskCount == 1)
      _ = buffer.enqueue(.input(.key(.init(.return))))
      _ = buffer.enqueue(.input(.key(exitKey)))
      #expect(
        try runLoop.processPendingEventsSynchronously(
          from: .init(
            stream: AsyncStream { $0.finish() }, drainEvents: { buffer.drain() },
            hasPendingEvents: { buffer.hasPendingEvents() }, cancel: {},
            scheduleDeadlineWake: { _ in }), renderedFrames: &frames) == .userExit(exitKey))
    } else {
      #expect(try await runLoop.run().exitReason == .userExit(exitKey))
    }
    #expect(recorder.checkedVeto)
    #expect(recorder.requests == [.userExit(exitKey), .userExit(exitKey)])
    #expect(surface.frames.last?.contains("value 2") == true)
  }

  @Test("default exit binding is Ctrl+C alone; Ctrl+D is left to apps")
  func defaultExitBindingUsesCtrlC() {
    #expect(ExitKeyBindings.default.contains(KeyPress(.character("c"), modifiers: .ctrl)))
    #expect(!ExitKeyBindings.default.contains(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(ExitKeyBindings.default.keys.count == 1)
  }

  @Test("onTerminationRequest receives signal exits")
  func terminationRequestReceivesSignals() async throws {
    let recorder = TerminationRecorder()

    let result = try await runTerminationHarness(
      signals: ["SIGTERM"]
    ) { request in
      recorder.requests.append(request)
      return .allow
    }

    #expect(result.exitReason == .signal("SIGTERM"))
    #expect(recorder.requests == [.signal("SIGTERM")])
  }

  @Test("environment action requests programmatic termination")
  func environmentActionRequestsTermination() async throws {
    let recorder = TerminationRecorder()
    let rootIdentity = testIdentity("ProgrammaticTerminationRoot")
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: TerminationTestTerminalHost(),
      terminalInputReader: TerminationTestInputReader(
        events: [],
        finishAfterEvents: false
      ),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      viewBuilder: { _, _ in
        ProgrammaticTerminationFixture()
          .onTerminationRequest { request in
            recorder.requests.append(request)
            return .allow
          }
      }
    )

    let result = try await runLoop.run()
    #expect(result.exitReason == .programmatic)
    #expect(recorder.requests == [.programmatic])
  }

  @Test("synchronous event pump consumes programmatic termination")
  func synchronousEventPumpConsumesProgrammaticTermination() throws {
    let rootIdentity = testIdentity("SynchronousProgrammaticTerminationRoot")
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: TerminationTestTerminalHost(),
      terminalInputReader: TerminationTestInputReader(
        events: [],
        finishAfterEvents: false
      ),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      viewBuilder: { _, _ in Text("Root") }
    )
    runLoop.isSessionActive = true
    defer { runLoop.isSessionActive = false }
    let eventPump = runLoop.makeEventPump()
    defer { eventPump.cancel() }

    #expect(runLoop.runtimeRequestTerminationAction()())
    var renderedFrames = 0
    #expect(
      try runLoop.processPendingEventsSynchronously(
        from: eventPump,
        renderedFrames: &renderedFrames
      ) == .programmatic
    )
  }

  @Test("signal exit is honored promptly during a self-invalidating animation")
  func signalExitIsBoundedDuringSelfInvalidatingAnimation() async throws {
    let rootIdentity = testIdentity("TerminationAnimationRoot")
    let signalReader = InProcessSignalReader()
    let progress = AnimationProgressBox()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: TerminationTestTerminalHost(),
      terminalInputReader: TerminationTestInputReader(
        events: [],
        finishAfterEvents: false
      ),
      signalReader: signalReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      viewBuilder: { _, _ in
        SelfInvalidatingAnimationFixture(
          signalReader: signalReader,
          progress: progress
        )
      }
    )

    let result = try await runLoop.run()

    // The exit flush is frame-bounded: the signal must end the run loop
    // while the fixture animation still has iterations left. An unbounded
    // flush keeps consuming the animation's invalidation-caused ready
    // frames (the deadline-arm cut cannot withhold them) and only exits
    // once the animation runs dry.
    #expect(result.exitReason == .signal("SIGTERM"))
    #expect(!progress.finished.withLock { $0 })
  }

  @Test("onTerminationRequest is notified when input ends")
  func terminationRequestReceivesInputEnded() async throws {
    let recorder = TerminationRecorder()

    let result = try await runTerminationHarness { request in
      recorder.requests.append(request)
      return .cancel
    }

    #expect(result.exitReason == .inputEnded)
    #expect(recorder.requests == [.inputEnded])
  }
}

private final class TerminationRecorder {
  var requests: [TerminationRequest] = []
  var activeTasks: (@MainActor () -> Int)?
  var checkedVeto = false
}

private struct ProgrammaticTerminationFixture: View {
  @Environment(\.requestTermination) private var requestTermination

  var body: some View {
    Text("requesting termination")
      .task { _ = requestTermination() }
  }
}

private struct ExitFlushTerminationFixture: View {
  let value: Int
  @Environment(\.requestTermination) private var requestTermination
  var body: some View {
    Text("value \(value)").onChange(of: value) { _, _ in requestTermination() }
  }
}

@MainActor
private func runTerminationHarness(
  events: [InputEvent] = [],
  signals: [String] = [],
  handler: @escaping @MainActor @Sendable (TerminationRequest) -> TerminationDisposition
) async throws -> RunLoopResult<Int> {
  let rootIdentity = testIdentity("TerminationRoot")
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: TerminationTestTerminalHost(),
    terminalInputReader: TerminationTestInputReader(
      events: events,
      finishAfterEvents: signals.isEmpty
    ),
    signalReader: TerminationTestSignalReader(signals: signals),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
    viewBuilder: { _, _ in
      Text("Root")
        .onTerminationRequest(perform: handler)
    }
  )
  return try await runLoop.run()
}

private final class AnimationProgressBox: Sendable {
  let finished = Mutex<Bool>(false)
}

private struct ButtonTerminationFixture: View {
  @Environment(\.requestTermination) private var requestTermination
  var body: some View {
    Button("Quit") { requestTermination() }
  }
}

/// Drives an invalidation-caused frame per iteration — the frame source the
/// deadline-arm cut cannot bound — and raises SIGTERM mid-animation.
private struct SelfInvalidatingAnimationFixture: View {
  let signalReader: InProcessSignalReader
  let progress: AnimationProgressBox
  @State private var count = 0

  var body: some View {
    Text("tick \(count)")
      .task {
        for iteration in 0..<400 {
          count = iteration
          if iteration == 50 {
            signalReader.send("SIGTERM")
          }
          await Task.yield()
        }
        progress.finished.withLock { $0 = true }
      }
  }
}

private final class TerminationTestTerminalHost: PresentationSurface {
  var frames: [String] = []
  var surfaceSize: CellSize { CellSize(width: 20, height: 4) }
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    frames.append(TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface))
    return TerminalPresentationMetrics.fullRepaint(
      for: surface,
      capabilityProfile: capabilityProfile
    )
  }
}

private final class TerminationTestInputReader: TerminalInputReading {
  let events: [InputEvent]
  let finishAfterEvents: Bool

  init(events: [InputEvent], finishAfterEvents: Bool = true) {
    self.events = events
    self.finishAfterEvents = finishAfterEvents
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in events {
        continuation.yield(event)
      }
      if finishAfterEvents {
        continuation.finish()
      }
    }
  }
}

private final class TerminationTestSignalReader: SignalReading {
  let signals: [String]

  init(signals: [String]) {
    self.signals = signals
  }

  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      for signal in signals {
        continuation.yield(signal)
      }
      continuation.finish()
    }
  }
}

@MainActor
private final class SignalExitFrameSink: FrameDiagnosticSink {
  let scheduler: FrameScheduler
  let root: Identity
  init(scheduler: FrameScheduler, root: Identity) {
    self.scheduler = scheduler
    self.root = root
  }
  func record(_ sample: RuntimeFrameSample) {
    scheduler.requestInvalidation(of: [root])
  }
}
