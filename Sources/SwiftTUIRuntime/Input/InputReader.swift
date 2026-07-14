import SwiftTUICore
import Synchronization

#if canImport(Dispatch)
  @unsafe @preconcurrency import Dispatch
#endif

/// Reads terminal input from a file descriptor.
public final class InputReader: InputReading, TerminalInputReading,
  TerminalInputCapabilityConfiguring
{
  private let fileDescriptor: Int32
  private let mouseCoordinateMode: Mutex<MouseCoordinateMode>
  private let controlHandler: @Sendable (TerminalControlMessage) -> Void
  private let controlChannelEnabled: Bool

  #if !canImport(WASILibc)
    /// Live dispatch read-sources, registered so ``withInputSuspended(_:)``
    /// can pause them around a capability probe's reads of the shared input
    /// descriptor (F42).
    private struct SuspendableSourceRegistry {
      var nextID: UInt64 = 0
      var sources: [UInt64: (source: any DispatchSourceRead, queue: DispatchQueue)] = [:]
    }

    private let suspendableSources = OSAllocatedUnfairLock(
      uncheckedState: SuspendableSourceRegistry()
    )

    private func registerSuspendableSource(
      _ source: any DispatchSourceRead,
      queue: DispatchQueue
    ) -> UInt64 {
      suspendableSources.withLockUnchecked { registry in
        registry.nextID += 1
        registry.sources[registry.nextID] = (source, queue)
        return registry.nextID
      }
    }

    private func unregisterSuspendableSource(_ id: UInt64) {
      suspendableSources.withLockUnchecked { registry in
        _ = registry.sources.removeValue(forKey: id)
      }
    }
  #endif

  /// Creates an input reader bound to `fileDescriptor`.
  public init(
    fileDescriptor: Int32 = 0,
    pointerPrecisionPolicy: PointerPrecisionPolicy = .cellOnly,
    cellPixelMetrics: CellPixelMetrics? = nil,
    controlHandler: @escaping @Sendable (TerminalControlMessage) -> Void = { _ in }
  ) {
    self.fileDescriptor = fileDescriptor
    self.mouseCoordinateMode = Mutex(
      .resolving(
        policy: pointerPrecisionPolicy,
        metrics: cellPixelMetrics
      )
    )
    self.controlHandler = controlHandler
    // The in-band 0x1E control channel is written only by embedded-host
    // transports (the WebHost browser transport feeding a hosted binary's
    // stdin, WASI stdin records). A real interactive TTY never emits the
    // introducer — but with the channel armed, a typed Ctrl+^ silently
    // diverts all input into the control buffer until the next newline
    // (F138). Gate on the descriptor itself: TTY → off, pipe/WASI → on
    // (the pre-F138 behavior, which hosted transports rely on for resize).
    #if canImport(WASILibc)
      self.controlChannelEnabled = true
    #else
      self.controlChannelEnabled = !POSIXTerminalController().isATTY(fileDescriptor)
    #endif
  }

  package func updateInputCapabilities(
    _ capabilities: ResolvedTerminalInputCapabilities
  ) {
    mouseCoordinateMode.withLock { mode in
      mode = capabilities.mouseCoordinateMode
    }
  }

  /// Reads keyboard-only events.
  public func events() -> AsyncStream<KeyPress> {
    makeEventStream(
      transform: { parser, input in
        parser.feed(input).compactMap {
          guard case .key(let keyPress) = $0 else {
            return nil
          }
          return keyPress
        }
      },
      flushTransform: { parser in
        parser.flush().compactMap {
          guard case .key(let keyPress) = $0 else {
            return nil
          }
          return keyPress
        }
      }
    )
  }

  /// Reads keyboard and mouse events.
  public func inputEvents() -> AsyncStream<InputEvent> {
    makeTerminalInputEventStream()
  }
}

extension InputReader {
  #if canImport(WASILibc)
    private func makeTerminalInputEventStream() -> AsyncStream<InputEvent> {
      let fileDescriptor = self.fileDescriptor
      let controlHandler = self.controlHandler
      let controlChannelEnabled = self.controlChannelEnabled
      let mouseCoordinateMode = self.mouseCoordinateMode.withLock { $0 }

      return makeTaskBackedAsyncStream(
        launch: { operation in
          Task.detached {
            await operation()
          }
        }
      ) { continuation in
        var decoder = TerminalInputEventDecoder<InputEvent>(
          mouseCoordinateMode: mouseCoordinateMode,
          controlChannelEnabled: controlChannelEnabled,
          transform: { parser, input in parser.feed(input) },
          flushTransform: { parser in parser.flush() }
        )
        var pendingMouseEvents: [InputEvent] = []

        func flushPendingMouseEvents() {
          guard !pendingMouseEvents.isEmpty else {
            return
          }

          let flushedEvents = coalescedInputEvents(pendingMouseEvents)
          pendingMouseEvents.removeAll(keepingCapacity: true)
          for event in flushedEvents {
            continuation.yield(event)
          }
        }

        var backoff = InputPollBackoff()

        while !Task.isCancelled {
          switch readTerminalInputChunk(from: fileDescriptor, maxBytes: 512) {
          case .bytes(let chunk):
            backoff.recordInput()
            let decoded = decoder.decode(chunk)

            for message in decoded.controlMessages {
              flushPendingMouseEvents()
              controlHandler(message)
            }

            for event in decoded.events {
              switch event {
              case .mouse(let mouseEvent) where mouseEvent.isCoalescible:
                pendingMouseEvents.append(.mouse(mouseEvent))
              default:
                flushPendingMouseEvents()
                continuation.yield(event)
              }
            }
            continue
          case .wouldBlock:
            if !pendingMouseEvents.isEmpty {
              flushPendingMouseEvents()
            }
            // An idle poll is the WASI equivalent of the escape-disambiguation
            // timeout: a lone ESC that has not been followed by a continuation
            // byte is committed to a bare Escape. `flushEscape()` is a no-op
            // unless the parser is holding one.
            for event in decoder.flushEscape() {
              continuation.yield(event)
            }
            try? await Task.sleep(nanoseconds: backoff.delayNanoseconds)
            backoff.recordIdlePoll()
            continue
          case .endOfFile, .failure:
            flushPendingMouseEvents()
            continuation.finish()
            return
          }
        }
      }
    }

    private func makeEventStream<Event: Sendable>(
      transform: @escaping @Sendable (inout TerminalInputParser, [UInt8]) -> [Event],
      flushTransform: @escaping @Sendable (inout TerminalInputParser) -> [Event]
    ) -> AsyncStream<Event> {
      let fileDescriptor = self.fileDescriptor
      let controlHandler = self.controlHandler
      let controlChannelEnabled = self.controlChannelEnabled
      let mouseCoordinateMode = self.mouseCoordinateMode.withLock { $0 }

      return makeTaskBackedAsyncStream(
        launch: { operation in
          Task.detached {
            await operation()
          }
        }
      ) { continuation in
        var decoder = TerminalInputEventDecoder<Event>(
          mouseCoordinateMode: mouseCoordinateMode,
          controlChannelEnabled: controlChannelEnabled,
          transform: transform,
          flushTransform: flushTransform
        )
        var backoff = InputPollBackoff()

        while !Task.isCancelled {
          switch readTerminalInputChunk(from: fileDescriptor, maxBytes: 512) {
          case .bytes(let chunk):
            backoff.recordInput()
            let decoded = decoder.decode(chunk)

            for message in decoded.controlMessages {
              controlHandler(message)
            }

            for event in decoded.events {
              continuation.yield(event)
            }
            await Task.yield()
            continue
          case .wouldBlock:
            // An idle poll is the WASI escape-disambiguation timeout: commit a
            // lone buffered ESC to a bare Escape (no-op unless one is pending).
            for event in decoder.flushEscape() {
              continuation.yield(event)
            }
            try? await Task.sleep(nanoseconds: backoff.delayNanoseconds)
            backoff.recordIdlePoll()
            continue
          case .endOfFile, .failure:
            continuation.finish()
            return
          }
        }
      }
    }
  #else
    private func makeTerminalInputEventStream() -> AsyncStream<InputEvent> {
      makeManagedAsyncStream { continuation in
        let fileDescriptor = self.fileDescriptor
        let controlHandler = self.controlHandler
        let controlChannelEnabled = self.controlChannelEnabled
        let mouseCoordinateMode = self.mouseCoordinateMode.withLock { $0 }
        let queue = DispatchQueue(label: "InputReader.\(fileDescriptor)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        let suspendableID = self.registerSuspendableSource(source, queue: queue)
        var decoder = TerminalInputEventDecoder<InputEvent>(
          mouseCoordinateMode: mouseCoordinateMode,
          controlChannelEnabled: controlChannelEnabled,
          transform: { parser, input in parser.feed(input) },
          flushTransform: { parser in parser.flush() }
        )
        let coalescingState = MouseEventCoalescingState()
        var scheduledFlush: DispatchWorkItem?
        var scheduledEscapeFlush: DispatchWorkItem?

        let flushPendingMouseEvents = {
          scheduledFlush?.cancel()
          scheduledFlush = nil

          let drained = coalescingState.drain()
          guard !drained.isEmpty else {
            return
          }

          let flushedEvents = coalescedInputEvents(drained)
          for event in flushedEvents {
            continuation.yield(event)
          }
        }

        // Escape-disambiguation timer (vim `ttimeoutlen`): a lone ESC is
        // buffered by the parser because byte-wise it is indistinguishable from
        // the start of an escape sequence. Arm a short idle timer whenever the
        // decoder is holding one; a continuation byte arriving first cancels it
        // (see `reconcileEscapeDisambiguation`), otherwise it fires and commits
        // the bare Escape. Both closures run on `queue`, so the shared `decoder`
        // and `scheduledEscapeFlush` need no extra synchronization.
        let flushPendingEscape = {
          scheduledEscapeFlush?.cancel()
          scheduledEscapeFlush = nil
          for event in decoder.flushEscape() {
            continuation.yield(event)
          }
        }

        let reconcileEscapeDisambiguation = {
          guard decoder.isAwaitingEscapeDisambiguation else {
            scheduledEscapeFlush?.cancel()
            scheduledEscapeFlush = nil
            return
          }
          guard scheduledEscapeFlush == nil else {
            return
          }
          let workItem = DispatchWorkItem {
            flushPendingEscape()
          }
          scheduledEscapeFlush = workItem
          queue.asyncAfter(
            deadline: .now()
              + .milliseconds(InputReaderTiming.escapeDisambiguationDelayMilliseconds),
            execute: workItem
          )
        }

        let appendMouseEventAndArmFlushIfNeeded = { (event: InputEvent) in
          // The coalescing state implements the
          // schedule-once-per-cluster invariant.  See its docs for
          // why this matters — TL;DR: rescheduling on every event
          // pushes the flush deadline forward indefinitely under a
          // continuous burst, which is the gallery's "scroll does
          // nothing until I click" bug.
          guard coalescingState.append(event) else {
            return
          }
          let workItem = DispatchWorkItem {
            flushPendingMouseEvents()
          }
          scheduledFlush = workItem
          queue.asyncAfter(
            deadline: .now() + .milliseconds(InputReaderTiming.mouseEventFlushDelayMilliseconds),
            execute: workItem
          )
        }

        source.setEventHandler {
          let drainResult = drainAvailableTerminalInput(
            from: fileDescriptor,
            maxBytesPerRead: 256
          )
          if drainResult.failureErrno != nil {
            scheduledEscapeFlush?.cancel()
            scheduledEscapeFlush = nil
            flushPendingMouseEvents()
            continuation.finish()
            source.cancel()
            return
          }

          if !drainResult.bytes.isEmpty {
            let decoded = decoder.decode(drainResult.bytes)
            for message in decoded.controlMessages {
              flushPendingMouseEvents()
              controlHandler(message)
            }

            for event in decoded.events {
              switch event {
              case .mouse(let mouseEvent) where mouseEvent.isCoalescible:
                appendMouseEventAndArmFlushIfNeeded(.mouse(mouseEvent))
              default:
                flushPendingMouseEvents()
                continuation.yield(event)
              }
            }
            reconcileEscapeDisambiguation()
          }

          if drainResult.shouldFinish {
            scheduledEscapeFlush?.cancel()
            scheduledEscapeFlush = nil
            flushPendingMouseEvents()
            continuation.finish()
            source.cancel()
          }
        }

        source.setCancelHandler {
          self.unregisterSuspendableSource(suspendableID)
          scheduledFlush?.cancel()
          scheduledEscapeFlush?.cancel()
          flushPendingMouseEvents()
          continuation.finish()
        }

        source.resume()

        return { _ in
          source.cancel()
        }
      }
    }

    private func makeEventStream<Event: Sendable>(
      transform: @escaping @Sendable (inout TerminalInputParser, [UInt8]) -> [Event],
      flushTransform: @escaping @Sendable (inout TerminalInputParser) -> [Event]
    ) -> AsyncStream<Event> {
      makeManagedAsyncStream { continuation in
        let fileDescriptor = self.fileDescriptor
        let controlHandler = self.controlHandler
        let controlChannelEnabled = self.controlChannelEnabled
        let mouseCoordinateMode = self.mouseCoordinateMode.withLock { $0 }
        let queue = DispatchQueue(label: "InputReader.\(fileDescriptor)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        let suspendableID = self.registerSuspendableSource(source, queue: queue)
        var decoder = TerminalInputEventDecoder<Event>(
          mouseCoordinateMode: mouseCoordinateMode,
          controlChannelEnabled: controlChannelEnabled,
          transform: transform,
          flushTransform: flushTransform
        )
        var scheduledEscapeFlush: DispatchWorkItem?

        // Escape-disambiguation timer (vim `ttimeoutlen`): commit a lone
        // buffered ESC to a bare Escape after a quiet window unless a
        // continuation byte completes the sequence first. Both closures run on
        // `queue`, so the shared `decoder`/`scheduledEscapeFlush` need no lock.
        let reconcileEscapeDisambiguation = {
          guard decoder.isAwaitingEscapeDisambiguation else {
            scheduledEscapeFlush?.cancel()
            scheduledEscapeFlush = nil
            return
          }
          guard scheduledEscapeFlush == nil else {
            return
          }
          let workItem = DispatchWorkItem {
            scheduledEscapeFlush = nil
            for event in decoder.flushEscape() {
              continuation.yield(event)
            }
          }
          scheduledEscapeFlush = workItem
          queue.asyncAfter(
            deadline: .now()
              + .milliseconds(InputReaderTiming.escapeDisambiguationDelayMilliseconds),
            execute: workItem
          )
        }

        source.setEventHandler {
          let drainResult = drainAvailableTerminalInput(
            from: fileDescriptor,
            maxBytesPerRead: 256
          )
          if drainResult.failureErrno != nil {
            scheduledEscapeFlush?.cancel()
            scheduledEscapeFlush = nil
            continuation.finish()
            source.cancel()
            return
          }

          if !drainResult.bytes.isEmpty {
            let decoded = decoder.decode(drainResult.bytes)
            for message in decoded.controlMessages {
              controlHandler(message)
            }

            for event in decoded.events {
              continuation.yield(event)
            }
            reconcileEscapeDisambiguation()
          }

          if drainResult.shouldFinish {
            scheduledEscapeFlush?.cancel()
            scheduledEscapeFlush = nil
            continuation.finish()
            source.cancel()
          }
        }

        source.setCancelHandler {
          self.unregisterSuspendableSource(suspendableID)
          scheduledEscapeFlush?.cancel()
          continuation.finish()
        }

        source.resume()

        return { _ in
          source.cancel()
        }
      }
    }
  #endif
}

extension InputReader: TerminalInputSuspending {
  /// Suspends every live read source, barriers their queues so no in-flight
  /// drain can still consume the probe's reply, runs `body`, then resumes.
  /// Called from the main-actor capability probe; not reentrant.
  package func withInputSuspended<T>(_ body: () throws -> T) rethrows -> T {
    #if canImport(WASILibc)
      return try body()
    #else
      let entries = suspendableSources.withLockUnchecked { registry in
        Array(registry.sources.values)
      }
      for entry in entries {
        entry.source.suspend()
      }
      for entry in entries {
        entry.queue.sync {}
      }
      defer {
        for entry in entries {
          entry.source.resume()
        }
      }
      return try body()
    #endif
  }
}
