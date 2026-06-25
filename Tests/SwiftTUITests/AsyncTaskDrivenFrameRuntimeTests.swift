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
    let terminal = AsyncTaskDrivenFrameRecordingHost(
      surfaceSize: .init(width: 32, height: 8)
    )
    let rootIdentity = testIdentity("AsyncTaskDrivenLifecycleRoot")
    let inputReader = AsyncTaskDrivenFrameInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .awaitCondition {
          terminal.frames.contains { $0.contains("task ready") }
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: inputReader,
      signalReader: AsyncTaskDrivenFrameEmptySignalReader(),
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

    let result = try await valueWithTimeout("lifecycle task-driven frame") {
      try await runLoop.run()
    }

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(terminal.frames.contains { $0.contains("task pending") })
    #expect(terminal.frames.contains { $0.contains("task ready") })
  }

  @Test("action-spawned task state write presents a frame after action returns")
  func actionSpawnedTaskStateWritePresentsFrameAfterActionReturns() async throws {
    let terminal = AsyncTaskDrivenFrameRecordingHost(
      surfaceSize: .init(width: 32, height: 8)
    )
    let rootIdentity = testIdentity("AsyncTaskDrivenActionRoot")
    let inputReader = AsyncTaskDrivenFrameInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .press(KeyPress(.return)),
        .awaitCondition {
          terminal.frames.contains { $0.contains("action ready") }
        },
        .press(KeyPress(.character("d"), modifiers: .ctrl)),
      ])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: inputReader,
      signalReader: AsyncTaskDrivenFrameEmptySignalReader(),
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

    let result = try await valueWithTimeout("action task-driven frame") {
      try await runLoop.run()
    }

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

private final class AsyncTaskDrivenFrameRecordingHost: PresentationSurface {
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

private enum AsyncTaskDrivenFrameInputStep {
  case press(KeyPress)
  case awaitCondition(predicate: @MainActor () -> Bool)
}

private final class AsyncTaskDrivenFrameInputReader: InputReading {
  private let steps: [AsyncTaskDrivenFrameInputStep]
  private let frameSignal: MainActorConditionSignal

  init(
    frameSignal: MainActorConditionSignal,
    steps: [AsyncTaskDrivenFrameInputStep]
  ) {
    self.frameSignal = frameSignal
    self.steps = steps
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let task = Task { @MainActor in
        for step in steps {
          switch step {
          case .press(let event):
            continuation.yield(event)
          case .awaitCondition(let predicate):
            await frameSignal.wait(until: predicate)
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class AsyncTaskDrivenFrameEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
