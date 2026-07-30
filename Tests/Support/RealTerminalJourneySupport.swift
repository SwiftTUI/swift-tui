@unsafe @preconcurrency public import Dispatch
public import SwiftTUICore
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// What actually arrived on the PTY while a wait was running.
///
/// A blank rendered screen is ambiguous on its own: the host may have written
/// nothing at all, or it may have written control sequences that produced no
/// visible glyphs. Separating those two cases is the first question worth
/// asking when a journey times out, and it is not recoverable after the fact —
/// the visible-screen projection has already discarded the evidence.
@_spi(Testing) public struct PTYByteTranscript: Sendable {
  /// Every byte read during the wait, including ones that produced no glyph.
  @_spi(Testing) public private(set) var byteCount = 0
  /// The most recent bytes, bounded so a chatty host cannot flood a failure.
  @_spi(Testing) public private(set) var tail: [UInt8] = []

  private static let tailByteBudget = 512

  @_spi(Testing) public init() {}

  mutating func append(_ bytes: [UInt8]) {
    guard !bytes.isEmpty else { return }
    byteCount += bytes.count
    tail.append(contentsOf: bytes)
    if tail.count > Self.tailByteBudget {
      tail.removeFirst(tail.count - Self.tailByteBudget)
    }
  }

  /// The tail rendered so control bytes survive a CI log verbatim.
  @_spi(Testing) public var escapedTail: String {
    var escaped = ""
    for byte in tail {
      switch byte {
      case 0x1B: escaped += "\\e"
      case 0x0A: escaped += "\\n"
      case 0x0D: escaped += "\\r"
      case 0x09: escaped += "\\t"
      case 0x5C: escaped += "\\\\"
      case 0x20...0x7E: escaped.append(Character(UnicodeScalar(byte)))
      default: escaped += "\\x" + String(byte, radix: 16, uppercase: true)
      }
    }
    return escaped
  }

  var summary: String {
    guard byteCount > 0 else {
      return "the host wrote 0 bytes to the PTY during the wait"
    }
    let elided = byteCount > tail.count ? " (last \(tail.count) of them)" : ""
    return "the host wrote \(byteCount) bytes to the PTY\(elided):\n\(escapedTail)"
  }
}

/// Failures reported by the shared real-terminal test primitives.
@_spi(Testing) public enum RealTerminalJourneyError: Error, CustomStringConvertible, Sendable {
  case unsupportedPlatform
  case operationFailed(operation: String, errno: Int32)
  case writeMadeNoProgress
  case reachedEndOfFile(rendered: String, transcript: PTYByteTranscript)
  case timedOut(rendered: String, transcript: PTYByteTranscript)

  @_spi(Testing) public var description: String {
    switch self {
    case .unsupportedPlatform:
      "Real-terminal journeys require Darwin or Glibc PTY support"
    case .operationFailed(let operation, let errorNumber):
      "\(operation) failed with errno \(errorNumber)"
    case .writeMadeNoProgress:
      "Writing to the PTY made no progress"
    case .reachedEndOfFile(let rendered, let transcript):
      """
      PTY reached end of file before the screen condition held; \
      \(transcript.summary)
      last screen was:
      \(rendered)
      """
    case .timedOut(let rendered, let transcript):
      """
      Timed out waiting for the PTY screen condition; \(transcript.summary)
      last screen was:
      \(rendered)
      """
    }
  }
}

/// A real pseudo-terminal pair for end-to-end runtime journeys.
///
/// The master is configured as nonblocking so a readable source can drain all
/// currently available output without stalling. Closing either side is
/// idempotent, and deinitialization closes any descriptor still owned by the
/// pair.
@_spi(Testing) public final class RealTerminalPTYPair: Sendable {
  private struct State {
    var ownsMaster = true
    var ownsSlave = true
  }

  @_spi(Testing) public let master: Int32
  @_spi(Testing) public let slave: Int32

  private let state = Mutex(State())

  private init(master: Int32, slave: Int32) {
    self.master = master
    self.slave = slave
  }

  deinit {
    closeMaster()
    closeSlave()
  }

  /// Opens a PTY with the requested initial terminal size.
  @_spi(Testing) public static func open(size: CellSize) throws -> RealTerminalPTYPair {
    #if canImport(Darwin) || canImport(Glibc)
      var master: Int32 = -1
      var slave: Int32 = -1
      var windowSize = winsize(
        ws_row: UInt16(max(1, size.height)),
        ws_col: UInt16(max(1, size.width)),
        ws_xpixel: 0,
        ws_ypixel: 0
      )

      guard unsafe openpty(&master, &slave, nil, nil, &windowSize) == 0 else {
        throw RealTerminalJourneyError.operationFailed(
          operation: "openpty",
          errno: errno
        )
      }

      let currentFlags = fcntl(master, F_GETFL)
      guard currentFlags >= 0 else {
        let errorNumber = errno
        _ = DarwinOrGlibcClose(master)
        _ = DarwinOrGlibcClose(slave)
        throw RealTerminalJourneyError.operationFailed(
          operation: "fcntl(F_GETFL)",
          errno: errorNumber
        )
      }
      guard fcntl(master, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
        let errorNumber = errno
        _ = DarwinOrGlibcClose(master)
        _ = DarwinOrGlibcClose(slave)
        throw RealTerminalJourneyError.operationFailed(
          operation: "fcntl(F_SETFL)",
          errno: errorNumber
        )
      }

      return RealTerminalPTYPair(master: master, slave: slave)
    #else
      throw RealTerminalJourneyError.unsupportedPlatform
    #endif
  }

  /// Closes the master descriptor if it is still owned by this pair.
  @_spi(Testing) public func closeMaster() {
    let shouldClose = state.withLock { state in
      guard state.ownsMaster else {
        return false
      }
      state.ownsMaster = false
      return true
    }
    guard shouldClose else {
      return
    }
    Self.close(fileDescriptor: master)
  }

  /// Closes the slave descriptor if it is still owned by this pair.
  @_spi(Testing) public func closeSlave() {
    let shouldClose = state.withLock { state in
      guard state.ownsSlave else {
        return false
      }
      state.ownsSlave = false
      return true
    }
    guard shouldClose else {
      return
    }
    Self.close(fileDescriptor: slave)
  }

  /// Closes both descriptors if they are still owned by this pair.
  @_spi(Testing) public func close() {
    closeMaster()
    closeSlave()
  }

  private static func close(fileDescriptor: Int32) {
    #if canImport(Darwin) || canImport(Glibc)
      _ = DarwinOrGlibcClose(fileDescriptor)
    #endif
  }
}

/// A `DispatchSource`-backed signal that a PTY has bytes ready to drain.
///
/// The stream finishes at `deadline`, so a consumer can never hang after the
/// runtime goes idle. Call and await ``cancel()`` before closing the file
/// descriptor so libdispatch releases its reference first.
@_spi(Testing) public final class RealTerminalPTYReadableSource {
  @_spi(Testing) public let events: AsyncStream<Void>

  private let source: any DispatchSourceRead
  private let cancelled = CancellationInsensitiveEvent()

  @_spi(Testing) public init(
    fileDescriptor: Int32,
    deadline: DispatchTime,
    queueLabel: String = "SwiftTUITestSupport.realTerminalPTYReadable"
  ) {
    let queue = DispatchQueue(label: queueLabel)
    let source = DispatchSource.makeReadSource(
      fileDescriptor: fileDescriptor,
      queue: queue
    )
    self.source = source

    var streamContinuation: AsyncStream<Void>.Continuation!
    events = AsyncStream<Void> { streamContinuation = $0 }
    let continuation = streamContinuation!
    let cancelledEvent = cancelled

    source.setEventHandler {
      continuation.yield(())
    }
    source.setCancelHandler {
      continuation.finish()
      cancelledEvent.fire()
    }
    source.resume()
    queue.asyncAfter(deadline: deadline) {
      source.cancel()
    }
  }

  /// Cancels the source and waits until libdispatch releases the descriptor.
  @_spi(Testing) public func cancel() async {
    source.cancel()
    await cancelled.wait()
  }
}

/// Writes every byte to a terminal file descriptor or throws.
@_spi(Testing) public func writeAllBytes(
  _ bytes: [UInt8],
  to fileDescriptor: Int32
) throws {
  #if canImport(Darwin) || canImport(Glibc)
    var totalBytesWritten = 0

    try unsafe bytes.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else {
        return
      }

      while totalBytesWritten < bytes.count {
        let nextAddress = unsafe baseAddress.advanced(by: totalBytesWritten)
        let bytesRemaining = bytes.count - totalBytesWritten
        let bytesWritten = unsafe write(fileDescriptor, nextAddress, bytesRemaining)

        if bytesWritten > 0 {
          totalBytesWritten += bytesWritten
          continue
        }
        if bytesWritten == 0 {
          throw RealTerminalJourneyError.writeMadeNoProgress
        }
        if errno == EINTR {
          continue
        }
        throw RealTerminalJourneyError.operationFailed(
          operation: "write",
          errno: errno
        )
      }
    }
  #else
    throw RealTerminalJourneyError.unsupportedPlatform
  #endif
}

/// Minimal visible-screen projection for ANSI output captured from a PTY.
///
/// The model intentionally implements only presentation operations emitted by
/// SwiftTUI's terminal host: cursor addressing and movement, clear-screen and
/// clear-line, styling/private-mode no-ops, and OSC/APC string suppression.
/// It is a test assertion boundary, not a general terminal emulator.
@_spi(Testing) public struct ANSIVisibleScreen: Sendable {
  private var size: CellSize
  private var cells: [[Character]]
  private var cursor = CellPoint.zero
  private var pendingBytes: [UInt8] = []

  @_spi(Testing) public init(size: CellSize) {
    self.size = size
    cells = Array(
      repeating: Array(repeating: " ", count: max(1, size.width)),
      count: max(1, size.height)
    )
  }

  /// The current visible rows with trailing spaces removed.
  @_spi(Testing) public var renderedText: String {
    cells
      .map { row in
        var endIndex = row.endIndex
        while endIndex > row.startIndex, row[row.index(before: endIndex)] == " " {
          endIndex = row.index(before: endIndex)
        }
        return String(row[..<endIndex])
      }
      .joined(separator: "\n")
  }

  /// Applies a possibly fragmented chunk of UTF-8 and ANSI output.
  @_spi(Testing) public mutating func feed(_ bytes: [UInt8]) {
    pendingBytes.append(contentsOf: bytes)

    var index = 0
    while index < pendingBytes.count {
      let byte = pendingBytes[index]

      if byte == 0x1B {
        guard index + 1 < pendingBytes.count else {
          break
        }

        let next = pendingBytes[index + 1]
        if next == 0x5B {
          guard let consumed = consumeCSI(startingAt: index) else {
            break
          }
          index = consumed
          continue
        }

        if next == 0x5D || next == 0x5F {
          guard let consumed = consumeStringEscape(startingAt: index) else {
            break
          }
          index = consumed
          continue
        }

        index += 2
        continue
      }

      if byte == 0x0D {
        cursor.x = 0
        index += 1
        continue
      }

      if byte == 0x0A {
        cursor.x = 0
        cursor.y = min(max(0, size.height - 1), cursor.y + 1)
        index += 1
        continue
      }

      if byte < 0x20 {
        index += 1
        continue
      }

      if byte < 0x80 {
        write(Character(UnicodeScalar(Int(byte))!))
        index += 1
        continue
      }

      let sequenceLength = utf8SequenceLength(for: byte)
      guard index + sequenceLength <= pendingBytes.count else {
        break
      }
      let character =
        String(
          decoding: pendingBytes[index..<(index + sequenceLength)],
          as: UTF8.self
        ).first ?? "•"
      write(character)
      index += sequenceLength
    }

    if index > 0 {
      pendingBytes.removeFirst(index)
    }
  }

  private mutating func consumeCSI(startingAt startIndex: Int) -> Int? {
    var index = startIndex + 2
    while index < pendingBytes.count {
      let byte = pendingBytes[index]
      if (0x40...0x7E).contains(byte) {
        let parameters = Array(pendingBytes[(startIndex + 2)..<index])
        applyCSI(parameters: parameters, command: byte)
        return index + 1
      }
      index += 1
    }
    return nil
  }

  private mutating func consumeStringEscape(startingAt startIndex: Int) -> Int? {
    var index = startIndex + 2
    while index + 1 < pendingBytes.count {
      if pendingBytes[index] == 0x1B, pendingBytes[index + 1] == 0x5C {
        return index + 2
      }
      if pendingBytes[index] == 0x07 {
        return index + 1
      }
      index += 1
    }
    return nil
  }

  private mutating func applyCSI(parameters: [UInt8], command: UInt8) {
    let parameterString = String(decoding: parameters, as: UTF8.self)
    let privateMode = parameterString.hasPrefix("?")
    let cleanedParameters =
      privateMode
      ? String(parameterString.dropFirst())
      : parameterString
    let values = cleanedParameters.split(separator: ";").compactMap { Int($0) }

    switch command {
    case 0x48, 0x66:  // H, f
      let row = max(1, values.first ?? 1) - 1
      let column = max(1, values.dropFirst().first ?? 1) - 1
      cursor = CellPoint(
        x: min(max(0, size.width - 1), column),
        y: min(max(0, size.height - 1), row)
      )
    case 0x4A:  // J
      if values.first == 2 || values.isEmpty {
        clearAll()
      }
    case 0x4B:  // K
      eraseToEndOfLine()
    case 0x43:  // C
      cursor.x = min(max(0, size.width - 1), cursor.x + max(1, values.first ?? 1))
    case 0x44:  // D
      cursor.x = max(0, cursor.x - max(1, values.first ?? 1))
    case 0x41:  // A
      cursor.y = max(0, cursor.y - max(1, values.first ?? 1))
    case 0x42:  // B
      cursor.y = min(max(0, size.height - 1), cursor.y + max(1, values.first ?? 1))
    case 0x47:  // G
      cursor.x = min(max(0, size.width - 1), max(1, values.first ?? 1) - 1)
    case 0x6D, 0x68, 0x6C:  // m, h, l
      return
    default:
      return
    }
  }

  private mutating func clearAll() {
    for row in cells.indices {
      for column in cells[row].indices {
        cells[row][column] = " "
      }
    }
    cursor = .zero
  }

  private mutating func eraseToEndOfLine() {
    guard cursor.y >= 0, cursor.y < cells.count else {
      return
    }
    let row = cursor.y
    guard cursor.x >= 0, cursor.x < cells[row].count else {
      return
    }
    for column in cursor.x..<cells[row].count {
      cells[row][column] = " "
    }
  }

  private mutating func write(_ character: Character) {
    guard cursor.y >= 0, cursor.y < cells.count else {
      return
    }
    guard cursor.x >= 0, cursor.x < cells[cursor.y].count else {
      return
    }
    cells[cursor.y][cursor.x] = character
    cursor.x += 1
  }

  private func utf8SequenceLength(for byte: UInt8) -> Int {
    switch byte {
    case 0xC0...0xDF:
      2
    case 0xE0...0xEF:
      3
    case 0xF0...0xF7:
      4
    default:
      1
    }
  }
}

/// Waits until PTY output makes `condition` hold on the visible screen.
///
/// The wait drains output immediately, then suspends on readable edges until
/// the condition holds, EOF proves it cannot hold, or `deadline` expires.
@_spi(Testing) public func waitForANSIVisibleScreen(
  on fileDescriptor: Int32,
  screen: inout ANSIVisibleScreen,
  deadline: DispatchTime,
  condition: (String) -> Bool
) async throws -> String {
  let readable = RealTerminalPTYReadableSource(
    fileDescriptor: fileDescriptor,
    deadline: deadline
  )
  do {
    var rendered = screen.renderedText
    var transcript = PTYByteTranscript()
    let initial = try readAvailablePTYBytes(
      from: fileDescriptor,
      deadline: deadline
    )
    transcript.append(initial.bytes)
    if !initial.bytes.isEmpty {
      screen.feed(initial.bytes)
      rendered = screen.renderedText
    }
    if initial.reachedDeadline || deadlineHasExpired(deadline) {
      throw RealTerminalJourneyError.timedOut(rendered: rendered, transcript: transcript)
    }
    try Task.checkCancellation()
    if condition(rendered) {
      await readable.cancel()
      try Task.checkCancellation()
      return rendered
    }
    if initial.reachedEOF {
      throw RealTerminalJourneyError.reachedEndOfFile(
        rendered: rendered,
        transcript: transcript
      )
    }

    var reachedEndOfFile = false

    for await _ in readable.events {
      let next = try readAvailablePTYBytes(
        from: fileDescriptor,
        deadline: deadline
      )
      transcript.append(next.bytes)
      if !next.bytes.isEmpty {
        screen.feed(next.bytes)
        rendered = screen.renderedText
      }
      if next.reachedDeadline || deadlineHasExpired(deadline) {
        break
      }
      try Task.checkCancellation()
      if condition(rendered) {
        await readable.cancel()
        try Task.checkCancellation()
        return rendered
      }
      if next.reachedEOF {
        reachedEndOfFile = true
        break
      }
    }

    await readable.cancel()
    try Task.checkCancellation()
    if reachedEndOfFile {
      throw RealTerminalJourneyError.reachedEndOfFile(
        rendered: rendered,
        transcript: transcript
      )
    }
    throw RealTerminalJourneyError.timedOut(rendered: rendered, transcript: transcript)
  } catch {
    await readable.cancel()
    throw error
  }
}

private let realTerminalDrainByteBudget = 64 * 1024

private func readAvailablePTYBytes(
  from fileDescriptor: Int32,
  deadline: DispatchTime
) throws -> (bytes: [UInt8], reachedEOF: Bool, reachedDeadline: Bool) {
  #if canImport(Darwin) || canImport(Glibc)
    var collected: [UInt8] = []
    var buffer = Array(repeating: UInt8(0), count: 4096)

    while collected.count < realTerminalDrainByteBudget {
      try Task.checkCancellation()
      guard !deadlineHasExpired(deadline) else {
        return (collected, false, true)
      }
      let bytesRead = unsafe read(fileDescriptor, &buffer, buffer.count)

      if bytesRead > 0 {
        collected.append(contentsOf: buffer.prefix(Int(bytesRead)))
        continue
      }
      if bytesRead == 0 {
        return (collected, true, false)
      }
      if errno == EINTR {
        continue
      }
      if errno == EAGAIN || errno == EWOULDBLOCK {
        return (collected, false, false)
      }
      throw RealTerminalJourneyError.operationFailed(
        operation: "read",
        errno: errno
      )
    }
    return (collected, false, deadlineHasExpired(deadline))
  #else
    throw RealTerminalJourneyError.unsupportedPlatform
  #endif
}

private func deadlineHasExpired(_ deadline: DispatchTime) -> Bool {
  DispatchTime.now().uptimeNanoseconds >= deadline.uptimeNanoseconds
}

private final class CancellationInsensitiveEvent: Sendable {
  private struct State {
    var isFired = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())

  func fire() {
    let waiters: [CheckedContinuation<Void, Never>] = state.withLock { state in
      guard !state.isFired else {
        return []
      }
      state.isFired = true
      defer { state.waiters = [] }
      return state.waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  func wait() async {
    await withCheckedContinuation { continuation in
      let resumeImmediately = state.withLock { state in
        if state.isFired {
          return true
        }
        state.waiters.append(continuation)
        return false
      }
      if resumeImmediately {
        continuation.resume()
      }
    }
  }
}

#if canImport(Darwin)
  private let DarwinOrGlibcClose = Darwin.close
#elseif canImport(Glibc)
  private let DarwinOrGlibcClose = Glibc.close
#endif
