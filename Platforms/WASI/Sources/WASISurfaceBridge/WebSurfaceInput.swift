@_spi(Runners) package import SwiftTUIRuntime

package final class WebSurfaceInputReader: TerminalInputReading, Sendable {
  private let fileDescriptor: Int32
  private let controlHandler: @Sendable (WebSurfaceInputControlMessage) -> Void

  package init(
    fileDescriptor: Int32 = webSurfaceStandardInputFileDescriptor,
    controlHandler: @escaping @Sendable (WebSurfaceInputControlMessage) -> Void = { _ in }
  ) {
    self.fileDescriptor = fileDescriptor
    self.controlHandler = controlHandler
  }

  package func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let fileDescriptor = self.fileDescriptor
      let controlHandler = self.controlHandler
      let task = Task.detached {
        var parser = WebSurfaceInputParser()
        var backoff = InputPollBackoff()

        while !Task.isCancelled {
          var buffer = Array(repeating: UInt8(0), count: 512)
          let bytesRead = unsafe webSurfaceRead(fileDescriptor, &buffer, buffer.count)

          if bytesRead > 0 {
            backoff.recordInput()
            let chunk = Array(buffer.prefix(Int(bytesRead)))
            let parsed = parser.feed(chunk)
            for controlMessage in parsed.controlMessages {
              controlHandler(controlMessage)
            }
            for event in coalescedWebSurfaceInputEvents(parsed.events) {
              continuation.yield(event)
            }
            await Task.yield()
            continue
          }

          if bytesRead < 0, webSurfaceErrnoIsWouldBlock(webSurfaceErrno) {
            try? await Task.sleep(nanoseconds: backoff.delayNanoseconds)
            backoff.recordIdlePoll()
            continue
          }

          continuation.finish()
          return
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

package enum WebSurfaceInputControlMessage: Equatable, Sendable {
  case resize(CellSize, cellPixelSize: PixelSize?)
  case style(TerminalRenderStyle)
  /// A host capability declaration (`caps:{json}`), sent once by the
  /// WebSocket client after open. Absence means ``HostWireCapabilities``
  /// defaults — today's bytes. See `HostWireSchema.capabilityMappings`.
  case capabilities(HostWireCapabilities)
}

// `WebSurfaceInputParser` — the incremental byte/command parser — lives in
// `WebSurfaceInputParser.swift`.

private func coalescedWebSurfaceInputEvents(
  _ events: [InputEvent]
) -> [InputEvent] {
  guard !events.isEmpty else {
    return []
  }

  var coalesced: [InputEvent] = []
  var pendingMouseEvent: MouseEvent?

  func flushPendingMouseEvent() {
    guard let mouseEvent = pendingMouseEvent else {
      return
    }
    coalesced.append(.mouse(mouseEvent))
    pendingMouseEvent = nil
  }

  for event in events {
    switch event {
    case .key, .paste, .drop:
      flushPendingMouseEvent()
      coalesced.append(event)
    case .mouse(let mouseEvent):
      switch mouseEvent.kind {
      case .moved, .dragged, .scrolled:
        if let existing = pendingMouseEvent,
          let merged = mergeWebSurfaceMouseEvents(existing, mouseEvent)
        {
          pendingMouseEvent = merged
        } else {
          flushPendingMouseEvent()
          pendingMouseEvent = mouseEvent
        }
      case .down, .up:
        flushPendingMouseEvent()
        coalesced.append(event)
      }
    }
  }

  flushPendingMouseEvent()
  return coalesced
}

private func mergeWebSurfaceMouseEvents(
  _ lhs: MouseEvent,
  _ rhs: MouseEvent
) -> MouseEvent? {
  guard lhs.location.precision == rhs.location.precision,
    lhs.modifiers == rhs.modifiers
  else {
    return nil
  }

  switch (lhs.kind, rhs.kind) {
  case (.scrolled(let lhsDeltaX, let lhsDeltaY), .scrolled(let rhsDeltaX, let rhsDeltaY))
  where lhs.location.cell == rhs.location.cell:
    return .init(
      kind: .scrolled(deltaX: lhsDeltaX + rhsDeltaX, deltaY: lhsDeltaY + rhsDeltaY),
      location: rhs.location,
      modifiers: rhs.modifiers
    )
  case (.moved, .moved):
    return rhs
  case (.dragged(let lhsButton), .dragged(let rhsButton)) where lhsButton == rhsButton:
    return rhs
  default:
    return nil
  }
}
