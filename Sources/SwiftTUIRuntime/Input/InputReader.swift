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

/// Incrementally parses terminal bytes into normalized keyboard and mouse
/// events.
public struct TerminalInputParser: Sendable {
  private var bufferedBytes: [UInt8] = []
  private var mouseCoordinateMode: MouseCoordinateMode

  public init() {
    self.init(mouseCoordinateMode: .cells)
  }

  package init(
    mouseCoordinateMode: MouseCoordinateMode
  ) {
    self.mouseCoordinateMode = mouseCoordinateMode
  }

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
      // Ctrl+A through Ctrl+Z (excluding 0x03=Ctrl+C, 0x09=Tab, 0x0A/0x0D=Return).
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
      guard (0x30...0x39).contains(byte) || byte == 0x2D || byte == 0x3B else {
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
      let encodedX = asciiSignedInteger(from: parameters[1]),
      let encodedY = asciiSignedInteger(from: parameters[2])
    else {
      return nil
    }

    let location = pointerLocation(encodedX: encodedX, encodedY: encodedY)
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

  private func asciiSignedInteger(
    from bytes: ArraySlice<UInt8>
  ) -> Int? {
    guard !bytes.isEmpty else {
      return nil
    }

    // Avoid shadowing a `var ArraySlice<UInt8>` parameter and reassigning
    // it through `dropFirst()`. Under -Osize that pattern crashed the
    // OwnershipModelEliminator SIL pass on the wasm target in
    // Swift 6.3.1. Computing the digit subslice as a `let` once
    // sidesteps the bug and is also clearer.
    let isNegative = bytes.first == 0x2D
    let digits = isNegative ? bytes.dropFirst() : bytes

    guard !digits.isEmpty else {
      return nil
    }

    guard let value = asciiInteger(from: digits) else {
      return nil
    }
    return isNegative ? -value : value
  }

  private func pointerLocation(
    encodedX: Int,
    encodedY: Int
  ) -> PointerLocation {
    switch mouseCoordinateMode {
    case .disabled, .cells:
      return .cellFallback(
        CellPoint(
          x: max(0, encodedX - 1),
          y: max(0, encodedY - 1)
        )
      )
    case .pixels(let metrics, let source):
      let pixelX = encodedX - 1
      let pixelY = encodedY - 1
      let cellWidth = max(1, metrics.width)
      let cellHeight = max(1, metrics.height)
      return .subCell(
        location: Point(
          x: Double(pixelX) / Double(cellWidth),
          y: Double(pixelY) / Double(cellHeight)
        ),
        source: source,
        metrics: metrics,
        rawPixel: PixelPoint(x: Double(pixelX), y: Double(pixelY))
      )
    }
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
