@unsafe @preconcurrency public import Dispatch
import Foundation
public import SwiftTUICore
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(ucrt)
  import CRT
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
  case watchdogUnavailable(reason: String)

  @_spi(Testing) public var description: String {
    switch self {
    case .unsupportedPlatform:
      "Real-terminal journeys require Darwin or Glibc PTY support"
    case .watchdogUnavailable(let reason):
      "The real-terminal journey watchdog sidecar could not start: \(reason)"
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
  private let watchdog: RealTerminalJourneyWatchdog?

  private init(master: Int32, slave: Int32, watchdog: RealTerminalJourneyWatchdog?) {
    self.master = master
    self.slave = slave
    self.watchdog = watchdog
  }

  deinit {
    closeMaster()
    closeSlave()
  }

  /// Opens a PTY with the requested initial terminal size.
  ///
  /// The pair arms a ``RealTerminalJourneyWatchdog`` with `stallBudget`, so a
  /// journey that stops making progress ends the test process about that long
  /// after its last activity instead of at the CI job timeout. Pass `nil` to
  /// run without one. The `open` call site is what the watchdog names when it
  /// fires, so open the pair from the journey itself rather than a helper.
  @_spi(Testing) public static func open(
    size: CellSize,
    stallBudget: Duration? = .seconds(60),
    fileID: String = #fileID,
    line: Int = #line
  ) throws -> RealTerminalPTYPair {
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

      // Neither descriptor may leak into the watchdog sidecar (or any other
      // child spawned without explicit file actions): a stray master would
      // keep the pair's child from ever seeing hangup, a stray slave would
      // keep the master from ever reaching end of file. Children that need
      // the slave receive it through dup2, which clears the flag on the copy.
      for descriptor in [master, slave] where fcntl(descriptor, F_SETFD, FD_CLOEXEC) != 0 {
        let errorNumber = errno
        _ = DarwinOrGlibcClose(master)
        _ = DarwinOrGlibcClose(slave)
        throw RealTerminalJourneyError.operationFailed(
          operation: "fcntl(F_SETFD, FD_CLOEXEC)",
          errno: errorNumber
        )
      }

      let watchdog: RealTerminalJourneyWatchdog?
      do {
        watchdog = try stallBudget.map { budget in
          try RealTerminalJourneyWatchdog.arm(
            fileDescriptor: master,
            stallBudget: budget,
            origin: "\(fileID):\(line)"
          )
        }
      } catch {
        _ = DarwinOrGlibcClose(master)
        _ = DarwinOrGlibcClose(slave)
        throw error
      }
      return RealTerminalPTYPair(master: master, slave: slave, watchdog: watchdog)
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
    watchdog?.disarm()
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

// MARK: - Journey watchdog

/// Ends the test process when a real-terminal journey stops making progress,
/// so a wedged journey fails CI in about a minute instead of at the job's
/// timeout (60–75 minutes on the example gates).
///
/// Every ``RealTerminalPTYPair`` arms one watchdog in `open` and disarms it
/// when its master descriptor closes. Progress is any harness traffic on that
/// pair — a wait starting or finishing, bytes read, bytes written — and each
/// one is recorded as a heartbeat. The journey counts as stalled once
/// `stallBudget` passes with no heartbeat; every consumer wait carries a
/// deadline well inside the default budget, so healthy journeys that run for
/// minutes keep heartbeating and are never affected.
///
/// The watchdog lives OUTSIDE the test process. `arm` spawns a `/bin/sh`
/// sidecar that polls a heartbeat file and, on a stall, prints a diagnostic
/// to the inherited stderr (the CI log) and signals the test process: SIGCONT
/// and SIGABRT first, so a runtime with crash reporting enabled dumps its
/// threads, then SIGKILL. Nothing inside the test process is trusted: Swift
/// Testing's `.timeLimit` cannot stop a body that never reaches a suspension
/// point, and the 0.9.8 example gates wedged a process thoroughly enough that
/// an in-process libdispatch timer never ran either. The sidecar exits on its
/// own when the pair disarms or the test process goes away, and removes its
/// heartbeat file.
@_spi(Testing) public final class RealTerminalJourneyWatchdog: Sendable {
  private struct State {
    var armed = true
    var heartbeat: UInt64 = 0
    var lastWrite: DispatchTime
  }

  private static let registry = Mutex<[Int32: RealTerminalJourneyWatchdog]>([:])

  /// Polls per `budget / ticks`; a short budget (the harness tests use a few
  /// hundred milliseconds) still fires promptly and a 60-second budget is
  /// checked every 15 seconds.
  private static let ticksPerBudget = 4

  /// The sidecar. Positional arguments: test pid, ticks per budget, tick
  /// interval in seconds (may be fractional), heartbeat path, open site,
  /// budget label, grace before SIGKILL. POSIX sh only — this runs on macOS
  /// and Linux runners alike.
  private static let sidecarScript = #"""
    pid=$1; ticks=$2; interval=$3; file=$4; origin=$5; budget=$6; grace=$7
    last=''; idle=0
    while :; do
      sleep "$interval"
      kill -0 "$pid" 2>/dev/null || { rm -f "$file"; exit 0; }
      v=$(cat "$file" 2>/dev/null)
      if [ "$v" = disarmed ]; then rm -f "$file"; exit 0; fi
      if [ "$v" = "$last" ]; then idle=$((idle + 1)); else idle=0; last=$v; fi
      if [ "$idle" -ge "$ticks" ]; then
        printf '\nSwiftTUITestSupport: real-terminal journey watchdog fired: the PTY pair opened at %s made no progress for about %s s (test process %s). Sending SIGABRT for a crash report, then SIGKILL, so CI fails now instead of at the job timeout. The wedged journey is the last "Test ... started" line without a result.\n\n' "$origin" "$budget" "$pid" >&2
        kill -CONT "$pid" 2>/dev/null
        kill -ABRT "$pid" 2>/dev/null
        sleep "$grace"
        kill -KILL "$pid" 2>/dev/null
        rm -f "$file"
        exit 0
      fi
    done
    """#

  private let fileDescriptor: Int32
  private let origin: String
  private let heartbeatPath: String
  private let minimumWriteSpacingNanoseconds: UInt64
  private let state: Mutex<State>

  private init(
    fileDescriptor: Int32,
    origin: String,
    heartbeatPath: String,
    minimumWriteSpacingNanoseconds: UInt64
  ) {
    self.fileDescriptor = fileDescriptor
    self.origin = origin
    self.heartbeatPath = heartbeatPath
    self.minimumWriteSpacingNanoseconds = minimumWriteSpacingNanoseconds
    state = Mutex(State(lastWrite: .now()))
  }

  /// Arms a watchdog for `fileDescriptor`, replacing any earlier registration
  /// for a descriptor number the kernel has since recycled.
  fileprivate static func arm(
    fileDescriptor: Int32,
    stallBudget: Duration,
    origin: String
  ) throws -> RealTerminalJourneyWatchdog {
    #if canImport(Darwin) || canImport(Glibc)
      let budgetSeconds = max(0.05, seconds(in: stallBudget))
      let interval = budgetSeconds / Double(ticksPerBudget)
      let grace = min(20.0, max(1.0, budgetSeconds / 2))
      let heartbeatPath = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "swifttui-journey-watchdog-\(getpid())-\(fileDescriptor)-\(UUID().uuidString)"
        )
        .path
      do {
        try writeAtomically("0", to: heartbeatPath)
      } catch {
        throw RealTerminalJourneyError.watchdogUnavailable(
          reason: "could not seed \(heartbeatPath): \(error)"
        )
      }

      let sidecar = Process()
      sidecar.executableURL = URL(fileURLWithPath: "/bin/sh")
      sidecar.arguments = [
        "-c", sidecarScript, "swifttui-journey-watchdog",
        String(getpid()), String(ticksPerBudget), format(interval), heartbeatPath, origin,
        format(budgetSeconds), format(grace),
      ]
      sidecar.standardInput = FileHandle.nullDevice
      do {
        try sidecar.run()
      } catch {
        try? FileManager.default.removeItem(atPath: heartbeatPath)
        throw RealTerminalJourneyError.watchdogUnavailable(reason: "\(error)")
      }

      let watchdog = RealTerminalJourneyWatchdog(
        fileDescriptor: fileDescriptor,
        origin: origin,
        heartbeatPath: heartbeatPath,
        minimumWriteSpacingNanoseconds: UInt64(interval / 4 * 1_000_000_000)
      )
      registry.withLock { $0[fileDescriptor] = watchdog }
      return watchdog
    #else
      throw RealTerminalJourneyError.unsupportedPlatform
    #endif
  }

  /// The armed watchdog for a PTY master descriptor, if any.
  @_spi(Testing) public static func registered(
    for fileDescriptor: Int32
  ) -> RealTerminalJourneyWatchdog? {
    registry.withLock { $0[fileDescriptor] }
  }

  @_spi(Testing) public var isArmed: Bool {
    state.withLock { $0.armed }
  }

  /// Records harness traffic on the pair; rate-limited so a chatty read loop
  /// does not rewrite the heartbeat file on every chunk.
  @_spi(Testing) public func noteActivity() {
    heartbeat(forced: false)
  }

  /// Marks a bounded wait as in flight.
  @_spi(Testing) public func beginWait() {
    heartbeat(forced: true)
  }

  /// Marks the in-flight wait as finished.
  @_spi(Testing) public func endWait() {
    heartbeat(forced: true)
  }

  /// Stops the watchdog; the pair calls this when its master descriptor
  /// closes. The sidecar sees the sentinel within one tick and exits.
  fileprivate func disarm() {
    let wasArmed = state.withLock { state in
      let wasArmed = state.armed
      state.armed = false
      return wasArmed
    }
    guard wasArmed else {
      return
    }
    Self.registry.withLock { registry in
      if registry[fileDescriptor] === self {
        registry[fileDescriptor] = nil
      }
    }
    try? Self.writeAtomically("disarmed", to: heartbeatPath)
  }

  private func heartbeat(forced: Bool) {
    let payload: UInt64? = state.withLock { state in
      guard state.armed else {
        return nil
      }
      let now = DispatchTime.now()
      let sinceLastWrite = now.uptimeNanoseconds &- state.lastWrite.uptimeNanoseconds
      if !forced, sinceLastWrite < minimumWriteSpacingNanoseconds {
        return nil
      }
      state.heartbeat &+= 1
      state.lastWrite = now
      return state.heartbeat
    }
    guard let payload else {
      return
    }
    try? Self.writeAtomically(String(payload), to: heartbeatPath)
  }

  private static func writeAtomically(_ contents: String, to path: String) throws {
    try Data(contents.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  private static func seconds(in duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
  }

  /// Millisecond-precision decimal text for `sleep`; hand-rolled because
  /// `String(format:)` is a variadic (unsafe) call under strict memory safety.
  private static func format(_ seconds: Double) -> String {
    let milliseconds = Int((seconds * 1_000).rounded())
    let fraction = String(milliseconds % 1_000)
    return "\(milliseconds / 1_000)." + String(repeating: "0", count: 3 - fraction.count) + fraction
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
    RealTerminalJourneyWatchdog.registered(for: fileDescriptor)?.noteActivity()

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
  /// DECSTBM vertical scroll region, 0-based inclusive rows. SU/SD move only
  /// the rows inside it; CSI r resets it to the full screen.
  private var scrollRegionTop = 0
  private var scrollRegionBottom: Int

  @_spi(Testing) public init(size: CellSize) {
    self.size = size
    cells = Array(
      repeating: Array(repeating: " ", count: max(1, size.width)),
      count: max(1, size.height)
    )
    scrollRegionBottom = max(0, size.height - 1)
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
    case 0x72:  // r — DECSTBM set/reset scroll region
      guard !privateMode else {
        return
      }
      let top = max(1, values.first ?? 1) - 1
      let bottom = max(1, values.dropFirst().first ?? size.height) - 1
      guard top < bottom else {
        return
      }
      scrollRegionTop = min(max(0, size.height - 1), top)
      scrollRegionBottom = min(max(0, size.height - 1), bottom)
      // DECSTBM homes the cursor on a conforming terminal.
      cursor = .zero
    case 0x53:  // S — SU: region content moves up, blanks at region bottom
      guard !privateMode else {
        return
      }
      scrollRegion(up: max(1, values.first ?? 1))
    case 0x54:  // T — SD: region content moves down, blanks at region top
      guard !privateMode else {
        return
      }
      scrollRegion(up: -max(1, values.first ?? 1))
    case 0x6D, 0x68, 0x6C:  // m, h, l
      return
    default:
      return
    }
  }

  private mutating func scrollRegion(up rows: Int) {
    let top = min(scrollRegionTop, max(0, cells.count - 1))
    let bottom = min(scrollRegionBottom, max(0, cells.count - 1))
    guard rows != 0, top <= bottom else {
      return
    }
    let blankRow = [Character](repeating: " ", count: max(1, size.width))
    let magnitude = min(abs(rows), bottom - top + 1)
    if rows > 0 {
      // SU: row r takes row r + magnitude; vacated rows at the bottom blank.
      for row in top...bottom {
        let source = row + magnitude
        cells[row] = source <= bottom ? cells[source] : blankRow
      }
    } else {
      // SD: row r takes row r - magnitude; vacated rows at the top blank.
      for row in stride(from: bottom, through: top, by: -1) {
        let source = row - magnitude
        cells[row] = source >= top ? cells[source] : blankRow
      }
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
  let watchdog = RealTerminalJourneyWatchdog.registered(for: fileDescriptor)
  watchdog?.beginWait()
  defer { watchdog?.endWait() }
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
    let watchdog = RealTerminalJourneyWatchdog.registered(for: fileDescriptor)

    while collected.count < realTerminalDrainByteBudget {
      try Task.checkCancellation()
      guard !deadlineHasExpired(deadline) else {
        return (collected, false, true)
      }
      let bytesRead = unsafe read(fileDescriptor, &buffer, buffer.count)

      if bytesRead > 0 {
        watchdog?.noteActivity()
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
