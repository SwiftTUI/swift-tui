import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct DirtyTrackingCoherenceTests {
  @Test("A local state change queues scheduler and graph dirty work together")
  func stateChangeAndGraphDirtyAgree() throws {
    let rootIdentity = testIdentity("DirtyTrackingRoot")
    let scheduler = FrameScheduler()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: DirtyTrackingHost(),
      terminalInputReader: DirtyTrackingInputReader(),
      signalReader: DirtyTrackingSignalReader(),
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 20, height: 4)
    ) { _, _ in
      DirtyTrackingCounterView()
    }
    stateContainer.invalidator = scheduler
    runLoop.focusTracker.invalidator = scheduler

    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()

    #expect(renderedFrames == 1)
    #expect(!scheduler.hasPendingFrame(at: .now()))
    #expect(runLoop.previousRenderedState == stateContainer.state)
    #expect(!runLoop.hasGraphDirtyWork)

    let incrementButtonIdentity = try #require(
      runLoop.latestSemanticSnapshot.focusRegions.first?.identity)
    #expect(runLoop.localActionRegistry.dispatch(identity: incrementButtonIdentity))

    #expect(scheduler.hasPendingFrame(at: .now()))
    #expect(runLoop.hasGraphDirtyWork)
    #expect(
      runLoop.previousRenderedState == stateContainer.state,
      "local @State dirties the graph, not the external RunLoop state signal"
    )

    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(renderedFrames == 2)
    #expect(!scheduler.hasPendingFrame(at: .now()))
    #expect(!runLoop.hasGraphDirtyWork)
    #expect(runLoop.previousRenderedState == stateContainer.state)
  }
}

@MainActor
private struct DirtyTrackingCounterView: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("count \(count)")
      Button("Increment") {
        count += 1
      }
    }
  }
}

@MainActor
extension RunLoop {
  fileprivate var hasGraphDirtyWork: Bool {
    let graph = renderer.debugRuntimeSubsystemSnapshot().viewGraph
    return !graph.invalidatedIdentities.isEmpty || !graph.graphLocalDirtyIdentities.isEmpty
  }
}

private final class DirtyTrackingHost: PresentationSurface {
  let surfaceSize = CellSize(width: 20, height: 4)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
}

private final class DirtyTrackingInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class DirtyTrackingSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
