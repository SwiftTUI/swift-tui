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
/// It drives the shared `ScriptedAutonomousWakeInputReader` + recording surface
/// from `SwiftTUITestSupport`: synchronization is direct, not timeout-polled (per
/// the test-sync ratchet) — the reader stays open across the wake via a poll-free
/// `MainActorConditionSignal.wait(until:)`, then quits with Ctrl-D → `.userExit`.
@MainActor
@Suite("Autonomous task wake on the terminal-input path")
struct AutonomousWakeTerminalInputTests {
  @Test("a .task state write presents a frame with no further terminal input")
  func taskStateWritePresentsFrameWithoutFurtherTerminalInput() async throws {
    let terminalSize = CellSize(width: 32, height: 8)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity("AutonomousWakeTerminalRoot")

    // No scripted input at all: the only step keeps the stream open until the
    // autonomous `.task` write lands its frame, then the reader quits with Ctrl+D.
    let inputReader = ScriptedAutonomousWakeInputReader(
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
      signalReader: ImmediateFinishSignalReader(),
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
