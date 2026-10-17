#if !os(Windows) && !canImport(WASILibc)
  @testable import SwiftTUICore
  @testable import SwiftTUIViews
  @_spi(Testing) import SwiftTUITestSupport
  import Synchronization
  import Testing

  @_spi(Runners) @testable import SwiftTUIRuntime

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Android)
    import Android
  #elseif canImport(Musl)
    import Musl
  #endif

  @MainActor
  @Suite("Adversarial test case set A: terminal input lifetime", .timeLimit(.minutes(1)))
  struct AdversarialSetATerminalInputLifetimeTests {
    @Test func setA1001EOFDrainsBeyondOneReadQuantumWithoutLosingTheUnicodeTail() async throws {
      // Hypothesis: the first 256-byte read causes EOF handling to finish before
      // subsequent chunks, including the final multi-byte character, are delivered.
      try await withTerminalLifetimePipe { pipe in
        let text = String(repeating: "ab", count: 700) + "😀z"
        try pipe.write(Array(text.utf8))
        pipe.closeWriter()
        let received = pipe.observe(pipe.reader.inputEvents())
        try await received.waitForEnd()
        let exactPayload = received.snapshot == text.map { .key(.character($0)) }
        #expect(exactPayload)
        #expect(pipe.reader.liveReadSourceCount == 0)
      }
    }

    @Test func setA1002WouldBlockDoesNotConsumeTheNextReadableBurstOrBecomeEOF() async throws {
      // Hypothesis: an empty nonblocking read is treated as terminal EOF, or
      // its reusable drain state leaks bytes into the next acquisition.
      try await withTerminalLifetimePipe { pipe in
        let empty = drainAvailableTerminalInput(from: pipe.readFD, maxBytesPerRead: 3)
        #expect(empty == .init(bytes: [], shouldFinish: false))
        try pipe.write(Array("abcdefg".utf8))
        let burst = drainAvailableTerminalInput(from: pipe.readFD, maxBytesPerRead: 3)
        #expect(burst == .init(bytes: Array("abcdefg".utf8), shouldFinish: false))
        pipe.closeWriter()
        let ended = drainAvailableTerminalInput(from: pipe.readFD, maxBytesPerRead: 3)
        #expect(ended == .init(bytes: [], shouldFinish: true))
      }
    }

    @Test func setA1003ThrowingSuspensionResumesBytesQueuedInsideTheHandoff() async throws {
      // Hypothesis: a capability probe's thrown error skips source resume and
      // permanently strands bytes that arrived while the probe owned the FD.
      try await withTerminalLifetimePipe { pipe in
        let received = pipe.observe(pipe.reader.inputEvents())
        var caughtSentinel = false
        do {
          try pipe.reader.withInputSuspended {
            try pipe.write(Array("q".utf8))
            #expect(received.snapshot.isEmpty)
            throw TerminalLifetimeFailure.probe
          }
        } catch TerminalLifetimeFailure.probe {
          caughtSentinel = true
        }
        #expect(caughtSentinel)
        pipe.closeWriter()
        try await received.waitForEnd()
        #expect(received.snapshot == [.key(.character("q"))])
      }
    }

    @Test func setA1004CanceledAwaitedHandoffBalancesTheSuspendedReadSource() async throws {
      // Hypothesis: cooperative cancellation exits an awaited probe without
      // balancing its suspension, leaving the still-open reader unable to run.
      try await withTerminalLifetimePipe { pipe in
        let received = pipe.observe(pipe.reader.inputEvents())
        let entered = AsyncEvent()
        let release = AsyncEvent()
        let probe = Task { @MainActor in
          try await pipe.reader.withInputSuspended {
            entered.fire()
            await release.wait()
            try Task.checkCancellation()
          }
        }
        defer {
          probe.cancel()
          release.fire()
        }
        try await terminalLifetimeWait(entered, label: "suspended handoff entered")
        try pipe.write(Array("r".utf8))
        #expect(received.snapshot.isEmpty)
        probe.cancel()
        let result = await probe.result
        if case .failure(let error) = result {
          #expect(error is CancellationError)
        } else {
          Issue.record("the suspended probe did not observe cancellation")
        }
        pipe.closeWriter()
        try await received.waitForEnd()
        #expect(received.snapshot == [.key(.character("r"))])
      }
    }

    @Test func setA1005CancelingAConsumerRetiresItsSourceButLeavesTheBorrowedFDOpen() async throws {
      // Hypothesis: cancellation either leaves a dispatch read source registered
      // or closes the caller-owned descriptor during stream teardown.
      try await withTerminalLifetimePipe { pipe in
        let received = pipe.observe(pipe.reader.inputEvents())
        try pipe.write(Array("a".utf8))
        try await terminalLifetimeWait(received.first, label: "first pipe key")
        try await pipe.cancelReaders()
        #expect(received.snapshot == [.key(.character("a"))])
        #expect(pipe.reader.liveReadSourceCount == 0)
        try pipe.write(Array("b".utf8))
        let stillOwned = readTerminalInputChunk(from: pipe.readFD, maxBytes: 16)
        #expect(stillOwned == .bytes(Array("b".utf8)))
      }
    }

    @Test func setA1006RestartedFDStreamDoesNotInheritTheRetiredDecodersPartialScalar() async throws
    {
      // Hypothesis: canceling one subscription retains its unfinished UTF-8
      // decoder state and corrupts the next subscription's first ASCII key.
      try await withTerminalLifetimePipe { pipe in
        let original = pipe.observe(pipe.reader.inputEvents())
        try pipe.write([0x61, 0xF0, 0x9F])
        try await terminalLifetimeWait(original.first, label: "original decoder consumed prefix")
        try await pipe.cancelReaders()
        let replacement = pipe.observe(pipe.reader.inputEvents())
        try pipe.write(Array("b".utf8))
        pipe.closeWriter()
        try await replacement.waitForEnd()
        #expect(original.snapshot == [.key(.character("a"))])
        #expect(replacement.snapshot == [.key(.character("b"))])
      }
    }

    @Test func setA1007ProbeReplayContinuesTheLiveBracketedPasteTransaction() async throws {
      // Hypothesis: replay uses a fresh parser, exposing probe-consumed bytes as
      // keys instead of continuing a paste already opened by the real FD.
      try await withTerminalLifetimePipe { pipe in
        let received = pipe.observe(pipe.reader.inputEvents())
        try pipe.write(Array("a\u{1B}[200~before".utf8))
        try await terminalLifetimeWait(received.first, label: "paste prefix consumed")
        let replay = "\u{1B}]10;rgb:f/f/f\u{7}middle"
        pipe.reader.withInputSuspended {
          pipe.reader.replayProbeInput(Array(replay.utf8))
        }
        try pipe.write(Array("after\u{1B}[201~z".utf8))
        pipe.closeWriter()
        try await received.waitForEnd()
        #expect(
          received.snapshot == [
            .key(.character("a")), .paste(.init(content: "before" + replay + "after")),
            .key(.character("z")),
          ])
      }
    }

    @Test func setA1008ProbeReplayCannotCrossTwoIndependentDescriptorOwners() async throws {
      // Hypothesis: replay wakeups share a pending-byte reservoir and allow one
      // reader to drain or duplicate bytes belonging to another live terminal.
      try await withTerminalLifetimePipe { first in
        try await withTerminalLifetimePipe { second in
          let a = first.observe(first.reader.inputEvents())
          let b = second.observe(second.reader.inputEvents())
          first.reader.withInputSuspended { first.reader.replayProbeInput(Array("left".utf8)) }
          second.reader.withInputSuspended { second.reader.replayProbeInput(Array("right".utf8)) }
          first.closeWriter()
          second.closeWriter()
          try await a.waitForEnd()
          try await b.waitForEnd()
          #expect(a.snapshot == "left".map { .key(.character($0)) })
          #expect(b.snapshot == "right".map { .key(.character($0)) })
        }
      }
    }

    @Test func setA1009KeyboardProjectionConsumesNonKeyEnvelopesWithoutLeakingTheirPayload()
      async throws
    {
      // Hypothesis: projecting the full byte decoder into keyboard-only events
      // leaves mouse/paste bytes behind, turning payload into later shortcuts.
      try await withTerminalLifetimePipe { pipe in
        let received = pipe.observe(pipe.reader.events())
        try pipe.write(Array("a\u{1B}[<0;2;3M\u{1B}[200~not keys\u{1B}[201~b".utf8))
        pipe.closeWriter()
        try await received.waitForEnd()
        #expect(received.snapshot == [.init(.character("a")), .init(.character("b"))])
      }
    }

    @Test func setA1010TerminalReplyTrafficDoesNotEndTheStreamBeforeTheNextUserBurst() async throws
    {
      // Hypothesis: capability response envelopes are mistaken for stream
      // completion, so a later read-ready callback no longer delivers keys.
      try await withTerminalLifetimePipe { pipe in
        let received = pipe.observe(pipe.reader.inputEvents())
        try pipe.write(Array("\u{1B}]10;rgb:f/f/f\u{7}\u{1B}[?1016;2$y\u{1B}[?5ua".utf8))
        try await terminalLifetimeWait(received.first, label: "user key after terminal replies")
        #expect(received.snapshot == [.key(.character("a"))])
        #expect(pipe.reader.liveReadSourceCount == 1)
        try pipe.write(Array("b".utf8))
        pipe.closeWriter()
        try await received.waitForEnd()
        #expect(received.snapshot == [.key(.character("a")), .key(.character("b"))])
      }
    }

    @Test func setA1011InjectedEOFFlushesAnUndecidedEscapeBeforeFinishing() async throws {
      // Hypothesis: injected EOF invalidates the escape timer before committing
      // the pending key, unlike the real descriptor reader's EOF path.
      let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      let stream = reader.inputEvents()
      reader.send([0x1B])
      reader.finish()
      let events = try await terminalLifetimeCollect(stream)
      withKnownIssue("STUI-1026: Injected EOF clears the Escape token without flushing the parser")
      {
        #expect(events == [.key(.escape)])
      }
    }

    @Test func setA1012AttachingTheFirstConsumerArmsAnAlreadyBufferedEscape() async throws {
      // Hypothesis: an Escape received before consumer attachment never gains a
      // disambiguation token, so starting the stream leaves that key stranded.
      let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      reader.send([0x1B])
      let stream = reader.inputEvents()
      reader.flushPendingEscapeDisambiguation()
      reader.send(Array("a".utf8))
      reader.finish()
      let events = try await terminalLifetimeCollect(stream)
      withKnownIssue("STUI-1027: Consumer attachment does not arm an already-buffered Escape") {
        #expect(events == [.key(.escape), .key(.character("a"))])
      }
    }

    @Test func setA1013DetachingADirectConsumerCannotSilentlyConsumeItsPendingEscape() async throws
    {
      // Hypothesis: direct-handler detach leaves its old flush token alive; the
      // callback then empties the parser while no consumer can receive its key.
      let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      let direct = TerminalLifetimeObservation<InputEvent>()
      reader.installDirectHandler({ direct.record($0) }, onFinish: { direct.ended.fire() })
      reader.send([0x1B])
      reader.clearDirectHandler()
      reader.flushPendingEscapeDisambiguation()
      let stream = reader.inputEvents()
      reader.send(Array("a".utf8))
      reader.finish()
      let events = try await terminalLifetimeCollect(stream)
      #expect(direct.snapshot.isEmpty)
      withKnownIssue(
        "STUI-1028: Direct-handler detach leaves a flush token that consumes unowned input"
      ) {
        #expect(events == [.key(.character("a"), modifiers: .alt)])
      }
    }

    @Test func setA1014DisambiguatedEscapeCannotOvertakeEarlierBufferedMouseInput() async throws {
      // Hypothesis: the escape timer yields directly instead of honoring the
      // pending pointer batch that every ordinary non-mouse event flushes.
      let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      let stream = reader.inputEvents()
      let move = terminalLifetimeMove(4)
      reader.send(move)
      reader.send([0x1B])
      reader.flushPendingEscapeDisambiguation()
      reader.finish()
      let events = try await terminalLifetimeCollect(stream)
      withKnownIssue("STUI-1029: Escape flush bypasses the pending-mouse ordering barrier") {
        #expect(events == [move, .key(.escape)])
      }
    }

    @Test func setA1015ReentrantFinishCannotBeFollowedByBufferedDirectEvents() {
      // Hypothesis: draining a detached copy of pre-consumer events continues
      // invoking the direct handler after reentrant finish reports EOF.
      let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      reader.send([.key(.character("a")), .key(.character("b"))])
      let observed = Mutex<[String]>([])
      reader.installDirectHandler(
        { event in
          observed.withLock { $0.append("event") }
          if event == .key(.character("a")) { reader.finish() }
        }, onFinish: { observed.withLock { $0.append("end") } })
      reader.finish()
      let trace = observed.withLock { $0 }
      #expect(trace.first == "event")
      #expect(trace.filter { $0 == "end" }.count == 1)
      withKnownIssue("STUI-1030: The detached buffered-event drain continues after reentrant EOF") {
        #expect(trace.last == "end")
      }
    }

    @Test func setA1016CompletedFDStreamsReleaseTheirReaderAndReplayClosureOwners() async throws {
      // Hypothesis: the canceled dispatch/replay sources retain their reader
      // through captured callbacks after EOF has removed every live source.
      try await withTerminalLifetimePipe { pipe in
        let ownership = TerminalLifetimeWeakReader()
        let released = AsyncEvent()
        try await terminalLifetimeCompleteTransientReader(
          pipe, ownership: ownership, released: released)
        try await pipe.cancelReaders()
        // A deinit signal from the reader's captured callback is the release
        // witness; the weak reference independently checks the reader itself.
        try await terminalLifetimeWait(released, label: "reader callback owner released")
        #expect(ownership.reader == nil)
      }
    }

    @Test func setA1017CancelingAnOldStreamCannotRetireTheReplacementEscapeOwner() async throws {
      // Hypothesis: an older continuation's late termination clears a newer
      // continuation or its timer, even though the reader minted a new generation.
      let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      let oldStream = reader.inputEvents()
      let old = Task { for await _ in oldStream {} }
      defer {
        old.cancel()
        reader.finish()
      }
      let replacement = reader.inputEvents()
      reader.send([0x1B])
      old.cancel()
      await old.value
      reader.flushPendingEscapeDisambiguation()
      reader.send(Array("z".utf8))
      reader.finish()
      let events = try await terminalLifetimeCollect(replacement)
      #expect(events == [.key(.escape), .key(.character("z"))])
    }

    @Test func setA1018RepeatedFinishDrainsMouseOnceAndFencesEveryLaterSendPath() async throws {
      // Hypothesis: EOF drains a pending coalesced batch without retiring its
      // manual flush state, duplicating delivery or accepting post-EOF input.
      let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      let stream = reader.inputEvents()
      reader.send(terminalLifetimeMove(1))
      let last = terminalLifetimeMove(8)
      reader.send(last)
      reader.finish()
      reader.finish()
      let residue = reader.flushPendingCoalescedMouseEvents()
      reader.send(Array("x".utf8))
      reader.send(.key(.character("y")))
      reader.send([.key(.character("z"))])
      let events = try await terminalLifetimeCollect(stream)
      #expect(residue.isEmpty)
      #expect(events == [last])
    }

    @Test func setA1019ClearingDirectDeliveryReturnsFutureEventsToTheExistingStream() async throws {
      // Hypothesis: installing a direct handler destroys the stream continuation
      // or broadcasts to both owners, so detaching cannot restore sole delivery.
      let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      let stream = reader.inputEvents()
      let direct = TerminalLifetimeObservation<InputEvent>()
      reader.send(.key(.character("a")))
      reader.installDirectHandler({ direct.record($0) }, onFinish: { direct.ended.fire() })
      reader.send(.key(.character("b")))
      reader.clearDirectHandler()
      reader.send(.key(.character("c")))
      reader.finish()
      let events = try await terminalLifetimeCollect(stream)
      #expect(direct.snapshot == [.key(.character("b"))])
      #expect(events == [.key(.character("a")), .key(.character("c"))])
    }

    @Test func setA1020AdmissionSurvivesDrainUntilTheFinalEventCopyIsReleased() {
      // Hypothesis: leaving the pump releases ingress capacity while a drained
      // event copy still owns the reservation and awaits dispatch.
      let buffer = EventPumpBuffer()
      let releases = Mutex(0)
      buffer.enqueue(
        .scopedInput(
          .init(
            .key(.character("a")), origin: .terminal,
            admission: InputAdmission { releases.withLock { $0 += 1 } })))
      var drained = buffer.drain()
      var retained = drained
      drained.removeAll()
      #expect(buffer.pendingBatchCount() == 0)
      #expect(releases.withLock { $0 } == 0)
      #expect(retained.count == 1)
      retained.removeAll()
      #expect(releases.withLock { $0 } == 1)
    }

    @Test func setA1021PointerReplacementReleasesOnlyTheDisplacedAdmission() throws {
      // Hypothesis: coalescing retains every obsolete reservation, or releases
      // the surviving event's reservation before the merged batch is consumed.
      let buffer = EventPumpBuffer()
      let releases = Mutex<[Int]>([])
      let lease = InputConnectionLease()
      for index in 0..<2 {
        buffer.enqueue(
          .scopedInput(
            .init(
              terminalLifetimeMove(index), origin: .terminal, lease: lease,
              admission: InputAdmission { releases.withLock { $0.append(index) } })))
      }
      #expect(releases.withLock { $0 } == [1])
      var drained = buffer.drain()
      try #require(drained.count == 1)
      #expect(drained[0].arrival.count == 2)
      #expect(releases.withLock { $0 } == [1])
      drained.removeAll()
      #expect(releases.withLock { $0 } == [1, 0])
    }

    @Test func setA1022TerminalReconnectLeasePreventsPointerCoalescingAcrossOwners() throws {
      // Hypothesis: same-origin pointer coalescing ignores connection identity,
      // allowing retirement of an old terminal lease to discard the new event.
      let buffer = EventPumpBuffer()
      let old = InputConnectionLease()
      let current = InputConnectionLease()
      buffer.enqueue(.scopedInput(.init(terminalLifetimeMove(1), origin: .terminal, lease: old)))
      buffer.enqueue(
        .scopedInput(.init(terminalLifetimeMove(9), origin: .terminal, lease: current)))
      old.retire()
      let batch = buffer.drain()
      try #require(batch.count == 2)
      let scoped = batch.compactMap { item -> ScopedInputEvent? in
        guard case .scopedInput(let event) = item.event else { return nil }
        return event
      }
      #expect(scoped.map(\.isCurrent) == [false, true])
      #expect(scoped.map(\.event) == [terminalLifetimeMove(1), terminalLifetimeMove(9)])
      #expect(batch.map(\.arrival.count) == [1, 1])
    }

    @Test func setA1023ConcurrentTerminalProducersRetainEveryPerProducerKeyOrder() async throws {
      // Hypothesis: concurrent appends to the pump lose a batch, mint duplicate
      // arrival IDs, or reorder sequential writes from the same producer.
      let buffer = EventPumpBuffer()
      await withTaskGroup(of: Void.self) { group in
        for producer in 0..<4 {
          group.addTask {
            for offset in 0..<80 {
              let key = Character(UnicodeScalar(0xE000 + producer * 80 + offset)!)
              buffer.enqueue(.input(.key(.character(key))))
            }
          }
        }
      }
      var decoded: [Int] = []
      var arrivalIDs: [UInt64] = []
      while buffer.hasPendingEvents() {
        let batch = buffer.drain()
        try #require(batch.count == 1)
        let item = batch[0]
        guard case .input(.key(let key)) = item.event,
          case .character(let character) = key.key,
          let scalar = character.unicodeScalars.first
        else {
          Issue.record("expected a terminal key")
          continue
        }
        decoded.append(Int(scalar.value) - 0xE000)
        arrivalIDs.append(item.arrival.id)
      }
      #expect(decoded.count == 320)
      let allArrivalIDsPreserved = arrivalIDs == (0..<320).map(UInt64.init)
      #expect(allArrivalIDsPreserved)
      for producer in 0..<4 {
        let producerOrderPreserved =
          decoded.filter { $0 / 80 == producer } == Array((producer * 80)..<((producer + 1) * 80))
        #expect(producerOrderPreserved)
      }
    }

    @Test func setA1024ScrollArithmeticOverflowPreservesSeparateOrderedArrivals() throws {
      // Hypothesis: pump compression adds independently valid integral deltas
      // without checked arithmetic, trapping or reversing the resulting scroll.
      let buffer = EventPumpBuffer()
      let first = MouseEvent(
        kind: .scrolled(deltaX: Int.max, deltaY: 2), location: .init(x: 2, y: 2))
      let next = MouseEvent(kind: .scrolled(deltaX: 1, deltaY: 3), location: .init(x: 2, y: 2))
      buffer.enqueue(.input(.mouse(first)))
      buffer.enqueue(.input(.mouse(next)))
      let batch = buffer.drain()
      try #require(batch.count == 2)
      let events = batch.compactMap { item -> InputEvent? in
        guard case .input(let event) = item.event else { return nil }
        return event
      }
      #expect(events == [.mouse(first), .mouse(next)])
      #expect(batch.map(\.arrival.count) == [1, 1])
      #expect(!buffer.hasPendingEvents())
    }

    @Test func setA1025RetiringALeaseAfterDrainRejectsOnlyItsStaleTerminalKey() throws {
      // Hypothesis: terminal validity is captured when an event enters the
      // pump, so a drained event still dispatches after its connection retires.
      let root = testIdentity("SetA1025")
      let input = InjectedTerminalInputReader()
      let host = RecordingPresentationSurface(surfaceSize: .init(width: 24, height: 3))
      let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
      let state = StateContainer(initialState: 0, invalidationIdentities: [root])
      let loop = RunLoop(
        rootIdentity: root, presentationSurface: host, terminalInputReader: input,
        scheduler: scheduler, stateContainer: state,
        focusTracker: FocusTracker(invalidationIdentities: [root]),
        keyHandler: { key, _, state in
          guard key == KeyPress(.character("a")) else { return .ignored }
          state.mutate { $0 += 1 }
          return .handled
        }, exitKeyBindings: .none,
        viewBuilder: .init { input in Text("Count \(input.state)") })
      state.invalidator = scheduler
      loop.installFocusTrackerInvalidator()
      loop.isSessionActive = true
      defer {
        input.finish()
        loop.isSessionActive = false
        loop.lifecycleCoordinator.shutdown()
      }
      var frames = 0
      scheduler.requestInvalidation(of: [root])
      try loop.renderPendingFrames(renderedFrames: &frames)
      try #require(host.frames.last?.contains("Count 0") == true)
      let buffer = EventPumpBuffer()
      let old = InputConnectionLease()
      let current = InputConnectionLease()
      buffer.enqueue(.scopedInput(.init(.key(.character("a")), origin: .terminal, lease: old)))
      buffer.enqueue(.scopedInput(.init(.key(.character("a")), origin: .terminal, lease: current)))
      let staleBatch = buffer.drain()
      let freshBatch = buffer.drain()
      let stale = try #require(staleBatch.first)
      let fresh = try #require(freshBatch.first)
      old.retire()
      _ = loop.handle(stale.event, arrival: stale.arrival)
      #expect(state.state == 0)
      _ = loop.handle(fresh.event, arrival: fresh.arrival)
      #expect(state.state == 1)
      try loop.renderPendingFrames(renderedFrames: &frames)
      #expect(host.frames.last?.contains("Count 1") == true)
      #expect(loop.currentInputOrigin == nil)
    }

  }

  private enum TerminalLifetimeFailure: Error { case probe }

  private final class TerminalLifetimeObservation<Event: Sendable>: Sendable {
    private let events = Mutex<[Event]>([])
    let first = AsyncEvent()
    let ended = AsyncEvent()
    var snapshot: [Event] { events.withLock { $0 } }
    func record(_ event: Event) {
      events.withLock { $0.append(event) }
      first.fire()
    }
    func waitForEnd() async throws {
      try await terminalLifetimeWait(ended, label: "terminal input EOF")
    }
  }

  private func terminalLifetimeWait(_ event: AsyncEvent, label: String) async throws {
    try await valueWithTimeout(label) {
      await event.wait()
      try Task.checkCancellation()
    }
  }

  private func terminalLifetimeCollect(_ stream: AsyncStream<InputEvent>) async throws
    -> [InputEvent]
  {
    try await valueWithTimeout("finite injected input stream") {
      var result: [InputEvent] = []
      for await event in stream { result.append(event) }
      try Task.checkCancellation()
      return result
    }
  }

  private func terminalLifetimeMove(_ x: Int) -> InputEvent {
    .mouse(.init(kind: .moved, location: .init(x: Double(x), y: 1)))
  }

  @MainActor
  private final class TerminalLifetimePipe {
    let readFD: Int32
    private var writeFD: Int32
    let reader: InputReader
    private var consumers: [Task<Void, Never>] = []
    private var additionalSourceOwners: [InputReader] = []

    init() throws {
      var descriptors: [Int32] = [-1, -1]
      let created = unsafe pipe(&descriptors)
      try #require(created == 0)
      var initialized = false
      defer {
        if !initialized {
          _ = close(descriptors[0])
          _ = close(descriptors[1])
        }
      }
      let flags = fcntl(descriptors[0], F_GETFL)
      try #require(flags >= 0)
      let configured = fcntl(descriptors[0], F_SETFL, flags | O_NONBLOCK)
      try #require(configured == 0)
      readFD = descriptors[0]
      writeFD = descriptors[1]
      reader = InputReader(fileDescriptor: readFD)
      initialized = true
    }

    func observe<Event: Sendable>(
      _ stream: AsyncStream<Event>, retaining sourceOwner: InputReader? = nil
    ) -> TerminalLifetimeObservation<Event> {
      if let sourceOwner { additionalSourceOwners.append(sourceOwner) }
      let observation = TerminalLifetimeObservation<Event>()
      let task = Task {
        for await event in stream { observation.record(event) }
        observation.ended.fire()
      }
      consumers.append(task)
      return observation
    }

    func write(_ bytes: [UInt8]) throws {
      try #require(writeFD >= 0)
      try bytes.withUnsafeBufferPointer { buffer in
        var offset = 0
        while offset < buffer.count {
          let written = unsafe platformTerminalLifetimeWrite(
            writeFD, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
          try #require(written > 0)
          offset += written
        }
      }
    }

    func closeWriter() {
      if writeFD >= 0 {
        _ = close(writeFD)
        writeFD = -1
      }
    }

    func cancelReaders() async throws {
      for consumer in consumers { consumer.cancel() }
      for consumer in consumers { await consumer.value }
      consumers.removeAll()
      let inputReaders = [reader] + additionalSourceOwners
      try await valueWithTimeout("dispatch source cancellation") {
        while inputReaders.contains(where: { $0.liveReadSourceCount != 0 }) {
          try Task.checkCancellation()
          await Task.yield()
        }
      }
      additionalSourceOwners.removeAll()
    }

    func closeReaderAfterCancellation() {
      // Never close a descriptor still registered with libdispatch, even if a
      // failed teardown assertion takes the error path through this fixture.
      if reader.liveReadSourceCount == 0
        && additionalSourceOwners.allSatisfy({ $0.liveReadSourceCount == 0 })
      {
        _ = close(readFD)
      }
    }
  }

  @MainActor
  private final class TerminalLifetimeWeakReader {
    weak var reader: InputReader?
  }

  private final class TerminalLifetimeCallbackOwner: Sendable {
    let released: AsyncEvent
    let received = Mutex(0)
    init(released: AsyncEvent) { self.released = released }
    func record() { received.withLock { $0 += 1 } }
    deinit { released.fire() }
  }

  @MainActor
  private func terminalLifetimeCompleteTransientReader(
    _ pipe: TerminalLifetimePipe, ownership: TerminalLifetimeWeakReader, released: AsyncEvent
  ) async throws {
    let callbackOwner = TerminalLifetimeCallbackOwner(released: released)
    let reader = InputReader(
      fileDescriptor: pipe.readFD, controlHandler: { _ in callbackOwner.record() })
    ownership.reader = reader
    let received = pipe.observe(reader.inputEvents(), retaining: reader)
    try pipe.write(Array("\u{1E}resize:80:24\nz".utf8))
    pipe.closeWriter()
    try await received.waitForEnd()
    #expect(received.snapshot == [.key(.character("z"))])
    #expect(callbackOwner.received.withLock { $0 } == 1)
    #expect(ownership.reader != nil)
    #expect(reader.liveReadSourceCount == 0)
  }

  @MainActor
  private func withTerminalLifetimePipe(
    _ body: @MainActor (TerminalLifetimePipe) async throws -> Void
  ) async throws {
    let pipe = try TerminalLifetimePipe()
    do {
      try await body(pipe)
      pipe.closeWriter()
      try await pipe.cancelReaders()
      pipe.closeReaderAfterCancellation()
    } catch {
      pipe.closeWriter()
      try? await pipe.cancelReaders()
      pipe.closeReaderAfterCancellation()
      throw error
    }
  }

  private func platformTerminalLifetimeWrite(
    _ descriptor: Int32, _ bytes: UnsafeRawPointer?, _ count: Int
  ) -> Int {
    #if canImport(Darwin)
      unsafe Darwin.write(descriptor, bytes, count)
    #elseif canImport(Glibc)
      unsafe Glibc.write(descriptor, bytes, count)
    #elseif canImport(Android)
      unsafe Android.write(descriptor, bytes, count)
    #elseif canImport(Musl)
      unsafe Musl.write(descriptor, bytes, count)
    #endif
  }
#endif
