import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Proves an **autonomous wake** on the *terminal-input* path: a `.task`-driven
/// `@State` write must present an extra committed frame through the real
/// `RunLoop` with **no further input**.
///
/// The capability itself is already exercised on the keyboard (`InputReading`)
/// path by `AsyncTaskDrivenFrameRuntimeTests`; the documented "wall" is only that
/// the loop exits when the input stream finishes. This covers the same capability
/// on the `TerminalInputReading` path — the one `runTerminalInputHarness` /
/// `ScriptedTerminalInputReader` use, where the scripted reader finishes
/// immediately and so cannot observe an autonomous wake.
///
/// Synchronization is direct, not timeout-polled (per the repo's test-sync
/// ratchet): the keep-open reader stays open via a poll-free
/// `MainActorConditionSignal.wait(until:)` that returns the instant the
/// autonomous frame commits, then yields Ctrl-D → `.userExit`. `onTermination`
/// cancels the driver task. This mirrors the proven `AsyncTaskDrivenFrameInputReader`
/// pattern exactly; a regression that breaks the wake is caught by the suite-level
/// timeout rather than a per-test sleep.
@MainActor
@Suite("Autonomous task wake on the terminal-input path")
struct AutonomousWakeTerminalInputTests {
  @Test("a .task state write presents a frame with no further terminal input")
  func taskStateWritePresentsFrameWithoutFurtherTerminalInput() async throws {
    let terminalSize = CellSize(width: 32, height: 8)
    let terminal = AutonomousWakeRecordingHost(surfaceSize: terminalSize)
    let rootIdentity = testIdentity("AutonomousWakeTerminalRoot")

    // No scripted input at all: the only step keeps the stream open until the
    // autonomous `.task` write lands its frame, then the reader quits with Ctrl+D.
    let inputReader = AutonomousWakeTerminalInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .awaitCondition {
          terminal.frames.contains { $0.contains("task ready") }
        }
      ]
    )

    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize

    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      signalReader: AutonomousWakeEmptySignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        AutonomousWakeTaskProbe()
      }
    )

    let result = try await runLoop.run()

    // The loop reached the quit key the reader yielded *after* the autonomous
    // frame — i.e. it stayed alive across the wake (not `.inputEnded`).
    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(terminal.frames.contains { $0.contains("task pending") })
    #expect(terminal.frames.contains { $0.contains("task ready") })
  }
}

private struct AutonomousWakeTaskProbe: View {
  @State private var status = "pending"

  var body: some View {
    Text("task \(status)")
      .task(id: "load") {
        await Task.yield()
        status = "ready"
      }
  }
}

/// Records every presented frame and pulses a `MainActorConditionSignal` so the
/// keep-open reader can wait for the autonomous frame poll-free. Mirrors the
/// proven `AsyncTaskDrivenFrameRecordingHost`.
private final class AutonomousWakeRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var frames: [String] = []

  let frameSignal = MainActorConditionSignal()

  init(
    surfaceSize: CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    ).render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
    return TerminalPresentationMetrics.fullRepaint(
      for: surface,
      capabilityProfile: capabilityProfile
    )
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
  }

  private func notifyFrameObservers() {
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }
}

private enum AutonomousWakeTerminalStep {
  case event(InputEvent)
  /// Keeps `inputEvents()` open until the predicate holds (the autonomous frame).
  case awaitCondition(predicate: @MainActor () -> Bool)
}

/// A `TerminalInputReading` double that keeps its stream open across an
/// autonomous wake (via a direct `MainActorConditionSignal`), then quits.
private final class AutonomousWakeTerminalInputReader: TerminalInputReading {
  private let steps: [AutonomousWakeTerminalStep]
  private let frameSignal: MainActorConditionSignal
  private let quitEvent: InputEvent

  init(
    frameSignal: MainActorConditionSignal,
    steps: [AutonomousWakeTerminalStep],
    quitEvent: InputEvent = .key(KeyPress(.character("d"), modifiers: .ctrl))
  ) {
    self.frameSignal = frameSignal
    self.steps = steps
    self.quitEvent = quitEvent
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let quitEvent = self.quitEvent

      // Walk the steps, staying open across the autonomous wake via
      // `frameSignal.wait`, then quit. Never finish in the same step as a scripted
      // event, or the loop would exit `.inputEnded` before the wake lands.
      let driver = Task { @MainActor in
        for step in steps {
          switch step {
          case .event(let event):
            continuation.yield(event)
          case .awaitCondition(let predicate):
            await frameSignal.wait(until: predicate)
          }
        }
        continuation.yield(quitEvent)
        continuation.finish()
      }

      continuation.onTermination = { _ in
        driver.cancel()
      }
    }
  }
}

private final class AutonomousWakeEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
