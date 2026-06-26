import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Async task-driven runtime frames")
struct AsyncTaskDrivenFrameRuntimeTests {
  @Test("lifecycle task state write presents a frame without further input")
  func lifecycleTaskStateWritePresentsFrameWithoutFurtherInput() async throws {
    let terminal = RecordingPresentationSurface(
      surfaceSize: .init(width: 32, height: 8)
    )
    let rootIdentity = testIdentity("AsyncTaskDrivenLifecycleRoot")
    let inputReader = ScriptedAutonomousWakeInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .awaitCondition {
          terminal.frames.contains { $0.contains("task ready") }
        }
      ])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: inputReader,
      signalReader: ImmediateFinishSignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 32, height: 8),
      viewBuilder: { _, _ in
        AsyncLifecycleTaskFrameProbe()
      }
    )

    let result = try await runLoop.run()

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(terminal.frames.contains { $0.contains("task pending") })
    #expect(terminal.frames.contains { $0.contains("task ready") })
  }

  @Test("action-spawned task state write presents a frame after action returns")
  func actionSpawnedTaskStateWritePresentsFrameAfterActionReturns() async throws {
    let terminal = RecordingPresentationSurface(
      surfaceSize: .init(width: 32, height: 8)
    )
    let rootIdentity = testIdentity("AsyncTaskDrivenActionRoot")
    let inputReader = ScriptedAutonomousWakeInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.return)),
        .awaitCondition {
          terminal.frames.contains { $0.contains("action ready") }
        },
      ])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: inputReader,
      signalReader: ImmediateFinishSignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 32, height: 8),
      viewBuilder: { _, _ in
        AsyncActionTaskFrameProbe()
      }
    )

    let result = try await runLoop.run()

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(terminal.frames.contains { $0.contains("action idle") })
    #expect(terminal.frames.contains { $0.contains("action ready") })
  }
}

private struct AsyncLifecycleTaskFrameProbe: View {
  @State private var status = "pending"

  var body: some View {
    Text("task \(status)")
      .task(id: "load") {
        await Task.yield()
        status = "ready"
      }
  }
}

private struct AsyncActionTaskFrameProbe: View {
  @State private var status = "idle"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("action \(status)")
      Button("Start") {
        status = "loading"
        Task { @MainActor in
          await Task.yield()
          status = "ready"
        }
      }
    }
  }
}

// The recording surface, keep-open reader, and empty signal reader these tests
// used now live in SwiftTUITestSupport (ScriptedAutonomousWakeHarness) — shared
// with the terminal-input autonomous-wake test rather than duplicated per suite.
