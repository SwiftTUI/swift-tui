@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Pins when an app observes the lifecycle of a view that leaves under a
/// removal transition (first-class transitions, requirement 3.3: "The times
/// at which an app observes `onDisappear`, task cancellation and state
/// teardown do not move").
///
/// SwiftTUI ends the departing view's lifetime on the frame that STARTS the
/// removal: the frame on which presence flips cancels the view's task, runs
/// `onDisappear` and drops its `@State` storage. The removal overlay that the
/// animation controller then draws for the animation's duration is a visual
/// afterimage with no lifecycle of its own. SwiftUI instead keeps the view
/// alive until the transition ends. Every assertion here is written to FAIL
/// if lifecycle moved to the end of the removal animation: the lifecycle
/// events are required on the flip frame itself, while the 800 ms overlay is
/// required to stay in flight for at least `inFlightMargin` further frames
/// (measured: it is held through flip + 25 on the 33 ms animation deadline
/// chain, and `.removed` fires on flip + 26).
///
/// The journeys run a real `RunLoop` on an injected frame clock and render
/// one armed scheduler turn at a time, so every ordinal is deterministic.
/// Events are recorded against presented-frame ordinals (see
/// ``RemovalRecorder``) and the frame clock; the assertions are stated
/// relative to the flip frame.
@MainActor
@Suite("Removal lifecycle timing under a removal transition", .serialized)
struct RemovalLifecycleTimingTests {
  /// The three ways a view leaves under an animated transaction.
  enum Shape: String, CaseIterable, Sendable {
    /// `if show { Probe().transition(.opacity) }`
    case opacity
    /// `if show { Probe().transition(.move(edge: .leading)) }`
    case moveLeading
    /// `if show { Probe() }`: no modifier, the default opacity presence.
    case unmarked
  }

  /// Frames after the flip frame on which the removal overlay must still be
  /// in flight. About half of the 25 the 800 ms removal lasts, and far more
  /// than the zero frames of slack the lifecycle events get.
  private static let inFlightMargin = 12

  @Test(
    "task cancellation, onDisappear and state teardown land on the frame that starts the removal",
    arguments: Shape.allCases)
  func lifecycleRunsAtRemovalStart(shape: Shape) async throws {
    let outcome = try await removalOutcome(shape: shape, criteria: .removed)
    let flip = outcome.flip
    let cancelled = try outcome.single(.taskCancelled(mount: outcome.mount))
    let disappeared = try outcome.single(.disappeared(mount: outcome.mount))
    let released = try outcome.single(.stateReleased(mount: outcome.mount))
    let removed = try outcome.single(.completion)

    // 1. `onDisappear` runs at the commit of the flip frame. Deferred to the
    // overlay's end it would carry an ordinal about 25 frames later.
    #expect(disappeared.frame == flip, "\(outcome.timeline)")
    #expect(disappeared.instant == outcome.instant(of: flip), "\(outcome.timeline)")

    // 2. The probe's task observes cancellation on the flip frame. The
    // recorder writes from the cancellation handler, which `Task.cancel()`
    // runs synchronously, so the ordinal is the frame whose commit cancelled
    // the task. (The task body's own resumption needs a main-actor turn that
    // this synchronous driver does not yield; it is not asserted.)
    #expect(cancelled.frame == flip, "\(outcome.timeline)")
    #expect(cancelled.instant == outcome.instant(of: flip), "\(outcome.timeline)")

    // 3. State teardown: the object the probe's `@State` owns is released on
    // the flip frame. Measured at this pin: the release happens in that
    // frame's resolve, ahead of the commit that dispatches 1 and 2; only the
    // frame is asserted. An engine that kept the departing subtree's state
    // alive for the overlay would release it about 25 frames later.
    #expect(released.frame == flip, "\(outcome.timeline)")

    // 5. Removal cancels the owned task before it runs disappear handlers.
    #expect(cancelled.sequence < disappeared.sequence, "\(outcome.timeline)")

    // 4. With 1-3 done, the removal overlay is still in flight: the
    // controller holds the removal on the flip frame and on each of the next
    // `inFlightMargin` frames, and the departing text is still drawn.
    for frame in flip...(flip + Self.inFlightMargin) {
      #expect(outcome.overlayInFlight(at: frame), "frame \(frame)\n\(outcome.timeline)")
    }
    for frame in flip...(flip + 3) {
      #expect(outcome.text(at: frame).contains("count 0"), "frame \(frame)\n\(outcome.timeline)")
    }
    if shape == .moveLeading {
      // The move transition is what is in flight: the overlay slides off the
      // leading edge, so a later frame draws the probe's row clipped.
      let clipped = (flip...(flip + Self.inFlightMargin)).contains { frame in
        let text = outcome.text(at: frame)
        return text.contains("count 0") && !text.contains("probe count 0")
      }
      #expect(clipped, "\(outcome.timeline)")
    }

    // 6. The `.removed` completion fires only once the overlay has left the
    // tree: strictly after every lifecycle event, a full removal later.
    #expect(removed.frame > flip + Self.inFlightMargin, "\(outcome.timeline)")
    #expect(removed.sequence > disappeared.sequence, "\(outcome.timeline)")
    #expect(removed.sequence > released.sequence, "\(outcome.timeline)")
    #expect(
      try #require(outcome.elapsed(from: flip, to: removed.frame))
        >= RemovalJourney.animationDuration,
      "\(outcome.timeline)")
    #expect(!outcome.overlayInFlight(at: removed.frame), "\(outcome.timeline)")
    #expect(!outcome.text(at: removed.frame).contains("count"), "\(outcome.timeline)")

    // The lifetime ended once: no second disappear, no remount.
    #expect(outcome.count { $0 == .appeared(mount: outcome.mount) } == 1, "\(outcome.timeline)")
    #expect(outcome.mounts == [outcome.mount], "\(outcome.timeline)")
  }

  @Test(
    "completion barriers trail the lifecycle events by the whole removal",
    arguments: Shape.allCases)
  func completionBarriersTrailLifecycle(shape: Shape) async throws {
    let logical = try await removalOutcome(shape: shape, criteria: .logicallyComplete)
    let removed = try await removalOutcome(shape: shape, criteria: .removed)
    // Both journeys run the same clock script, so their ordinals compare.
    try #require(logical.flip == removed.flip)
    let flip = removed.flip
    let logicalCompletion = try logical.single(.completion)
    let removedCompletion = try removed.single(.completion)

    // `.logicallyComplete` fires when the curve ends, `.removed` when the
    // overlay has been purged: never before it.
    #expect(logicalCompletion.frame <= removedCompletion.frame)

    for (outcome, completion) in [(logical, logicalCompletion), (removed, removedCompletion)] {
      // The barrier a completion waits on does not move the lifecycle.
      let cancelled = try outcome.single(.taskCancelled(mount: outcome.mount))
      let disappeared = try outcome.single(.disappeared(mount: outcome.mount))
      let released = try outcome.single(.stateReleased(mount: outcome.mount))
      #expect(cancelled.frame == flip, "\(outcome.timeline)")
      #expect(disappeared.frame == flip, "\(outcome.timeline)")
      #expect(released.frame == flip, "\(outcome.timeline)")
      #expect(cancelled.sequence < disappeared.sequence, "\(outcome.timeline)")

      // Either completion waits out the animation; the lifecycle does not.
      #expect(completion.frame > flip + Self.inFlightMargin, "\(outcome.timeline)")
      #expect(completion.sequence > disappeared.sequence, "\(outcome.timeline)")
      #expect(
        try #require(outcome.elapsed(from: flip, to: completion.frame))
          >= RemovalJourney.animationDuration,
        "\(outcome.timeline)")
    }
  }

  @Test(
    "re-insertion during the removal mounts a new lifetime with fresh state",
    arguments: Shape.allCases)
  func reinsertionDuringRemovalMountsNewLifetime(shape: Shape) async throws {
    let (outcome, reinsert) = try await withRemovalJourney(shape: shape) { journey in
      let mount = try await journey.awaitMountedProbe()
      try journey.setCount(3)
      try #require(journey.harness.frame.contains("probe count 3"))
      let flip = try journey.setShown(false, criteria: nil)
      // Re-insert on the first armed turn at or after 300 ms, with well over
      // half of the 800 ms removal still to run.
      try journey.advance(by: .milliseconds(300))

      // Before the re-insertion, with the overlay still in flight, the first
      // lifetime is already over: it ended on the flip frame. Had it been
      // held for the overlay, none of these would have been recorded yet and
      // its task would still be live.
      let removal = journey.outcome(mount: mount, flip: flip)
      try #require(journey.overlayInFlight, "\(removal.timeline)")
      #expect(try removal.single(.taskCancelled(mount: mount)).frame == flip, "\(removal.timeline)")
      #expect(try removal.single(.disappeared(mount: mount)).frame == flip, "\(removal.timeline)")
      #expect(try removal.single(.stateReleased(mount: mount)).frame == flip, "\(removal.timeline)")
      #expect(journey.harness.activeTaskCount == 0, "\(removal.timeline)")

      let reinsert = try journey.setShown(true, criteria: nil)
      // The re-insertion's commit starts the new mount's task. Let its body
      // take its first turn.
      try #require(
        journey.harness.activeTaskCount == 1,
        "exactly the new mount's task is live after the re-insertion commits")
      await journey.recorder.changed.wait { [recorder = journey.recorder] in
        recorder.records.contains { record in
          if case .taskStarted(let started) = record.event { return started != mount }
          return false
        }
      }
      try journey.advance(by: .milliseconds(1200))
      return (journey.outcome(mount: mount, flip: flip), reinsert)
    }
    let flip = outcome.flip
    let first = outcome.mount
    try #require(reinsert > flip + 5, "\(outcome.timeline)")

    // The re-insertion did not end the first lifetime a second time: each of
    // its events still happened exactly once, on the flip frame.
    #expect(try outcome.single(.taskCancelled(mount: first)).frame == flip, "\(outcome.timeline)")
    #expect(try outcome.single(.disappeared(mount: first)).frame == flip, "\(outcome.timeline)")
    #expect(try outcome.single(.stateReleased(mount: first)).frame == flip, "\(outcome.timeline)")

    // The re-insertion is a NEW mount: `onAppear` fires again, on the
    // re-insertion frame, for a probe that owns a different state object.
    let appearances = outcome.records.compactMap { record -> (mount: Int, frame: Int)? in
      if case .appeared(let mount) = record.event { return (mount, record.frame) }
      return nil
    }
    try #require(appearances.count == 2, "\(outcome.timeline)")
    let second = appearances[1].mount
    #expect(appearances[0].mount == first, "\(outcome.timeline)")
    #expect(second != first, "\(outcome.timeline)")
    #expect(appearances[1].frame == reinsert, "\(outcome.timeline)")
    #expect(outcome.mounts == [first, second], "\(outcome.timeline)")
    #expect(outcome.count { $0 == .taskStarted(mount: second) } == 1, "\(outcome.timeline)")

    // State was reset: the first mount's counter read 3 when it left, the new
    // mount's starts from the initial value again.
    #expect(outcome.counts(of: first).last == 3, "\(outcome.timeline)")
    #expect(outcome.counts(of: second).first == 0, "\(outcome.timeline)")
    #expect(outcome.counts(of: second).allSatisfy { $0 == 0 }, "\(outcome.timeline)")
    #expect(outcome.lastText.contains("probe count 0"), "\(outcome.timeline)")

    // The new lifetime is live: nothing has ended it.
    #expect(outcome.count { $0 == .disappeared(mount: second) } == 0, "\(outcome.timeline)")
    #expect(outcome.count { $0 == .taskCancelled(mount: second) } == 0, "\(outcome.timeline)")
    #expect(outcome.count { $0 == .stateReleased(mount: second) } == 0, "\(outcome.timeline)")
  }
}

/// Runs one removal: mounts the probe, lets its task start, flips `show` to
/// `false` under the 800 ms linear animation with a completion on `criteria`,
/// and renders every armed turn until the removal has drained.
@MainActor
private func removalOutcome(
  shape: RemovalLifecycleTimingTests.Shape,
  criteria: AnimationCompletionCriteria
) async throws -> RemovalOutcome {
  try await withRemovalJourney(shape: shape) { journey in
    let mount = try await journey.awaitMountedProbe()
    let flip = try journey.setShown(false, criteria: criteria)
    try journey.advance(by: .seconds(2))
    return journey.outcome(mount: mount, flip: flip)
  }
}

@MainActor
private func withRemovalJourney<Result>(
  shape: RemovalLifecycleTimingTests.Shape,
  _ body: (RemovalJourney) async throws -> Result
) async throws -> Result {
  let journey = try RemovalJourney(shape: shape)
  do {
    let result = try await body(journey)
    await journey.finish()
    return result
  } catch {
    await journey.finish()
    throw error
  }
}

private enum RemovalEvent: Hashable, Sendable {
  /// The probe's body ran for the mount that owns state token `mount`.
  case body(mount: Int, count: Int)
  case appeared(mount: Int)
  case disappeared(mount: Int)
  case taskStarted(mount: Int)
  /// Recorded from the task's cancellation handler.
  case taskCancelled(mount: Int)
  case taskFinished(mount: Int)
  /// The `deinit` of the object the mount's `@State` owns.
  case stateReleased(mount: Int)
  case completion
}

private struct RemovalRecord: Sendable {
  var event: RemovalEvent
  /// Position in the recorder's log: the order in which events happened.
  var sequence: Int
  /// See ``RemovalRecorder``.
  var frame: Int
  var instant: MonotonicInstant?
}

/// Records lifecycle events against presented-frame ordinals.
///
/// The ordinal counts the frames the run loop has acquired since the recorder
/// was attached; on the synchronous driver every acquisition presents. An
/// event carries the ordinal of the most recently acquired frame, so an event
/// recorded while frame N resolves or commits, or after it and before frame
/// N + 1 is acquired, carries N. Lifecycle handlers and completions run after
/// the frame is presented, inside its commit. Frame 0 is the harness's
/// initial frame, rendered before the recorder is attached.
///
/// `Sendable` behind a mutex because two producers are not on the main actor:
/// a cancellation handler runs wherever `Task.cancel()` is called, and a
/// `deinit` runs wherever the last reference is dropped.
private final class RemovalRecorder: Sendable {
  private struct Storage {
    var instants: [MonotonicInstant?] = [nil]
    var nextSerial = 1
    var records: [RemovalRecord] = []
  }

  private let storage = Mutex(Storage())
  let changed = MainActorConditionSignal()

  var frame: Int { storage.withLock { $0.instants.count - 1 } }
  var instants: [MonotonicInstant?] { storage.withLock { $0.instants } }
  var records: [RemovalRecord] { storage.withLock { $0.records } }

  func beginFrame(at instant: MonotonicInstant) {
    storage.withLock { $0.instants.append(instant) }
  }

  func allocateSerial() -> Int {
    storage.withLock {
      defer { $0.nextSerial += 1 }
      return $0.nextSerial
    }
  }

  func record(_ event: RemovalEvent) {
    storage.withLock {
      $0.records.append(
        RemovalRecord(
          event: event, sequence: $0.records.count, frame: $0.instants.count - 1,
          instant: $0.instants[$0.instants.count - 1]))
    }
  }

  /// The probe's task: signals that it started, then stays suspended until
  /// it is cancelled. The cancellation handler records synchronously inside
  /// `Task.cancel()`, on the frame whose commit cancelled the task.
  @MainActor
  func runTask(mount: Int) async {
    record(.taskStarted(mount: mount))
    changed.notify()
    await withTaskCancellationHandler {
      await suspendUntilCancelled()
    } onCancel: {
      record(.taskCancelled(mount: mount))
    }
    record(.taskFinished(mount: mount))
    changed.notify()
  }
}

/// Reference state for the probe's `@State`. Every `RemovalProbe` value
/// creates one as its initial value; the one a mounted probe's state slot
/// owns is the one whose `serial` its body reads, and that serial names the
/// mount in every event.
private final class RemovalStateToken: Sendable {
  let serial: Int
  private let recorder: RemovalRecorder

  init(recorder: RemovalRecorder) {
    self.recorder = recorder
    serial = recorder.allocateSerial()
  }

  deinit {
    recorder.record(.stateReleased(mount: serial))
  }
}

@MainActor
private final class RemovalControls {
  var show: Binding<Bool>?
  var count: Binding<Int>?
}

@MainActor
private final class RemovalClock {
  var now = MonotonicInstant.now()
}

private struct RemovalFrameSample {
  var overlayInFlight: Bool
  var text: String
}

/// What one journey observed, detached from the harness.
private struct RemovalOutcome {
  /// The state-token serial of the probe that was mounted before the flip.
  var mount: Int
  /// The ordinal of the frame on which presence flipped.
  var flip: Int
  var records: [RemovalRecord]
  var instants: [MonotonicInstant?]
  var samples: [Int: RemovalFrameSample]

  func count(where matches: (RemovalEvent) -> Bool) -> Int {
    records.count { matches($0.event) }
  }

  func single(_ event: RemovalEvent) throws -> RemovalRecord {
    let matches = records.filter { $0.event == event }
    try #require(matches.count == 1, "expected exactly one \(event)\n\(timeline)")
    return matches[0]
  }

  /// The distinct mounts whose body ran, in first-evaluation order.
  var mounts: [Int] {
    var seen: [Int] = []
    for case .body(let mount, _) in records.map(\.event) where !seen.contains(mount) {
      seen.append(mount)
    }
    return seen
  }

  func counts(of mount: Int) -> [Int] {
    records.compactMap { record in
      if case .body(mount, let count) = record.event { return count }
      return nil
    }
  }

  func instant(of frame: Int) -> MonotonicInstant? {
    instants.indices.contains(frame) ? instants[frame] : nil
  }

  func elapsed(from start: Int, to end: Int) -> Duration? {
    guard let start = instant(of: start), let end = instant(of: end) else { return nil }
    return start.duration(to: end)
  }

  func overlayInFlight(at frame: Int) -> Bool {
    samples[frame]?.overlayInFlight ?? false
  }

  func text(at frame: Int) -> String {
    samples[frame]?.text ?? ""
  }

  var lastText: String {
    samples.keys.max().map { text(at: $0) } ?? ""
  }

  /// The event log and the overlay's span, for failure messages.
  var timeline: String {
    var lines = ["flip frame \(flip), mount \(mount)"]
    for record in records {
      let offset =
        if let base = instant(of: flip), let instant = record.instant {
          "\(base.duration(to: instant))"
        } else {
          "before the clock"
        }
      lines.append("  #\(record.sequence) frame \(record.frame) (\(offset)): \(record.event)")
    }
    let inFlight = samples.filter(\.value.overlayInFlight).keys.sorted()
    if let first = inFlight.first, let last = inFlight.last {
      lines.append("  overlay in flight on frames \(first)...\(last) of 0...\(instants.count - 1)")
    } else {
      lines.append("  overlay never in flight")
    }
    return lines.joined(separator: "\n")
  }
}

/// A `StressRuntimeHarness` on an injected frame clock, with the recorder
/// attached to the run loop's frame acquisitions.
@MainActor
private final class RemovalJourney {
  static let animationDuration = Duration.milliseconds(800)

  let recorder: RemovalRecorder
  let harness: StressRuntimeHarness<RemovalRoot>
  private let controls: RemovalControls
  private let controller: AnimationController
  private let clock: RemovalClock
  private var samples: [Int: RemovalFrameSample] = [:]

  init(shape: RemovalLifecycleTimingTests.Shape) throws {
    let recorder = RemovalRecorder()
    let controls = RemovalControls()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("RemovalLifecycleTiming", shape.rawValue),
      size: .init(width: 30, height: 4)
    ) { RemovalRoot(shape: shape, recorder: recorder, controls: controls) }
    let clock = RemovalClock()
    self.recorder = recorder
    self.controls = controls
    self.harness = harness
    self.clock = clock
    controller = harness.runLoop.renderer.internalAnimationController
    harness.runLoop.frameClock = { clock.now }
    // Sample the frame that just finished before the next one is counted, so
    // every frame is sampled even when one turn presents more than one.
    harness.runLoop.frameClockDidAcquire = { [weak self] instant in
      self?.sampleCurrentFrame()
      recorder.beginFrame(at: instant)
    }
    sampleCurrentFrame()
  }

  /// Whether the animation controller holds a removal overlay.
  var overlayInFlight: Bool {
    !controller.debugStateSnapshot().removingNodeIDs.isEmpty
  }

  private func sampleCurrentFrame() {
    samples[recorder.frame] = RemovalFrameSample(
      overlayInFlight: overlayInFlight, text: harness.frame)
  }

  private func renderTurn() throws {
    _ = try harness.render()
    sampleCurrentFrame()
  }

  /// Moves the clock to the turn the scheduler already has armed, if any, so
  /// that a write made next is answered by that turn's frame. A mounted
  /// `.transition` keeps the 33 ms animation deadline armed at this pin; a
  /// write made off that grid would start a second deadline chain and double
  /// the frames per interval. No assertion depends on the cadence, but one
  /// frame per interval keeps the ordinals easy to read.
  private func rideArmedTurn() {
    if let wake = harness.runLoop.scheduler.nextWakeInstant(after: clock.now) {
      clock.now = wake
    }
  }

  /// Waits until the mounted probe's task body has started, and returns the
  /// mount's state-token serial. A task cancelled before its first turn never
  /// enters its body, so it could not observe the cancellation.
  func awaitMountedProbe() async throws -> Int {
    let mounts = outcome(mount: 0, flip: 0).mounts
    try #require(mounts.count == 1)
    let mount = mounts[0]
    try #require(harness.frame.contains("probe count 0"))
    try #require(harness.activeTaskCount == 1)
    await recorder.changed.wait { [recorder] in
      recorder.records.contains { $0.event == .taskStarted(mount: mount) }
    }
    return mount
  }

  func setCount(_ value: Int) throws {
    let binding = try #require(controls.count)
    rideArmedTurn()
    try withAnimationSinks(controller) {
      binding.wrappedValue = value
      try renderTurn()
    }
  }

  /// Writes `show` under the journey's animation and renders the frame that
  /// answers the write. Returns that frame's ordinal: the flip frame.
  func setShown(_ shown: Bool, criteria: AnimationCompletionCriteria?) throws -> Int {
    let binding = try #require(controls.show)
    let animation = Animation.linear(duration: Self.animationDuration)
    rideArmedTurn()
    let frame = recorder.frame + 1
    try withAnimationSinks(controller) {
      if let criteria {
        withAnimation(animation, completionCriteria: criteria) {
          binding.wrappedValue = shown
        } completion: { [recorder] in
          recorder.record(.completion)
        }
      } else {
        withAnimation(animation) { binding.wrappedValue = shown }
      }
      try renderTurn()
    }
    try #require(recorder.frame >= frame)
    return frame
  }

  /// Advances the clock by `duration`, rendering every turn the scheduler
  /// arms on the way at exactly its wake instant.
  func advance(by duration: Duration) throws {
    let target = clock.now.advanced(by: duration)
    try withAnimationSinks(controller) {
      var turns = 0
      while let wake = harness.runLoop.scheduler.nextWakeInstant(after: clock.now),
        wake <= target, turns < 256
      {
        clock.now = wake
        try renderTurn()
        turns += 1
      }
      #expect(turns < 256, "the journey must fit the fixed turn budget")
    }
    clock.now = target
  }

  func outcome(mount: Int, flip: Int) -> RemovalOutcome {
    RemovalOutcome(
      mount: mount, flip: flip, records: recorder.records, instants: recorder.instants,
      samples: samples)
  }

  /// Shuts the harness down and waits for every started task body to return,
  /// so no task outlives its test.
  func finish() async {
    harness.shutdown()
    await recorder.changed.wait { [recorder] in
      let records = recorder.records
      let started = records.count {
        if case .taskStarted = $0.event { return true }
        return false
      }
      let finished = records.count {
        if case .taskFinished = $0.event { return true }
        return false
      }
      return started == finished
    }
  }
}

private struct RemovalRoot: View {
  let shape: RemovalLifecycleTimingTests.Shape
  let recorder: RemovalRecorder
  let controls: RemovalControls
  @State private var show = true

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Text("survivor")
      switch shape {
      case .opacity:
        if show { probe.transition(.opacity) }
      case .moveLeading:
        if show { probe.transition(.move(edge: .leading)) }
      case .unmarked:
        if show { probe }
      }
    }
  }

  private var probe: RemovalProbe {
    RemovalProbe(recorder: recorder, controls: controls)
  }

  private func capture() {
    controls.show = $show
  }
}

/// The departing view. Its lifecycle closures capture the recorder and the
/// mount's serial only, never the probe value: a captured probe would keep
/// its `@State` wrapper's initial value alive, and for the first mount that
/// is the very object the state slot owns.
private struct RemovalProbe: View {
  let recorder: RemovalRecorder
  let controls: RemovalControls
  @State private var token: RemovalStateToken
  @State private var count = 0

  init(recorder: RemovalRecorder, controls: RemovalControls) {
    self.recorder = recorder
    self.controls = controls
    _token = State(wrappedValue: RemovalStateToken(recorder: recorder))
  }

  var body: some View {
    let mount = token.serial
    let _ = capture(mount: mount)
    Text("probe count \(count)")
      .onAppear { [recorder] in recorder.record(.appeared(mount: mount)) }
      .onDisappear { [recorder] in recorder.record(.disappeared(mount: mount)) }
      .task { [recorder] in await recorder.runTask(mount: mount) }
  }

  private func capture(mount: Int) {
    recorder.record(.body(mount: mount, count: count))
    controls.count = $count
  }
}
