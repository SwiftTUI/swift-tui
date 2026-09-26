@_spi(Runners) package import SwiftTUIRuntime
import Synchronization

/// Reads the web surface's stdin ring.
///
/// Two consumption modes, exactly one of which is active per instance:
///
/// - **Pull delivery** (`SynchronousInputPulling`), used by the run loop's
///   event pump. The run loop calls `pullPendingInput()` at its turn
///   boundaries and the reader's idle poll calls it between them; both are
///   main-actor isolated, so the parser has one owner and delivery order is
///   parse order. This is the repair for the one-activation-per-frame ingress
///   limit measured in the counter burst (plan 2026-09-24-001 §2/§4D,
///   STUI-618): the detached reader task, its `AsyncStream`, and the pump's
///   copy task all needed the run-loop task to suspend before an event could
///   move, and on the browser's cooperative executor that happened about once
///   per frame.
/// - **Stream adapter** (`inputEvents()`), retained for consumers that read
///   the reader as an `AsyncStream`. Not used by the pump when pull delivery
///   is available.
package final class WebSurfaceInputReader: TerminalInputReading, SynchronousInputPulling,
  Sendable
{
  private let fileDescriptor: Int32
  private let controlHandler: @Sendable (WebSurfaceInputControlMessage) -> Void
  /// Pull-delivery state. Only the main actor touches it — the boundary pull
  /// and the idle poll are both main-actor isolated — and the mutex is what
  /// lets a `Sendable` class hold the parser.
  private let pull = Mutex(PullState())

  private struct PullState {
    var parser = WebSurfaceInputParser()
    var sink: InputPullDeliverySink?
    var pollingTask: Task<Void, Never>?
    var ended = false
  }

  /// Bytes one pull reads at most before returning, so a pull at a frame
  /// boundary is bounded work; the remainder is read at the next boundary
  /// or by the idle poll. Sixteen kibibytes is about eight hundred pointer
  /// records — far beyond any burst a frame can answer.
  package static let maximumBytesPerPull = 16 * 1024

  package init(
    fileDescriptor: Int32 = webSurfaceStandardInputFileDescriptor,
    controlHandler: @escaping @Sendable (WebSurfaceInputControlMessage) -> Void = { _ in }
  ) {
    self.fileDescriptor = fileDescriptor
    self.controlHandler = controlHandler
  }

  // MARK: - Pull delivery

  @MainActor
  package func installPullDelivery(_ sink: InputPullDeliverySink) {
    let alreadyEnded = pull.withLock { state -> Bool in
      state.sink = sink
      return state.ended
    }
    if alreadyEnded {
      sink.inputEnded()
      return
    }
    // The idle poll: wakes a quiet loop when input arrives. It calls the same
    // pull the run loop calls, on the same actor, so the two paths cannot
    // interleave a parse. Under load the run loop's own boundary pulls carry
    // the input and this task mostly finds the ring empty.
    let task = Task { @MainActor [weak self] in
      var backoff = InputPollBackoff()
      while !Task.isCancelled {
        guard let self, !self.hasEnded else {
          return
        }
        if self.pullPendingInput() > 0 {
          backoff.recordInput()
        } else {
          backoff.recordIdlePoll()
        }
        try? await Task.sleep(nanoseconds: backoff.delayNanoseconds)
      }
    }
    pull.withLock { $0.pollingTask = task }
  }

  @MainActor
  @discardableResult
  package func pullPendingInput() -> Int {
    guard let sink = pull.withLock({ $0.ended ? nil : $0.sink }) else {
      return 0
    }
    var delivered = 0
    var totalBytes = 0
    var ended = false
    var buffer = [UInt8](repeating: 0, count: 4096)
    while totalBytes < Self.maximumBytesPerPull {
      let bytesRead = unsafe webSurfaceRead(fileDescriptor, &buffer, buffer.count)
      if bytesRead > 0 {
        totalBytes += bytesRead
        let chunk = Array(buffer.prefix(Int(bytesRead)))
        let records = pull.withLock { $0.parser.feedRecords(chunk) }
        let events = deliver(records, through: sink)
        sink.recordSourceRead(Int(bytesRead), events)
        delivered += events
        continue
      }
      if bytesRead < 0, webSurfaceErrnoIsWouldBlock(webSurfaceErrno) {
        break
      }
      // EOF or a non-retryable error: the source is gone.
      ended = true
      break
    }
    if ended {
      let firstEnd = pull.withLock { state -> Bool in
        defer { state.ended = true }
        return !state.ended
      }
      if firstEnd {
        sink.inputEnded()
      }
    }
    return delivered
  }

  @MainActor
  package func uninstallPullDelivery() {
    let task = pull.withLock { state -> Task<Void, Never>? in
      state.sink = nil
      defer { state.pollingTask = nil }
      return state.pollingTask
    }
    task?.cancel()
  }

  private var hasEnded: Bool {
    pull.withLock { $0.ended }
  }

  /// Delivers parsed records in order: input events are coalesced in runs
  /// between control messages exactly as the stream adapter coalesces them,
  /// and control messages go to the control handler at their position in
  /// the sequence. Returns the number of input events delivered.
  @MainActor
  private func deliver(
    _ records: [WebSurfaceInputRecord],
    through sink: InputPullDeliverySink
  ) -> Int {
    var pending: [InputEvent] = []
    var delivered = 0
    func flush() {
      for event in coalescedWebSurfaceInputEvents(pending) {
        sink.deliver(event)
        delivered += 1
      }
      pending.removeAll(keepingCapacity: true)
    }
    for record in records {
      switch record {
      case .input(let event):
        pending.append(event)
      case .control(let message):
        flush()
        controlHandler(message)
      }
    }
    flush()
    return delivered
  }

  // MARK: - Stream adapter

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
            let records = parser.feedRecords(chunk)
            var pending: [InputEvent] = []
            for record in records {
              switch record {
              case .input(let event): pending.append(event)
              case .control(let message):
                for event in coalescedWebSurfaceInputEvents(pending) { continuation.yield(event) }
                pending.removeAll(keepingCapacity: true)
                controlHandler(message)
              }
            }
            for event in coalescedWebSurfaceInputEvents(pending) { continuation.yield(event) }
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

package enum WebSurfaceInputRecord: Equatable, Sendable {
  case input(InputEvent)
  case control(WebSurfaceInputControlMessage)
}

package enum WebSurfaceInputControlMessage: Equatable, Sendable {
  case resize(CellSize, cellPixelSize: PixelSize?)
  case geometry(HostGeometryRequest)
  case style(TerminalRenderStyle)
  /// A pointer-paradigm declaration (`pointer:panning=1`), sent by the page
  /// when it resolves the pointer type and again whenever it changes — a
  /// tablet docked to a mouse switches paradigm without reloading.
  ///
  /// Unlike `caps:` this *is* live on the in-process transport: it describes
  /// the browsing device, which the WASI environment cannot see and which can
  /// change mid-session. Absence means the desktop paradigm (no panning),
  /// which is what a page bundle predating the record produces.
  case pointerCapabilities(supportsScrollPanning: Bool)
  /// A host capability declaration (`caps:{json}`), sent once by the
  /// WebSocket client after open. Absence means ``HostWireCapabilities``
  /// defaults — today's bytes. See `HostWireSchema.capabilityMappings`.
  case capabilities(HostWireCapabilities)
  /// A host delivery-repair request (`resync:{json}`).
  case resync(HostWireResyncRequest)
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
    case .key, .paste, .drop, .accessibility:
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
      case .down, .up, .cancelled:
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
    lhs.modifiers == rhs.modifiers,
    lhs.hostGeometryStamp == rhs.hostGeometryStamp
  else {
    return nil
  }

  switch (lhs.kind, rhs.kind) {
  case (.scrolled(let lhsDeltaX, let lhsDeltaY), .scrolled(let rhsDeltaX, let rhsDeltaY))
  where lhs.location.cell == rhs.location.cell:
    let (deltaX, overflowX) = lhsDeltaX.addingReportingOverflow(rhsDeltaX)
    let (deltaY, overflowY) = lhsDeltaY.addingReportingOverflow(rhsDeltaY)
    guard !overflowX, !overflowY else { return nil }
    var merged = rhs
    merged.kind = .scrolled(deltaX: deltaX, deltaY: deltaY)
    return merged
  case (.moved, .moved):
    return rhs
  case (.dragged(let lhsButton), .dragged(let rhsButton)) where lhsButton == rhsButton:
    return rhs
  default:
    return nil
  }
}
