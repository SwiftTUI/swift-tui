import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F79: the skipped-frame animation re-arm must CLAMP (arm unconditionally),
/// not guard on `hasPendingFrame`. A pending input/invalidation CAUSE is not
/// durable wake insurance — the frame that drains it can itself be skipped,
/// leaving live animation work with no armed deadline, parked until the next
/// input ("stuck until you scroll"). The scheduler's deadline set makes the
/// unconditional arm idempotent-safe, and the departed-identity prune (F44)
/// keeps `requiresContinuedAnimationFrames` truthful, so the clamp cannot
/// re-create the orphaned-work cancel-cascade the guard was added to stop.
@MainActor
@Suite
struct SkippedFrameAnimationRearmTests {
  @Test("a skipped frame re-arms the animation deadline despite a pending cause")
  func skippedFrameReArmsDespitePendingCause() throws {
    let rootIdentity = testIdentity("SkippedRearm", "Root")
    let terminal = RearmTerminalHost(surfaceSize: CellSize(width: 20, height: 4))
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: RearmEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = CellSize(width: 20, height: 4)
        return values
      }(),
      proposal: .init(width: 20, height: 4),
      viewBuilder: { _, _ in Text("hi") }
    )

    // Give the live controller un-drained animation work (a registered
    // transition is the cheapest `requiresContinuedAnimationFrames == true`
    // source — the exact predicate the re-arm consults).
    let controller = runLoop.renderer.internalAnimationController
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: testIdentity("SkippedRearm", "Leaf"),
      viewNodeID: ViewNodeID(rawValue: 7),
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()
    #expect(controller.requiresContinuedAnimationFrames)

    // The park shape: a pending CAUSE (input) with NO armed deadline.
    scheduler.requestInput()

    runLoop.requestNextAnimationFrameAfterSkippedFrameIfNeeded()

    // Draining the pending cause must reveal an armed animation deadline —
    // the guard used to decline here (`hasPendingFrame` was true via the
    // cause alone), leaving nothing armed once this frame was consumed.
    let frame = try #require(scheduler.consumeReadyFrame(at: .now()))
    #expect(frame.causes.contains(.input))
    #expect(
      frame.nextDeadline != nil,
      "live animation work must keep a deadline armed across a skipped frame"
    )
    #expect(!scheduler.hasPendingFrame(at: .now()))
    #expect(scheduler.nextWakeInstant(after: .now()) != nil)
  }
}

private final class RearmTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  init(surfaceSize: CellSize) { self.surfaceSize = surfaceSize }
  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}
  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    .init(
      bytesWritten: 0, linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height, strategy: .fullRepaint)
  }
}

private final class RearmEmptyInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}
