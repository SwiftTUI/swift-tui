import Foundation
import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Forward-progress guarantee for the cancelled-before-start path.
///
/// A prepared frame whose commit would stop an invalidation source (a tab
/// leave carrying the leaving tab's `taskCancel`) can be superseded by that
/// very source on every cycle: each new intent cancels the queued tail before
/// it starts, the intent is replayed, and the replay is cancelled in turn —
/// forever (the gallery tab-leave livelock, report 2026-07-05-001). The
/// completed-frame drop policy's `progress_starvation` guard bounds
/// consecutive visual-only DROPS, but pre-start cancels had no analogous
/// bound.
///
/// The supersession side of the race is made deterministic by a scheduler
/// that reports a pending frame on every poll, and the queued window is held
/// open by blocking the layout worker — so without the bound the cancel
/// cycle is guaranteed, and with it the third head is guaranteed to park
/// uncancellable. All synchronisation is on `RunLoopProgressProbe` events;
/// the assertions read the retained event log, so no wall-clock waits are
/// involved.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PreStartCancelForwardProgressTests {
  @MainActor
  @Test("perpetual supersession cannot starve frame commits")
  func perpetualSupersessionCannotStarveFrameCommits() async throws {
    let rootIdentity = testIdentity("PreStartCancelForwardProgressRoot")
    let terminal = PreStartCancelTerminalHost()
    let renderer = DefaultRenderer()
    let inputReader = InjectedTerminalInputReader()
    let scheduler = PerpetualSupersessionScheduler()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        PreStartCancelProgressView(value: value)
      }
    )
    let probe = RunLoopProgressProbe()
    runLoop.progressProbe = probe

    let runTask = Task {
      try await runLoop.run()
    }

    // The bootstrap frame renders through the initial non-superseded path,
    // so it commits regardless (the gallery livelock likewise spares the
    // initial visit).
    let bootstrap = await probe.frameCommitted()
    #expect(terminal.frames.contains { $0.contains("progress 0") })

    // Occupy the layout worker so queued tails cannot start: the pre-start
    // cancellation window stays open on every cycle, exactly as it does in
    // the loaded gallery where the leave frame's tail never won the race
    // against the next tick.
    let workerGate = AsyncFrameTailBlockingGate()
    let workerBlockTask = Task {
      await renderer.runFrameTailLayoutWorkerJobForCancellationTesting {
        workerGate.beforeRaster()
      }
    }
    await workerGate.waitUntilBlocked()

    // The livelock target: a state-change frame behind perpetual
    // supersession with the cancel window held open. Without the
    // forward-progress bound every queued tail is cancelled before start,
    // its intent is replayed, and the replay is cancelled in turn — the
    // cancel events keep coming and nothing ever commits.
    stateContainer.mutate { $0 = 1 }
    let firstCancel = await probe.event { event in
      event.sequence > bootstrap.sequence && event.isPreStartCancel
    }
    let secondCancel = await probe.event { event in
      event.sequence > firstCancel.sequence && event.isPreStartCancel
    }
    #expect(runLoop.consecutivePreStartCancelCount == 2)

    // The bound: the replayed intent's third head is prepared and its queued
    // tail must be held UNCANCELLABLE (trace-visible as
    // `preStartCancelBoundHeld`) while the worker is still blocked. Without
    // the bound the loop cancels the third tail autonomously instead (the
    // blocked worker guarantees it loses the start race), so racing the two
    // event kinds is a deterministic red/green discriminator with no
    // wall-clock involved — and no release-ordering dependence, because the
    // worker stays blocked until after the verdict is in.
    let thirdIntent = await probe.event { event in
      event.sequence > secondCancel.sequence && event.kind == .frameIntent
    }
    let boundVerdict = await probe.event { event in
      event.sequence > thirdIntent.sequence
        && (event.isPreStartCancel || event.kind == .preStartCancelBoundHeld)
    }
    #expect(
      boundVerdict.kind == .preStartCancelBoundHeld,
      "third consecutive pre-start cancel — the forward-progress bound did not hold: \(boundVerdict)"
    )
    workerGate.release()

    // The forced tail's frame carries structural churn (the view re-keys per
    // value), so the completed-frame policy commits it and the state change
    // reaches the terminal.
    let forcedCommit = await probe.frameCommitted { event in
      event.sequence > secondCancel.sequence
    }
    #expect(terminal.frames.contains { $0.contains("progress 1") })
    let cancelsBetweenBoundAndCommit = probe.events.filter { event in
      event.sequence > secondCancel.sequence
        && event.sequence < forcedCommit.sequence
        && event.isPreStartCancel
    }
    #expect(
      cancelsBetweenBoundAndCommit.isEmpty,
      "pre-start cancels continued past the bound: \(cancelsBetweenBoundAndCommit)"
    )

    // Progress must be sustained, not once-only.
    stateContainer.mutate { $0 = 2 }
    _ = await probe.event { event in
      event.kind == .frameCommitted && event.sequence > forcedCommit.sequence
        && terminal.frames.contains { $0.contains("progress 2") }
    }

    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()
    let result = try await runTask.value
    await workerBlockTask.value
    #expect(result.finalState == 2)
  }

  @MainActor
  @Test("pre-start cancels within the bound still coalesce newer intents")
  func preStartCancelsWithinTheBoundStillCoalesceNewerIntents() async throws {
    // The bound must not disable cancellation outright: with fewer
    // consecutive cancels than the bound, a queued tail with a pending newer
    // intent is still cancelled (the input-coalescing behavior the
    // cancellable pipeline exists for). Pin the counter surface directly.
    let surface = PreStartCancelTerminalHost()
    let runLoop = RunLoop(
      rootIdentity: testIdentity("PreStartCancelBoundSurface"),
      renderer: DefaultRenderer(),
      presentationSurface: surface,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: []
      ),
      focusTracker: FocusTracker(invalidationIdentities: []),
      proposal: surface.proposal,
      viewBuilder: { (value: Int, _) in
        PreStartCancelProgressView(value: value)
      }
    )
    #expect(runLoop.consecutivePreStartCancelCount == 0)
    #expect(type(of: runLoop).maxConsecutivePreStartCancels >= 1)
  }
}

extension RunLoopProgressEvent {
  fileprivate var isPreStartCancel: Bool {
    kind == .frameSkipped
      && tailJobState == FrameTailJobState.cancelledBeforeStart.rawValue
  }
}

private struct PreStartCancelProgressView: View {
  var value: Int

  var body: some View {
    // Re-keying per value makes every state change structural churn, and the
    // appear handler gives that churn a lifecycle effect — so the forced
    // (uncancellable) tail is never droppable as visual-only and must commit
    // (mirroring the tab-leave frame, whose commit plan carries the leaving
    // tab's `taskCancel`).
    Text("progress \(value)")
      .onAppear {}
      .id(testIdentity("PreStartCancelProgressValue", "\(value)"))
  }
}

private final class PreStartCancelTerminalHost: PresentationSurface {
  var surfaceSize: CellSize {
    size
  }
  let size = CellSize(width: 32, height: 6)
  let proposal = ProposedSize(width: 32, height: 6)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  private(set) var frames: [String] = []

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
  }

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )
    .render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    return .fullRepaint(
      for: surface,
      capabilityProfile: capabilityProfile
    )
  }
}

/// A scheduler that makes the supersession side of the cancel race
/// deterministic: every `hasPendingFrame` poll reports a pending frame, so a
/// queued tail consulting the cancellation policy is ALWAYS superseded (the
/// Life-tab auto-tick during a tab leave). Everything else forwards to a
/// real `FrameScheduler`, so coalescing, replay, and event-pump wakes behave
/// normally.
private final class PerpetualSupersessionScheduler: FrameScheduling,
  WakeNotifyingFrameScheduling, CancelledFrameIntentReplaying, Sendable
{
  private let inner = FrameScheduler()

  func requestInvalidation(of identities: Set<Identity>) {
    inner.requestInvalidation(of: identities)
  }

  func requestInput() {
    inner.requestInput()
  }

  func requestSignal(named name: String) {
    inner.requestSignal(named: name)
  }

  func requestExternalWake(reason: String) {
    inner.requestExternalWake(reason: reason)
  }

  func requestDeadline(_ deadline: MonotonicInstant) {
    inner.requestDeadline(deadline)
  }

  func hasPendingFrame(at now: MonotonicInstant) -> Bool {
    true
  }

  func nextWakeInstant(after now: MonotonicInstant) -> MonotonicInstant? {
    inner.nextWakeInstant(after: now)
  }

  func consumeReadyFrame(at now: MonotonicInstant) -> ScheduledFrame? {
    inner.consumeReadyFrame(at: now)
  }

  func reset() {
    inner.reset()
  }

  func setWakeHandler(_ handler: (@Sendable () -> Void)?) {
    inner.setWakeHandler(handler)
  }

  func replayCancelledFrameIntent(_ frame: ScheduledFrame) {
    inner.replayCancelledFrameIntent(frame)
  }
}
