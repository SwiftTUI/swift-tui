import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// The synchronous pull seam (plan 2026-09-24-001 §4D, STUI-618): a reader
/// whose source is an immediately visible queue is drained by the run loop
/// itself at its turn boundaries, so input service no longer depends on the
/// reader task and the pump's copy task getting executor time while the
/// loop renders. These scenarios use a scripted pulling reader; the WASI
/// reader's byte-level behavior is covered in `WebSurfaceInputPullTests`.
@MainActor
@Suite(.serialized)
struct IngressPullSeamTests {
  @Test("a turn-boundary pull delivers queued input in order without the idle poll")
  func turnBoundaryPullDeliversQueuedInputInOrder() async throws {
    let harness = PullSeamHarness(idlePolling: false)
    harness.reader.push(.key(.character("a")), .key(.character("b")), .key(.character("c")))
    // Nothing polls, so once the loop has mounted, wake it the way an
    // animation or state write would; the turn's boundary pull then finds
    // the queued input.
    Task { @MainActor in
      await harness.mounted()
      harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
    }

    let result = try await harness.runLoop.run()

    #expect(result.exitReason == .inputEnded)
    #expect(harness.handled == ["a", "b", "c"])
    #expect(result.finalState == 3)
    #expect(harness.reader.pullCalls > 0)
    let counters = harness.sink.ingressCounters
    #expect(counters.sourceEvents == 3, "\(counters)")
    #expect(counters.pullEvents == 3, "\(counters)")
    #expect(counters.pumpEnqueues == 3, "\(counters)")
  }

  @Test("the idle poll wakes a quiet loop and delivers through the same path")
  func idlePollWakesAQuietLoop() async throws {
    let harness = PullSeamHarness(idlePolling: true)
    Task { @MainActor in
      // Push only once the loop is quiet, and the next burst only once the
      // first key has been presented, so each delivery exercises the poll.
      await harness.mounted()
      harness.reader.push(.key(.character("a")))
      await harness.presented("value 1")
      harness.reader.push(.key(.character("b")), .key(.character("c")))
    }

    let result = try await harness.runLoop.run()

    #expect(result.exitReason == .inputEnded)
    #expect(harness.handled == ["a", "b", "c"])
    #expect(result.finalState == 3)
    #expect(harness.sink.ingressCounters.sourceEvents == 3)
  }

  @Test("input queued while a drain pass runs is served before the next acquisition")
  func inputQueuedDuringDispatchIsServedBeforeTheNextAcquisition() async throws {
    let harness = PullSeamHarness(idlePolling: false)
    // Handling `a` queues `b` and `c` at the source (as a burst arriving
    // mid-frame would) and keeps invalidating, so the drain pass has more
    // frames it could render; the pull before its second acquisition must
    // see the queued input and yield instead.
    harness.onHandle = { character in
      if character == "a" {
        harness.reader.push(.key(.character("b")), .key(.character("c")))
        harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
      }
    }
    harness.reader.push(.key(.character("a")))
    Task { @MainActor in
      await harness.mounted()
      harness.scheduler.requestInvalidation(of: [harness.rootIdentity])
    }

    let result = try await harness.runLoop.run()

    #expect(result.exitReason == .inputEnded)
    #expect(harness.handled == ["a", "b", "c"])
    #expect(result.finalState == 3)
    // The frame that answered `b` and `c` shows the pull that delivered
    // them, and no committed frame answered zero inputs while `b`/`c` were
    // queued: the pass yielded rather than rendering ahead of them.
    let samples = harness.sink.committed
    // The first input can coalesce into the same commit as the next two
    // (STUI-633). Account for every pull without requiring a separate frame
    // for `a`; the acquisition assertion below owns the service-order check.
    let pullCounts = samples.map { $0.ingress.counters.pullEvents }
    #expect(pullCounts.reduce(0, +) == 3, "\(samples.map(\.ingress))")
    #expect(pullCounts.contains { $0 >= 2 }, "\(samples.map(\.ingress))")
    #expect(
      !samples.contains { $0.ingress.acquisition.pumpBatches > 0 && $0.answeredInputs == nil },
      "a frame was acquired while input waited in the pump: \(samples.map(\.ingress))"
    )
  }

  @Test("end of input is reported exactly once, after every queued event")
  func inputEndedIsReportedOnceAfterQueuedEvents() async throws {
    let harness = PullSeamHarness(idlePolling: true, finishAfter: nil)
    Task { @MainActor in
      await harness.mounted()
      harness.reader.push(.key(.character("a")), .key(.character("b")))
      harness.reader.finish()
    }

    let result = try await harness.runLoop.run()

    #expect(result.exitReason == .inputEnded)
    #expect(harness.handled == ["a", "b"])
    #expect(harness.reader.inputEndedReports == 1)
    // Pulls after the end deliver nothing and never report the end again.
    #expect(harness.reader.pullPendingInput() == 0)
    #expect(harness.reader.inputEndedReports == 1)
  }
}

// MARK: - Harness

@MainActor
private final class PullSeamHarness {
  let rootIdentity = testIdentity("IngressPullSeam")
  let scheduler = FrameScheduler()
  let reader: ScriptedPullingReader
  let sink = IngressRecordingSink()
  let surface = RecordingPresentationSurface(surfaceSize: .init(width: 20, height: 2))
  let runLoop: SwiftTUIRuntime.RunLoop<Int, Text>
  private let ledger = HandledLedger()

  var handled: [String] { ledger.handled }
  var onHandle: (@MainActor (String) -> Void)? {
    get { ledger.onHandle }
    set { ledger.onHandle = newValue }
  }

  /// `finishAfter` names the character whose handling ends the source;
  /// `nil` leaves ending to the scenario.
  init(idlePolling: Bool, finishAfter: String? = "c") {
    let reader = ScriptedPullingReader(idlePolling: idlePolling)
    let ledger = self.ledger
    self.reader = reader
    runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: reader,
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { key, _, state in
        guard case .character(let character) = key.key else { return .ignored }
        let text = String(character)
        ledger.handled.append(text)
        state.mutate { $0 += 1 }
        ledger.onHandle?(text)
        if text == finishAfter {
          reader.finish()
        }
        return .handled
      },
      proposal: .init(width: 20, height: 2),
      viewBuilder: { value, _ in Text("value \(value)") }
    )
    runLoop.frameSink = sink
  }

  /// Resumes once the loop has presented its first frame (frame-signal
  /// driven, no clock).
  func mounted() async {
    await presented("value 0")
  }

  /// Resumes once a presented frame contains `text`.
  func presented(_ text: String) async {
    let surface = self.surface
    await surface.frameSignal.wait(until: { surface.frames.contains { $0.contains(text) } })
  }
}

@MainActor
private final class HandledLedger {
  var handled: [String] = []
  var onHandle: (@MainActor (String) -> Void)?
}

/// A pulling reader over an in-memory queue. `idlePolling` mirrors the WASI
/// reader's idle poll task; off, only the run loop's boundary pulls deliver.
/// The poll is signal-driven rather than timed: `push`/`finish` notify it.
@MainActor
private final class ScriptedPullingReader: SynchronousInputPulling {
  private var queue: [InputEvent] = []
  private var sink: InputPullDeliverySink?
  private var finished = false
  private var pollingTask: Task<Void, Never>?
  private let idlePolling: Bool
  private let arrivals = MainActorConditionSignal()
  private(set) var pullCalls = 0
  private(set) var inputEndedReports = 0

  init(idlePolling: Bool) {
    self.idlePolling = idlePolling
  }

  func push(_ events: InputEvent...) {
    queue.append(contentsOf: events)
    arrivals.notify()
  }

  func finish() {
    finished = true
    arrivals.notify()
  }

  nonisolated func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }

  func installPullDelivery(_ sink: InputPullDeliverySink) {
    self.sink = sink
    guard idlePolling else { return }
    pollingTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.arrivals.wait(until: { [weak self] in
          guard let self else { return true }
          return !self.queue.isEmpty || (self.finished && self.inputEndedReports == 0)
        })
        guard !Task.isCancelled else { return }
        self.pullPendingInput()
      }
    }
  }

  @discardableResult
  func pullPendingInput() -> Int {
    guard let sink else { return 0 }
    pullCalls += 1
    let events = queue
    queue.removeAll()
    for event in events {
      sink.deliver(event)
    }
    if !events.isEmpty {
      sink.recordSourceRead(events.count, events.count)
    }
    if finished, inputEndedReports == 0 {
      inputEndedReports += 1
      sink.inputEnded()
    }
    return events.count
  }

  func uninstallPullDelivery() {
    pollingTask?.cancel()
    pollingTask = nil
    sink = nil
  }
}

@MainActor
private final class IngressRecordingSink: FrameDiagnosticSink {
  private(set) var committed: [CommittedFrameSample] = []

  nonisolated init() {}

  func record(_ sample: RuntimeFrameSample) {
    guard case .committed(let committedSample) = sample else { return }
    committed.append(committedSample)
  }

  /// Every committed frame's counters summed: the per-frame counters are
  /// drained at each emit, so the sum is the session total.
  var ingressCounters: IngressFrameCounters {
    committed.reduce(into: IngressFrameCounters()) { total, sample in
      total.sourceBytes += sample.ingress.counters.sourceBytes
      total.sourceReads += sample.ingress.counters.sourceReads
      total.sourceEvents += sample.ingress.counters.sourceEvents
      total.pullEvents += sample.ingress.counters.pullEvents
      total.pumpEnqueues += sample.ingress.counters.pumpEnqueues
      total.pumpHighWater = max(total.pumpHighWater, sample.ingress.counters.pumpHighWater)
    }
  }
}
