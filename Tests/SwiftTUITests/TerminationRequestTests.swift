import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Termination requests")
struct TerminationRequestTests {
  @Test("onTerminationRequest can cancel an exit key and allow a later one")
  func terminationRequestCanCancelExitKey() async throws {
    let recorder = TerminationRecorder()
    let exitKey = KeyPress(.character("c"), modifiers: .ctrl)

    let result = try await runTerminationHarness(
      events: [.key(exitKey), .key(exitKey)]
    ) { request in
      recorder.requests.append(request)
      return recorder.requests.count == 1 ? .cancel : .allow
    }

    #expect(result.exitReason == .userExit(exitKey))
    #expect(recorder.requests == [.userExit(exitKey), .userExit(exitKey)])
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
      return .allow
    }

    #expect(result.exitReason == .inputEnded)
    #expect(recorder.requests == [.inputEnded])
  }
}

private final class TerminationRecorder {
  var requests: [TerminationRequest] = []
}

private struct ProgrammaticTerminationFixture: View {
  @Environment(\.requestTermination) private var requestTermination

  var body: some View {
    Text("requesting termination")
      .task { _ = requestTermination() }
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
    TerminalPresentationMetrics.fullRepaint(
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
