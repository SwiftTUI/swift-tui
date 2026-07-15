import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F149: deadline-only animation ticks are controller-owned presentation work.
/// They must advance active property and removal animations without evaluating
/// authored view bodies or defeating retained reuse in disjoint subtrees.
@Suite("AnimationScopedReuseRuntime", .serialized)
@MainActor
struct AnimationScopedReuseRuntimeTests {
  @Test("deadline-only property ticks do not re-evaluate the authored animation cone")
  func propertyTicksDoNotReEvaluateAuthoredCone() async throws {
    let terminalSize = CellSize(width: 24, height: 4)
    let rootIdentity = testIdentity("ScopedReuseProperty", "Root")
    let terminal = ScopedReuseProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let counter = ScopedReuseEvaluationCounter()
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
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        PropertyScopedReuseProbe(counter: counter)
      }
    )

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {
      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      let controller = runLoop.renderer.internalAnimationController
      runLoop.renderer.enableSelectiveEvaluation()

      #expect(controller.activeAnimationCount == 1)
      let evaluationsAfterStart = counter.evaluations
      let skipsBeforeTicks = controller.resolvedTreeProcessingSkipCount

      for _ in 0..<5 {
        scheduler.requestDeadline(.now())
        _ = try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
      }

      #expect(
        counter.evaluations == evaluationsAfterStart,
        "controller-owned deadlines must not re-run the authored property-animation body"
      )
      #expect(controller.resolvedTreeProcessingSkipCount >= skipsBeforeTicks + 5)
      #expect(controller.lastResolvedTreeProcessedNodeCount == 0)
      #expect(controller.activeAnimationCount == 1)
    }
  }

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

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {

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
      // animates nor reads invalidated state, so deadline-only ticks must leave
      // its authored subtree untouched.
      let evaluationsAfterRemovalStart = siblingCounter.evaluations
      let skipsBeforeTicks = controller.resolvedTreeProcessingSkipCount
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
      #expect(controller.resolvedTreeProcessingSkipCount >= skipsBeforeTicks + ticks)
      #expect(controller.lastResolvedTreeProcessedNodeCount == 0)

      let tickEvaluations = siblingCounter.evaluations - evaluationsAfterRemovalStart
      #expect(
        tickEvaluations <= 1,
        "disjoint sibling re-evaluated \(tickEvaluations)x across \(ticks) removal ticks — controller-owned removal ticks are evaluating authored views"
      )
    }
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

    try withAnimationSinks(runLoop.renderer.internalAnimationController) {

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

private struct PropertyScopedReuseProbe: View {
  @State private var opacity = 1.0
  let counter: ScopedReuseEvaluationCounter

  var body: some View {
    counter.increment()
    return Text("property-tick")
      .opacity(opacity)
      .onAppear {
        withAnimation(
          .linear(duration: .milliseconds(500)).repeatForever(autoreverses: true)
        ) {
          opacity = 0.2
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
