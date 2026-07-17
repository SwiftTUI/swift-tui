@_spi(Runners) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
import Synchronization
import Testing

@testable import SwiftTUICLI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

#if canImport(SwiftTUIVendorUnixSignals)
  import SwiftTUIVendorUnixSignals
#endif

@Suite
@MainActor
struct SignalReaderArmingTests {
  #if canImport(SwiftTUIVendorUnixSignals) && canImport(Darwin)
    /// A signal delivered after arming but before the run loop starts
    /// consuming events must be buffered, not dropped: arming registers the
    /// kqueue sources with the kernel before returning. SIGCONT is used
    /// because no other suite traps it and its default disposition is
    /// harmless if a raise ever leaks.
    @Test(.timeLimit(.minutes(1)))
    func armedReaderBuffersSignalRaisedBeforeConsumption() async {
      let reader = SignalReader(signals: [.sigcont])
      await reader.armSignalSources()
      kill(getpid(), UnixSignal.sigcont.rawValue)  // ignore-unacceptable-language

      var caught: String?
      for await name in reader.events() {
        caught = name
        break
      }
      #expect(caught == "SIGCONT")
    }
  #endif

  @Test("Primary scene arms signal sources before the session runs")
  func primarySceneArmsSignalSourcesBeforeSessionRuns() async throws {
    let selection = collectWindowSceneSelections(
      from: WindowGroup("Primary", id: WindowIdentifier("primary")) {
        Text("Primary")
      }
    )[0]

    let reader = ArmRecordingSignalReader()
    let armedWhenSessionRan = Mutex<Bool?>(nil)
    let runtime = try SceneRuntime(
      selection: selection,
      isPrimary: true,
      resources: SceneSessionResources(
        presentationSurface: MetricsOnlyPresentationSurface(),
        terminalInputReader: EmptyTerminalInputReader(),
        signalReader: reader
      ),
      sessionRunner: { _, _ in
        armedWhenSessionRan.withLock { $0 = reader.isArmed }
        return RunLoopResult(
          finalState: SceneSessionState(),
          renderedFrames: 0,
          exitReason: .inputEnded
        )
      }
    )

    _ = try await runtime.run(sessionName: "signal-arming")
    #expect(armedWhenSessionRan.withLock { $0 } == true)
  }
}

private final class ArmRecordingSignalReader: SignalReading, SignalSourceArming, Sendable {
  private let armed = Mutex<Bool>(false)

  var isArmed: Bool {
    armed.withLock { $0 }
  }

  func armSignalSources() async {
    armed.withLock { $0 = true }
  }

  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class MetricsOnlyPresentationSurface: PresentationSurfaceMetricsProvider {
  let surfaceSize = CellSize(width: 40, height: 12)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let theme: Theme? = nil
  let graphicsCapabilities: TerminalGraphicsCapabilities = .none
  let pointerInputCapabilities = PointerInputCapabilities()
}

private final class EmptyTerminalInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
