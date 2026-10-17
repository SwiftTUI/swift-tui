// Adversarial set B: run-loop exit and termination ordering.
//
// Probes the seams behind the Sept–Oct 2026 reports: programmatic termination
// requests raised while an exit is already resolving or flushing (STUI-917,
// STUI-919, and the exit-flush consumption fix), exit keys that share a drained
// batch with other input, case-folded Ctrl+letter bindings, signals raised
// during the exit flush, and pending ESC bytes at end of input (STUI-510 parity).

@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: exit and termination", .serialized, .timeLimit(.minutes(1)))
struct AdversarialSetBExitTests {
  @Test func setB071ExitKeyFirstInBatchDropsLaterProgrammaticTrigger() async throws {
    let recorder = SetBTerminationRecorder()
    let box = SetBActionBox()
    let exitKey = SetBKeys.ctrlC
    let input = SetBPullingInputReader()
    input.send(.key(exitKey))
    input.send(.key(KeyPress(.space)))
    defer { input.finish() }
    let root = testIdentity("SetBExit", "ExitFirstInBatch")
    let surface = SetBTerminalHost()
    let runLoop = RunLoop(
      rootIdentity: root,
      presentationSurface: surface,
      terminalInputReader: input,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      keyHandler: { key, _, _ in
        guard key == KeyPress(.space) else { return .ignored }
        recorder.quitTaps += 1
        recorder.quitAccepted = box.action?() ?? false
        return .handled
      },
      viewBuilder: { value, _ in
        SetBProgrammaticFixture(
          value: value, recorder: recorder, box: box, vetoUserExit: false)
      })

    let result = try await runLoop.run()

    // The exit resolves at the first event; nothing after it in the batch runs.
    #expect(result.exitReason == .userExit(exitKey))
    #expect(recorder.requests == [.userExit(exitKey)])
    #expect(recorder.quitTaps == 0)
    #expect(!recorder.quitAccepted)
    #expect(result.renderedFrames == 1)
    #expect(surface.frames.count == 1)
    #expect(!runLoop.hasPendingProgrammaticTermination)
    #expect(!runLoop.isSessionActive)
  }

  @Test func setB072VetoedExitKeyLetsLaterBatchedProgrammaticRequestExit() async throws {
    let recorder = SetBTerminationRecorder()
    let box = SetBActionBox()
    let exitKey = SetBKeys.ctrlC
    let input = SetBPullingInputReader()
    input.send(.key(exitKey))
    input.send(.key(KeyPress(.space)))
    defer { input.finish() }
    let root = testIdentity("SetBExit", "VetoThenProgrammatic")
    let surface = SetBTerminalHost()
    let runLoop = RunLoop(
      rootIdentity: root,
      presentationSurface: surface,
      terminalInputReader: input,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      keyHandler: { key, _, _ in
        guard key == KeyPress(.space) else { return .ignored }
        recorder.quitTaps += 1
        recorder.quitAccepted = box.action?() ?? false
        return .handled
      },
      viewBuilder: { value, _ in
        SetBProgrammaticFixture(
          value: value, recorder: recorder, box: box, vetoUserExit: true)
      })

    let result = try await runLoop.run()

    // The veto keeps the batch alive, so the Space reaches the handler and its
    // request is dispatched after the ordinary post-batch frame.
    #expect(recorder.quitTaps == 1)
    #expect(recorder.quitAccepted)
    #expect(recorder.requests == [.userExit(exitKey), .programmatic])
    #expect(result.exitReason == .programmatic)
    #expect(result.renderedFrames == 2)
    #expect(surface.frames.count == 2)
    #expect(!runLoop.hasPendingProgrammaticTermination)
  }

  @Test func setB073TerminationHandlerReenteringRequestTerminationIsDispatched() async throws {
    let exitKey = SetBKeys.ctrlC
    for vetoReentry in [false, true] {
      let recorder = SetBTerminationRecorder()
      let input = SetBPullingInputReader()
      input.send(.key(exitKey))
      defer { input.finish() }
      let root = testIdentity("SetBExit", "ReentrantHandler")
      let runLoop = RunLoop(
        rootIdentity: root,
        presentationSurface: SetBTerminalHost(),
        terminalInputReader: input,
        scheduler: FrameScheduler(),
        stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
        focusTracker: FocusTracker(invalidationIdentities: [root]),
        viewBuilder: { _, _ in
          SetBReentrantFixture(recorder: recorder, vetoReentry: vetoReentry)
        })

      let result = try await runLoop.run()

      // A request raised inside the exit-key disposition is a live request:
      // it is dispatched once, after the accepted exit, and its own veto
      // leaves the already accepted exit in force.
      #expect(recorder.reentryResults == [true], "veto=\(vetoReentry)")
      #expect(
        recorder.requests == [.userExit(exitKey), .programmatic], "veto=\(vetoReentry)")
      #expect(
        result.exitReason == (vetoReentry ? .userExit(exitKey) : .programmatic),
        "veto=\(vetoReentry)")
      #expect(!runLoop.hasPendingProgrammaticTermination, "veto=\(vetoReentry)")
      #expect(!runLoop.isSessionActive, "veto=\(vetoReentry)")
    }
  }

  @Test func setB074SelfRetriggeringOnChangeChainIsBoundedDuringExitFlush() async throws {
    let recorder = SetBTerminationRecorder()
    let exitKey = SetBKeys.ctrlC
    let input = SetBPullingInputReader()
    input.send(.key(KeyPress(.return)))
    input.send(.key(exitKey))
    defer { input.finish() }
    let root = testIdentity("SetBExit", "OnChangeChain")
    let surface = SetBTerminalHost()
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
      viewBuilder: { value, _ in
        SetBChainFixture(value: value, recorder: recorder)
      })

    let result = try await runLoop.run()

    // The handled input and its first lifecycle follow-up are presented; a
    // chain that never settles is cut at the drain-pass acquisition bound.
    let bound = type(of: runLoop).maxFramesPerDrainPass
    #expect(result.exitReason == .userExit(exitKey))
    #expect(result.finalState == 1)
    #expect(result.renderedFrames >= 3)
    #expect(result.renderedFrames <= 1 + bound)
    #expect(recorder.chainWrites <= bound)
    #expect(surface.frames.count == result.renderedFrames)
    #expect(surface.frames.last?.contains("value 1") == true)
    #expect(!runLoop.isSessionActive)
  }

  @Test func setB075UppercaseControlBindingMatchesRawControlByteOnly() async throws {
    let binding = KeyPress(.character("Z"), modifiers: .ctrl)
    let ctrlZ = KeyPress(.character("z"), modifiers: .ctrl)
    let ctrlShiftZ = KeyPress(.character("Z"), modifiers: [.ctrl, .shift])
    struct Probe {
      let label: String
      let script: (InjectedTerminalInputReader) -> Void
      let expectedExit: RunLoopExitReason
      let expectedKeys: [KeyPress]
    }
    let probes = [
      Probe(
        label: "raw 0x1A exits as the pressed lowercase chord",
        script: { $0.send([0x1A]) },
        expectedExit: .userExit(ctrlZ),
        expectedKeys: []),
      Probe(
        label: "lowercase Ctrl+z event matches the uppercase binding",
        script: { $0.send(.key(ctrlZ)) },
        expectedExit: .userExit(ctrlZ),
        expectedKeys: []),
      Probe(
        label: "bare z is not an exit",
        script: {
          $0.send([0x7A])
          $0.finish()
        },
        expectedExit: .inputEnded,
        expectedKeys: [KeyPress(.character("z"))]),
      Probe(
        label: "Ctrl+Shift+Z is not an exit",
        script: {
          $0.send(.key(ctrlShiftZ))
          $0.finish()
        },
        expectedExit: .inputEnded,
        expectedKeys: [ctrlShiftZ]),
    ]

    for probe in probes {
      let recorder = SetBTerminationRecorder()
      let input = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      probe.script(input)
      defer { input.finish() }
      let root = testIdentity("SetBExit", "UppercaseControlBinding")
      let runLoop = RunLoop(
        rootIdentity: root,
        presentationSurface: SetBTerminalHost(),
        terminalInputReader: input,
        scheduler: FrameScheduler(),
        stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
        focusTracker: FocusTracker(invalidationIdentities: [root]),
        keyHandler: { key, _, _ in
          recorder.keys.append(key)
          return .ignored
        },
        exitKeyBindings: ExitKeyBindings([binding]),
        viewBuilder: { _, _ in Text("binding probe") })

      let result = try await runLoop.run()

      #expect(result.exitReason == probe.expectedExit, "\(probe.label)")
      #expect(recorder.keys == probe.expectedKeys, "\(probe.label)")
    }
  }

  @Test func setB076PendingEscapePrefixBeforeFinishResolvesLikeStdinEOF() async throws {
    let altA = KeyPress(.character("a"), modifiers: .alt)
    let altO = KeyPress(.character("O"), modifiers: .alt)
    struct Probe {
      let label: String
      let bytes: [UInt8]
      let expectedExit: RunLoopExitReason
      let expectedKeys: [KeyPress]
    }
    let probes = [
      Probe(
        label: "lone ESC commits to Escape at end of input",
        bytes: [0x1B],
        expectedExit: .userExit(KeyPress(.escape)),
        expectedKeys: []),
      Probe(
        label: "completed Alt chord arrives before end of input",
        bytes: [0x1B, 0x61],
        expectedExit: .inputEnded,
        expectedKeys: [altA]),
      Probe(
        label: "incomplete SS3 prefix resolves to Alt+O at end of input",
        bytes: [0x1B, 0x4F],
        expectedExit: .inputEnded,
        expectedKeys: [altO]),
    ]

    for probe in probes {
      let recorder = SetBTerminationRecorder()
      let input = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      input.send(probe.bytes)
      input.finish()
      let root = testIdentity("SetBExit", "EscapeAtFinish")
      let runLoop = RunLoop(
        rootIdentity: root,
        presentationSurface: SetBTerminalHost(),
        terminalInputReader: input,
        scheduler: FrameScheduler(),
        stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
        focusTracker: FocusTracker(invalidationIdentities: [root]),
        keyHandler: { key, _, _ in
          recorder.keys.append(key)
          return .ignored
        },
        exitKeyBindings: ExitKeyBindings([KeyPress(.escape)]),
        viewBuilder: { _, _ in Text("escape probe") })

      let result = try await runLoop.run()

      // The stdin reader resolves a pending escape prefix at EOF (STUI-510);
      // an injected reader that ends its input owes the same resolution.
      do {
        #expect(result.exitReason == probe.expectedExit, "\(probe.label)")
        #expect(recorder.keys == probe.expectedKeys, "\(probe.label)")
      }
    }
  }

  @Test func setB077EndOfInputIgnoresHandlerCancelAndTearsDownSession() async throws {
    let recorder = SetBTerminationRecorder()
    let box = SetBActionBox()
    let root = testIdentity("SetBExit", "ImmediateEOF")
    let surface = SetBTerminalHost()
    let state = StateContainer(initialState: 0, invalidationIdentities: [root])
    let runLoop = RunLoop(
      rootIdentity: root,
      presentationSurface: surface,
      terminalInputReader: SetBStreamInputReader(events: [], finishAfterEvents: true),
      signalReader: SetBSignalReader(signals: []),
      scheduler: FrameScheduler(),
      stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      viewBuilder: { value, _ in
        SetBEndOfInputFixture(value: value, recorder: recorder, state: state, box: box)
      })

    let result = try await runLoop.run()

    // Handlers are notified for end of input, but cannot keep the session
    // alive; the session still tears down completely.
    #expect(result.exitReason == .inputEnded)
    #expect(recorder.requests == [.inputEnded])
    #expect(result.finalState == 9)
    #expect(result.renderedFrames == surface.frames.count)
    #expect(surface.rawModeEvents == ["enable", "disable"])
    #expect(!runLoop.isSessionActive)
    #expect(runLoop.lifecycleCoordinator.activeTaskCount == 0)
    #expect(box.action != nil)
    #expect(box.action?() == false)
    #expect(!runLoop.hasPendingProgrammaticTermination)
  }

  @Test func setB078VetoedSIGTERMThenSIGINTDispatchesBothAndExitsOnSecond() async throws {
    for cancelFirst in [false, true] {
      let recorder = SetBTerminationRecorder()
      let root = testIdentity("SetBExit", "SignalPair")
      let surface = SetBTerminalHost()
      let runLoop = RunLoop(
        rootIdentity: root,
        presentationSurface: surface,
        terminalInputReader: SetBStreamInputReader(events: [], finishAfterEvents: false),
        signalReader: SetBSignalReader(signals: ["SIGTERM", "SIGINT"]),
        scheduler: FrameScheduler(),
        stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
        focusTracker: FocusTracker(invalidationIdentities: [root]),
        viewBuilder: { _, _ in
          Text("signal pair").onTerminationRequest { request in
            recorder.requests.append(request)
            if cancelFirst, request == .signal("SIGTERM") {
              return .cancel
            }
            return .allow
          }
        })

      let result = try await runLoop.run()

      if cancelFirst {
        // The veto re-renders, then the second signal ends the session with a
        // single-acquisition flush.
        #expect(result.exitReason == .signal("SIGINT"))
        #expect(recorder.requests == [.signal("SIGTERM"), .signal("SIGINT")])
        #expect(result.renderedFrames == 2)
      } else {
        // The first accepted signal exits; the queued second signal is never
        // dispatched.
        #expect(result.exitReason == .signal("SIGTERM"))
        #expect(recorder.requests == [.signal("SIGTERM")])
        #expect(result.renderedFrames == 1)
      }
      #expect(surface.frames.count == result.renderedFrames, "cancelFirst=\(cancelFirst)")
      #expect(!runLoop.isSessionActive, "cancelFirst=\(cancelFirst)")
    }
  }

  @Test func setB079ResizeSignalRaisedDuringExitFlushIsNotDrained() async throws {
    let exitKey = SetBKeys.ctrlC
    let signals = InProcessSignalReader()
    defer { signals.finish() }
    let surface = SetBTerminalHost()
    let sink = SetBResizeOnCommitSink(surface: surface, signals: signals)
    let input = SetBPullingInputReader()
    input.send(.key(KeyPress(.return)))
    input.send(.key(exitKey))
    defer { input.finish() }
    let root = testIdentity("SetBExit", "ResizeDuringFlush")
    let runLoop = RunLoop(
      rootIdentity: root,
      presentationSurface: surface,
      terminalInputReader: input,
      signalReader: signals,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      keyHandler: { key, _, state in
        guard key == KeyPress(.return) else { return .ignored }
        sink.isArmed = true
        state.mutate { $0 += 1 }
        return .handled
      },
      viewBuilder: { value, _ in Text("value \(value)") })
    runLoop.frameSink = sink

    let result = try await runLoop.run()

    // The flush presents the handled input exactly once; a resize signal that
    // lands during that presentation is unrelated late work and stays undrained.
    #expect(result.exitReason == .userExit(exitKey))
    #expect(sink.fired)
    #expect(result.renderedFrames == 2)
    #expect(surface.frames.count == 2)
    #expect(surface.frameSizes == [SetBTerminalHost.initialSize, SetBTerminalHost.initialSize])
    #expect(surface.frames.last?.contains("value 1") == true)
    #expect(!runLoop.isSessionActive)
  }

  @Test func setB080HandlerMountedByExitFlushFrameReceivesOnlyLateRequest() async throws {
    let exitKey = SetBKeys.ctrlC
    for vetoProgrammatic in [false, true] {
      let recorder = SetBTerminationRecorder()
      let input = SetBPullingInputReader()
      input.send(.key(KeyPress(.return)))
      input.send(.key(exitKey))
      defer { input.finish() }
      let root = testIdentity("SetBExit", "LateHandler")
      let surface = SetBTerminalHost()
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
        viewBuilder: { value, _ in
          SetBLateHandlerFixture(
            value: value, recorder: recorder, vetoProgrammatic: vetoProgrammatic)
        })

      let result = try await runLoop.run()

      // The handler does not exist when the exit key is resolved, so it never
      // sees that request; it is live by the time the flush frame's onChange
      // raises the programmatic request, which it must receive.
      #expect(result.finalState == 1, "veto=\(vetoProgrammatic)")
      #expect(surface.frames.last?.contains("armed") == true, "veto=\(vetoProgrammatic)")
      #expect(recorder.requests == [.programmatic], "veto=\(vetoProgrammatic)")
      #expect(
        result.exitReason == (vetoProgrammatic ? .userExit(exitKey) : .programmatic),
        "veto=\(vetoProgrammatic)")
      #expect(!runLoop.hasPendingProgrammaticTermination, "veto=\(vetoProgrammatic)")
    }
  }
}

// MARK: - Keys

private enum SetBKeys {
  static let ctrlC = KeyPress(.character("c"), modifiers: .ctrl)
}

// MARK: - Recorders

@MainActor
private final class SetBTerminationRecorder {
  var requests: [TerminationRequest] = []
  var keys: [KeyPress] = []
  var quitTaps = 0
  var quitAccepted = false
  var reentryResults: [Bool] = []
  var chainWrites = 0
}

@MainActor
private final class SetBActionBox {
  var action: RequestTerminationAction?
}

// MARK: - Fixtures

private struct SetBProgrammaticFixture: View {
  let value: Int
  let recorder: SetBTerminationRecorder
  let box: SetBActionBox
  let vetoUserExit: Bool
  @Environment(\.requestTermination) private var requestTermination

  var body: some View {
    Text("value \(value)")
      .onAppear { box.action = requestTermination }
      .onTerminationRequest { request in
        recorder.requests.append(request)
        if vetoUserExit, case .userExit = request {
          return .cancel
        }
        return .allow
      }
  }
}

private struct SetBReentrantFixture: View {
  let recorder: SetBTerminationRecorder
  let vetoReentry: Bool
  @Environment(\.requestTermination) private var requestTermination

  var body: some View {
    Text("reentrant").onTerminationRequest { request in
      recorder.requests.append(request)
      switch request {
      case .userExit:
        recorder.reentryResults.append(requestTermination())
        return .allow
      case .programmatic:
        return vetoReentry ? .cancel : .allow
      case .signal, .inputEnded:
        return .allow
      }
    }
  }
}

private struct SetBChainFixture: View {
  let value: Int
  let recorder: SetBTerminationRecorder
  @State private var chain = 0

  var body: some View {
    Text("value \(value) chain \(chain)")
      .onChange(of: value) { _, _ in
        chain += 1
      }
      .onChange(of: chain) { _, _ in
        recorder.chainWrites += 1
        chain += 1
      }
  }
}

private struct SetBEndOfInputFixture: View {
  let value: Int
  let recorder: SetBTerminationRecorder
  let state: StateContainer<Int>
  let box: SetBActionBox
  @Environment(\.requestTermination) private var requestTermination

  var body: some View {
    Text("value \(value)")
      .onAppear { box.action = requestTermination }
      .task { await suspendUntilCancelled() }
      .onTerminationRequest { request in
        recorder.requests.append(request)
        state.mutate { $0 = 9 }
        return .cancel
      }
  }
}

private struct SetBLateHandlerFixture: View {
  let value: Int
  let recorder: SetBTerminationRecorder
  let vetoProgrammatic: Bool
  @Environment(\.requestTermination) private var requestTermination

  var body: some View {
    VStack {
      Text("value \(value)")
      if value > 0 {
        Text("armed").onTerminationRequest { request in
          recorder.requests.append(request)
          return vetoProgrammatic && request == .programmatic ? .cancel : .allow
        }
      }
    }
    .onChange(of: value) { _, _ in requestTermination() }
  }
}

// MARK: - Frame sink

@MainActor
private final class SetBResizeOnCommitSink: FrameDiagnosticSink {
  private let surface: SetBTerminalHost
  private let signals: InProcessSignalReader
  var isArmed = false
  private(set) var fired = false

  init(surface: SetBTerminalHost, signals: InProcessSignalReader) {
    self.surface = surface
    self.signals = signals
  }

  func record(_ sample: RuntimeFrameSample) {
    guard case .committed = sample, isArmed, !fired else { return }
    fired = true
    surface.surfaceSize = CellSize(width: 12, height: 2)
    signals.send("SIGWINCH")
  }
}

// MARK: - Terminal host

private final class SetBTerminalHost: PresentationSurface {
  static let initialSize = CellSize(width: 30, height: 3)
  var surfaceSize = SetBTerminalHost.initialSize
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

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let output = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    frames.append(String(output.filter { $0 != "\r" }))
    frameSizes.append(surface.size)
    return .fullRepaint(for: surface, capabilityProfile: capabilityProfile)
  }
}

// MARK: - Input readers

/// One source pull forwards every queued event together, so a handled key and
/// the exit that follows it land in the same drained batch.
@MainActor
private final class SetBPullingInputReader: SynchronousInputPulling {
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

private final class SetBStreamInputReader: TerminalInputReading {
  let events: [InputEvent]
  let finishAfterEvents: Bool

  init(events: [InputEvent], finishAfterEvents: Bool) {
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

// MARK: - Signal reader

private final class SetBSignalReader: SignalReading {
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
