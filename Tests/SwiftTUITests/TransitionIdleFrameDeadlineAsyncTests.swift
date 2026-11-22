@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A view under `.transition(_:)` at rest arms no frame on the asynchronous
/// run loop either (STUI-1547).
///
/// `TransitionIdleFrameDeadlineTests` steps the synchronous frame driver on a
/// virtual clock. These tests run the real `RunLoop.run()` in its default
/// asynchronous render mode, on the wall clock, with a scripted input reader.
/// The scene has a view under a transition that stays, and a second one that
/// a key inserts and then removes inside `withAnimation(_:completion:)`.
///
/// After each key press the script sends nothing. The transition has to play
/// to its end, its completion has to fire, and the scheduler has to come to
/// rest with nothing armed, all without input.
///
/// In the noisy tests a task of the scene writes state from each key press
/// until the completion of the transition. Nothing times the writer: it
/// writes once for each event the run loop records (`AsyncIdlePacer`), and
/// it runs when the run loop next suspends. That is often while a frame
/// waits for its tail, so a write often asks for a new frame while the frame
/// before is in flight. The run loop then cancels that frame before its tail
/// starts, and the transition has to make its way through frames that never
/// commit. The frames the writer forced leave frame deadlines behind, and
/// the run loop has to serve those on its own before it comes to rest.
///
/// No wait reads a clock. The script waits on a signal: the surface
/// presenting a frame, or the frame driver ending a pass. The writer waits
/// on a signal too: the run loop recording an event. Each wait of the
/// script has a wall-clock bound, which is the failure bound and never the
/// pacing.
@MainActor
@Suite("A transition at rest arms no frame deadline, asynchronous run loop", .serialized)
struct TransitionIdleFrameDeadlineAsyncTests {
  private static let size = CellSize(width: 30, height: 6)
  private static let exitKey = KeyPress(.character("c"), modifiers: .ctrl)

  @Test(
    "an insertion and a removal play to their end and the scheduler comes to rest with no input",
    arguments: AsyncIdleKind.allCases)
  func quietSceneComesToRest(kind: AsyncIdleKind) async throws {
    let session = try await Self.play(kind, isNoisy: false)
    try Self.expectBothTransitionsCameToRest(session)
  }

  @Test(
    "they do so while a task writes state on every step of the run loop and frames are cancelled",
    arguments: AsyncIdleKind.allCases)
  func noisySceneComesToRest(kind: AsyncIdleKind) async throws {
    let session = try await Self.play(kind, isNoisy: true)
    try Self.expectBothTransitionsCameToRest(session)

    // The writer ran through each transition and stopped after it.
    let insertion = try #require(session.report.insertion)
    let removal = try #require(session.report.removal)
    #expect(insertion.writes >= 2, "\(session.context)")
    #expect(removal.writes >= insertion.writes + 2, "\(session.context)")
    #expect(session.finishedBursts == 2, "\(session.context)")
    // Its writes superseded frames: the run loop cancelled some before
    // their tail started.
    #expect(session.cancelledFrames > 0, "\(session.context)")
  }

  /// What one session of the run loop left behind.
  private struct Session {
    var report: AsyncIdleReport
    var exitReason: RunLoopExitReason
    /// How many frames the run loop cancelled before their tail started.
    var cancelledFrames: Int
    /// How many times the writer of a noisy scene stopped.
    var finishedBursts: Int
    /// The observations in words, for the message of a failed expectation.
    var context: String
  }

  /// Runs the scene on a run loop of its own until the script has pressed
  /// its keys and sent the exit chord.
  private static func play(_ kind: AsyncIdleKind, isNoisy: Bool) async throws -> Session {
    let host = AsyncIdleHost(size: size)
    let rootIdentity = testIdentity(
      "TransitionIdleAsync", kind.rawValue, isNoisy ? "noisy" : "quiet")
    let scheduler = FrameScheduler()
    let pacer = isNoisy ? AsyncIdlePacer() : nil
    let probe = RunLoopProgressProbe()
    let watch = AsyncIdleRestWatch(probe: probe, scheduler: scheduler, pacer: pacer)
    let script = AsyncIdleScript(
      host: host, scheduler: scheduler, watch: watch, pacer: pacer, exitKey: exitKey)
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: script,
      signalReader: AsyncIdleSignals(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in AsyncIdleScene(kind: kind, pacer: pacer) }
    )
    runLoop.progressProbe = probe
    #expect(runLoop.renderMode == .async)
    watch.startObserving()

    let result = try await runLoop.run()
    watch.finishObserving()

    let report = script.report
    return Session(
      report: report,
      exitReason: result.exitReason,
      cancelledFrames: runLoop.cancelledRenderCount,
      finishedBursts: pacer?.finishedBursts ?? 0,
      context: "\(report.summary), \(runLoop.cancelledRenderCount) frames cancelled, "
        + "\(host.frames.count) frames presented, last frame \(host.rows)")
  }

  /// The insertion and then the removal played to their end with no input,
  /// and each left the scheduler with nothing armed.
  private static func expectBothTransitionsCameToRest(_ session: Session) throws {
    let report = session.report
    let context = session.context
    #expect(session.exitReason == .userExit(exitKey), "\(context)")
    #expect(report.observerWasReady, "\(context)")
    #expect(report.sawFirstFrame, "\(context)")

    // The insertion. The script pressed the key once and then only waited.
    let insertion = try #require(report.insertion, "the script never pressed a key: \(context)")
    #expect(insertion.cameToRest, "the scheduler did not come to rest: \(context)")
    // The completion fired, the view is in its place, and nothing is armed.
    #expect(insertion.rows.contains("keys i1 r0"), "\(context)")
    #expect(insertion.rows.contains("HERE"), "\(context)")
    #expect(insertion.rows.contains("anchor"), "\(context)")
    #expect(insertion.nextWake == nil, "a frame is armed at rest: \(context)")
    #expect(!insertion.hasPendingFrame, "a frame is pending at rest: \(context)")

    // The removal, the same way.
    let removal = try #require(report.removal, "the script stopped after the insertion: \(context)")
    #expect(removal.cameToRest, "the scheduler did not come to rest: \(context)")
    #expect(removal.rows.contains("keys i1 r1"), "\(context)")
    #expect(!removal.rows.contains { $0.contains("HERE") }, "\(context)")
    #expect(removal.rows.contains("anchor"), "\(context)")
    #expect(removal.nextWake == nil, "a frame is armed at rest: \(context)")
    #expect(!removal.hasPendingFrame, "a frame is pending at rest: \(context)")
  }
}

// MARK: - The script

/// What the script saw when one phase of the scene had ended.
private struct AsyncIdlePhase: CustomStringConvertible {
  /// Whether a pass of the frame driver ended, before the bound, with the
  /// phase's end state on the surface and nothing armed in the scheduler.
  var cameToRest: Bool
  /// The rows of the surface when the script went on.
  var rows: [String]
  /// What the scheduler had armed then.
  var nextWake: MonotonicInstant?
  var hasPendingFrame: Bool
  /// How many values the writer of a noisy scene had written by then.
  var writes: Int
  /// What the run loop and the writer had done last, in words.
  var trail: String

  var description: String {
    "(cameToRest: \(cameToRest), rows: \(rows), "
      + "nextWake: \(nextWake.map { "\($0.offset)" } ?? "nil"), pending: \(hasPendingFrame), "
      + "writes: \(writes), \(trail))"
  }
}

/// What the script observed, for the test body to assert on.
@MainActor
private final class AsyncIdleReport {
  var observerWasReady = false
  var sawFirstFrame = false
  var insertion: AsyncIdlePhase?
  var removal: AsyncIdlePhase?

  var summary: String {
    "insertion \(insertion.map(\.description) ?? "not reached"), "
      + "removal \(removal.map(\.description) ?? "not reached")"
  }
}

/// The input of a session: one key that inserts the view, one key that
/// removes it, and the exit chord. Between them the script sends nothing and
/// waits for the scene to come to rest.
@MainActor
private final class AsyncIdleScript: TerminalInputReading {
  private let host: AsyncIdleHost
  private let scheduler: FrameScheduler
  private let watch: AsyncIdleRestWatch
  /// The pacer of a noisy scene's writer, or `nil` for a quiet scene.
  private let pacer: AsyncIdlePacer?
  private let exitKey: KeyPress
  let report = AsyncIdleReport()

  init(
    host: AsyncIdleHost, scheduler: FrameScheduler, watch: AsyncIdleRestWatch,
    pacer: AsyncIdlePacer?, exitKey: KeyPress
  ) {
    self.host = host
    self.scheduler = scheduler
    self.watch = watch
    self.pacer = pacer
    self.exitKey = exitKey
  }

  /// How long one wait may last. A wait that runs into it has failed.
  private var limit: Duration {
    AsyncTestTimeouts.scaled(.seconds(10))
  }

  nonisolated func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let task = Task { @MainActor in
        await self.play(continuation)
        // The observer ends on the next event the run loop records, which
        // is the one for this key.
        self.watch.stop()
        continuation.yield(.key(self.exitKey))
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func play(_ continuation: AsyncStream<InputEvent>.Continuation) async {
    let host = self.host
    let pacer = self.pacer
    report.observerWasReady = watch.isObserving
    report.sawFirstFrame = await AsyncIdleBoundedWait(on: host.frameSignal) {
      host.rows.contains("keys i0 r0")
    }.wait(within: limit)
    guard report.sawFirstFrame, report.observerWasReady else { return }

    // The view is in, its completion has fired, and the writer has stopped.
    report.insertion = await phase(continuation) {
      host.rows.contains("keys i1 r0") && host.rows.contains("HERE")
        && (pacer.map { $0.finishedBursts == 1 } ?? true)
    }
    guard report.insertion?.cameToRest == true else { return }

    // The view is gone, its completion has fired, and the writer has stopped.
    report.removal = await phase(continuation) {
      host.rows.contains("keys i1 r1") && !host.rows.contains { $0.contains("HERE") }
        && (pacer.map { $0.finishedBursts == 2 } ?? true)
    }
  }

  /// Presses the toggle key once and waits, with no further input, until a
  /// pass of the frame driver ends with `endState` on the surface and the
  /// scheduler at rest.
  private func phase(
    _ continuation: AsyncStream<InputEvent>.Continuation,
    endState: @escaping @MainActor () -> Bool
  ) async -> AsyncIdlePhase {
    watch.arm(endState: endState)
    continuation.yield(.key(KeyPress(.character("t"))))
    let cameToRest = await watch.waitForRest(within: limit)
    let now = MonotonicInstant.now()
    return AsyncIdlePhase(
      cameToRest: cameToRest,
      rows: host.rows,
      nextWake: scheduler.nextWakeInstant(after: now),
      hasPendingFrame: scheduler.hasPendingFrame(at: now),
      writes: pacer?.writes ?? 0,
      trail: watch.trail + (pacer.map { ", \($0.summary)" } ?? ""))
  }
}

/// Tells when the run loop has come to rest.
///
/// The frame driver records a `schedulerIdle` event when a pass ends: no
/// frame is ready, and every frame of the pass has already asked for the
/// frame after it. Whether the run loop then sleeps for good is what the
/// scheduler says at that moment. So the question is asked there, inside the
/// probe's predicate, which the probe calls on the main actor as it records
/// each event. Asked later, from another task, it could catch the run loop
/// between two frames, with one in flight and nothing armed yet.
///
/// The watch also passes every event on to the pacer of a noisy scene.
@MainActor
private final class AsyncIdleRestWatch {
  private let probe: RunLoopProgressProbe
  private let scheduler: FrameScheduler
  private let pacer: AsyncIdlePacer?
  private let signal = MainActorConditionSignal()
  private var endState: (@MainActor () -> Bool)?
  private var armedFromSequence: UInt64 = 0
  private var rests = 0
  private var isStopped = false
  private(set) var isObserving = false
  private var didEndObserving = false
  private var lastEventAt: MonotonicInstant?

  /// The events the probe recorded last and the time since the last one,
  /// for the message of a failed expectation.
  var trail: String {
    let events = probe.events.suffix(24).map { "\($0.kind.rawValue)#\($0.frameNumber)" }
    let age = lastEventAt.map { "\($0.duration(to: .now()))" } ?? "no time"
    return "last event \(age) ago, last events \(events.joined(separator: " "))"
  }

  init(probe: RunLoopProgressProbe, scheduler: FrameScheduler, pacer: AsyncIdlePacer?) {
    self.probe = probe
    self.scheduler = scheduler
    self.pacer = pacer
  }

  /// Starts to read every event the probe records, until ``stop()``.
  func startObserving() {
    Task { @MainActor in
      self.isObserving = true
      _ = await self.probe.event { event in self.note(event) }
      self.didEndObserving = true
    }
  }

  /// Lets the observer end on the next event.
  func stop() {
    isStopped = true
  }

  /// Ends the observer when the run loop has returned and recorded no event
  /// since ``stop()``: the probe gets one more event, for the observer alone.
  func finishObserving() {
    isStopped = true
    if isObserving, !didEndObserving {
      probe.record(.schedulerIdle, frameNumber: 0)
    }
  }

  /// Sets what the surface has to show at the next rest. Only passes that
  /// end from now on count.
  func arm(endState: @escaping @MainActor () -> Bool) {
    self.endState = endState
    armedFromSequence = probe.events.last.map { $0.sequence + 1 } ?? 0
  }

  /// Waits until a pass has ended at rest since ``arm(endState:)``, for
  /// `limit` at most, and returns whether one did.
  func waitForRest(within limit: Duration) async -> Bool {
    let seen = rests
    return await AsyncIdleBoundedWait(on: signal) { self.rests > seen }.wait(within: limit)
  }

  private func note(_ event: RunLoopProgressEvent) -> Bool {
    lastEventAt = .now()
    // The run loop made a step: the writer of a noisy scene may write again.
    pacer?.noteStep()
    guard !isStopped else { return true }
    guard event.kind == .schedulerIdle, event.sequence >= armedFromSequence,
      let endState, endState()
    else { return false }
    let now = MonotonicInstant.now()
    guard scheduler.nextWakeInstant(after: now) == nil, !scheduler.hasPendingFrame(at: now)
    else { return false }
    rests += 1
    signal.notify()
    return false
  }
}

/// Paces the writer of a noisy scene on the run loop's own steps, and tells
/// it when to stop.
///
/// The writer is a task of the scene. It writes one value, then waits here
/// until the run loop has recorded another progress event, and writes
/// again. So nothing times it, and it writes as often as the run loop lets
/// it: the task runs each time the run loop suspends, which is while a frame
/// waits for its tail and while the run loop waits for work.
///
/// The wait cannot outlast a session. A write asks the scheduler for a
/// frame, so the run loop records an event after it. When the task is
/// cancelled, by the next key press or by the end of the run loop, the wait
/// returns at once: the condition signal resumes a cancelled waiter.
///
/// The writer stops when the completion of its transition has fired. Each
/// frame it forced while the transition played armed a frame deadline of
/// its own, so a train of deadlines is still pending then, a fraction of a
/// millisecond apart. The run loop serves them on its own after the writer
/// has stopped, and comes to rest when the last one is gone.
@MainActor
private final class AsyncIdlePacer {
  private let signal = MainActorConditionSignal()
  /// How many progress events the run loop has recorded.
  private(set) var steps = 0
  /// How many transitions the scene has started.
  private(set) var startedTransitions = 0
  /// How many of them have fired their completion.
  private(set) var completedTransitions = 0
  /// How many values the writer has written.
  private(set) var writes = 0
  /// How many times the writer has stopped.
  private(set) var finishedBursts = 0

  /// The counts in words, for the message of a failed expectation.
  var summary: String {
    "writer: \(writes) writes, \(steps) steps, \(startedTransitions) transitions started, "
      + "\(completedTransitions) completed, \(finishedBursts) bursts finished"
  }

  /// The run loop recorded a progress event.
  func noteStep() {
    steps += 1
    signal.notify()
  }

  func transitionDidStart() {
    startedTransitions += 1
  }

  func transitionDidComplete() {
    completedTransitions += 1
  }

  func noteWrite() {
    writes += 1
  }

  func writerDidFinish() {
    finishedBursts += 1
  }

  /// Waits until the run loop has recorded an event after the `seen`th.
  func step(after seen: Int) async {
    await signal.wait(until: { self.steps > seen })
  }
}

/// A wait on a condition signal with a wall-clock bound. The signal's owner
/// notifies it after each change, so the wait resumes on the change. The
/// bound only ends a wait that would never resume.
@MainActor
private final class AsyncIdleBoundedWait {
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

// MARK: - The scene

/// The transitions the inserted view is put under.
enum AsyncIdleKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
  /// A built-in the frame head samples.
  case opacity
  /// A built-in the placed pass samples.
  case move
  /// A type that conforms to `Transition`, whose body holds a view modifier
  /// that conforms to `Animatable`.
  case animatableBody

  var testDescription: String { rawValue }

  @MainActor
  fileprivate var transition: AnyTransition {
    switch self {
    case .opacity:
      .opacity
    case .move:
      .move(edge: .leading)
    case .animatableBody:
      AnyTransition(AsyncIdleSlide())
    }
  }
}

/// A transition whose body reads an `Animatable` value: `AsyncIdleShift`
/// gets data 1 in the identity phase and 0 outside it.
private struct AsyncIdleSlide: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(AsyncIdleShift(progress: phase.isIdentity ? 1 : 0))
  }
}

/// A view modifier that conforms to `Animatable`. It indents its content by
/// six columns at 0 and by none at 1.
private struct AsyncIdleShift: ViewModifier, Animatable {
  var progress: Double

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    content.padding(.leading, max(0, min(6, Int((6 * (1 - progress)).rounded()))))
  }
}

/// An anchor under a transition that never leaves, and a view under a
/// transition that the `t` key inserts and removes inside a 120 ms linear
/// animation with a completion. The first row counts the completions.
///
/// With a pacer the scene is noisy: from each key press until the
/// completion of its transition, a task writes the state of the last row,
/// once for each step of the run loop.
private struct AsyncIdleScene: View {
  @State private var isShown = false
  @State private var inserted = 0
  @State private var removed = 0
  @State private var noise = 0
  @State private var burst = 0
  let kind: AsyncIdleKind
  /// The pacer of the writer, or `nil` for a quiet scene.
  let pacer: AsyncIdlePacer?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("keys i\(inserted) r\(removed)")
        .focusable()
        .onKeyPress(.character("t")) { _ in
          toggle()
          return .handled
        }
      Text("anchor").transition(.opacity)
      if isShown {
        Text("HERE").transition(kind.transition)
      }
      Text("n\(noise)")
    }
    .task(id: burst) {
      guard let pacer, burst > 0 else { return }
      // The writer. It writes one value for each step of the run loop, from
      // the key press until the completion of the transition it started.
      let transition = pacer.startedTransitions
      while pacer.completedTransitions < transition {
        // Read the step count before the write, so that every event the run
        // loop records from the write on ends the wait below.
        let seen = pacer.steps
        noise += 1
        pacer.noteWrite()
        await pacer.step(after: seen)
        if Task.isCancelled { return }
      }
      // One last value: the frame it asks for ends a pass of the frame
      // driver, and at the end of a pass the script reads that the writer
      // has stopped.
      pacer.writerDidFinish()
      noise += 1
      pacer.noteWrite()
    }
  }

  private func toggle() {
    burst += 1
    pacer?.transitionDidStart()
    let isInserting = !isShown
    withAnimation(.linear(duration: .milliseconds(120)), completionCriteria: .removed) {
      isShown.toggle()
    } completion: {
      pacer?.transitionDidComplete()
      if isInserting {
        inserted += 1
      } else {
        removed += 1
      }
    }
  }
}

// MARK: - The host

/// A surface that keeps the text of every frame it is given and notifies a
/// signal for each.
@MainActor
private final class AsyncIdleHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let frameSignal = MainActorConditionSignal()
  private(set) var frames: [[String]] = []

  init(size: CellSize) {
    surfaceSize = size
  }

  /// The rows of the frame presented last, without their trailing spaces.
  var rows: [String] {
    (frames.last ?? []).map { line in
      var characters = Array(line)
      while characters.last == " " {
        characters.removeLast()
      }
      return String(characters)
    }
  }

  nonisolated func enableRawMode() throws {}
  nonisolated func disableRawMode() throws {}
  nonisolated func write(_: String) throws {}
  nonisolated func clearScreen() throws {}
  nonisolated func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  nonisolated func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let lines = surface.lines
    // The run loop presents on the main actor.
    MainActor.assumeIsolated {
      frames.append(lines)
      frameSignal.notify()
    }
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }
}

private final class AsyncIdleSignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
