@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Live-graph regression for the stale-`@State`-in-`onSubmit` shape: type
/// into a focused `TextField` through the real `RunLoop` input path, press
/// Return, and assert the submit closure observes the typed value — not the
/// authored seed.
///
/// This must run on an invalidator-backed graph: the snapshot render harness
/// (`DefaultRenderer.render` with no invalidator) mirrors state writes into
/// the box seed, which masks the seed-fallback failure by construction.
/// The registration snapshot is explicitly nil — the failing shape — so the
/// closure's `@State` read can only succeed through the ambient dispatch
/// context that `withImperativeAuthoringContext(nil)` now preserves.
@MainActor
@Suite
struct SubmitClosureLiveStateTests {
  @MainActor
  private final class SubmitObservationLog {
    var observed: [String] = []
  }

  private enum IDs {
    static let field = testIdentity("SubmitLiveStateField")
  }

  private struct SubmitLiveStateRoot: View {
    @State private var text = ""
    let log: SubmitObservationLog

    var body: some View {
      TextField("Name", text: $text)
        .id(IDs.field)
        .textFieldStyle(.plain)
        .modifier(
          SubmitActionModifier(
            authoringContext: nil,
            action: { log.observed.append(text) }
          )
        )
    }
  }

  @Test("the submit closure observes interactively typed @State on a live graph")
  func submitClosureObservesTypedState() throws {
    let log = SubmitObservationLog()
    let terminalSize = CellSize(width: 40, height: 6)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity("SubmitLiveStateRoot")
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: InertTerminalInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in SubmitLiveStateRoot(log: log) }
    )
    focusTracker.invalidator = runLoop.scheduler

    var renderedFrames = 0
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()

    _ = runLoop.focusTracker.setFocus(to: IDs.field)
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    for character in "07" {
      #expect(runLoop.handleKeyPress(KeyPress(.character(character))) == nil)
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    }
    #expect(runLoop.handleKeyPress(KeyPress(.return)) == nil)
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    // The closure must see the interactively typed value; the pre-fix
    // behavior observed the authored seed ("").
    #expect(log.observed == ["07"])
  }
}

private final class InertTerminalInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
