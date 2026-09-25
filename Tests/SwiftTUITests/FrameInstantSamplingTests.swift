import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// The frame-instant sampling contract (plan 2026-09-24-001 §4B, STUI-618).
///
/// Every acquisition — deadline, input, invalidation — samples the injected
/// frame clock once and animates to that reading, made non-decreasing across
/// acquisitions. Deadline frames no longer animate to their *scheduled*
/// instant, so a loop whose frames cost more than the 33 ms cadence advances
/// animation time by the elapsed cost and skips the missed visual samples
/// instead of replaying 33 ms steps until the armed chain catches up. The
/// counter demo's ripple backlog was that replay: a 1.6 s effect needed about
/// 49 rendered ticks however slow each one was.
///
/// The scenarios use a virtual frame clock and a diagnostic sink that charges
/// a fixed render cost per committed frame, so "a 160 ms frame" is exact and
/// machine-independent.
@MainActor
@Suite
struct FrameInstantSamplingTests {
  @Test("an on-time deadline frame animates to the deadline instant with no lag")
  func onTimeDeadlineFrameSamplesTheDeadline() throws {
    let harness = try SampledClockHarness()
    try harness.click("go")
    harness.sink.reset()

    let deadline = try #require(harness.scheduler.nextWakeInstant(after: harness.clock.now))
    #expect(deadline == harness.clock.now.advanced(by: .milliseconds(33)))
    harness.clock.now = deadline
    try harness.render()

    let sample = try #require(harness.sink.committed.last)
    #expect(sample.scheduledFrame.causes.contains(.deadline))
    #expect(sample.scheduledFrame.triggeredDeadline == deadline)
    #expect(sample.frameInstant == deadline)
    #expect(sample.consumedAt == deadline)
    #expect(sample.frameInstant.duration(to: sample.consumedAt) == .zero)
  }

  @Test(
    "slow frames advance animation time by their elapsed cost on both drivers",
    arguments: [false, true]
  )
  func slowFramesAdvanceByElapsedTime(asyncDriver: Bool) async throws {
    let harness = try SampledClockHarness()
    // Every committed frame costs 160 ms of virtual time — five animation
    // cadences per frame, the counter demo's large-viewport regime. The
    // click's own frames pay it too, so the curve starts on a slow loop.
    harness.sink.renderCost = .milliseconds(160)
    try harness.click("go")
    let startedAt = try #require(harness.sink.committed.last).frameInstant
    #expect(harness.runLoop.renderer.internalAnimationController.activeAnimationCount > 0)
    harness.sink.reset()

    var deadlineFrames = 0
    // Step to each armed wake; after a 160 ms commit the re-armed deadline is
    // already overdue, so the wake is "now" and no further stepping occurs.
    while let wake = harness.scheduler.nextWakeInstant(after: harness.clock.now),
      deadlineFrames < 64
    {
      harness.clock.now = wake
      if asyncDriver {
        try await harness.renderAsync()
      } else {
        try harness.render()
      }
      deadlineFrames += 1
    }

    // 1.6 s of animation at 160 ms per frame is ten samples to the endpoint
    // plus the completion/removal turn — not the ~49 ticks the old deadline
    // rule replayed.
    #expect(harness.completions == 1, "frame:\n\(harness.frame)")
    #expect(deadlineFrames >= 10 && deadlineFrames <= 13, "deadline frames: \(deadlineFrames)")
    #expect(harness.runLoop.renderer.internalAnimationController.activeAnimationCount == 0)
    #expect(SampledClockHarness.barWidth(in: harness.frame) == 40)

    // Each sample advanced animation time by exactly the elapsed cost, with
    // no lag between the consume reading and the frame instant.
    let deltas = harness.sink.committed.compactMap { sample in
      sample.previousFrameInstant.map { $0.duration(to: sample.frameInstant) }
    }
    #expect(!deltas.isEmpty)
    #expect(deltas.allSatisfy { $0 == .milliseconds(160) }, "deltas: \(deltas)")
    #expect(
      harness.sink.committed.allSatisfy { $0.frameInstant.duration(to: $0.consumedAt) == .zero }
    )
    // The endpoint sample lands at the first acquisition at or after the
    // curve's end, never earlier.
    let endpointFrame = try #require(
      harness.sink.committed.first {
        $0.frameInstant >= startedAt.advanced(by: .milliseconds(1_600))
      }
    )
    #expect(endpointFrame.frameInstant == startedAt.advanced(by: .milliseconds(1_600)))
  }

  @Test("the wake cause never changes the sampled instant")
  func wakeCauseDoesNotChangeTheSampledInstant() throws {
    let harness = try SampledClockHarness()
    try harness.click("go")
    harness.sink.reset()

    // Deadline wake: step to the armed deadline.
    harness.clock.advance(by: .milliseconds(33))
    try harness.render()
    // Input wake, later than the next armed deadline so both are pending.
    harness.clock.advance(by: .milliseconds(50))
    #expect(harness.runLoop.handle(.input(.key(KeyPress(.character("x"))))) == nil)
    try harness.render()
    // Invalidation wake before the next deadline is due.
    harness.clock.advance(by: .milliseconds(20))
    harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
    try harness.render()

    let samples = harness.sink.committed
    #expect(samples.count == 3, "causes: \(samples.map(\.scheduledFrame.causes))")
    #expect(samples[0].scheduledFrame.causes.contains(.deadline))
    #expect(samples[1].scheduledFrame.causes.contains(.input))
    #expect(samples[2].scheduledFrame.causes.contains(.invalidation))
    #expect(!samples[2].scheduledFrame.causes.contains(.deadline))
    for sample in samples {
      #expect(sample.frameInstant == sample.consumedAt, "\(sample.scheduledFrame.causes)")
    }
    let deltas = samples.compactMap { sample in
      sample.previousFrameInstant.map { $0.duration(to: sample.frameInstant) }
    }
    #expect(deltas == [.milliseconds(33), .milliseconds(50), .milliseconds(20)])
  }

  @Test("the frame instant never decreases even when the installed clock does")
  func frameInstantNeverDecreases() throws {
    let harness = try SampledClockHarness()
    try harness.click("go")
    harness.clock.advance(by: .milliseconds(33))
    try harness.render()
    let pinned = try #require(harness.sink.committed.last).frameInstant
    harness.sink.reset()

    // A misbehaving clock closure steps backwards; the frame must not.
    harness.clock.now = harness.clock.now.advanced(by: .milliseconds(-10))
    harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
    try harness.render()
    let held = try #require(harness.sink.committed.last)
    #expect(held.frameInstant == pinned)
    #expect(held.consumedAt == pinned.advanced(by: .milliseconds(-10)))
    #expect(held.previousFrameInstant.map { $0.duration(to: held.frameInstant) } == .zero)

    // Once the clock is ahead again, animation time resumes from the held
    // instant, not from the backwards reading.
    harness.clock.now = pinned.advanced(by: .milliseconds(30))
    harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
    try harness.render()
    let resumed = try #require(harness.sink.committed.last)
    #expect(resumed.frameInstant == pinned.advanced(by: .milliseconds(30)))
    #expect(
      resumed.previousFrameInstant.map { $0.duration(to: resumed.frameInstant) }
        == .milliseconds(30))
  }

  @Test("a re-arm made during a long frame is due at once and is not replayed")
  func rearmAfterLongFrameIsDueImmediately() throws {
    let harness = try SampledClockHarness()
    try harness.click("go")
    harness.sink.reset()
    harness.sink.renderCost = .milliseconds(160)

    // The click frame itself cost nothing (the sink was charged after it);
    // this is the first deadline frame, whose commit charges 160 ms.
    harness.clock.advance(by: .milliseconds(33))
    try harness.render()
    let long = try #require(harness.sink.committed.last)
    #expect(harness.clock.now == long.frameInstant.advanced(by: .milliseconds(160)))
    // The deadline armed from the long frame's instant is already overdue.
    #expect(harness.scheduler.nextWakeInstant(after: harness.clock.now) == harness.clock.now)

    try harness.render()
    let next = try #require(harness.sink.committed.last)
    #expect(
      next.scheduledFrame.triggeredDeadline == long.frameInstant.advanced(by: .milliseconds(33)))
    // One acquisition answered the overdue deadline and animated to the
    // elapsed instant — no 33 ms replay steps in between.
    #expect(harness.sink.committed.count == 2)
    #expect(
      next.previousFrameInstant.map { $0.duration(to: next.frameInstant) } == .milliseconds(160))
  }

  @Test("a long stall crosses both completion barriers in order, exactly once")
  func longStallCrossesBothBarriersOnce() throws {
    let harness = try SampledClockHarness(fixture: .spring)
    try harness.click("go")
    #expect(harness.runLoop.renderer.internalAnimationController.activeAnimationCount > 0)
    harness.sink.reset()

    // Three seconds pass before the next acquisition — well past the 500 ms
    // logical barrier and the 1.5 s removal barrier.
    harness.clock.advance(by: .seconds(3))
    var frames = 0
    while harness.scheduler.hasPendingFrame(at: harness.clock.now), frames < 16 {
      try harness.render()
      frames += 1
    }

    #expect(
      harness.frame.contains("logical=1"),
      "order=\(harness.barrierOrder) frames=\(frames) frame:\n\(harness.frame)"
    )
    #expect(harness.frame.contains("removed=1"), "frame:\n\(harness.frame)")
    #expect(harness.barrierOrder == ["logical", "removed"], "order=\(harness.barrierOrder)")
    #expect(frames <= 3, "the stall must skip unseen poses, not replay them: \(frames) frames")
    #expect(harness.runLoop.renderer.internalAnimationController.activeAnimationCount == 0)
    #expect(SampledClockHarness.barWidth(in: harness.frame) == 40)
  }

  @Test("a frozen clock ages nothing and resuming advances by elapsed time only")
  func frozenClockAgesNothing() throws {
    let harness = try SampledClockHarness()
    try harness.click("go")
    harness.clock.advance(by: .milliseconds(400))
    try harness.render()
    let quarterWidth = SampledClockHarness.barWidth(in: harness.frame)
    #expect(quarterWidth > 8 && quarterWidth < 40, "width: \(quarterWidth)")
    let live = harness.runLoop.renderer.internalAnimationController.activeAnimationCount
    #expect(live > 0)

    // The host parks the scene: its pause-aware clock stops. Frames forced
    // through while parked must not age the curve.
    for _ in 0..<5 {
      harness.scheduler.requestDeadline(harness.clock.now)
      harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
      try harness.render()
      #expect(SampledClockHarness.barWidth(in: harness.frame) == quarterWidth)
      #expect(harness.runLoop.renderer.internalAnimationController.activeAnimationCount == live)
    }

    // Resume: the curve continues from where it was, by the resumed elapsed
    // time — no catch-up burst for the parked interval.
    harness.clock.advance(by: .milliseconds(400))
    harness.scheduler.requestDeadline(harness.clock.now)
    try harness.render()
    let halfWidth = SampledClockHarness.barWidth(in: harness.frame)
    #expect(halfWidth > quarterWidth && halfWidth < 40, "width: \(halfWidth)")
    #expect(abs(halfWidth - 24) <= 1, "800 ms of a 1.6 s 8→40 curve: \(halfWidth)")
  }
}

// MARK: - Harness

@MainActor
private final class SampledClockHarness {
  enum Fixture {
    case linear
    case spring
  }

  let rootIdentity = testIdentity("FrameInstantSampling")
  let clock = VirtualFrameClock(MonotonicInstant(offset: .seconds(100)))
  let scheduler = FrameScheduler()
  let surface = RecordingPresentationSurface(surfaceSize: .init(width: 48, height: 4))
  let sink: CommittedSampleSink
  let runLoop: SwiftTUIRuntime.RunLoop<Int, AnyView>
  private let ledger = BarrierLedger()
  private var renderedFrames = 0

  init(fixture: Fixture = .linear) throws {
    let ledger = self.ledger
    let sink = CommittedSampleSink(clock: clock)
    self.sink = sink
    runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 48, height: 4),
      viewBuilder: { _, _ in
        // AnyView policy: test-only fixture selection; production code is not
        // involved.
        switch fixture {
        case .linear: AnyView(LinearBarFixture(ledger: ledger))
        case .spring: AnyView(SpringBarrierFixture(ledger: ledger))
        }
      }
    )
    runLoop.frameClock = { [clock] in clock.now }
    runLoop.frameSink = sink
    scheduler.requestInvalidation(of: [rootIdentity])
    try render()
    runLoop.renderer.enableSelectiveEvaluation()
  }

  var frame: String { surface.frames.last ?? "" }
  var completions: Int { ledger.completions }
  var barrierOrder: [String] { ledger.order }

  func render() throws {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  }

  func renderAsync() async throws {
    var frames = renderedFrames
    defer { renderedFrames = frames }
    _ = try await runLoop.renderPendingFramesAsync(
      renderedFrames: &frames,
      eventPump: nil
    )
  }

  /// Clicks the button under the run loop's animation sinks, as `run()`
  /// installs them, so the action's `withAnimation` registers its curve and
  /// completion with the controller.
  func click(_ label: String) throws {
    let point = try #require(centerOfText(label), "no '\(label)' in frame:\n\(frame)")
    try withAnimationSinks(runLoop.renderer.internalAnimationController) {
      #expect(runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: point)))) == nil)
      try render()
      #expect(runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: point)))) == nil)
      try render()
    }
  }

  private func centerOfText(_ target: String) -> Point? {
    let lines = frame.split(separator: "\n", omittingEmptySubsequences: false)
    for (row, line) in lines.enumerated() {
      guard let start = line.firstRange(of: target) else { continue }
      let column = line.distance(from: line.startIndex, to: start.lowerBound)
      return Point(x: Double(column + target.count / 2), y: Double(row))
    }
    return nil
  }

  /// The widest run of `█` on any single line of `frame`.
  static func barWidth(in frame: String) -> Int {
    frame.split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        var best = 0
        var current = 0
        for character in line {
          if character == "█" {
            current += 1
            best = max(best, current)
          } else {
            current = 0
          }
        }
        return best
      }
      .max() ?? 0
  }
}

/// Records committed samples and charges a fixed render cost to the virtual
/// clock at each commit, so a "slow frame" is exact rather than measured.
@MainActor
private final class CommittedSampleSink: FrameDiagnosticSink {
  private(set) var committed: [CommittedFrameSample] = []
  var renderCost: Duration = .zero
  private let clock: VirtualFrameClock

  nonisolated init(clock: VirtualFrameClock) {
    self.clock = clock
  }

  func record(_ sample: RuntimeFrameSample) {
    guard case .committed(let committedSample) = sample else { return }
    committed.append(committedSample)
    if renderCost > .zero {
      clock.advance(by: renderCost)
    }
  }

  func reset() {
    committed.removeAll()
  }
}

@MainActor
private final class BarrierLedger {
  var completions = 0
  var order: [String] = []
}

@MainActor
private struct LinearBarFixture: View {
  let ledger: BarrierLedger
  @State private var wide = false
  @State private var done = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("go") {
        withAnimation(.linear(duration: .milliseconds(1_600)), completionCriteria: .removed) {
          wide.toggle()
        } completion: {
          done += 1
          ledger.completions += 1
        }
      }
      Text(String(repeating: "█", count: 40))
        .frame(maxWidth: .finite(wide ? 40 : 8), alignment: .leading)
      Text("done=\(done)")
    }
  }
}

@MainActor
private struct SpringBarrierFixture: View {
  let ledger: BarrierLedger
  @State private var wide = false
  @State private var logical = 0
  @State private var removed = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("go") {
        var transaction = Transaction(
          animation: .spring(duration: .milliseconds(1_500), bounce: 0.4)
            .logicallyComplete(after: .milliseconds(500))
        )
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
          logical += 1
          ledger.order.append("logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
          removed += 1
          ledger.order.append("removed")
        }
        withTransaction(transaction) { wide.toggle() }
      }
      Text(String(repeating: "█", count: 40))
        .frame(maxWidth: .finite(wide ? 40 : 8), alignment: .leading)
      Text("logical=\(logical) removed=\(removed)")
    }
  }
}
