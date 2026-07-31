import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// WP-1: the runtime stamps every event's arrival at the pump seam and reports,
/// per committed frame, how many inputs the frame answered and the
/// arrival→commit latency of the oldest and newest of them.
///
/// Every case runs on a ``VirtualFrameClock`` so the arithmetic is exact:
/// arrivals are authored, the commit reading is the pinned clock, and a
/// latency assertion is an equality rather than a range.
@MainActor
struct InputLatencyStampingTests {
  // MARK: - T-01

  @Test("A single wheel notch is answered by one frame at the authored latency")
  func singleNotchReportsOneAnsweredInputAndItsLatency() throws {
    let harness = try LatencyHarness()
    let arrivedAt = harness.clock.now
    harness.clock.advance(by: .milliseconds(7))

    harness.scroll(deltaY: 1, arrivalAt: arrivedAt)
    try harness.render()

    let frame = try #require(harness.sink.committedSamples.last)
    let answered = try #require(frame.answeredInputs)
    #expect(answered.count == 1)
    #expect(answered.first == arrivedAt)
    #expect(answered.last == arrivedAt)
    #expect(answered.first.duration(to: frame.commitInstant) == .milliseconds(7))

    let record = FrameRecordDerivation.record(from: .committed(frame))
    #expect(record.answeredInputCount == 1)
    #expect(record.inputToCommitFirst == .milliseconds(7))
    #expect(record.inputToCommitLast == .milliseconds(7))
  }

  // MARK: - T-02

  @Test("A deadline-driven frame with no input reports no latency at all")
  func deadlineOnlyFrameReportsNoAnsweredInputs() throws {
    let harness = try LatencyHarness()

    // Answer one input first, so a frame that fails to clear the accumulator
    // would be caught reporting the previous frame's input again.
    let arrivedAt = harness.clock.now
    harness.clock.advance(by: .milliseconds(4))
    harness.scroll(deltaY: 1, arrivalAt: arrivedAt)
    try harness.render()
    #expect(harness.sink.committedSamples.last?.answeredInputs?.count == 1)

    // A bare deadline — the shape scroll momentum and animation ticks drive
    // frames with once the user stops touching anything.
    let framesBefore = harness.sink.committedSamples.count
    harness.runLoop.scheduler.requestDeadline(
      harness.clock.now.advanced(by: .milliseconds(33))
    )
    harness.clock.advance(by: .milliseconds(33))
    try harness.render()

    #expect(harness.sink.committedSamples.count > framesBefore)
    let frame = try #require(harness.sink.committedSamples.last)
    #expect(frame.answeredInputs == nil)

    let record = FrameRecordDerivation.record(from: .committed(frame))
    #expect(record.answeredInputCount == 0)
    #expect(record.inputToCommitFirst == nil)
    #expect(record.inputToCommitLast == nil)
  }

  // MARK: - T-03

  @Test("The pump fuses a merged notch cluster's arrivals instead of dropping them")
  func mergedNotchClusterKeepsEveryArrival() {
    let clock = VirtualFrameClock()
    let buffer = EventPumpBuffer(clock: { MainActor.assumeIsolated { clock.now } })
    let firstArrival = clock.now

    for _ in 0..<3 {
      buffer.enqueue(.input(.mouse(Self.scrollEvent(deltaY: 1))))
      clock.advance(by: .milliseconds(2))
    }
    let lastArrival = clock.now.advanced(by: .milliseconds(-2))

    let drained = buffer.drain()
    // The three same-cell notches merged into one summed event...
    #expect(drained.count == 1)
    if case .input(.mouse(let mouseEvent)) = drained[0].event {
      #expect(mouseEvent.kind == .scrolled(deltaX: 0, deltaY: 3))
    } else {
      Issue.record("expected a merged scroll event, got \(drained[0].event)")
    }
    // ...but the envelope still stands for three raw arrivals, bracketed by
    // the true spread. Without this the coalescing rate would undercount
    // exactly the back-pressure it exists to measure.
    #expect(drained[0].arrival.count == 3)
    #expect(drained[0].arrival.first == firstArrival)
    #expect(drained[0].arrival.last == lastArrival)
  }

  @Test("A fused three-notch cluster is answered as three inputs by one frame")
  func fusedClusterIsAnsweredAsThreeInputs() throws {
    let harness = try LatencyHarness()
    let firstArrival = harness.clock.now
    let lastArrival = firstArrival.advanced(by: .milliseconds(4))
    harness.clock.advance(by: .milliseconds(9))

    harness.runLoop.handle(
      .input(.mouse(Self.scrollEvent(deltaY: 3))),
      arrival: InputArrival(
        id: 0,
        count: 3,
        first: firstArrival,
        last: lastArrival
      )
    )
    try harness.render()

    let frame = try #require(harness.sink.committedSamples.last)
    let answered = try #require(frame.answeredInputs)
    #expect(answered.count == 3)
    #expect(answered.first == firstArrival)
    #expect(answered.last == lastArrival)

    let record = FrameRecordDerivation.record(from: .committed(frame))
    #expect(record.answeredInputCount == 3)
    // The edges bracket the per-notch latencies: oldest notch waited 9 ms,
    // newest waited 5 ms.
    #expect(record.inputToCommitFirst == .milliseconds(9))
    #expect(record.inputToCommitLast == .milliseconds(5))
  }

  // MARK: - T-04

  @Test("An input whose dispatch asks the scheduler for nothing is not attributed")
  func nonSchedulingInputDoesNotAttributeToTheNextFrame() throws {
    let harness = try LatencyHarness()

    // Pointer motion with no hover subscriber and no active routing: it
    // schedules no frame of its own (`shouldScheduleFrame` is false for
    // `.moved` here) and no handler requests anything.
    //
    // The plan named an unclaimed key press as this case, but on HEAD every
    // key dispatch calls `scheduler.requestInput()` unconditionally before the
    // handler chain runs, so a key *always* asks for a frame and is always
    // answered by one. Pointer motion over blank surface is the real instance
    // of the non-requesting class — and the register records it as the reason
    // idle pointer movement commits no frames.
    harness.runLoop.handle(
      .input(
        .mouse(
          MouseEvent(
            kind: .moved,
            location: .cellFallback(CellPoint(x: 2, y: 2))
          ))),
      arrival: InputArrival(id: 0, arrival: harness.clock.now)
    )
    #expect(harness.runLoop.pendingAnsweredInputs == nil)

    // Drive a frame from an unrelated source. If the move had been attributed
    // it would smear its wait onto this frame's latency.
    harness.clock.advance(by: .milliseconds(50))
    harness.runLoop.scheduler.requestInvalidation(of: [harness.rootIdentity])
    try harness.render()

    let frame = try #require(harness.sink.committedSamples.last)
    #expect(frame.answeredInputs == nil)
  }

  // MARK: - T-05

  @Test("A key press carries an envelope arrival even though KeyPress has no timestamp")
  func keyPressesGetEnvelopeArrivals() throws {
    let harness = try LatencyHarness()
    let arrivedAt = harness.clock.now
    harness.clock.advance(by: .milliseconds(12))

    harness.runLoop.handle(
      .input(.key(KeyPress(.arrowDown, modifiers: []))),
      arrival: InputArrival(id: 0, arrival: arrivedAt)
    )
    try harness.render()

    let frame = try #require(harness.sink.committedSamples.last)
    let answered = try #require(frame.answeredInputs)
    #expect(answered.count == 1)

    let record = FrameRecordDerivation.record(from: .committed(frame))
    #expect(record.inputToCommitFirst == .milliseconds(12))
    #expect(record.inputToCommitLast == .milliseconds(12))
  }

  // MARK: - Carry-forward

  @Test("Answered inputs are cleared by the frame that reports them")
  func answeredInputsAreAttributedToExactlyOneFrame() throws {
    let harness = try LatencyHarness()
    harness.scroll(deltaY: 1, arrivalAt: harness.clock.now)
    harness.clock.advance(by: .milliseconds(3))
    try harness.render()
    #expect(harness.runLoop.pendingAnsweredInputs == nil)

    harness.clock.advance(by: .milliseconds(3))
    harness.runLoop.scheduler.requestInvalidation(of: [harness.rootIdentity])
    try harness.render()
    #expect(harness.sink.committedSamples.last?.answeredInputs == nil)
  }

  // MARK: - The presents join coordinate

  @Test("The commit coordinate makes an input's arrival exactly recoverable")
  func committedAtRecoversTheArrivalInstant() throws {
    // `presents.tsv` records write submission and completion as offsets on the
    // process monotonic origin, while every other column of `frames.tsv` is a
    // duration. Publishing the commit instant's offset is what lets a reducer
    // cross between the two: arrival = committedAt − inputToCommitFirst. If
    // this identity ever stopped holding, arrival→write would silently become
    // an estimate while still being reported as a measurement.
    let harness = try LatencyHarness()
    let arrivedAt = harness.clock.now
    harness.clock.advance(by: .milliseconds(11))

    harness.scroll(deltaY: 1, arrivalAt: arrivedAt)
    try harness.render()

    let frame = try #require(harness.sink.committedSamples.last)
    let record = FrameRecordDerivation.record(from: .committed(frame))
    let committedAt = try #require(record.committedAt)
    let inputToCommitFirst = try #require(record.inputToCommitFirst)

    #expect(committedAt == frame.commitInstant.offset)
    #expect(committedAt - inputToCommitFirst == arrivedAt.offset)
  }

  @Test("A frame that answered nothing still publishes its commit coordinate")
  func deadlineFrameStillPublishesTheJoinCoordinate() throws {
    // A momentum tick answers no input, so its latency columns are empty — but
    // its bytes still reach the terminal, and the presents join is keyed on the
    // frame ordinal. Withholding the coordinate here would drop exactly the
    // frames a fling scenario is made of.
    let harness = try LatencyHarness()
    harness.clock.advance(by: .milliseconds(4))
    harness.runLoop.scheduler.requestInvalidation(of: [harness.rootIdentity])
    try harness.render()

    let frame = try #require(harness.sink.committedSamples.last)
    let record = FrameRecordDerivation.record(from: .committed(frame))

    #expect(record.answeredInputCount == 0)
    #expect(record.inputToCommitFirst == nil)
    #expect(record.committedAt == frame.commitInstant.offset)
  }

  private static func scrollEvent(deltaY: Int) -> MouseEvent {
    MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: deltaY),
      location: .cellFallback(CellPoint(x: 4, y: 3))
    )
  }
}

// MARK: - Harness

@MainActor
private final class LatencyHarness {
  let clock = VirtualFrameClock()
  let sink = RecordingCommittedFrameSink()
  let rootIdentity = testIdentity("InputLatencyFixture")
  let runLoop: RunLoop<Int, AnyView>
  private var renderedFrames = 0

  init() throws {
    let terminalSize = CellSize(width: 24, height: 10)
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = terminalSize
    let rootIdentity = rootIdentity

    runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: RecordingPresentationSurface(surfaceSize: terminalSize),
      terminalInputReader: LatencyHarnessInputReader(),
      signalReader: LatencyHarnessSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: ScopedMapper { _ in
        AnyView(
          ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<120) { index in
                Text("Row \(index)")
              }
            }
          }
          .frame(width: 14, height: 6, alignment: .topLeading)
        )
      }
    )
    runLoop.frameClock = { [clock] in clock.now }
    runLoop.frameSink = sink

    // Mount synchronously, mirroring `RunLoop.run()`'s pre-loop bootstrap.
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    sink.reset()
  }

  func scroll(deltaY: Int, arrivalAt arrival: MonotonicInstant) {
    runLoop.handle(
      .input(
        .mouse(
          MouseEvent(
            kind: .scrolled(deltaX: 0, deltaY: deltaY),
            location: .cellFallback(CellPoint(x: 4, y: 3))
          ))),
      arrival: InputArrival(id: 0, arrival: arrival)
    )
  }

  func render() throws {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  }
}

@MainActor
private final class RecordingCommittedFrameSink: FrameDiagnosticSink {
  private(set) var committedSamples: [CommittedFrameSample] = []

  nonisolated init() {}

  func record(_ sample: RuntimeFrameSample) {
    if case .committed(let committed) = sample {
      committedSamples.append(committed)
    }
  }

  func reset() {
    committedSamples.removeAll()
  }
}

private final class LatencyHarnessInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class LatencyHarnessSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
