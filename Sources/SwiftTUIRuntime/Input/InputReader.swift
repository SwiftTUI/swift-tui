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
    makeEventStream { parser, input in
      parser.feed(input).compactMap {
        guard case .key(let keyPress) = $0 else {
          return nil
        }
        return keyPress
      }
    }
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
      let mouseCoordinateMode = self.mouseCoordinateMode.withLock { $0 }

      return makeTaskBackedAsyncStream(
        launch: { operation in
          Task.detached {
            await operation()
          }
        }
      ) { continuation in
        var decoder = TerminalInputEventDecoder<InputEvent>(
          mouseCoordinateMode: mouseCoordinateMode
        ) { parser, input in
          parser.feed(input)
        }
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
      transform: @escaping @Sendable (inout TerminalInputParser, [UInt8]) -> [Event]
    ) -> AsyncStream<Event> {
      let fileDescriptor = self.fileDescriptor
      let controlHandler = self.controlHandler
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
          transform: transform
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
        let mouseCoordinateMode = self.mouseCoordinateMode.withLock { $0 }
        let queue = DispatchQueue(label: "InputReader.\(fileDescriptor)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        let suspendableID = self.registerSuspendableSource(source, queue: queue)
        var decoder = TerminalInputEventDecoder<InputEvent>(
          mouseCoordinateMode: mouseCoordinateMode
        ) { parser, input in
          parser.feed(input)
        }
        let coalescingState = MouseEventCoalescingState()
        var scheduledFlush: DispatchWorkItem?

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
          }

          if drainResult.shouldFinish {
            flushPendingMouseEvents()
            continuation.finish()
            source.cancel()
          }
        }

        source.setCancelHandler {
          self.unregisterSuspendableSource(suspendableID)
          scheduledFlush?.cancel()
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
      transform: @escaping @Sendable (inout TerminalInputParser, [UInt8]) -> [Event]
    ) -> AsyncStream<Event> {
      makeManagedAsyncStream { continuation in
        let fileDescriptor = self.fileDescriptor
        let controlHandler = self.controlHandler
        let mouseCoordinateMode = self.mouseCoordinateMode.withLock { $0 }
        let queue = DispatchQueue(label: "InputReader.\(fileDescriptor)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        let suspendableID = self.registerSuspendableSource(source, queue: queue)
        var decoder = TerminalInputEventDecoder<Event>(
          mouseCoordinateMode: mouseCoordinateMode,
          transform: transform
        )

        source.setEventHandler {
          let drainResult = drainAvailableTerminalInput(
            from: fileDescriptor,
            maxBytesPerRead: 256
          )
          if drainResult.failureErrno != nil {
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
          }

          if drainResult.shouldFinish {
            continuation.finish()
            source.cancel()
          }
        }

        source.setCancelHandler {
          self.unregisterSuspendableSource(suspendableID)
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
