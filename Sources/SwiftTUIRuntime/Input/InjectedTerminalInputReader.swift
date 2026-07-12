import Synchronization

package final class InjectedTerminalInputReader: TerminalInputReading, Sendable {
  package enum MouseFlushScheduling: Sendable {
    case automatic
    case manual
  }

  private struct State: Sendable {
    var parser: TerminalInputParser
    var controlParser = ControlMessageParser()
    var continuation: AsyncStream<InputEvent>.Continuation?
    var continuationGeneration: UInt64 = 0
    var pendingEvents: [InputEvent] = []
    var pendingMouseEvents: [InputEvent] = []
    var activeMouseFlushToken: UInt64?
    var nextMouseFlushToken: UInt64 = 0
    var activeEscapeFlushToken: UInt64?
    var nextEscapeFlushToken: UInt64 = 0
    var directHandler: (@Sendable (InputEvent) -> Void)?
    var finished = false
  }

  private let state: Mutex<State>
  private let controlHandler: @Sendable (TerminalControlMessage) -> Void
  private let mouseFlushScheduling: MouseFlushScheduling

  package init(
    mouseCoordinateMode: MouseCoordinateMode = .cells,
    mouseFlushScheduling: MouseFlushScheduling = .automatic,
    controlHandler: @escaping @Sendable (TerminalControlMessage) -> Void = { _ in }
  ) {
    state = Mutex(State(parser: TerminalInputParser(mouseCoordinateMode: mouseCoordinateMode)))
    self.mouseFlushScheduling = mouseFlushScheduling
    self.controlHandler = controlHandler
  }

  package func send(
    _ bytes: [UInt8]
  ) {
    let (messages, bufferedEvents, continuation, directHandler, escapeFlushToken):
      (
        [TerminalControlMessage],
        [InputEvent],
        AsyncStream<InputEvent>.Continuation?,
        (@Sendable (InputEvent) -> Void)?,
        UInt64?
      ) = state.withLock { state in
        guard !state.finished else {
          return (
            [],
            [],
            nil,
            nil,
            nil
          )
        }

        let filtered = state.controlParser.feed(bytes)
        let events = state.parser.feed(filtered.payload)
        let directHandler = state.directHandler
        if directHandler == nil && state.continuation == nil {
          state.pendingEvents.append(contentsOf: events)
        }
        let hasConsumer = directHandler != nil || state.continuation != nil
        let escapeFlushToken = armEscapeFlush(&state, hasConsumer: hasConsumer)
        return (
          filtered.messages,
          events,
          directHandler == nil ? state.continuation : nil,
          directHandler,
          escapeFlushToken
        )
      }

    for message in messages {
      controlHandler(message)
    }

    defer { scheduleEscapeFlush(escapeFlushToken) }

    if let directHandler {
      for event in bufferedEvents {
        directHandler(event)
      }
      return
    }

    guard continuation != nil else {
      return
    }

    for event in bufferedEvents {
      yieldInjectedEvent(event)
    }
  }

  package func send(
    _ event: InputEvent
  ) {
    let (continuation, directHandler):
      (
        AsyncStream<InputEvent>.Continuation?,
        (@Sendable (InputEvent) -> Void)?
      ) = state.withLock { state in
        guard !state.finished else {
          return (
            nil as AsyncStream<InputEvent>.Continuation?,
            nil as (@Sendable (InputEvent) -> Void)?
          )
        }

        if let directHandler = state.directHandler {
          return (nil, directHandler)
        }

        guard let continuation = state.continuation else {
          state.pendingEvents.append(event)
          return (nil, nil)
        }

        return (continuation, nil)
      }

    if let directHandler {
      directHandler(event)
      return
    }

    guard continuation != nil else {
      return
    }

    yieldInjectedEvent(event)
  }

  package func installDirectHandler(
    _ handler: @escaping @Sendable (InputEvent) -> Void
  ) -> [InputEvent] {
    state.withLock { state in
      state.directHandler = handler
      let pendingEvents = state.pendingEvents
      state.pendingEvents.removeAll(keepingCapacity: true)
      return pendingEvents
    }
  }

  package func clearDirectHandler() {
    state.withLock { state in
      state.directHandler = nil
    }
  }

  package func send(
    _ events: [InputEvent]
  ) {
    guard !events.isEmpty else {
      return
    }

    for event in events {
      send(event)
    }
  }

  package func finish() {
    let (continuation, pendingMouseEvents):
      (
        AsyncStream<InputEvent>.Continuation?,
        [InputEvent]
      ) = state.withLock { state in
        guard !state.finished else {
          return (nil, [])
        }

        state.finished = true
        let continuation = state.continuation
        state.continuation = nil
        state.directHandler = nil
        let pendingMouseEvents = coalescedInputEvents(state.pendingMouseEvents)
        state.pendingMouseEvents.removeAll(keepingCapacity: true)
        state.activeMouseFlushToken = nil
        state.activeEscapeFlushToken = nil
        return (continuation, pendingMouseEvents)
      }

    for event in pendingMouseEvents {
      continuation?.yield(event)
    }
    continuation?.finish()
  }

  @discardableResult
  package func flushPendingCoalescedMouseEvents() -> [InputEvent] {
    let (continuation, flushedMouseEvents) = flushPendingMouseEvents()
    for event in flushedMouseEvents {
      continuation?.yield(event)
    }
    return flushedMouseEvents
  }

  package func inputEvents() -> AsyncStream<InputEvent> {
    makeManagedAsyncStream { continuation in
      let (generation, shouldFinish, pendingEvents) = self.state.withLock { state in
        state.continuationGeneration &+= 1
        state.continuation = continuation
        let pendingEvents = state.pendingEvents
        state.pendingEvents.removeAll(keepingCapacity: true)
        return (
          state.continuationGeneration,
          state.finished,
          pendingEvents
        )
      }

      for event in pendingEvents {
        continuation.yield(event)
      }

      if shouldFinish {
        continuation.finish()
        return { _ in }
      }

      return { _ in
        self.state.withLock { state in
          guard state.continuationGeneration == generation else {
            return
          }
          state.continuation = nil
          state.activeMouseFlushToken = nil
        }
      }
    }
  }

  private func yieldInjectedEvent(
    _ event: InputEvent
  ) {
    switch event {
    case .mouse(let mouseEvent) where mouseEvent.isCoalescible:
      scheduleCoalescedMouseFlush(for: .mouse(mouseEvent))
    default:
      let (continuation, flushedMouseEvents) = flushPendingMouseEvents()
      for flushedEvent in flushedMouseEvents {
        continuation?.yield(flushedEvent)
      }
      let currentContinuation = state.withLock { $0.continuation }
      currentContinuation?.yield(event)
    }
  }

  private func scheduleCoalescedMouseFlush(
    for event: InputEvent
  ) {
    let token: UInt64? = state.withLock { state in
      state.pendingMouseEvents.append(event)
      guard state.activeMouseFlushToken == nil else {
        return nil
      }

      state.nextMouseFlushToken += 1
      let token = state.nextMouseFlushToken
      state.activeMouseFlushToken = token
      return token
    }

    guard let token else {
      return
    }
    guard mouseFlushScheduling == .automatic else {
      return
    }

    Task { [weak self] in
      try? await Task.sleep(
        nanoseconds: UInt64(InputReaderTiming.mouseEventFlushDelayMilliseconds) * 1_000_000
      )
      let (continuation, flushedMouseEvents) =
        self?.flushPendingMouseEvents(
          matching: token
        ) ?? (nil, [])
      for flushedEvent in flushedMouseEvents {
        continuation?.yield(flushedEvent)
      }
    }
  }

  private func flushPendingMouseEvents(
    matching token: UInt64? = nil
  ) -> (
    AsyncStream<InputEvent>.Continuation?,
    [InputEvent]
  ) {
    state.withLock { state in
      if let token, state.activeMouseFlushToken != token {
        return (state.continuation, [])
      }

      let continuation = state.continuation
      let flushedMouseEvents = coalescedInputEvents(state.pendingMouseEvents)
      state.pendingMouseEvents.removeAll(keepingCapacity: true)
      state.activeMouseFlushToken = nil
      return (continuation, flushedMouseEvents)
    }
  }

  // MARK: - Escape disambiguation (vim `ttimeoutlen`)

  /// Mints an escape-flush token when the parser is holding a lone ESC and a
  /// consumer is attached; returns `nil` (and releases any pending token) once
  /// a continuation byte has completed or advanced the sequence. Mirrors the
  /// mouse-flush schedule-once invariant so a token is only re-armed after the
  /// previous one resolves. Must be called with `state` locked.
  private func armEscapeFlush(
    _ state: inout State,
    hasConsumer: Bool
  ) -> UInt64? {
    guard state.parser.isAwaitingEscapeDisambiguation, hasConsumer else {
      state.activeEscapeFlushToken = nil
      return nil
    }
    guard state.activeEscapeFlushToken == nil else {
      return nil
    }
    state.nextEscapeFlushToken += 1
    let token = state.nextEscapeFlushToken
    state.activeEscapeFlushToken = token
    return token
  }

  private func scheduleEscapeFlush(
    _ token: UInt64?
  ) {
    guard let token, mouseFlushScheduling == .automatic else {
      return
    }

    Task { [weak self] in
      try? await Task.sleep(
        nanoseconds: UInt64(InputReaderTiming.escapeDisambiguationDelayMilliseconds) * 1_000_000
      )
      self?.flushEscape(matching: token)
    }
  }

  private func flushEscape(
    matching token: UInt64
  ) {
    let (continuation, directHandler, events):
      (
        AsyncStream<InputEvent>.Continuation?,
        (@Sendable (InputEvent) -> Void)?,
        [InputEvent]
      ) = state.withLock { state in
        guard state.activeEscapeFlushToken == token else {
          return (nil, nil, [])
        }
        state.activeEscapeFlushToken = nil
        // A continuation byte may have completed the sequence after the token
        // was minted; `flush()` returns empty in that case.
        return (state.continuation, state.directHandler, state.parser.flush())
      }

    guard !events.isEmpty else {
      return
    }

    if let directHandler {
      for event in events {
        directHandler(event)
      }
      return
    }

    for event in events {
      continuation?.yield(event)
    }
  }
}
