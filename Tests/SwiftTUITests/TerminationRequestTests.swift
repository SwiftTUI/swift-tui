import Testing

@testable import SwiftTUIRuntime
@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite("Termination requests")
struct TerminationRequestTests {
  @Test("onTerminationRequest can cancel an exit key and allow a later one")
  func terminationRequestCanCancelExitKey() async throws {
    let recorder = TerminationRecorder()
    let exitKey = KeyPress(.character("d"), modifiers: .ctrl)

    let result = try await runTerminationHarness(
      events: [.key(exitKey), .key(exitKey)]
    ) { request in
      recorder.requests.append(request)
      return recorder.requests.count == 1 ? .cancel : .allow
    }

    #expect(result.exitReason == .userExit(exitKey))
    #expect(recorder.requests == [.userExit(exitKey), .userExit(exitKey)])
  }

  @Test("default exit binding is Ctrl+D and leaves Ctrl+C for app shortcuts")
  func defaultExitBindingUsesCtrlD() {
    #expect(ExitKeyBindings.default.contains(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(!ExitKeyBindings.default.contains(KeyPress(.character("c"), modifiers: .ctrl)))
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
    terminalInputReader: TerminationTestInputReader(events: events),
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
