import Core

#if canImport(Dispatch)
  @preconcurrency import Dispatch
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
    Darwin.read(fileDescriptor, buffer, count)
  }
#elseif canImport(Glibc)
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Glibc.read(fileDescriptor, buffer, count)
  }
#elseif canImport(Android)
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Android.read(fileDescriptor, buffer, count)
  }
#elseif canImport(WASILibc)
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Int(WASILibc.read(fileDescriptor, buffer, count))
  }
#endif

/// A normalized keyboard event emitted by the terminal input parser.
public enum KeyEvent: Equatable, Sendable {
  case character(Character)
  case enter
  case space
  case tab
  case shiftTab
  case arrowLeft
  case arrowRight
  case arrowUp
  case arrowDown
  case backspace
  case escape
  case ctrlC
}

/// A mouse button recognized by the input parser.
public enum MouseButton: Equatable, Sendable {
  case primary
  case middle
  case secondary
}

/// A normalized mouse event emitted by the terminal input parser.
public struct MouseEvent: Equatable, Sendable {
  /// Keyboard modifiers that accompanied the mouse event.
  public struct Modifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
  }

  /// The action represented by the mouse event.
  public enum Kind: Equatable, Sendable {
    case down(MouseButton)
    case up(MouseButton)
    case moved
    case dragged(MouseButton)
    case scrolled(deltaX: Int, deltaY: Int)
  }

  public var kind: Kind
  public var location: Point
  public var modifiers: Modifiers

  public init(
    kind: Kind,
    location: Point,
    modifiers: Modifiers = []
  ) {
    self.kind = kind
    self.location = location
    self.modifiers = modifiers
  }
}

/// A normalized terminal input event.
public enum InputEvent: Equatable, Sendable {
  case key(KeyEvent)
  case mouse(MouseEvent)
}

/// A non-input control message multiplexed onto the terminal input stream.
public enum TerminalControlMessage: Equatable, Sendable {
  case resize(Size)
}

func coalescedInputEvents(
  _ events: [InputEvent]
) -> [InputEvent] {
  guard !events.isEmpty else {
    return []
  }

  var coalesced: [InputEvent] = []
  coalesced.reserveCapacity(events.count)
  var pendingMouseEvent: MouseEvent?

  func flushPendingMouseEvent() {
    guard let currentPendingMouseEvent = pendingMouseEvent else {
      return
    }
    coalesced.append(.mouse(currentPendingMouseEvent))
    pendingMouseEvent = nil
  }

  for event in events {
    switch event {
    case .key:
      flushPendingMouseEvent()
      coalesced.append(event)
    case .mouse(let mouseEvent):
      guard mouseEvent.isCoalescible else {
        flushPendingMouseEvent()
        coalesced.append(.mouse(mouseEvent))
        continue
      }

      if let currentPendingMouseEvent = pendingMouseEvent,
        let mergedMouseEvent = currentPendingMouseEvent.merged(with: mouseEvent)
      {
        pendingMouseEvent = mergedMouseEvent
      } else {
        flushPendingMouseEvent()
        pendingMouseEvent = mouseEvent
      }
    }
  }

  flushPendingMouseEvent()
  return coalesced
}

enum InputReaderTiming {
  static let mouseEventFlushDelayMilliseconds = 1
}

/// Produces keyboard events from an input source.
public protocol InputReading: AnyObject {
  func events() -> AsyncStream<KeyEvent>
}

/// Produces keyboard and mouse events from an input source.
public protocol TerminalInputReading: AnyObject {
  func inputEvents() -> AsyncStream<InputEvent>
}

/// Incrementally parses terminal bytes into normalized keyboard and mouse
/// events.
public struct TerminalInputParser: Sendable {
  private var bufferedBytes: [UInt8] = []

  public init() {}

  /// Feeds raw bytes into the parser and returns any completed input events.
  public mutating func feed(_ bytes: [UInt8]) -> [InputEvent] {
    bufferedBytes.append(contentsOf: bytes)

    var events: [InputEvent] = []
    while let event = parseNextEvent() {
      events.append(event)
    }
    return events
  }
}

/// A keyboard-only view of ``TerminalInputParser``.
public struct KeyParser: Sendable {
  private var parser = TerminalInputParser()

  public init() {}

  /// Feeds raw bytes into the parser and returns only keyboard events.
  public mutating func feed(_ bytes: [UInt8]) -> [KeyEvent] {
    parser.feed(bytes).compactMap {
      guard case .key(let keyEvent) = $0 else {
        return nil
      }
      return keyEvent
    }
  }
}

extension TerminalInputParser {
  private mutating func parseNextEvent() -> InputEvent? {
    guard let firstByte = bufferedBytes.first else {
      return nil
    }

    switch firstByte {
    case 0x03:
      bufferedBytes.removeFirst()
      return .key(.ctrlC)
    case 0x08, 0x7F:
      bufferedBytes.removeFirst()
      return .key(.backspace)
    case 0x09:
      bufferedBytes.removeFirst()
      return .key(.tab)
    case 0x0A, 0x0D:
      bufferedBytes.removeFirst()
      return .key(.enter)
    case 0x1B:
      return parseEscapeSequence()
    case 0x20:
      bufferedBytes.removeFirst()
      return .key(.space)
    case 0x21...0x7E:
      bufferedBytes.removeFirst()
      let scalar = UnicodeScalar(Int(firstByte))!
      return .key(.character(Character(scalar)))
    default:
      bufferedBytes.removeFirst()
      return nil
    }
  }

  private mutating func parseEscapeSequence() -> InputEvent? {
    guard bufferedBytes.count > 1 else {
      return nil
    }

    guard bufferedBytes[1] == 0x5B else {
      bufferedBytes.removeFirst()
      return .key(.escape)
    }

    guard bufferedBytes.count > 2 else {
      return nil
    }

    if bufferedBytes[2] == 0x3C {
      return parseSGRMouseSequence()
    }

    switch bufferedBytes[2] {
    case 0x41:
      bufferedBytes.removeFirst(3)
      return .key(.arrowUp)
    case 0x42:
      bufferedBytes.removeFirst(3)
      return .key(.arrowDown)
    case 0x43:
      bufferedBytes.removeFirst(3)
      return .key(.arrowRight)
    case 0x44:
      bufferedBytes.removeFirst(3)
      return .key(.arrowLeft)
    case 0x5A:
      bufferedBytes.removeFirst(3)
      return .key(.shiftTab)
    default:
      bufferedBytes.removeFirst(3)
      return .key(.escape)
    }
  }

  private mutating func parseSGRMouseSequence() -> InputEvent? {
    var index = 3
    while index < bufferedBytes.count,
      bufferedBytes[index] != 0x4D,
      bufferedBytes[index] != 0x6D
    {
      let byte = bufferedBytes[index]
      guard (0x30...0x39).contains(byte) || byte == 0x3B else {
        bufferedBytes.removeFirst(index + 1)
        return nil
      }
      index += 1
    }

    guard index < bufferedBytes.count else {
      return nil
    }

    let terminator = bufferedBytes[index]
    let parameterBytes = Array(bufferedBytes[3..<index])
    bufferedBytes.removeFirst(index + 1)

    let parameters = parameterBytes.split(separator: 0x3B)
    guard parameters.count == 3,
      let encodedButton = asciiInteger(from: parameters[0]),
      let encodedX = asciiInteger(from: parameters[1]),
      let encodedY = asciiInteger(from: parameters[2])
    else {
      return nil
    }

    let location = Point(
      x: max(0, encodedX - 1),
      y: max(0, encodedY - 1)
    )
    let modifiers = mouseModifiers(from: encodedButton)
    let baseCode = encodedButton & 0b11
    let isMotion = (encodedButton & 32) != 0
    let isWheel = (encodedButton & 64) != 0

    if isWheel {
      let delta: (x: Int, y: Int)?
      switch baseCode {
      case 0:
        delta = (0, -1)
      case 1:
        delta = (0, 1)
      case 2:
        delta = (-1, 0)
      case 3:
        delta = (1, 0)
      default:
        delta = nil
      }

      guard let delta else {
        return nil
      }

      return .mouse(
        MouseEvent(
          kind: .scrolled(deltaX: delta.x, deltaY: delta.y),
          location: location,
          modifiers: modifiers
        )
      )
    }

    if isMotion {
      let kind: MouseEvent.Kind
      switch baseCode {
      case 0:
        kind = .dragged(.primary)
      case 1:
        kind = .dragged(.middle)
      case 2:
        kind = .dragged(.secondary)
      case 3:
        kind = .moved
      default:
        return nil
      }

      return .mouse(
        MouseEvent(
          kind: kind,
          location: location,
          modifiers: modifiers
        )
      )
    }

    guard let button = mouseButton(from: baseCode) else {
      return nil
    }

    let kind: MouseEvent.Kind =
      terminator == 0x6D
      ? .up(button)
      : .down(button)

    return .mouse(
      MouseEvent(
        kind: kind,
        location: location,
        modifiers: modifiers
      )
    )
  }

  private func asciiInteger(
    from bytes: ArraySlice<UInt8>
  ) -> Int? {
    guard !bytes.isEmpty else {
      return nil
    }

    var value = 0
    for byte in bytes {
      guard (0x30...0x39).contains(byte) else {
        return nil
      }
      value = (value * 10) + Int(byte - 0x30)
    }
    return value
  }

  private func mouseButton(
    from baseCode: Int
  ) -> MouseButton? {
    switch baseCode {
    case 0:
      .primary
    case 1:
      .middle
    case 2:
      .secondary
    default:
      nil
    }
  }

  private func mouseModifiers(
    from encodedButton: Int
  ) -> MouseEvent.Modifiers {
    var modifiers: MouseEvent.Modifiers = []
    if (encodedButton & 4) != 0 {
      modifiers.insert(.shift)
    }
    if (encodedButton & 8) != 0 {
      modifiers.insert(.option)
    }
    if (encodedButton & 16) != 0 {
      modifiers.insert(.control)
    }
    return modifiers
  }
}

private struct ControlMessageParser {
  private static let introducer: UInt8 = 0x1E
  private var bufferedCommand: [UInt8]? = nil

  mutating func feed(
    _ bytes: [UInt8]
  ) -> (payload: [UInt8], messages: [TerminalControlMessage]) {
    var payload: [UInt8] = []
    payload.reserveCapacity(bytes.count)
    var messages: [TerminalControlMessage] = []

    for byte in bytes {
      if bufferedCommand != nil {
        if byte == 0x0A {
          if let message = parseBufferedCommand() {
            messages.append(message)
          }
          bufferedCommand = nil
        } else {
          bufferedCommand?.append(byte)
        }
        continue
      }

      if byte == Self.introducer {
        bufferedCommand = []
        continue
      }

      payload.append(byte)
    }

    return (payload, messages)
  }

  private func parseBufferedCommand() -> TerminalControlMessage? {
    guard let bufferedCommand else {
      return nil
    }

    let text = String(decoding: bufferedCommand, as: UTF8.self)
    let components = text.split(separator: ":")
    guard components.count == 3, components[0] == "resize",
      let width = Int(components[1]),
      let height = Int(components[2])
    else {
      return nil
    }

    return .resize(
      .init(
        width: max(1, width),
        height: max(1, height)
      )
    )
  }
}

/// Reads terminal input from a file descriptor.
public final class InputReader: InputReading, TerminalInputReading {
  private let fileDescriptor: Int32
  private let controlHandler: @Sendable (TerminalControlMessage) -> Void

  /// Creates an input reader bound to `fileDescriptor`.
  public init(
    fileDescriptor: Int32 = STDIN_FILENO,
    controlHandler: @escaping @Sendable (TerminalControlMessage) -> Void = { _ in }
  ) {
    self.fileDescriptor = fileDescriptor
    self.controlHandler = controlHandler
  }

  /// Reads keyboard-only events.
  public func events() -> AsyncStream<KeyEvent> {
    makeEventStream { parser, input in
      parser.feed(input).compactMap {
        guard case .key(let keyEvent) = $0 else {
          return nil
        }
        return keyEvent
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
      makeEventStream { parser, input in
        parser.feed(input)
      }
    }

    private func makeEventStream<Event: Sendable>(
      transform: @escaping @Sendable (inout TerminalInputParser, [UInt8]) -> [Event]
    ) -> AsyncStream<Event> {
      AsyncStream { continuation in
        let fileDescriptor = self.fileDescriptor
        let controlHandler = self.controlHandler
        let task = Task.detached {
          var parser = TerminalInputParser()
          var controlParser = ControlMessageParser()

          while !Task.isCancelled {
            var buffer = Array(repeating: UInt8(0), count: 512)
            let bytesRead = platformRead(fileDescriptor, &buffer, buffer.count)

            if bytesRead > 0 {
              let chunk = Array(buffer.prefix(Int(bytesRead)))
              let filtered = controlParser.feed(chunk)

              for message in filtered.messages {
                controlHandler(message)
              }

              for event in transform(&parser, filtered.payload) {
                continuation.yield(event)
              }
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
  #else
    private func makeTerminalInputEventStream() -> AsyncStream<InputEvent> {
      AsyncStream { continuation in
        let fileDescriptor = self.fileDescriptor
        let controlHandler = self.controlHandler
        let queue = DispatchQueue(label: "InputReader.\(fileDescriptor)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        var parser = TerminalInputParser()
        var controlParser = ControlMessageParser()
        var pendingMouseEvents: [InputEvent] = []
        var scheduledFlush: DispatchWorkItem?

        let flushPendingMouseEvents = {
          scheduledFlush?.cancel()
          scheduledFlush = nil

          guard !pendingMouseEvents.isEmpty else {
            return
          }

          let flushedEvents = coalescedInputEvents(pendingMouseEvents)
          pendingMouseEvents.removeAll(keepingCapacity: true)
          for event in flushedEvents {
            continuation.yield(event)
          }
        }

        let scheduleFlush = {
          scheduledFlush?.cancel()
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
            let bytesRead = platformRead(fileDescriptor, &buffer, buffer.count)

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
            let filtered = controlParser.feed(input)
            for message in filtered.messages {
              flushPendingMouseEvents()
              controlHandler(message)
            }

            for event in parser.feed(filtered.payload) {
              switch event {
              case .mouse(let mouseEvent) where mouseEvent.isCoalescible:
                pendingMouseEvents.append(.mouse(mouseEvent))
                scheduleFlush()
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

        continuation.onTermination = { _ in
          source.cancel()
        }
      }
    }

    private func makeEventStream<Event: Sendable>(
      transform: @escaping @Sendable (inout TerminalInputParser, [UInt8]) -> [Event]
    ) -> AsyncStream<Event> {
      AsyncStream { continuation in
        let fileDescriptor = self.fileDescriptor
        let controlHandler = self.controlHandler
        let queue = DispatchQueue(label: "InputReader.\(fileDescriptor)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        var parser = TerminalInputParser()
        var controlParser = ControlMessageParser()

        source.setEventHandler {
          var input: [UInt8] = []
          var shouldFinish = false

          while true {
            var buffer = Array(repeating: UInt8(0), count: 256)
            let bytesRead = platformRead(fileDescriptor, &buffer, buffer.count)

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
            let filtered = controlParser.feed(input)
            for message in filtered.messages {
              controlHandler(message)
            }

            for event in transform(&parser, filtered.payload) {
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

        continuation.onTermination = { _ in
          source.cancel()
        }
      }
    }
  #endif
}

extension MouseEvent {
  var isCoalescible: Bool {
    switch kind {
    case .moved, .dragged, .scrolled:
      true
    case .down, .up:
      false
    }
  }

  func merged(
    with next: MouseEvent
  ) -> MouseEvent? {
    guard modifiers == next.modifiers else {
      return nil
    }

    switch (kind, next.kind) {
    case (.moved, .moved):
      return next
    case (.dragged(let lhsButton), .dragged(let rhsButton)) where lhsButton == rhsButton:
      return next
    case (.scrolled(let lhsDeltaX, let lhsDeltaY), .scrolled(let rhsDeltaX, let rhsDeltaY))
    where location == next.location:
      return .init(
        kind: .scrolled(
          deltaX: lhsDeltaX + rhsDeltaX,
          deltaY: lhsDeltaY + rhsDeltaY
        ),
        location: location,
        modifiers: modifiers
      )
    default:
      return nil
    }
  }
}
