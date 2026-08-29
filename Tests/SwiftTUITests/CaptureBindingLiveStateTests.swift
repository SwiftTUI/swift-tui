@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Live-graph A/B for bound-at-capture state ownership (plan 2026-08-20-001
/// Stage 3): a closure the body captured is fired with **no dispatch context
/// at all** — no registration snapshot, no ambient authoring scope — after
/// interactive edits through the real `RunLoop` input path.
///
/// Gate off, that shape is the corruption class distilled: the read bottoms
/// out at the authored seed (loudly, since `a81ee22e`). Gate on, the closure
/// carries its owner and observes the typed value. Both halves run on an
/// invalidator-backed graph because the snapshot harness mirrors imperative
/// writes into the box seed and false-passes this shape by construction.
@MainActor
@Suite(.serialized)
struct CaptureBindingLiveStateTests {
  @MainActor
  private final class CapturedClosureLog {
    var read: (@MainActor () -> String)?
    var stashObservations: [String] = []
  }

  private enum IDs {
    static let field = testIdentity("CaptureBindingLiveField")
  }

  private struct CaptureBindingLiveRoot: View {
    @State private var text = ""
    let log: CapturedClosureLog

    var body: some View {
      let _ = stash()
      TextField("Name", text: $text)
        .id(IDs.field)
        .textFieldStyle(.plain)
    }

    private func stash() {
      #if DEBUG
        log.stashObservations.append(_text.captureSlotForTesting == nil ? "unbound" : "bound")
      #endif
      log.read = { text }
    }
  }

  private func typedValueObservedByContextFreeClosure(
    captureBindingEnabled: Bool
  ) throws -> String {
    let saved = StateCaptureBindingConfiguration.isEnabled
    StateCaptureBindingConfiguration.isEnabled = captureBindingEnabled
    defer { StateCaptureBindingConfiguration.isEnabled = saved }

    let log = CapturedClosureLog()
    let terminalSize = CellSize(width: 40, height: 6)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity("CaptureBindingLiveRoot")
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: InertCaptureTerminalInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in CaptureBindingLiveRoot(log: log) }
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

    // The bind pass reaches the root through the transparent forwarding
    // container seam (`ScopedBuilder` routes the wrapped body through
    // `resolveViewElements`, never a `resolveView` of its own) — the stash
    // observations pin that every body evaluation saw a bound copy exactly
    // when the gate was on.
    #if DEBUG
      #expect(!log.stashObservations.isEmpty)
      for observation in log.stashObservations {
        #expect(observation.hasPrefix(captureBindingEnabled ? "bound" : "unbound"))
      }
    #endif

    // Fire the body-captured closure with no dispatch context: not through a
    // registered handler, not under any ambient authoring scope — the shape
    // every dispatch-surface fix so far has patched one seam at a time.
    let read = try #require(log.read)
    return read()
  }

  @Test("gate on: a context-free body-captured closure observes the typed value")
  func captureCarriesOwnerThroughContextFreeDispatch() throws {
    let observed = try typedValueObservedByContextFreeClosure(captureBindingEnabled: true)
    #expect(observed == "07")
  }

  @Test("gate off: the same shape still bottoms out at the authored seed (today's pin)")
  func contextFreeDispatchStillSeedsWithoutCaptures() throws {
    let observed = try typedValueObservedByContextFreeClosure(captureBindingEnabled: false)
    #expect(observed == "")
  }
}

private final class InertCaptureTerminalInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
