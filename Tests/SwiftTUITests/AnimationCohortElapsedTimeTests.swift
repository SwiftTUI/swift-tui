import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// Framework-owned cohort fixture (plan 2026-09-24-001 §4A/§5, STUI-618):
/// 1, 8, 32, and 64 independently owned finite animations, created in one
/// frame and driven at the 33 ms cadence and at 160 ms per frame. Every
/// cohort must follow the elapsed-time contract — completion at the first
/// committed sample at or after its endpoint, not after a fixed number of
/// ticks — and every created animation must release its ownership: no live
/// animations, no pending completion work, no wake requirement left behind.
/// The fixture imports nothing from the counter demo; it stands in for its
/// ripple cohort without its geometry or blending.
@MainActor
@Suite
struct AnimationCohortElapsedTimeTests {
  private static let duration: Duration = .milliseconds(1_600)

  @Test(
    "a cohort completes by elapsed time at any size and step",
    arguments: [1, 8, 32, 64], [Duration.milliseconds(33), Duration.milliseconds(160)]
  )
  func cohortCompletesByElapsedTime(count: Int, step: Duration) throws {
    let harness = try CohortHarness(count: count)
    // Creation frames cost nothing so the cohort starts at one instant; every
    // deadline frame after it costs `step`.
    try harness.start()
    let controller = harness.runLoop.renderer.internalAnimationController
    #expect(controller.activeAnimationCount == count, "created: \(controller.activeAnimationCount)")
    let startedAt = try #require(harness.sink.committed.last).frameInstant
    harness.sink.reset()
    harness.sink.renderCost = step

    var frames = 0
    while let wake = harness.scheduler.nextWakeInstant(after: harness.clock.now), frames < 200 {
      harness.clock.now = wake
      try harness.render()
      frames += 1
    }

    // Completion count and ownership release are exact at every cohort size.
    #expect(harness.ledger.completions == count, "completions: \(harness.ledger.completions)")
    #expect(controller.activeAnimationCount == 0)
    #expect(!controller.requiresContinuedAnimationFrames)
    #expect(harness.scheduler.nextWakeInstant(after: harness.clock.now) == nil)
    #expect(harness.frame.contains("live=0"), "frame:\n\(harness.frame)")

    // The endpoint sample is the first acquisition at or after the curve's
    // end and the one before it is still mid-flight: the first eligible
    // sample completes the cohort, however many members it has. The first
    // deadline lands one cadence after creation and each later one `step`
    // after its predecessor, so the endpoint index is fixed by arithmetic.
    let endpoint = startedAt.advanced(by: Self.duration)
    let samples = harness.sink.committed.map(\.frameInstant)
    let endpointIndex = try #require(samples.firstIndex { $0 >= endpoint })
    #expect(endpointIndex > 0)
    #expect(samples[endpointIndex - 1] < endpoint)
    let stepMs = Self.milliseconds(step)
    let expectedIndex = (Self.milliseconds(Self.duration) - 33 + stepMs - 1) / stepMs
    #expect(endpointIndex == expectedIndex, "endpoint index \(endpointIndex) for step \(step)")
    // At 160 ms per frame that is ten samples, not the ~49 ticks a
    // deadline-paced clock replayed; completion and removal add a turn each.
    #expect(frames <= expectedIndex + 3, "frames: \(frames)")
  }

  @Test("a sustained creation rate reaches a steady live range set by duration, not frames")
  func sustainedCreationRateReachesSteadyState() throws {
    // 25 creations per second at 160 ms per frame: four members join per
    // deadline frame and each lives 1.6 s, so the live count must plateau
    // near 40 (creation rate × duration) rather than grow with the frames
    // rendered — the counter's ripple cohort under a 40 ms activation burst.
    let harness = try CohortHarness(count: 4)
    let controller = harness.runLoop.renderer.internalAnimationController
    var liveCounts: [Int] = []
    for _ in 0..<30 {
      harness.sink.renderCost = .zero
      try harness.start()
      harness.sink.renderCost = .milliseconds(160)
      if let wake = harness.scheduler.nextWakeInstant(after: harness.clock.now) {
        harness.clock.now = wake
      }
      try harness.render()
      liveCounts.append(controller.activeAnimationCount)
    }
    let plateau = liveCounts.suffix(10)
    #expect(plateau.allSatisfy { $0 >= 36 && $0 <= 44 }, "live counts: \(liveCounts)")

    // No further creations: everything drains and releases.
    var frames = 0
    while let wake = harness.scheduler.nextWakeInstant(after: harness.clock.now), frames < 40 {
      harness.clock.now = wake
      try harness.render()
      frames += 1
    }
    #expect(controller.activeAnimationCount == 0)
    #expect(harness.ledger.completions == 120, "completions: \(harness.ledger.completions)")
    #expect(!controller.requiresContinuedAnimationFrames)
    #expect(harness.frame.contains("live=0"), "frame:\n\(harness.frame)")
  }

  private static func milliseconds(_ duration: Duration) -> Int {
    Int(
      duration.components.seconds * 1_000
        + duration.components.attoseconds / 1_000_000_000_000_000)
  }
}

// MARK: - Fixture

@MainActor
private final class CohortLedger {
  var completions = 0
}

/// The counter's ripple shape without its geometry: every "go" appends
/// `count` members, each member owns its state and starts a finite curve when
/// it appears, and its completion removes it from the list.
@MainActor
private struct CohortFixture: View {
  let count: Int
  let ledger: CohortLedger
  @State private var members: [Int] = []
  @State private var nextID = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("go") {
        for _ in 0..<count {
          members.append(nextID)
          nextID += 1
        }
      }
      Text("live=\(members.count)")
      ForEach(members, id: \.self) { id in
        CohortMember(ledger: ledger) {
          members.removeAll { $0 == id }
        }
      }
    }
  }
}

@MainActor
private struct CohortMember: View {
  let ledger: CohortLedger
  let onCompletion: @MainActor @Sendable () -> Void
  @State private var wide = false

  var body: some View {
    Text("█")
      .frame(maxWidth: .finite(wide ? 12 : 1), alignment: .leading)
      .onAppear {
        withAnimation(.linear(duration: .milliseconds(1_600)), completionCriteria: .removed) {
          wide = true
        } completion: {
          ledger.completions += 1
          onCompletion()
        }
      }
  }
}

@MainActor
private final class CohortHarness {
  let rootIdentity = testIdentity("AnimationCohort")
  let clock = VirtualFrameClock(MonotonicInstant(offset: .seconds(50)))
  let scheduler = FrameScheduler()
  let surface = RecordingPresentationSurface(surfaceSize: .init(width: 24, height: 70))
  let sink: CohortSampleSink
  let ledger = CohortLedger()
  let runLoop: SwiftTUIRuntime.RunLoop<Int, CohortFixture>
  private var renderedFrames = 0

  init(count: Int) throws {
    let sink = CohortSampleSink(clock: clock)
    self.sink = sink
    let ledger = self.ledger
    runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 24, height: 70),
      viewBuilder: { _, _ in CohortFixture(count: count, ledger: ledger) }
    )
    runLoop.frameClock = { [clock] in clock.now }
    runLoop.frameSink = sink
    scheduler.requestInvalidation(of: [rootIdentity])
    try render()
    runLoop.renderer.enableSelectiveEvaluation()
  }

  var frame: String { surface.frames.last ?? "" }

  func render() throws {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  }

  /// Clicks "go" under the run loop's animation sinks so every new member's
  /// `onAppear` registers its curve and completion.
  func start() throws {
    let frame = surface.frames.last ?? ""
    let lines = frame.split(separator: "\n", omittingEmptySubsequences: false)
    let row = try #require(lines.firstIndex { $0.contains("go") }, "no go button:\n\(frame)")
    let line = lines[row]
    let column = line.distance(from: line.startIndex, to: line.firstRange(of: "go")!.lowerBound)
    let point = Point(x: Double(column + 1), y: Double(row))
    try withAnimationSinks(runLoop.renderer.internalAnimationController) {
      #expect(
        runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: point)))) == nil)
      try render()
      #expect(runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: point)))) == nil)
      try render()
    }
  }
}

@MainActor
private final class CohortSampleSink: FrameDiagnosticSink {
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
