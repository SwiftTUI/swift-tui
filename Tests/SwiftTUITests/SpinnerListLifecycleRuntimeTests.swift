@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Spinner list lifecycle", .timeLimit(.minutes(1)))
struct SpinnerListLifecycleRuntimeTests {
  @Test("unticked siblings cancel after selective frames", arguments: ["r", "h"])
  func untickedSiblingsCancel(command: Character) async throws {
    let identity = testIdentity("SpinnerListLifecycle")
    let sleeper = StaggeredSpinnerSleeper()
    var entries = sleeper.entered.stream.makeAsyncIterator()
    let loop = RunLoop(
      rootIdentity: identity,
      presentationSurface: RecordingPresentationSurface(surfaceSize: .init(width: 80, height: 24)),
      terminalInputReader: InjectedTerminalInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: SpinnerListState(), invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity]),
      keyHandler: { key, _, state in
        switch key.key {
        case .character("r"): state.mutate { $0.reduced = true }
        case .character("h"): state.mutate { $0.visible.toggle() }
        default: return .ignored
        }
        return .handled
      },
      proposal: .init(width: 80, height: 24),
      viewBuilder: { state, _ in SpinnerListRoot(state: state) })
    loop.stateContainer.invalidator = loop.scheduler
    defer {
      loop.lifecycleCoordinator.shutdown()
      sleeper.releaseAll()
    }
    var frames = 0
    try SpinnerTaskClock.withSleep(.init { _ in try await sleeper.suspendTick() }) {
      loop.scheduler.requestInvalidation(of: [identity])
      try loop.renderPendingFrames(renderedFrames: &frames)
    }
    for _ in 0..<40 { _ = await entries.next() }
    #expect(loop.lifecycleCoordinator.activeTaskCount == 40)

    // Advance just one pending spinner per frame. Advancing every sibling
    // together hides the bug: fresh evaluations repair the stale lifecycle
    // owner, while untouched rows keep the collapsed modifier's inner owner.
    for _ in 0..<4 {
      sleeper.releaseFirst()
      _ = await entries.next()
      try loop.renderPendingFrames(renderedFrames: &frames)
      #expect(loop.lifecycleCoordinator.activeTaskCount == 40)
    }
    #expect(loop.handleKeyPress(KeyPress(.character(command))) == nil)
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(loop.lifecycleCoordinator.activeTaskCount == 0)
    #expect(loop.lifecycleCoordinator.taskStartSkipCount == 0)
  }
}

private struct SpinnerListState: Equatable, Sendable {
  var visible = true
  var reduced = false
}

private struct SpinnerListRoot: View {
  let state: SpinnerListState

  var body: some View {
    VStack {
      Text("Progress")
      if state.visible {
        HStack {
          ForEach(0..<40) { index in
            Spinner().accessibilityLabel("Spinner \(index)")
          }
        }
      }
    }
    .environment(\.accessibilityReduceMotion, state.reduced)
  }
}

@MainActor
private final class StaggeredSpinnerSleeper {
  let entered = AsyncStream<Void>.makeStream()
  private var continuations: [CheckedContinuation<Void, any Error>] = []

  func suspendTick() async throws {
    try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
      entered.continuation.yield(())
    }
  }

  func releaseFirst() {
    continuations.removeFirst().resume()
  }

  func releaseAll() {
    let pending = continuations
    continuations = []
    for continuation in pending { continuation.resume() }
  }
}
