import Synchronization

package final class InjectedTerminalInputReader: TerminalInputReading, Sendable {
  private struct State: Sendable {
    var parser = TerminalInputParser()
    var controlParser = ControlMessageParser()
    var continuation: AsyncStream<InputEvent>.Continuation?
    var pendingEvents: [InputEvent] = []
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
    let (messages, events, continuation):
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

    for event in events {
      continuation?.yield(event)
    }
  }

  package func finish() {
    let continuation: AsyncStream<InputEvent>.Continuation? = state.withLock { state in
      guard !state.finished else {
        return nil
      }

      state.finished = true
      let continuation = state.continuation
      state.continuation = nil
      return continuation
    }

    continuation?.finish()
  }

  package func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let (shouldFinish, pendingEvents) = state.withLock { state in
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
        return
      }

      continuation.onTermination = { _ in
        self.state.withLock { state in
          state.continuation = nil
        }
      }
    }
  }
}
