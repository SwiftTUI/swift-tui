import SwiftTUICore
import Synchronization

#if canImport(Dispatch)
  @unsafe @preconcurrency import Dispatch
#endif

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(WASILibc)
  import WASILibc
#endif

#if canImport(Darwin)
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.read(fileDescriptor, buffer, count)
  }
#elseif canImport(Glibc)
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.read(fileDescriptor, buffer, count)
  }
#elseif canImport(Android)
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Android.read(fileDescriptor, buffer, count)
  }
#elseif canImport(WASILibc)
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe WASILibc.read(fileDescriptor, buffer, count))
  }
#endif

/// Reads terminal input from a file descriptor.
public final class InputReader: InputReading, TerminalInputReading,
  TerminalInputCapabilityConfiguring
{
  private let fileDescriptor: Int32
  private let mouseCoordinateMode: Mutex<MouseCoordinateMode>
  private let controlHandler: @Sendable (TerminalControlMessage) -> Void

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

        while !Task.isCancelled {
          var buffer = Array(repeating: UInt8(0), count: 512)
          let bytesRead = unsafe platformRead(fileDescriptor, &buffer, buffer.count)

          if bytesRead > 0 {
            let chunk = Array(buffer.prefix(Int(bytesRead)))
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
          }

          if bytesRead < 0, errno == EAGAIN || errno == EWOULDBLOCK {
            if !pendingMouseEvents.isEmpty {
              flushPendingMouseEvents()
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
            continue
          }

          flushPendingMouseEvents()
          continuation.finish()
          return
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

        while !Task.isCancelled {
          var buffer = Array(repeating: UInt8(0), count: 512)
          let bytesRead = unsafe platformRead(fileDescriptor, &buffer, buffer.count)

          if bytesRead > 0 {
            let chunk = Array(buffer.prefix(Int(bytesRead)))
            let decoded = decoder.decode(chunk)

            for message in decoded.controlMessages {
              controlHandler(message)
            }

            for event in decoded.events {
              continuation.yield(event)
            }
            await Task.yield()
            continue
          }

          if bytesRead < 0, errno == EAGAIN || errno == EWOULDBLOCK {
            try? await Task.sleep(nanoseconds: 1_000_000)
            continue
          }

          continuation.finish()
          return
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
          var input: [UInt8] = []
          var shouldFinish = false

          while true {
            var buffer = Array(repeating: UInt8(0), count: 256)
            let bytesRead = unsafe platformRead(fileDescriptor, &buffer, buffer.count)

            if bytesRead > 0 {
              input.append(contentsOf: buffer.prefix(Int(bytesRead)))
              continue
            }

            if bytesRead == 0 {
              shouldFinish = true
              break
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
              break
            }

            flushPendingMouseEvents()
            continuation.finish()
            source.cancel()
            return
          }

          if !input.isEmpty {
            let decoded = decoder.decode(input)
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

          if shouldFinish {
            flushPendingMouseEvents()
            continuation.finish()
            source.cancel()
          }
        }

        source.setCancelHandler {
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
        var decoder = TerminalInputEventDecoder<Event>(
          mouseCoordinateMode: mouseCoordinateMode,
          transform: transform
        )

        source.setEventHandler {
          var input: [UInt8] = []
          var shouldFinish = false

          while true {
            var buffer = Array(repeating: UInt8(0), count: 256)
            let bytesRead = unsafe platformRead(fileDescriptor, &buffer, buffer.count)

            if bytesRead > 0 {
              input.append(contentsOf: buffer.prefix(Int(bytesRead)))
              continue
            }

            if bytesRead == 0 {
              shouldFinish = true
              break
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
              break
            }

            continuation.finish()
            source.cancel()
            return
          }

          if !input.isEmpty {
            let decoded = decoder.decode(input)
            for message in decoded.controlMessages {
              controlHandler(message)
            }

            for event in decoded.events {
              continuation.yield(event)
            }
          }

          if shouldFinish {
            continuation.finish()
            source.cancel()
          }
        }

        source.setCancelHandler {
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
