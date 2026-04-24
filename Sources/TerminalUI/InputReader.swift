import Core

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

/// A mouse button recognized by the input parser.
public enum MouseButton: Equatable, Sendable {
  case primary
  case middle
  case secondary
}

/// A normalized mouse event emitted by the terminal input parser.
public struct MouseEvent: Equatable, Sendable {
  /// Keyboard modifiers that accompanied the mouse event.
  public typealias Modifiers = EventModifiers

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

/// A bracketed-paste burst emitted by the terminal between
/// `ESC[200~` and `ESC[201~`. The `content` is the raw payload with
/// no terminal framing — callers decide whether the bytes represent a
/// file drop (routed to `.dropDestination` destinations) or ordinary
/// pasted text (routed back as character `KeyPress` events).
public struct PasteEvent: Equatable, Sendable {
  public var content: String

  public init(content: String) {
    self.content = content
  }
}

/// A normalized terminal input event.
public enum InputEvent: Equatable, Sendable {
  case key(KeyPress)
  case mouse(MouseEvent)
  case paste(PasteEvent)

  /// Convenience for creating a key event with optional modifiers.
  public static func key(
    _ keyEvent: KeyEvent,
    modifiers: EventModifiers = []
  ) -> Self {
    .key(KeyPress(keyEvent, modifiers: modifiers))
  }
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
    case .paste:
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

/// Returns `true` when `buffer` begins with the 6-byte bracketed-paste
/// start marker `ESC [ 2 0 0 ~`.  Pure and side-effect free.
private func matchesBracketedPasteStart(_ buffer: [UInt8]) -> Bool {
  let marker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
  guard buffer.count >= marker.count else { return false }
  for index in 0..<marker.count where buffer[index] != marker[index] {
    return false
  }
  return true
}

/// Schedule-once-per-cluster state machine for the input reader's
/// pending-mouse-event flush.  Extracted from the dispatch-source-
/// based reader so the schedule invariant can be tested without
/// driving the dispatch source.
///
/// **The invariant**: only the FIRST event in a cluster arms the
/// flush timer.  Subsequent events appended while a flush is
/// already pending must NOT re-arm.  This caps flush latency at
/// `mouseEventFlushDelayMilliseconds` regardless of event rate.
///
/// The earlier reset-on-every-event behavior was the root cause
/// of the gallery's "scroll does nothing until I click" bug: a
/// continuous high-rate scroll burst kept pushing the flush
/// deadline forward, so the consumer never received any events
/// until the input stream went idle.
package final class MouseEventCoalescingState {
  package private(set) var pendingEvents: [InputEvent] = []
  package private(set) var isFlushScheduled = false

  package init() {}

  /// Appends `event` to the pending buffer.  Returns `true` when
  /// the caller is responsible for arming a flush timer (this
  /// is the first event in a new cluster); returns `false` when
  /// a flush is already scheduled and should be left alone.
  @discardableResult
  package func append(_ event: InputEvent) -> Bool {
    pendingEvents.append(event)
    guard !isFlushScheduled else {
      return false
    }
    isFlushScheduled = true
    return true
  }

  /// Drains the pending buffer and resets the scheduled-flush
  /// flag so the next appended event arms a fresh cluster.
  package func drain() -> [InputEvent] {
    let drained = pendingEvents
    pendingEvents.removeAll(keepingCapacity: true)
    isFlushScheduled = false
    return drained
  }
}

/// Produces keyboard events from an input source.
public protocol InputReading: AnyObject {
  func events() -> AsyncStream<KeyPress>
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
  public mutating func feed(_ bytes: [UInt8]) -> [KeyPress] {
    parser.feed(bytes).compactMap {
      guard case .key(let keyPress) = $0 else {
        return nil
      }
      return keyPress
    }
  }
}

extension TerminalInputParser {
  private mutating func parseNextEvent() -> InputEvent? {
    guard let firstByte = bufferedBytes.first else {
      return nil
    }

    switch firstByte {
    case 0x01...0x02, 0x04...0x08, 0x0B...0x0C, 0x0E...0x1A:
      // Ctrl+A through Ctrl+Z (excluding 0x03=Ctrl+C, 0x09=Tab, 0x0A/0x0D=Return)
      bufferedBytes.removeFirst()
      let letter = Character(UnicodeScalar(Int(firstByte) + 0x60)!)
      return .key(KeyPress(.character(letter), modifiers: .ctrl))
    case 0x03:
      bufferedBytes.removeFirst()
      return .key(KeyPress(.character("c"), modifiers: .ctrl))
    case 0x08, 0x7F:
      bufferedBytes.removeFirst()
      return .key(KeyPress(.backspace))
    case 0x09:
      bufferedBytes.removeFirst()
      return .key(KeyPress(.tab))
    case 0x0A, 0x0D:
      bufferedBytes.removeFirst()
      return .key(KeyPress(.return))
    case 0x1B:
      return parseEscapeSequence()
    case 0x20:
      bufferedBytes.removeFirst()
      return .key(KeyPress(.space))
    case 0x21...0x7E:
      bufferedBytes.removeFirst()
      let scalar = UnicodeScalar(Int(firstByte))!
      return .key(KeyPress(.character(Character(scalar))))
    default:
      bufferedBytes.removeFirst()
      return nil
    }
  }

  private mutating func parseEscapeSequence() -> InputEvent? {
    guard bufferedBytes.count > 1 else {
      // Lone ESC — emit a bare escape key press so consumers receive
      // the keystroke instead of stalling until the next byte arrives.
      bufferedBytes.removeFirst()
      return .key(KeyPress(.escape))
    }

    guard bufferedBytes[1] == 0x5B else {
      // Alt+key: ESC followed by a printable byte
      if (0x20...0x7E).contains(bufferedBytes[1]) {
        let byte = bufferedBytes[1]
        bufferedBytes.removeFirst(2)
        let character = Character(UnicodeScalar(Int(byte))!)
        let key: KeyEvent
        switch byte {
        case 0x20:
          key = .space
        default:
          key = .character(character)
        }
        return .key(KeyPress(key, modifiers: .alt))
      }
      bufferedBytes.removeFirst()
      return .key(KeyPress(.escape))
    }

    guard bufferedBytes.count > 2 else {
      return nil
    }

    // Bracketed-paste start: ESC [ 2 0 0 ~ ... ESC [ 2 0 1 ~
    if matchesBracketedPasteStart(bufferedBytes) {
      return parseBracketedPaste()
    }

    if bufferedBytes[2] == 0x3C {
      return parseSGRMouseSequence()
    }

    // CSI sequences with modifier parameters: ESC[1;{mod}{key}
    if bufferedBytes[2] == 0x31 {
      return parseCSIModifierSequence()
    }

    switch bufferedBytes[2] {
    case 0x41:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.arrowUp))
    case 0x42:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.arrowDown))
    case 0x43:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.arrowRight))
    case 0x44:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.arrowLeft))
    case 0x48:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.home))
    case 0x46:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.end))
    case 0x5A:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.tab, modifiers: .shift))
    default:
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.escape))
    }
  }

  /// Parses CSI sequences with modifier parameters: `ESC[1;{mod}{key}`
  ///
  /// The xterm modifier parameter convention is: value = 1 + bitmask
  /// where shift=1, alt=2, ctrl=4.
  private mutating func parseCSIModifierSequence() -> InputEvent? {
    // Expect at least ESC [ 1 ; {mod} {key} = 6 bytes minimum
    guard bufferedBytes.count >= 6,
      bufferedBytes[3] == 0x3B  // semicolon
    else {
      // Not a modifier sequence — fall through to consume as unknown
      bufferedBytes.removeFirst(3)
      return .key(KeyPress(.escape))
    }

    // Find the terminal byte (an uppercase letter)
    var index = 4
    while index < bufferedBytes.count, (0x30...0x39).contains(bufferedBytes[index]) {
      index += 1
    }

    guard index < bufferedBytes.count else {
      return nil  // incomplete sequence, wait for more bytes
    }

    let terminalByte = bufferedBytes[index]
    let modifierBytes = Array(bufferedBytes[4..<index])
    bufferedBytes.removeFirst(index + 1)

    let modifiers = csiModifiers(from: modifierBytes)

    guard let key = csiTerminalKey(from: terminalByte) else {
      return .key(KeyPress(.escape, modifiers: modifiers))
    }

    return .key(KeyPress(key, modifiers: modifiers))
  }

  private func csiModifiers(from bytes: [UInt8]) -> EventModifiers {
    guard let value = asciiInteger(from: ArraySlice(bytes)) else {
      return []
    }
    // xterm convention: modifier = 1 + bitmask (shift=1, alt=2, ctrl=4)
    let bitmask = value - 1
    var modifiers: EventModifiers = []
    if (bitmask & 1) != 0 {
      modifiers.insert(.shift)
    }
    if (bitmask & 2) != 0 {
      modifiers.insert(.alt)
    }
    if (bitmask & 4) != 0 {
      modifiers.insert(.ctrl)
    }
    return modifiers
  }

  private func csiTerminalKey(from byte: UInt8) -> KeyEvent? {
    switch byte {
    case 0x41: return .arrowUp
    case 0x42: return .arrowDown
    case 0x43: return .arrowRight
    case 0x44: return .arrowLeft
    case 0x48: return .home
    case 0x46: return .end
    default: return nil
    }
  }

  /// Parses a bracketed-paste envelope: `ESC [ 2 0 0 ~ <payload> ESC [ 2 0 1 ~`.
  ///
  /// On entry the buffer is guaranteed to begin with the 6-byte start marker.
  /// If the matching end marker is already buffered, the whole envelope is
  /// consumed and a `.paste` event is returned.  Otherwise the buffer is left
  /// untouched so the caller can wait for more bytes.
  private mutating func parseBracketedPaste() -> InputEvent? {
    // Buffer layout at entry: ESC [ 2 0 0 ~ <payload> ESC [ 2 0 1 ~
    let startMarker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
    let endMarker: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]
    guard bufferedBytes.count >= startMarker.count else { return nil }
    // Look for the end marker anywhere after the start marker.
    let payloadStart = startMarker.count
    var searchIndex = payloadStart
    let totalCount = bufferedBytes.count
    while searchIndex + endMarker.count <= totalCount {
      var matches = true
      for offset in 0..<endMarker.count
      where bufferedBytes[searchIndex + offset] != endMarker[offset] {
        matches = false
        break
      }
      if matches {
        let payloadBytes = Array(bufferedBytes[payloadStart..<searchIndex])
        bufferedBytes.removeFirst(searchIndex + endMarker.count)
        let content = String(decoding: payloadBytes, as: UTF8.self)
        return .paste(PasteEvent(content: content))
      }
      searchIndex += 1
    }
    // End marker not yet seen — keep buffering.
    return nil
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
      modifiers.insert(.alt)
    }
    if (encodedButton & 16) != 0 {
      modifiers.insert(.ctrl)
    }
    return modifiers
  }
}

/// Reads terminal input from a file descriptor.
public final class InputReader: InputReading, TerminalInputReading {
  private let fileDescriptor: Int32
  private let controlHandler: @Sendable (TerminalControlMessage) -> Void

  /// Creates an input reader bound to `fileDescriptor`.
  public init(
    fileDescriptor: Int32 = 0,
    controlHandler: @escaping @Sendable (TerminalControlMessage) -> Void = { _ in }
  ) {
    self.fileDescriptor = fileDescriptor
    self.controlHandler = controlHandler
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

      return makeTaskBackedAsyncStream(
        launch: { operation in
          Task.detached {
            await operation()
          }
        }
      ) { continuation in
        var parser = TerminalInputParser()
        var controlParser = ControlMessageParser()
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
            let filtered = controlParser.feed(chunk)

            for message in filtered.messages {
              flushPendingMouseEvents()
              controlHandler(message)
            }

            for event in parser.feed(filtered.payload) {
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

      return makeTaskBackedAsyncStream(
        launch: { operation in
          Task.detached {
            await operation()
          }
        }
      ) { continuation in
        var parser = TerminalInputParser()
        var controlParser = ControlMessageParser()

        while !Task.isCancelled {
          var buffer = Array(repeating: UInt8(0), count: 512)
          let bytesRead = unsafe platformRead(fileDescriptor, &buffer, buffer.count)

          if bytesRead > 0 {
            let chunk = Array(buffer.prefix(Int(bytesRead)))
            let filtered = controlParser.feed(chunk)

            for message in filtered.messages {
              controlHandler(message)
            }

            for event in transform(&parser, filtered.payload) {
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
        let queue = DispatchQueue(label: "InputReader.\(fileDescriptor)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        var parser = TerminalInputParser()
        var controlParser = ControlMessageParser()
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
            let filtered = controlParser.feed(input)
            for message in filtered.messages {
              flushPendingMouseEvents()
              controlHandler(message)
            }

            for event in parser.feed(filtered.payload) {
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
        let queue = DispatchQueue(label: "InputReader.\(fileDescriptor)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        var parser = TerminalInputParser()
        var controlParser = ControlMessageParser()

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

        return { _ in
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
