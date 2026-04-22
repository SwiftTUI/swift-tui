import Synchronization

package final class InjectedTerminalInputReader: TerminalInputReading, Sendable {
  private struct State: Sendable {
    var parser = TerminalInputParser()
    var controlParser = ControlMessageParser()
    var continuation: AsyncStream<InputEvent>.Continuation?
    var pendingEvents: [InputEvent] = []
    var pendingMouseEvents: [InputEvent] = []
    var activeMouseFlushToken: UInt64?
    var nextMouseFlushToken: UInt64 = 0
    var finished = false
  }

  private let state = Mutex(State())
  private let controlHandler: @Sendable (TerminalControlMessage) -> Void

  package init(
    controlHandler: @escaping @Sendable (TerminalControlMessage) -> Void = { _ in }
  ) {
    self.controlHandler = controlHandler
  }

  package func send(
    _ bytes: [UInt8]
  ) {
    let (messages, bufferedEvents, continuation):
      (
        [TerminalControlMessage],
        [InputEvent],
        AsyncStream<InputEvent>.Continuation?
      ) = state.withLock { state in
        guard !state.finished else {
          return (
            [],
            [],
            nil
          )
        }

        let filtered = state.controlParser.feed(bytes)
        let events = state.parser.feed(filtered.payload)
        if state.continuation == nil {
          state.pendingEvents.append(contentsOf: events)
        }
        return (filtered.messages, events, state.continuation)
      }

    for message in messages {
      controlHandler(message)
    }

    guard continuation != nil else {
      return
    }

    for event in bufferedEvents {
      yieldInjectedEvent(event)
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
        let pendingMouseEvents = coalescedInputEvents(state.pendingMouseEvents)
        state.pendingMouseEvents.removeAll(keepingCapacity: true)
        state.activeMouseFlushToken = nil
        return (continuation, pendingMouseEvents)
      }

    for event in pendingMouseEvents {
      continuation?.yield(event)
    }
    continuation?.finish()
  }

  package func inputEvents() -> AsyncStream<InputEvent> {
    makeManagedAsyncStream { continuation in
      let (shouldFinish, pendingEvents) = self.state.withLock { state in
        state.continuation = continuation
        let pendingEvents = state.pendingEvents
        state.pendingEvents.removeAll(keepingCapacity: true)
        return (state.finished, pendingEvents)
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
}
