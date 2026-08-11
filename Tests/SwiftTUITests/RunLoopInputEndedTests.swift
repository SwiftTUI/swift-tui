@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Five minutes is the cadence-suite hang bound, not an expectation: on the
// degraded amd64 CI runner class (swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md entry 12) these
// EOF exits run 60–120 s wall under parallel-gate load, and a one-minute
// limit turned starvation into a deterministic red.
@MainActor
@Suite(.timeLimit(.minutes(5)))
struct RunLoopInputEndedTests {
  @Test("input EOF exits while the production-shaped signal stream stays live")
  func inputEOFExitsWithLiveSignalReader() async throws {
    let harness = InputEndedHarness(events: [
      .key(KeyPress(.character("a"))),
      .key(KeyPress(.character("b"))),
    ])

    let result = try await harness.run()

    #expect(result.exitReason == .inputEnded)
    #expect(result.finalState == 2)
  }

  @Test("input EOF flushes the final input-driven frame before exit")
  func inputEOFFlushesFinalInputFrame() async throws {
    let harness = InputEndedHarness(events: [
      .key(KeyPress(.character("a"))),
      .key(KeyPress(.character("b"))),
    ])

    let result = try await harness.run()

    #expect(result.exitReason == .inputEnded)
    #expect(harness.host.frames.last?.contains("value:2") == true)
  }

  @Test("input EOF notifies a cancelling termination handler exactly once and still exits")
  func inputEOFCannotBeCancelled() async throws {
    let harness = InputEndedHarness(
      events: [],
      terminationDisposition: .cancel
    )

    let result = try await harness.run()

    #expect(result.exitReason == .inputEnded)
    #expect(harness.terminationProbe.requests == [.inputEnded])
  }
}

@MainActor
private final class InputEndedHarness {
  let host = InputEndedRecordingHost()
  let terminationProbe: InputEndedTerminationProbe
  let runLoop: RunLoop<Int, InputEndedHarnessView>

  init(
    events: [InputEvent],
    terminationDisposition: TerminationDisposition = .allow
  ) {
    let rootIdentity = testIdentity("InputEndedRoot")
    let terminationProbe = InputEndedTerminationProbe(disposition: terminationDisposition)
    self.terminationProbe = terminationProbe
    runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: FinishingInputReader(events: events),
      signalReader: NeverEndingSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { _, _, stateContainer in
        stateContainer.mutate { $0 += 1 }
        return .handled
      },
      exitKeyBindings: .none,
      viewBuilder: { state, _ in
        InputEndedHarnessView(value: state, terminationProbe: terminationProbe)
      }
    )
  }

  func run() async throws -> RunLoopResult<Int> {
    try await runLoop.run()
  }
}

private struct InputEndedHarnessView: View {
  let value: Int
  let terminationProbe: InputEndedTerminationProbe

  var body: some View {
    Text("value:\(value)")
      .onTerminationRequest { request in
        terminationProbe.requests.append(request)
        return terminationProbe.disposition
      }
  }
}

@MainActor
private final class InputEndedTerminationProbe {
  let disposition: TerminationDisposition
  var requests: [TerminationRequest] = []

  init(disposition: TerminationDisposition) {
    self.disposition = disposition
  }
}

private final class FinishingInputReader: TerminalInputReading {
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

private final class NeverEndingSignalReader: SignalReading {
  private let stream: AsyncStream<String>
  private let continuation: AsyncStream<String>.Continuation

  init() {
    (stream, continuation) = AsyncStream<String>.makeStream()
  }

  deinit {
    continuation.finish()
  }

  func events() -> AsyncStream<String> {
    stream
  }
}

private final class InputEndedRecordingHost: PresentationSurface {
  let surfaceSize = CellSize(width: 20, height: 4)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  private(set) var frames: [String] = []

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    frames.append(surface.lines.joined(separator: "\n"))
    return .fullRepaint(for: surface, capabilityProfile: capabilityProfile)
  }
}
