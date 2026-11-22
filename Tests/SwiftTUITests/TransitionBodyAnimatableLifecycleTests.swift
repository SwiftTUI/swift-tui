@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The lifecycle journeys of `RemovalLifecycleTimingTests` and of
/// `TransitionBodyRemovalLifecycleTests`, for a view that leaves under a
/// transition body with an `Animatable` view or modifier in it (STUI-1546).
///
/// Such a body is evaluated again on every frame of the removal, with the
/// data each conformer presents. That evaluation is outside the graph and
/// mounts nothing, so the times at which an app observes `onDisappear`, task
/// cancellation and state teardown do not move: the content's lifetime still
/// ends on the frame that STARTS the removal. On insertion the frame head
/// evaluates the conformer's owner a second time on the frame of the
/// insertion; that is one mount, with one `onAppear` and one task.
///
/// The tests are those of the custom-body suite, with a copy of its harness
/// (that file's helpers are private), the same clock script and the same
/// assertions, run for three shapes with a conformer in the body. A fourth
/// runs the built-in opacity transition through the same journey and requires
/// the same frame ordinals. The file uses only API that existed before the
/// change.
@MainActor
@Suite("Removal lifecycle timing under a transition body with an Animatable", .serialized)
struct TransitionBodyAnimatableLifecycleTests {
  /// The ways a view leaves here. The first three play a body with a
  /// conformer in it.
  enum Shape: String, CaseIterable, Sendable {
    /// `modifier(active:identity:)` around an `Animatable` modifier: a site
    /// at the identity the body resolves at.
    case modifier
    /// A body that adds an `Animatable` view beside the probe: a site at a
    /// deeper identity.
    case view
    /// The modifier transition combined with `.opacity`: a body with a site
    /// and a built-in effect.
    case mixed
    /// `if show { Probe().transition(.opacity) }`: the built-in reference.
    case builtIn

    static let custom: [Shape] = [.modifier, .view, .mixed]
  }

  /// Frames after the flip frame on which the removal overlay must still be
  /// in flight. About half of the 25 the 800 ms removal lasts, and far more
  /// than the zero frames of slack the lifecycle events get.
  private static let inFlightMargin = 12

  @Test(
    "task cancellation, onDisappear and state teardown land on the frame that starts the removal",
    arguments: Shape.custom)
  func lifecycleRunsAtRemovalStart(shape: Shape) async throws {
    let outcome = try await siteRemovalOutcome(shape: shape, criteria: .removed)
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
      #expect(outcome.text(at: frame).contains("probe co"), "frame \(frame)\n\(outcome.timeline)")
    }
    // The body is what is in flight: its conformer ran on the flip frame and
    // on each frame after it, with data that falls from 1 toward 0, while
    // the content's lifetime was already over.
    let samples = outcome.siteSamples(from: flip)
    for frame in flip...(flip + Self.inFlightMargin) {
      #expect(samples[frame]?.count == 1, "frame \(frame): \(samples[frame] ?? [])")
    }
    let presented = (flip...(flip + Self.inFlightMargin)).compactMap { samples[$0]?.last }
    #expect(presented.first == 1, "\(presented)")
    #expect(
      presented == presented.sorted(by: >) && Set(presented).count == presented.count,
      "\(presented)")
    for (index, value) in presented.enumerated() {
      #expect(abs(value - (1 - Double(index) * 33 / 800)) < 1e-9, "\(presented)")
    }

    // 6. The `.removed` completion fires only once the overlay has left the
    // tree: strictly after every lifecycle event, a full removal later.
    #expect(removed.frame > flip + Self.inFlightMargin, "\(outcome.timeline)")
    #expect(removed.sequence > disappeared.sequence, "\(outcome.timeline)")
    #expect(removed.sequence > released.sequence, "\(outcome.timeline)")
    #expect(
      try #require(outcome.elapsed(from: flip, to: removed.frame))
        >= SiteRemovalJourney.animationDuration,
      "\(outcome.timeline)")
    #expect(!outcome.overlayInFlight(at: removed.frame), "\(outcome.timeline)")
    #expect(!outcome.text(at: removed.frame).contains("probe"), "\(outcome.timeline)")

    // The lifetime ended once: no second disappear, no remount.
    #expect(outcome.count { $0 == .appeared(mount: outcome.mount) } == 1, "\(outcome.timeline)")
    #expect(outcome.mounts == [outcome.mount], "\(outcome.timeline)")
  }

  @Test(
    "completion barriers trail the lifecycle events by the whole removal",
    arguments: Shape.custom)
  func completionBarriersTrailLifecycle(shape: Shape) async throws {
    let logical = try await siteRemovalOutcome(shape: shape, criteria: .logicallyComplete)
    let removed = try await siteRemovalOutcome(shape: shape, criteria: .removed)
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
          >= SiteRemovalJourney.animationDuration,
        "\(outcome.timeline)")
    }
  }

  @Test(
    "re-insertion during the removal mounts a new lifetime with fresh state",
    arguments: Shape.custom)
  func reinsertionDuringRemovalMountsNewLifetime(shape: Shape) async throws {
    let (outcome, reinsert) = try await withSiteRemovalJourney(shape: shape) { journey in
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
  @Test(
    "a custom body removal has the frame ordinals of a built-in removal",
    arguments: Shape.custom, [AnimationCompletionCriteria.logicallyComplete, .removed])
  func ordinalsMatchTheBuiltInRemoval(
    shape: Shape, criteria: AnimationCompletionCriteria
  ) async throws {
    let builtIn = try await siteRemovalOutcome(shape: .builtIn, criteria: criteria)
    let custom = try await siteRemovalOutcome(shape: shape, criteria: criteria)
    // Both journeys run the same clock script, so their ordinals compare.
    try #require(custom.flip == builtIn.flip)
    for event in [
      SiteRemovalEvent.taskCancelled(mount: 0), .disappeared(mount: 0), .stateReleased(mount: 0),
    ] {
      let customRecord = try custom.single(event.for(mount: custom.mount))
      let builtInRecord = try builtIn.single(event.for(mount: builtIn.mount))
      #expect(customRecord.frame == builtInRecord.frame, "\(event)\n\(custom.timeline)")
      #expect(customRecord.frame == custom.flip, "\(event)\n\(custom.timeline)")
    }
    // The overlay is held for the same frames, and the completion fires on
    // the same frame, at the same instant on the frame clock.
    let customFrames = custom.samples.filter(\.value.overlayInFlight).keys.sorted()
    let builtInFrames = builtIn.samples.filter(\.value.overlayInFlight).keys.sorted()
    #expect(customFrames == builtInFrames, "\(custom.timeline)\n\(builtIn.timeline)")
    let customCompletion = try custom.single(.completion)
    let builtInCompletion = try builtIn.single(.completion)
    #expect(
      customCompletion.frame == builtInCompletion.frame,
      "\(custom.timeline)\n\(builtIn.timeline)")
    #expect(
      custom.elapsed(from: custom.flip, to: customCompletion.frame)
        == builtIn.elapsed(from: builtIn.flip, to: builtInCompletion.frame))
  }
}

/// Runs one removal: mounts the probe, lets its task start, flips `show` to
/// `false` under the 800 ms linear animation with a completion on `criteria`,
/// and renders every armed turn until the removal has drained.
@MainActor
private func siteRemovalOutcome(
  shape: TransitionBodyAnimatableLifecycleTests.Shape,
  criteria: AnimationCompletionCriteria
) async throws -> SiteRemovalOutcome {
  try await withSiteRemovalJourney(shape: shape) { journey in
    let mount = try await journey.awaitMountedProbe()
    let flip = try journey.setShown(false, criteria: criteria)
    try journey.advance(by: .seconds(2))
    return journey.outcome(mount: mount, flip: flip)
  }
}

@MainActor
private func withSiteRemovalJourney<Result>(
  shape: TransitionBodyAnimatableLifecycleTests.Shape,
  _ body: (SiteRemovalJourney) async throws -> Result
) async throws -> Result {
  let journey = try SiteRemovalJourney(shape: shape)
  do {
    let result = try await body(journey)
    await journey.finish()
    return result
  } catch {
    await journey.finish()
    throw error
  }
}

private enum SiteRemovalEvent: Hashable, Sendable {
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
  /// The body of the transition's `Animatable` conformer ran with `data`.
  case site(data: Double)

  /// This lifecycle event for another mount.
  func `for`(mount: Int) -> SiteRemovalEvent {
    switch self {
    case .taskCancelled: .taskCancelled(mount: mount)
    case .disappeared: .disappeared(mount: mount)
    case .stateReleased: .stateReleased(mount: mount)
    default: self
    }
  }
}

private struct SiteRemovalRecord: Sendable {
  var event: SiteRemovalEvent
  /// Position in the recorder's log: the order in which events happened.
  var sequence: Int
  /// See ``SiteRemovalRecorder``.
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
private final class SiteRemovalRecorder: Sendable {
  private struct Storage {
    var instants: [MonotonicInstant?] = [nil]
    var nextSerial = 1
    var records: [SiteRemovalRecord] = []
  }

  private let storage = Mutex(Storage())
  let changed = MainActorConditionSignal()

  var frame: Int { storage.withLock { $0.instants.count - 1 } }
  var instants: [MonotonicInstant?] { storage.withLock { $0.instants } }
  var records: [SiteRemovalRecord] { storage.withLock { $0.records } }

  func beginFrame(at instant: MonotonicInstant) {
    storage.withLock { $0.instants.append(instant) }
  }

  func allocateSerial() -> Int {
    storage.withLock {
      defer { $0.nextSerial += 1 }
      return $0.nextSerial
    }
  }

  func record(_ event: SiteRemovalEvent) {
    storage.withLock {
      $0.records.append(
        SiteRemovalRecord(
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

/// Reference state for the probe's `@State`. Every `SiteRemovalProbe` value
/// creates one as its initial value; the one a mounted probe's state slot
/// owns is the one whose `serial` its body reads, and that serial names the
/// mount in every event.
private final class SiteRemovalStateToken: Sendable {
  let serial: Int
  private let recorder: SiteRemovalRecorder

  init(recorder: SiteRemovalRecorder) {
    self.recorder = recorder
    serial = recorder.allocateSerial()
  }

  deinit {
    recorder.record(.stateReleased(mount: serial))
  }
}

@MainActor
private final class SiteRemovalControls {
  var show: Binding<Bool>?
  var count: Binding<Int>?
}

@MainActor
private final class SiteRemovalClock {
  var now = MonotonicInstant.now()
}

private struct SiteRemovalFrameSample {
  var overlayInFlight: Bool
  var text: String
}

/// What one journey observed, detached from the harness.
private struct SiteRemovalOutcome {
  /// The state-token serial of the probe that was mounted before the flip.
  var mount: Int
  /// The ordinal of the frame on which presence flipped.
  var flip: Int
  var records: [SiteRemovalRecord]
  var instants: [MonotonicInstant?]
  var samples: [Int: SiteRemovalFrameSample]

  func count(where matches: (SiteRemovalEvent) -> Bool) -> Int {
    records.count { matches($0.event) }
  }

  func single(_ event: SiteRemovalEvent) throws -> SiteRemovalRecord {
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

  /// The data the transition's conformer ran with on each frame from
  /// `frame` on, by frame.
  func siteSamples(from frame: Int) -> [Int: [Double]] {
    var samples: [Int: [Double]] = [:]
    for record in records where record.frame >= frame {
      if case .site(let data) = record.event {
        samples[record.frame, default: []].append(data)
      }
    }
    return samples
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
private final class SiteRemovalJourney {
  static let animationDuration = Duration.milliseconds(800)

  let recorder: SiteRemovalRecorder
  let harness: StressRuntimeHarness<SiteRemovalRoot>
  private let controls: SiteRemovalControls
  private let controller: AnimationController
  private let clock: SiteRemovalClock
  private var samples: [Int: SiteRemovalFrameSample] = [:]

  init(shape: TransitionBodyAnimatableLifecycleTests.Shape) throws {
    let recorder = SiteRemovalRecorder()
    let controls = SiteRemovalControls()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TransitionSiteRemovalLifecycle", shape.rawValue),
      size: .init(width: 30, height: 4)
    ) { SiteRemovalRoot(shape: shape, recorder: recorder, controls: controls) }
    let clock = SiteRemovalClock()
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
    samples[recorder.frame] = SiteRemovalFrameSample(
      overlayInFlight: overlayInFlight, text: harness.frame)
  }

  private func renderTurn() throws {
    _ = try harness.render()
    sampleCurrentFrame()
  }

  /// Moves the clock to the turn the scheduler already has armed, if any, so
  /// that a write made next is answered by that turn's frame. An animation
  /// in flight keeps the 33 ms deadline armed; a write made off that grid
  /// would start a second deadline chain and double the frames per interval.
  /// A mounted `.transition` at rest arms nothing, and the clock then stays
  /// where it is. No assertion depends on the cadence, but one frame per
  /// interval keeps the ordinals easy to read.
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

  func outcome(mount: Int, flip: Int) -> SiteRemovalOutcome {
    SiteRemovalOutcome(
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

private struct SiteRemovalRoot: View {
  let shape: TransitionBodyAnimatableLifecycleTests.Shape
  let recorder: SiteRemovalRecorder
  let controls: SiteRemovalControls
  @State private var show = true

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Text("survivor")
      switch shape {
      case .modifier:
        if show { probe.transition(fade) }
      case .view:
        if show { probe.transition(LifecycleMeterBeside(recorder: recorder)) }
      case .mixed:
        if show { probe.transition(fade.combined(with: .opacity)) }
      case .builtIn:
        if show { probe.transition(.opacity) }
      }
    }
  }

  private var probe: SiteRemovalProbe {
    SiteRemovalProbe(recorder: recorder, controls: controls)
  }

  private var fade: AnyTransition {
    .modifier(
      active: LifecycleFade(progress: 0, recorder: recorder),
      identity: LifecycleFade(progress: 1, recorder: recorder))
  }

  private func capture() {
    controls.show = $show
  }
}

/// The departing view. Its lifecycle closures capture the recorder and the
/// mount's serial only, never the probe value: a captured probe would keep
/// its `@State` wrapper's initial value alive, and for the first mount that
/// is the very object the state slot owns.
private struct SiteRemovalProbe: View {
  let recorder: SiteRemovalRecorder
  let controls: SiteRemovalControls
  @State private var token: SiteRemovalStateToken
  @State private var count = 0

  init(recorder: SiteRemovalRecorder, controls: SiteRemovalControls) {
    self.recorder = recorder
    self.controls = controls
    _token = State(wrappedValue: SiteRemovalStateToken(recorder: recorder))
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

/// A modifier that conforms to `Animatable`, records the data its body
/// runs with, and dims its content without hiding it.
private struct LifecycleFade: ViewModifier, Animatable {
  var progress: Double
  let recorder: SiteRemovalRecorder

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let _ = recorder.record(.site(data: progress))
    content.opacity(0.25 + 0.75 * max(0, min(1, progress)))
  }
}

/// A view that conforms to `Animatable` and draws a bar of its level.
private struct LifecycleMeter: View, Animatable {
  var level: Double
  let recorder: SiteRemovalRecorder

  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }

  var body: some View {
    let _ = recorder.record(.site(data: level))
    Text(String(repeating: "#", count: max(0, min(8, Int((level * 8).rounded())))))
  }
}

/// A body that adds an `Animatable` view beside its content.
private struct LifecycleMeterBeside: Transition {
  let recorder: SiteRemovalRecorder

  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 1) {
      content
      LifecycleMeter(level: phase.isIdentity ? 1 : 0, recorder: recorder)
    }
  }
}
