@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// `RunLoop.run()` does not wait while a frame is ready (STUI-1585).
///
/// The run loop waits for an event when a turn of its loop has ended. A
/// request to the scheduler puts a wake into the event pump, so a frame that
/// was asked for during the turn is safe. A deadline that comes due is not a
/// request. When it comes due after the frame driver's last look at the
/// scheduler, in a turn that asked for nothing, the pump holds no wake for
/// it. The run loop has to see that deadline when it decides to wait.
///
/// These tests run the real `run()`. The scheduler they install forwards to
/// a `FrameScheduler` and can move its own time forward at a chosen point of
/// the run loop's work (`WarpingFrameScheduler`), so a deadline comes due at
/// that point on every run. It also passes a request's wake on only when the
/// test says so. The pump then never holds a wake the test did not put
/// there, and what wakes the run loop is its own decision.
///
/// Nothing sleeps and nothing polls. Each wait is on a signal that the
/// scheduler notifies as the run loop calls it. The wall-clock bound of a
/// wait only ends a wait that would never resume.
///
/// No closure is written inside the arguments of `#expect` or `#require`
/// here: the result of a wait goes into a constant first. With Swift 6.4.0,
/// a closure in such an argument, in a test body that was itself a closure,
/// made the next closure of that body run the first one's code, so a wait
/// returned on the wrong condition.
@MainActor
@Suite("The run loop does not wait while a frame is ready", .serialized)
struct RunLoopWakeDecisionTests {
  @Test(
    "a deadline that comes due during a turn of the run loop is rendered with no further request",
    arguments: WakeTurnStart.allCases, [WakeWarpPoint.beforeTheLook, .afterTheLastLook])
  func deadlineThatComesDueDuringATurnIsRendered(
    turnStart: WakeTurnStart, point: WakeWarpPoint
  ) async throws {
    let session = WakeSession()
    defer { session.end() }
    let scheduler = session.scheduler
    scheduler.passesWakesOn = false
    session.start()

    // The first frame is out and the run loop has asked for its first
    // wake. It now waits for an event: the pump holds no wake and nothing
    // is armed.
    let started = await session.wait { scheduler.decisions >= 1 }
    try #require(started, "\(scheduler.summary)")
    try #require(scheduler.holdsNothing, "\(scheduler.summary)")

    // A deadline an hour away. The scheduler's time jumps two hours at
    // `point` of the turn that comes next.
    scheduler.requestDeadline(MonotonicInstant.now().advanced(by: .seconds(3600)))
    scheduler.warp(by: .seconds(7200), point)
    switch turnStart {
    case .aWake:
      // A cause for one frame, and the one wake that a request brings. The
      // turn has no event, and decides to wait in that branch of `run()`.
      scheduler.requestExternalWake(reason: "RunLoopWakeDecisionTests")
      scheduler.wake()
    case .anInputEvent:
      // A key that nothing in the scene handles. The turn has an event,
      // and decides to wait in the other branch of `run()`.
      session.input.press(KeyPress(.character("x")))
    }

    // The run loop renders the frame of the deadline. Nothing asks it to.
    let rendered = await session.wait { scheduler.deadlineFrames >= 1 }
    #expect(rendered, "the deadline got no frame: \(scheduler.summary)")
    #expect(scheduler.warps == 1, "\(scheduler.summary)")
    #expect(scheduler.deadlineFrames == 1, "\(scheduler.summary)")

    // The run loop is at rest again.
    let cameToRest = await session.wait { scheduler.holdsNothing }
    try #require(cameToRest, "\(scheduler.summary)")
    let result = try await session.finish()
    #expect(result.exitReason == .userExit(WakeSession.exitKey))
    #expect(scheduler.deadlineFrames == 1, "\(scheduler.summary)")
  }

  @Test("a deadline that comes due during the pass after the first presentation is rendered")
  func deadlineThatComesDueDuringStartUpIsRendered() async throws {
    let session = WakeSession()
    defer { session.end() }
    let scheduler = session.scheduler
    scheduler.passesWakesOn = false

    // Two deadlines, one hour and three hours away, and two jumps of two
    // hours. The first jump comes when start-up, after the first
    // presentation and its request for a wake, looks whether a frame is
    // ready: the first deadline is due then, and start-up runs a pass for
    // it. The second jump comes after the last look of that pass, so the
    // second deadline is due when start-up asks for a wake again. No
    // request has put a wake into the pump, and the loop's first wait
    // comes next.
    let now = MonotonicInstant.now()
    scheduler.requestDeadline(now.advanced(by: .seconds(3600)))
    scheduler.requestDeadline(now.advanced(by: .seconds(3 * 3600)))
    scheduler.warp(by: .seconds(7200), .atTheReadinessProbe)
    scheduler.warp(by: .seconds(7200), .afterTheLastLook)
    session.start()

    let rendered = await session.wait { scheduler.deadlineFrames >= 2 }
    #expect(rendered, "the second deadline got no frame: \(scheduler.summary)")
    #expect(scheduler.warps == 2, "\(scheduler.summary)")

    let cameToRest = await session.wait { scheduler.holdsNothing }

    try #require(cameToRest, "\(scheduler.summary)")
    let result = try await session.finish()
    #expect(result.exitReason == .userExit(WakeSession.exitKey))
    #expect(scheduler.deadlineFrames == 2, "\(scheduler.summary)")
  }

  @Test("a deadline due during a terminal handoff costs two turns and is rendered at its end")
  func deadlineDueDuringAHandoffWaitsForItsEnd() async throws {
    let session = WakeSession()
    defer { session.end() }
    let scheduler = session.scheduler
    scheduler.passesWakesOn = false
    session.start()
    let started = await session.wait { scheduler.decisions >= 1 }
    try #require(started, "\(scheduler.summary)")
    try #require(scheduler.holdsNothing, "\(scheduler.summary)")

    let handoff = session.runLoop.runtimeTerminalHandoffAction()
    let operationStarted = AsyncEvent()
    let finishOperation = AsyncEvent()
    defer { finishOperation.fire() }
    let handoffTask = Task { @MainActor in
      try await handoff {
        operationStarted.fire()
        await finishOperation.wait()
      }
    }
    await operationStarted.wait()
    #expect(session.runLoop.terminalHandoffInProgress)

    // A deadline that is due now, and the wake its request brings. The
    // frame driver renders nothing during a handoff, so the frame stays
    // ready.
    let decisionsBefore = scheduler.decisions
    let framesBefore = scheduler.frames
    scheduler.requestDeadline(.now())
    scheduler.wake()
    let tookATurn = await session.wait { scheduler.decisions > decisionsBefore }
    try #require(tookATurn, "\(scheduler.summary)")

    // The run loop gets many turns of the main actor. A loop that woke
    // itself for the ready frame each time would use every one of them.
    await session.giveTheMainActorAway(times: WakeSession.turnsOffered)
    #expect(scheduler.decisions - decisionsBefore <= 2, "\(scheduler.summary)")
    #expect(
      scheduler.frames == framesBefore,
      "a frame was rendered during the handoff: \(scheduler.summary)")

    // The handoff ends as it does in a session: the terminal comes back
    // and the run loop is asked for a frame.
    scheduler.passesWakesOn = true
    finishOperation.fire()
    try await handoffTask.value
    let rendered = await session.wait { scheduler.deadlineFrames >= 1 }
    #expect(rendered, "the deadline got no frame: \(scheduler.summary)")

    let result = try await session.finish()
    #expect(result.exitReason == .userExit(WakeSession.exitKey))
  }

  @Test("the end of a handoff that could not give the terminal back still wakes the run loop")
  func handoffThatFailsToRestoreTheTerminalStillWakesTheRunLoop() async throws {
    let session = WakeSession(failsToRestoreTheTerminal: true)
    defer { session.end() }
    let scheduler = session.scheduler
    scheduler.passesWakesOn = false
    session.start()
    let started = await session.wait { scheduler.decisions >= 1 }
    try #require(started, "\(scheduler.summary)")
    try #require(scheduler.holdsNothing, "\(scheduler.summary)")

    let handoff = session.runLoop.runtimeTerminalHandoffAction()
    let operationStarted = AsyncEvent()
    let finishOperation = AsyncEvent()
    defer { finishOperation.fire() }
    let handoffTask = Task { @MainActor in
      try await handoff {
        operationStarted.fire()
        await finishOperation.wait()
      }
    }
    await operationStarted.wait()

    let decisionsBefore = scheduler.decisions
    let framesBefore = scheduler.frames
    scheduler.requestDeadline(.now())
    scheduler.wake()
    let tookATurn = await session.wait { scheduler.decisions > decisionsBefore }
    try #require(tookATurn, "\(scheduler.summary)")
    #expect(scheduler.frames == framesBefore, "\(scheduler.summary)")

    // The terminal does not come back, so the handoff asks the scheduler
    // for nothing. The frame that came due during it is still owed.
    finishOperation.fire()
    do {
      try await handoffTask.value
      Issue.record("the handoff did not throw")
    } catch let error as TerminalHandoffError {
      #expect(error == .failedToRestoreTerminal)
    } catch {
      Issue.record("the handoff threw \(error)")
    }
    #expect(!session.runLoop.terminalHandoffInProgress)
    let rendered = await session.wait { scheduler.deadlineFrames >= 1 }
    #expect(rendered, "the deadline got no frame: \(scheduler.summary)")

    let result = try await session.finish()
    #expect(result.exitReason == .userExit(WakeSession.exitKey))
  }

  @Test("a deadline that only the wall clock sees as due costs the run loop two turns at most")
  func readyFrameThatTheFrameDriverCannotTakeDoesNotSpinTheRunLoop() async throws {
    let session = WakeSession()
    defer { session.end() }
    let scheduler = session.scheduler
    scheduler.passesWakesOn = false
    // The frame driver reads this clock, and the run loop's decision to
    // wait reads the wall clock. The frame clock stands still at a past
    // instant.
    let frozen = MonotonicInstant.now()
    session.runLoop.frameClock = { frozen }
    session.start()
    let started = await session.wait { scheduler.decisions >= 1 }
    try #require(started, "\(scheduler.summary)")
    try #require(scheduler.holdsNothing, "\(scheduler.summary)")

    // Later than the frame clock, earlier than the wall clock from now on.
    let decisionsBefore = scheduler.decisions
    scheduler.requestDeadline(frozen.advanced(by: .nanoseconds(1)))
    scheduler.wake()
    let tookATurn = await session.wait { scheduler.decisions > decisionsBefore }
    try #require(tookATurn, "\(scheduler.summary)")

    await session.giveTheMainActorAway(times: WakeSession.turnsOffered)
    #expect(scheduler.decisions - decisionsBefore <= 2, "\(scheduler.summary)")
    #expect(scheduler.deadlineFrames == 0, "\(scheduler.summary)")

    let result = try await session.finish()
    #expect(result.exitReason == .userExit(WakeSession.exitKey))
  }
}

/// How a test starts the turn of the run loop it looks at. The two starts
/// lead to the two places where a turn of `run()` decides to wait.
enum WakeTurnStart: String, CaseIterable, Sendable, CustomTestStringConvertible {
  /// With a wake and no event, as a request to the scheduler or a timer
  /// starts one.
  case aWake
  /// With an input event.
  case anInputEvent

  var testDescription: String { rawValue }
}

// MARK: - The session

/// One run loop on a scene at rest, with the scheduler, the surface and the
/// input the tests drive it through.
@MainActor
private final class WakeSession {
  static let exitKey = KeyPress(.character("c"), modifiers: .ctrl)
  /// How many turns of the main actor a test offers a run loop that should
  /// be waiting.
  static let turnsOffered = 10_000

  let scheduler = WarpingFrameScheduler()
  let input = WakeInput()
  let runLoop: SwiftTUIRuntime.RunLoop<Int, Text>
  private var runTask: Task<RunLoopResult<Int>, any Error>?

  init(failsToRestoreTheTerminal: Bool = false) {
    let rootIdentity = testIdentity(
      "RunLoopWakeDecision", failsToRestoreTheTerminal ? "noRestore" : "restore")
    let size = CellSize(width: 20, height: 2)
    runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: WakeSurface(
        size: size, failsToRestoreTheTerminal: failsToRestoreTheTerminal),
      terminalInputReader: input,
      signalReader: WakeSignals(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in Text("at rest") }
    )
  }

  func start() {
    let runLoop = self.runLoop
    runTask = Task { try await runLoop.run() }
  }

  /// Sends the exit chord and waits for `run()` to return.
  func finish() async throws -> RunLoopResult<Int> {
    let runTask = try #require(runTask, "the session was not started")
    self.runTask = nil
    input.press(Self.exitKey)
    return try await runTask.value
  }

  /// Sends the exit chord to a session that ``finish()`` has not ended, so
  /// that its run loop returns. Each test defers this: a test that stops at a
  /// failed requirement then leaves no run loop behind. It does not wait for
  /// `run()` to return, because a `defer` cannot.
  func end() {
    guard runTask != nil else {
      return
    }
    runTask = nil
    input.press(Self.exitKey)
  }

  /// Waits until `predicate` holds, on the scheduler's signal, and returns
  /// whether it does when the wait ends.
  func wait(until predicate: @escaping @MainActor () -> Bool) async -> Bool {
    await WakeBoundedWait(on: scheduler.signal, until: predicate)
      .wait(within: AsyncTestTimeouts.scaled(.seconds(5)))
  }

  /// Suspends and resumes `times` times. Each suspension lets every other
  /// task that is ready on the main actor run, the run loop among them.
  func giveTheMainActorAway(times: Int) async {
    for _ in 0..<times {
      await Task.yield()
    }
  }
}

/// A wait on a condition signal with a wall-clock bound. The signal's owner
/// notifies it after each change, so the wait resumes on the change. The
/// bound only ends a wait that would never resume.
@MainActor
private final class WakeBoundedWait {
  private let signal: MainActorConditionSignal
  private let predicate: @MainActor () -> Bool

  init(on signal: MainActorConditionSignal, until predicate: @escaping @MainActor () -> Bool) {
    self.signal = signal
    self.predicate = predicate
  }

  /// Returns whether the predicate holds when the wait ends.
  func wait(within limit: Duration) async -> Bool {
    let deadline = AsyncEvent.firing(after: limit)
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.awaitPredicate() }
      group.addTask { await deadline.wait() }
      await group.next()
      group.cancelAll()
    }
    return predicate()
  }

  private func awaitPredicate() async {
    let predicate = self.predicate
    await signal.wait(until: { predicate() })
  }
}

// MARK: - The scheduler

/// Where `WarpingFrameScheduler` moves its time forward.
enum WakeWarpPoint: String, Sendable, CustomTestStringConvertible {
  /// At the frame driver's next look, before the scheduler answers it. The
  /// deadline is due in that look.
  case beforeTheLook
  /// After the frame driver's next look that finds nothing ready, which is
  /// the last look of its pass. The deadline comes due between that look and
  /// the run loop's decision to wait.
  case afterTheLastLook
  /// When the run loop next asks whether a frame is ready, after it has
  /// asked for a wake at least once, and before the scheduler answers. At
  /// start-up that is the question that follows the first presentation.
  case atTheReadinessProbe

  var testDescription: String { rawValue }
}

/// A frame scheduler that forwards to a real one, counts what the run loop
/// asks it, and can move its own time forward.
///
/// Time: every instant the run loop passes in is moved forward by the skew
/// before the real scheduler sees it, and every instant that comes back is
/// moved back by it. A larger skew is time that has passed. `warp(by:_:)`
/// adds to the skew at one point of the run loop's work, once. Several
/// warps happen in the order they were asked for.
///
/// Wakes: a request for an invalidation, an external wake or a deadline asks
/// the run loop's event pump for a wake, through the handler the run loop
/// installs. The scheduler passes that on while `passesWakesOn` is true.
/// `wake()` puts one wake into the pump at any time.
///
/// The run loop calls the scheduler on the main actor, and so do the tests.
private final class WarpingFrameScheduler: FrameScheduling, WakeNotifyingFrameScheduling,
  Sendable
{
  private struct State {
    var skew: Duration = .zero
    var pendingWarps: [(amount: Duration, point: WakeWarpPoint)] = []
    var passesWakesOn = true
    var wakeHandler: (@Sendable () -> Void)?
    var decisions = 0
    var looks = 0
    var frames = 0
    var deadlineFrames = 0
    var warps = 0
    var wakesAskedFor = 0

    /// Moves the time forward when the next warp is one for `point`.
    mutating func warpIfNext(at point: WakeWarpPoint) {
      guard let warp = pendingWarps.first, warp.point == point else {
        return
      }
      pendingWarps.removeFirst()
      skew += warp.amount
      warps += 1
    }
  }

  private let inner = FrameScheduler()
  private let state = Mutex(State())
  /// Notified each time the run loop asks the scheduler for a frame or for
  /// its next wake.
  let signal = MainActorConditionSignal()

  /// Whether a request's wake reaches the run loop's event pump.
  var passesWakesOn: Bool {
    get { state.withLock { $0.passesWakesOn } }
    set { state.withLock { $0.passesWakesOn = newValue } }
  }

  /// How many times the run loop asked for its next wake. It asks once each
  /// time it is about to wait for an event.
  var decisions: Int { state.withLock { $0.decisions } }
  /// How many frames the frame driver took.
  var frames: Int { state.withLock { $0.frames } }
  /// How many of them a deadline caused.
  var deadlineFrames: Int { state.withLock { $0.deadlineFrames } }
  /// How many times the time moved forward.
  var warps: Int { state.withLock { $0.warps } }

  /// Whether nothing is pending and nothing is armed.
  var holdsNothing: Bool {
    let now = warped(.now())
    return inner.nextWakeInstant(after: now) == nil && !inner.hasPendingFrame(at: now)
  }

  /// The counts in words, for the message of a failed expectation.
  var summary: String {
    state.withLock { state in
      "\(state.decisions) decisions, \(state.looks) looks, \(state.frames) frames, "
        + "\(state.deadlineFrames) of a deadline, \(state.warps) warps, "
        + "\(state.wakesAskedFor) wakes asked for, skew \(state.skew)"
    }
  }

  /// Moves the time forward by `amount`, once, at `point`, after the warps
  /// asked for before this one.
  func warp(by amount: Duration, _ point: WakeWarpPoint) {
    state.withLock { $0.pendingWarps.append((amount, point)) }
  }

  /// Puts one wake into the run loop's event pump.
  func wake() {
    state.withLock { $0.wakeHandler }?()
  }

  // MARK: WakeNotifyingFrameScheduling

  func setWakeHandler(_ handler: (@Sendable () -> Void)?) {
    state.withLock { $0.wakeHandler = handler }
    guard handler != nil else {
      inner.setWakeHandler(nil)
      return
    }
    inner.setWakeHandler { [weak self] in
      self?.wakeWasAskedFor()
    }
  }

  private func wakeWasAskedFor() {
    let handler = state.withLock { state -> (@Sendable () -> Void)? in
      state.wakesAskedFor += 1
      return state.passesWakesOn ? state.wakeHandler : nil
    }
    handler?()
  }

  // MARK: FrameScheduling

  func requestInvalidation(of identities: Set<Identity>) {
    inner.requestInvalidation(of: identities)
  }

  func requestInput() { inner.requestInput() }
  func requestSignal(named name: String) { inner.requestSignal(named: name) }
  func requestExternalWake(reason: String) { inner.requestExternalWake(reason: reason) }

  func requestDeadline(_ deadline: MonotonicInstant) {
    inner.requestDeadline(warped(deadline))
  }

  func hasPendingFrame(at now: MonotonicInstant) -> Bool {
    let skew = state.withLock { state -> Duration in
      if state.decisions >= 1 {
        state.warpIfNext(at: .atTheReadinessProbe)
      }
      return state.skew
    }
    return inner.hasPendingFrame(at: now.advanced(by: skew))
  }

  func nextWakeInstant(after now: MonotonicInstant) -> MonotonicInstant? {
    let skew = state.withLock { state -> Duration in
      state.decisions += 1
      return state.skew
    }
    defer { notify() }
    return inner.nextWakeInstant(after: now.advanced(by: skew))
      .map { $0.advanced(by: .zero - skew) }
  }

  func consumeReadyFrame(at now: MonotonicInstant) -> ScheduledFrame? {
    look(at: now) { inner.consumeReadyFrame(at: $0) }
  }

  var deadlineArmCut: DeadlineArmCut { inner.deadlineArmCut }

  func consumeReadyFrame(
    at now: MonotonicInstant, armedBefore cut: DeadlineArmCut
  ) -> ScheduledFrame? {
    look(at: now) { inner.consumeReadyFrame(at: $0, armedBefore: cut) }
  }

  func reset() { inner.reset() }

  /// One look of the frame driver at the scheduler.
  private func look(
    at now: MonotonicInstant, _ consume: (MonotonicInstant) -> ScheduledFrame?
  ) -> ScheduledFrame? {
    let skew = state.withLock { state -> Duration in
      state.looks += 1
      state.warpIfNext(at: .beforeTheLook)
      return state.skew
    }
    let frame = consume(now.advanced(by: skew))
    state.withLock { state in
      if let frame {
        state.frames += 1
        if frame.causes.contains(.deadline) {
          state.deadlineFrames += 1
        }
      } else {
        state.warpIfNext(at: .afterTheLastLook)
      }
    }
    notify()
    return frame
  }

  private func warped(_ instant: MonotonicInstant) -> MonotonicInstant {
    instant.advanced(by: state.withLock { $0.skew })
  }

  private func notify() {
    let signal = self.signal
    MainActor.assumeIsolated {
      signal.notify()
    }
  }
}

// MARK: - The host

/// A terminal surface that presents nothing. With `failsToRestoreTheTerminal`
/// it enters raw mode once, for the session, and fails to enter it again
/// after a handoff.
private final class WakeSurface: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private let failsToRestoreTheTerminal: Bool
  private let rawModeEntries = Mutex(0)

  init(size: CellSize, failsToRestoreTheTerminal: Bool) {
    surfaceSize = size
    self.failsToRestoreTheTerminal = failsToRestoreTheTerminal
  }

  func enableRawMode() throws {
    let entries = rawModeEntries.withLock { entries -> Int in
      entries += 1
      return entries
    }
    if failsToRestoreTheTerminal, entries > 1 {
      throw WakeSurfaceError.rawModeEntryFailed
    }
  }

  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    .fullRepaint(for: surface, capabilityProfile: capabilityProfile)
  }
}

private enum WakeSurfaceError: Error {
  case rawModeEntryFailed
}

/// The input of a session: nothing, until the test presses the exit chord.
/// It can be suspended for a terminal handoff.
private final class WakeInput: TerminalInputReading, TerminalInputHandoffSuspending {
  private let continuation = Mutex<AsyncStream<InputEvent>.Continuation?>(nil)

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      self.continuation.withLock { $0 = continuation }
    }
  }

  func press(_ key: KeyPress) {
    _ = continuation.withLock { $0 }?.yield(.key(key))
  }

  func withInputSuspended<T>(_ body: () throws -> T) rethrows -> T {
    try body()
  }

  func replayProbeInput(_: [UInt8]) {}

  @MainActor
  func withInputSuspended<T: Sendable>(
    _ body: @MainActor @Sendable () async throws -> T
  ) async rethrows -> T {
    try await body()
  }
}

private final class WakeSignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
