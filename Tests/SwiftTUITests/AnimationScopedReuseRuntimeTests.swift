import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F32: an in-flight NON-property animation (here a removal transition) must
/// not defeat retained reuse for subtrees disjoint from the animating cone.
/// The run loop's frame-safety scope used to fall back to `.all` whenever
/// pending animation work had no property identities, so every body in the
/// app re-ran on every 33ms tick for the whole animation. The animating
/// identities are attributable (the controller holds them), so the scope must
/// suppress only those cones and disjoint siblings must keep reuse.
@Suite("AnimationScopedReuseRuntime", .serialized)
@MainActor
struct AnimationScopedReuseRuntimeTests {
  @Test("in-flight removal transition keeps disjoint sibling subtrees retained-reusable")
  func removalTransitionKeepsDisjointSiblingReusable() async throws {
    let terminalSize = CellSize(width: 24, height: 4)
    let rootIdentity = testIdentity("ScopedReuseRemoval", "Root")
    let terminal = ScopedReuseProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let siblingCounter = ScopedReuseEvaluationCounter()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ScopedReuseEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        RemovalScopedReuseProbe(siblingCounter: siblingCounter)
      }
    )

    AnimationRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    TransitionRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    AnimationCompletionStorage.currentSink = runLoop.renderer.internalAnimationController
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
      AnimationCompletionStorage.currentSink = nil
    }

    // Mount + the onAppear-triggered follow-up frame that starts the panel's
    // removal transition. The synchronous driver keeps the removal start
    // deterministic (see OffscreenFrameElisionRuntimeTests for the rationale).
    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    let controller = runLoop.renderer.internalAnimationController
    runLoop.renderer.enableSelectiveEvaluation()

    #expect(
      !controller.debugStateSnapshot().removingIdentities.isEmpty,
      "the removal transition must be in flight before ticking"
    )

    // Drive deadline ticks while the removal is in flight and count how many
    // times the DISJOINT sibling's body re-evaluates. The sibling neither
    // animates nor reads any invalidated state; with an attributable
    // suppression scope its subtree takes retained reuse on every tick.
    let evaluationsAfterRemovalStart = siblingCounter.evaluations
    var ticks = 0
    let maxTicks = 400
    while !controller.debugStateSnapshot().removingIdentities.isEmpty && ticks < maxTicks {
      scheduler.requestDeadline(.now())
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames
      )
      ticks += 1
    }
    #expect(ticks > 0, "the removal must tick at least once before draining")
    #expect(ticks < maxTicks, "the removal transition must drain")

    let tickEvaluations = siblingCounter.evaluations - evaluationsAfterRemovalStart
    #expect(
      tickEvaluations <= 1,
      "disjoint sibling re-evaluated \(tickEvaluations)x across \(ticks) removal ticks — non-property animation ticks are defeating retained reuse for subtrees outside the animating cone"
    )
  }
}

extension AnimationScopedReuseRuntimeTests {
  /// A focus relocation DISCOVERED MID-FRAME (the focused control is removed
  /// with a transition, and focus-sync adopts the next candidate after the
  /// first resolve pass) must reach runtime focus readers in the SAME
  /// committed frame: the eager rerender pass recomputes the frame-safety
  /// scope, so the relocated focus target's runtime readers are suppressed
  /// out of retained reuse even though the frame's ordinary invalidation does
  /// not touch them. With a frame-start scope snapshot, the disjoint readout
  /// below reuses its pre-relocation content and the committed frame shows
  /// the OLD focus.
  @Test("mid-frame focus relocation reaches disjoint runtime focus readers in the committed frame")
  func midFrameFocusRelocationReachesDisjointFocusReaders() throws {
    let terminalSize = CellSize(width: 60, height: 6)
    let rootIdentity = testIdentity("ScopedReuseFocusRelocation", "Root")
    let terminal = ScopedReuseProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ScopedReuseEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        FocusRelocationScopedReuseProbe()
      }
    )

    AnimationRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    TransitionRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    AnimationCompletionStorage.currentSink = runLoop.renderer.internalAnimationController
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
      AnimationCompletionStorage.currentSink = nil
    }

    runLoop.renderer.enableSelectiveEvaluation()

    // Mount (focus adopts the panel's button) + the onAppear follow-up frame:
    // the focused button's subtree is removed with a transition, so the SAME
    // frame's focus-sync pass discovers the loss, adopts the surviving
    // button, and eagerly rerenders.
    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    // Frame timeline: [0] mount, [1] removal starts (panel-gone onAppear
    // requests survivor focus post-commit), [2] the request resolves and
    // focus-sync relocates focus mid-frame — the frame under test. Later
    // frames recompute fully via the tracker's root invalidation, so only
    // frame [2] discriminates a stale frame-start suppression scope.
    #expect(terminal.presentedFrames.count >= 3, "expected the relocation frame to present")
    let relocationFrame = try #require(
      terminal.presentedFrames.dropFirst(2).first,
      "the relocation frame must present"
    )
    let readoutLine = try #require(
      relocationFrame.split(separator: "\n").first(where: { $0.contains("F:") }),
      "the focus readout line must render: \(relocationFrame)"
    )
    #expect(
      readoutLine.contains("SurvivorButton"),
      "committed relocation frame shows: \(readoutLine)"
    )
    #expect(
      !readoutLine.contains("PanelButton"),
      "the disjoint focus readout must not reuse pre-relocation content: \(readoutLine)"
    )
    #expect(
      !runLoop.renderer.internalAnimationController.debugStateSnapshot()
        .removingIdentities.isEmpty,
      "the removal transition must still be in flight on the relocation frame"
    )
  }
}

private struct FocusRelocationScopedReuseProbe: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      RelocationPanelSection()
        .id(testIdentity("RelocationPanelSection"))
      RelocationFocusReadout()
        .id(testIdentity("RelocationFocusReadout"))
    }
    .frame(width: 60, height: 6)
  }
}

private struct RelocationPanelSection: View {
  @State private var showPanel: Bool = true
  @FocusState private var survivorFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showPanel {
        Button("panel") {}
          .id(testIdentity("PanelButton"))
          .transition(.opacity)
      } else {
        // Appears on the removal frame; its onAppear fires post-commit and
        // requests survivor focus, so the NEXT frame resolves the request and
        // focus-sync relocates focus MID-frame (eager rerender) while the
        // removal transition is still in flight.
        Text("panel gone")
          .onAppear {
            survivorFocused = true
          }
      }
      Button("survivor") {}
        .id(testIdentity("SurvivorButton"))
        .focused($survivorFocused)
    }
    .onAppear {
      withAnimation(.linear(duration: .milliseconds(200))) {
        showPanel = false
      }
    }
  }
}

private struct RelocationFocusReadout: View {
  var body: some View {
    EnvironmentReader(\.focusedIdentity) { focusedIdentity in
      Text("F:\(focusedIdentity?.path.suffix(40) ?? "none")")
    }
  }
}

private struct RemovalScopedReuseProbe: View {
  @State private var showPanel: Bool = true
  let siblingCounter: ScopedReuseEvaluationCounter

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showPanel {
        Text("panel")
          .id(testIdentity("ScopedReuseRemovalPanel"))
          .transition(.opacity)
      }
      ScopedReuseSibling(counter: siblingCounter)
        .id(testIdentity("ScopedReuseSibling"))
    }
    .frame(width: 24, height: 4)
    .onAppear {
      withAnimation(.linear(duration: .milliseconds(120))) {
        showPanel = false
      }
    }
  }
}

private struct ScopedReuseSibling: View {
  let counter: ScopedReuseEvaluationCounter

  var body: some View {
    counter.increment()
    return Text("sibling:stable")
  }
}

@MainActor
private final class ScopedReuseEvaluationCounter {
  private(set) var evaluations = 0

  func increment() {
    evaluations += 1
  }
}

private final class ScopedReuseProbeTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var presentedFrames: [String] = []

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentedFrames.append(surface.lines.joined(separator: "\n"))
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }
}

private final class ScopedReuseEmptyInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
