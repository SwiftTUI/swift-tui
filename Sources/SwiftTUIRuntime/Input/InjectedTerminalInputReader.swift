import Synchronization

package final class InjectedTerminalInputReader: TerminalInputReading, Sendable {
  package enum MouseFlushScheduling: Sendable { case automatic, manual }

  private struct State: Sendable {
    var parser: TerminalInputParser
    var controlParser = ControlMessageParser()
    var continuation: AsyncStream<InputEvent>.Continuation?
    var continuationGeneration: UInt64 = 0
    var directHandler: (@Sendable (InputEvent) -> Void)?
    var directFinishHandler: (@Sendable () -> Void)?
    var pendingEvents: [InputEvent] = []
    var nextEvent = 0
    var pendingMouseEvents: [InputEvent] = []
    var activeMouseFlushToken: UInt64?
    var nextMouseFlushToken: UInt64 = 0
    var activeEscapeFlushToken: UInt64?
    var nextEscapeFlushToken: UInt64 = 0
    var finished = false
    var draining = false
    var hasConsumer: Bool { directHandler != nil || continuation != nil }
  }

  private enum Delivery {
    case event(InputEvent, @Sendable (InputEvent) -> Void)
    case end(@Sendable () -> Void)
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

  package func send(_ bytes: [UInt8]) {
    let result = state.withLock { state -> ([TerminalControlMessage], UInt64?, UInt64?) in
      guard !state.finished else { return ([], nil, nil) }
      let filtered = state.controlParser.feed(bytes)
      let events = state.parser.feed(filtered.payload)
      let mouseToken = append(events, to: &state)
      // This is an idle deadline: continued input renews it, including a
      // paste arriving in several reads over a slow connection.
      state.activeEscapeFlushToken = nil
      let escapeToken = armEscapeFlush(&state)
      return (filtered.messages, mouseToken, escapeToken)
    }
    for message in result.0 { controlHandler(message) }
    scheduleMouseFlush(result.1)
    scheduleEscapeFlush(result.2)
    drain()
  }

  package func send(_ event: InputEvent) { send([event]) }

  package func send(_ events: [InputEvent]) {
    guard !events.isEmpty else { return }
    let token = state.withLock { state -> UInt64? in
      guard !state.finished else { return nil }
      state.controlParser.endPendingPaste()
      let pending = state.parser.flush()
      state.activeEscapeFlushToken = nil
      return append(pending + events, to: &state)
    }
    scheduleMouseFlush(token)
    drain()
  }

  /// One queue owns delivery across stream/direct handoffs, timer callbacks,
  /// and EOF. Callbacks run outside the lock and may reenter any reader method.
  /// Reentrant sends and finish append work to the same drain, so EOF cannot
  /// overtake accepted input or be followed by a detached batch's callbacks.
  private func drain() {
    let acquired = state.withLock { state in
      guard !state.draining, state.hasConsumer else { return false }
      state.draining = true
      return true
    }
    guard acquired else { return }
    while let delivery = state.withLock({ state -> Delivery? in
      if state.nextEvent < state.pendingEvents.count, state.hasConsumer {
        let event = state.pendingEvents[state.nextEvent]
        state.nextEvent += 1
        if let handler = state.directHandler { return .event(event, handler) }
        if let continuation = state.continuation {
          return .event(event, { continuation.yield($0) })
        }
      }
      if state.nextEvent == state.pendingEvents.count {
        state.pendingEvents.removeAll(keepingCapacity: true)
        state.nextEvent = 0
        if state.finished, state.hasConsumer {
          let continuation = state.continuation
          let onFinish = state.directFinishHandler
          state.continuation = nil
          state.directHandler = nil
          state.directFinishHandler = nil
          return .end {
            continuation?.finish()
            onFinish?()
          }
        }
      }
      state.draining = false
      return nil
    }) {
      switch delivery {
      case .event(let event, let handler): handler(event)
      case .end(let finish): finish()
      }
    }
  }

  /// Append through the same pointer ordering barrier on every ingress path.
  /// Direct delivery remains uncoalesced, as required by the synchronous pump.
  private func append(_ events: [InputEvent], to state: inout State) -> UInt64? {
    var token: UInt64?
    for event in events {
      if state.directHandler == nil, state.continuation != nil,
        case .mouse(let mouse) = event, mouse.isCoalescible
      {
        state.pendingMouseEvents.append(event)
        if state.activeMouseFlushToken == nil {
          state.nextMouseFlushToken &+= 1
          state.activeMouseFlushToken = state.nextMouseFlushToken
          token = state.activeMouseFlushToken
        }
      } else {
        _ = appendPendingMouse(&state)
        state.pendingEvents.append(event)
      }
    }
    return token
  }

  @discardableResult
  private func appendPendingMouse(_ state: inout State) -> [InputEvent] {
    let events = coalescedInputEvents(state.pendingMouseEvents)
    state.pendingMouseEvents.removeAll(keepingCapacity: true)
    state.activeMouseFlushToken = nil
    state.pendingEvents.append(contentsOf: events)
    return events
  }

  package func installDirectHandler(
    _ handler: @escaping @Sendable (InputEvent) -> Void,
    onFinish: @escaping @Sendable () -> Void
  ) {
    let token = state.withLock { state in
      _ = appendPendingMouse(&state)
      state.directHandler = handler
      state.directFinishHandler = onFinish
      state.activeEscapeFlushToken = nil
      return armEscapeFlush(&state)
    }
    scheduleEscapeFlush(token)
    drain()
  }

  package func clearDirectHandler() {
    let token = state.withLock { state in
      state.directHandler = nil
      state.directFinishHandler = nil
      state.activeEscapeFlushToken = nil
      return armEscapeFlush(&state)
    }
    scheduleEscapeFlush(token)
    drain()
  }

  package func finish() {
    state.withLock { state in
      guard !state.finished else { return }
      state.finished = true
      state.controlParser.endPendingPaste()
      let events = state.parser.flush()
      _ = append(events, to: &state)
      _ = appendPendingMouse(&state)
      state.activeEscapeFlushToken = nil
    }
    drain()
  }

  package func inputEvents() -> AsyncStream<InputEvent> {
    makeManagedAsyncStream { continuation in
      let (generation, token) = self.state.withLock { state in
        state.continuationGeneration &+= 1
        state.continuation = continuation
        state.activeEscapeFlushToken = nil
        return (state.continuationGeneration, self.armEscapeFlush(&state))
      }
      self.scheduleEscapeFlush(token)
      self.drain()
      return { _ in
        let token = self.state.withLock { state -> UInt64? in
          guard state.continuationGeneration == generation else { return nil }
          state.continuation = nil
          // Preserve admitted input across a consumer handoff. A retired
          // timer cannot drain the parser while nobody owns delivery.
          _ = self.appendPendingMouse(&state)
          state.activeEscapeFlushToken = nil
          return self.armEscapeFlush(&state)
        }
        self.scheduleEscapeFlush(token)
        self.drain()
      }
    }
  }

  @discardableResult
  package func flushPendingCoalescedMouseEvents() -> [InputEvent] {
    flushMouse(matching: nil)
  }

  private func flushMouse(matching token: UInt64?) -> [InputEvent] {
    let events = state.withLock { state in
      if let token, state.activeMouseFlushToken != token { return [InputEvent]() }
      return appendPendingMouse(&state)
    }
    drain()
    return events
  }

  private func scheduleMouseFlush(_ token: UInt64?) {
    guard let token, mouseFlushScheduling == .automatic else { return }
    Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(InputReaderTiming.mouseEventFlushDelayMilliseconds))
      _ = self?.flushMouse(matching: token)
    }
  }

  private func armEscapeFlush(_ state: inout State) -> UInt64? {
    guard !state.finished, state.hasConsumer, state.parser.isAwaitingEscapeDisambiguation else {
      state.activeEscapeFlushToken = nil
      return nil
    }
    guard state.activeEscapeFlushToken == nil else { return nil }
    state.nextEscapeFlushToken &+= 1
    state.activeEscapeFlushToken = state.nextEscapeFlushToken
    return state.activeEscapeFlushToken
  }

  private func scheduleEscapeFlush(_ token: UInt64?) {
    guard let token, mouseFlushScheduling == .automatic else { return }
    Task { [weak self] in
      try? await Task.sleep(
        for: .milliseconds(InputReaderTiming.escapeDisambiguationDelayMilliseconds))
      self?.flushEscape(matching: token)
    }
  }

  package func flushPendingEscapeDisambiguation() {
    if let token = state.withLock({ $0.activeEscapeFlushToken }) { flushEscape(matching: token) }
  }

  private func flushEscape(matching token: UInt64) {
    state.withLock { state in
      guard state.activeEscapeFlushToken == token, state.hasConsumer, !state.finished else {
        return
      }
      state.activeEscapeFlushToken = nil
      state.controlParser.endPendingPaste()
      let events = state.parser.flush()
      _ = append(events, to: &state)
    }
    drain()
  }
}
