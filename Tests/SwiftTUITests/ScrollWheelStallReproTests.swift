import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Reproduction for the gallery "wheel scroll stalls partway, must click a
/// surface to continue" bug.
///
/// Root cause: the focus-sync loop runs `LocalScrollPositionRegistry.sync` on
/// EVERY committed frame, which re-reveals the currently-focused descendant.
/// After the user clicks a content control (focusing it) and then wheel-scrolls,
/// focus-reveal fights the wheel: the instant the focused control passes the
/// viewport's top edge, the next frame's reveal scrolls back to keep it visible,
/// pinning the offset at the focused control's content position (~halfway when
/// the control is mid-content). Focusing the scroll view itself or its indicator
/// (not a child) removes the constraint — matching "the scroll bar works".
@Suite("ScrollWheelStallRepro", .serialized)
@MainActor
struct ScrollWheelStallReproTests {
  private struct ProbeWithMidButton: View {
    @State private var taps = 0
    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<20, id: \.self) { Text("top \($0)") }
          Button("FOCUSME") { taps += 1 }.id("FOCUSBTN")
          ForEach(0..<20, id: \.self) { Text("bot \($0)") }
        }
      }
      .frame(width: 28, height: 8)
    }
  }

  @Test("a focused mid-content control does not pin wheel scroll short of the true bottom")
  func focusRevealDoesNotPinWheelScroll() async throws {
    let rootIdentity = testIdentity("FocusRevealStall", "Root")
    let terminal = ReproTerminalHost(surfaceSize: CellSize(width: 28, height: 8))
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ReproEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = CellSize(width: 28, height: 8)
        return values
      }(),
      proposal: .init(width: 28, height: 8),
      viewBuilder: { _, _ in ProbeWithMidButton() }
    )

    // Mount.
    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    var guardN = 0
    while scheduler.hasPendingFrame(at: .now()) && guardN < 50 {
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      guardN += 1
    }

    func committedY() -> Int {
      runLoop.localScrollPositionRegistry
        .routesWithCurrentOffsets(runLoop.latestSemanticSnapshot.scrollRoutes)
        .first?.contentOffset.y ?? -1
    }
    func route() -> ScrollRoute? {
      runLoop.latestSemanticSnapshot.scrollRoutes.first
    }
    let trueMaxY = max(
      0, (route()?.contentBounds.size.height ?? 0) - (route()?.viewportRect.size.height ?? 0))
    let center = PointerLocation.cellFallback(CellPoint(x: 14, y: 4))

    func drain() async throws {
      var i = 0
      while scheduler.hasPendingFrame(at: .now()) && i < 12 {
        _ = try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
        i += 1
      }
    }
    func wheelDown(_ n: Int) async throws {
      for _ in 0..<n {
        runLoop.handleMouseScroll(deltaX: 0, deltaY: 1, location: center)
        try await drain()
      }
    }

    // The focusable button sits at content row ~20 of ~43; viewport is 8.

    // 1) Scroll the FOCUSME button into view (no focus yet) — this works fine.
    try await wheelDown(16)

    // Click the button to focus it (exactly what a user does when they click a
    // control mid-scroll). Its on-screen interaction region is now visible.
    guard
      let btnRect = runLoop.latestSemanticSnapshot.interactionRegions
        .first(where: { $0.identity.description.contains("FOCUSBTN") })?.rect
    else {
      Issue.record("FOCUSME button not on-screen after scrolling it into view")
      return
    }
    let btnCenter = PointerLocation.cellFallback(
      CellPoint(
        x: btnRect.origin.x + btnRect.size.width / 2,
        y: btnRect.origin.y + btnRect.size.height / 2))
    runLoop.handleMouseDown(MouseButton.primary, location: btnCenter)
    runLoop.handleMouseUp(MouseButton.primary, location: btnCenter)
    try await drain()
    #expect(
      runLoop.focusTracker.currentFocusIdentity?.description.contains("FOCUSBTN") == true,
      "the click should have focused the FOCUSME button")

    // 2) Keep wheeling down hard with the mid button focused. Before the fix the
    //    offset was pinned at the focused control's content position (~20);
    //    after the fix focus-reveal yields to the wheel and it reaches the bottom.
    try await wheelDown(40)
    let reachedY = committedY()

    #expect(
      reachedY >= trueMaxY,
      """
      REGRESSION: a focused mid-content control must not pin wheel scrolling. \
      reached \(reachedY) of trueMaxY \(trueMaxY) (a value near the focused \
      control's content row ~20 means focus-reveal is fighting the wheel again).
      """
    )
  }
}

private final class ReproTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var presentCount = 0
  init(surfaceSize: CellSize) { self.surfaceSize = surfaceSize }
  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}
  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentCount += 1
    return .init(
      bytesWritten: 0, linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height, strategy: .fullRepaint)
  }
}

private final class ReproEmptyInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}
