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
///
/// The re-arm is for animation work only. A `.transition(_:)` registration
/// is not work, so a skipped frame arms nothing for a transition at rest
/// (STUI-1547).
@MainActor
@Suite
struct SkippedFrameAnimationRearmTests {
  private static let size = CellSize(width: 20, height: 4)
  private static let proposal = ProposedSize(width: .finite(20), height: .finite(4))

  @Test("a skipped frame re-arms the animation deadline despite a pending cause")
  func skippedFrameReArmsDespitePendingCause() throws {
    let rootIdentity = testIdentity("SkippedRearm", "Root")
    let scheduler = FrameScheduler()
    let runLoop = Self.makeRunLoop(rootIdentity: rootIdentity, scheduler: scheduler)

    // Give the live controller un-drained animation work: an offset
    // animation in flight, far from its end.
    let controller = runLoop.renderer.internalAnimationController
    let animation = Animation.linear(duration: .seconds(600))
    controller.register(animation)
    _ = runLoop.renderer.render(
      RearmOffsetProbe(offset: 0),
      context: ResolveContext(identity: rootIdentity),
      proposal: Self.proposal)
    var animate = TransactionSnapshot()
    animate.animationRequest = .animate(animation.animationBox)
    _ = runLoop.renderer.render(
      RearmOffsetProbe(offset: 10),
      context: ResolveContext(identity: rootIdentity, transaction: animate),
      proposal: Self.proposal)
    #expect(controller.activeAnimationCount >= 1, "the offset change must start an animation")
    #expect(controller.requiresContinuedAnimationFrames)

    // The park shape: a pending CAUSE (input) with NO armed deadline.
    scheduler.requestInput()

    // One instant for the whole frame, as the drivers derive it: the re-arm
    // and the consume that must observe it have to agree about the time.
    let frameInstant = MonotonicInstant.now()
    runLoop.requestNextAnimationFrameAfterSkippedFrameIfNeeded(at: frameInstant)

    // Draining the pending cause must reveal an armed animation deadline —
    // the guard used to decline here (`hasPendingFrame` was true via the
    // cause alone), leaving nothing armed once this frame was consumed.
    let frame = try #require(scheduler.consumeReadyFrame(at: frameInstant))
    #expect(frame.causes.contains(.input))
    #expect(
      frame.nextDeadline != nil,
      "live animation work must keep a deadline armed across a skipped frame"
    )
    #expect(!scheduler.hasPendingFrame(at: frameInstant))
    #expect(scheduler.nextWakeInstant(after: frameInstant) != nil)
  }

  @Test("a skipped frame and a committed frame arm nothing for a transition at rest")
  func registeredTransitionArmsNothing() throws {
    let rootIdentity = testIdentity("SkippedRearm", "Root")
    let scheduler = FrameScheduler()
    let runLoop = Self.makeRunLoop(rootIdentity: rootIdentity, scheduler: scheduler)

    // A view at rest under a transition, rendered twice: its registration is
    // in the controller's current and previous maps, and nothing animates.
    let controller = runLoop.renderer.internalAnimationController
    for _ in 0..<2 {
      _ = runLoop.renderer.render(
        RearmTransitionProbe(),
        context: ResolveContext(identity: rootIdentity),
        proposal: Self.proposal)
    }
    let state = controller.debugStateSnapshot()
    #expect(!state.transitionNodeIDs.isEmpty)
    #expect(!state.previousTransitionNodeIDs.isEmpty)
    #expect(state.activeAnimationKeys.isEmpty)
    #expect(!controller.requiresContinuedAnimationFrames)

    // The same park shape: a pending cause and no armed deadline.
    scheduler.requestInput()
    let frameInstant = MonotonicInstant.now()

    // Neither the skipped-frame path nor the committed-frame path arms a
    // deadline: there is no animation work to drain.
    runLoop.requestNextAnimationFrameAfterSkippedFrameIfNeeded(at: frameInstant)
    runLoop.requestNextAnimationFrameIfNeeded(controller.lastTickResult, at: frameInstant)

    let frame = try #require(scheduler.consumeReadyFrame(at: frameInstant))
    #expect(frame.causes.contains(.input))
    #expect(frame.nextDeadline == nil, "a registered transition is not animation work")
    #expect(!scheduler.hasPendingFrame(at: frameInstant))
    #expect(scheduler.nextWakeInstant(after: frameInstant) == nil)
  }

  private static func makeRunLoop(
    rootIdentity: Identity, scheduler: FrameScheduler
  ) -> RunLoop<Int, Text> {
    let terminal = RearmTerminalHost(surfaceSize: size)
    return RunLoop(
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
        values.terminalSize = size
        return values
      }(),
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in Text("hi") }
    )
  }
}

/// A view whose offset the caller sets: a change of it under an animation
/// puts a property animation in the controller.
private struct RearmOffsetProbe: View {
  let offset: Int

  var body: some View {
    VStack {
      Text("head")
      Text("anim").offset(x: offset, y: 0)
    }
  }
}

/// A view at rest under a transition.
private struct RearmTransitionProbe: View {
  var body: some View {
    VStack {
      Text("head")
      Text("leaf").transition(.opacity)
    }
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
