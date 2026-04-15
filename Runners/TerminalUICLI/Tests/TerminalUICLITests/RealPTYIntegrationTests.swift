import Synchronization
@_spi(Runners) import TerminalUI
import Testing

@testable import TerminalUICLI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite("Real PTY integration", .serialized)
struct RealPTYIntegrationTests {
  @Test(
    "Scene sessions render and handle character input across a real pty",
    .timeLimit(.minutes(1))
  )
  func sceneSessionRendersAndHandlesCharacterInput() async throws {
    let terminalSize = Size(width: 32, height: 6)
    let pty = try PtyPair()
    var slaveFD = sceneOpen(pty.slavePath, O_RDWR | O_NOCTTY)

    #expect(slaveFD >= 0)

    try configureRawMode(on: slaveFD)
    try configureWindowSize(
      of: slaveFD,
      to: terminalSize
    )

    let recorder = PTYKeyRecorder()
    let task = Task { @MainActor in
      try await runRealPTYSceneSession(
        scene: WindowGroup("PTY Probe", id: WindowIdentifier("pty-probe")) {
          PTYProbeView(recorder: recorder)
        },
        sessionName: "RealPTYIntegrationTests.PTYProbe",
        masterFD: pty.masterFD,
        fallbackSize: terminalSize
      )
    }

    defer {
      task.cancel()
      if slaveFD >= 0 {
        sceneClose(slaveFD)
      }
      pty.close()
    }

    let bootOutput = try await readFromPTY(
      fileDescriptor: slaveFD,
      until: { output in
        output.contains("\u{001B}[?1049h") && output.contains("PTY ready")
      }
    )

    #expect(bootOutput.contains("\u{001B}[?1049h"))
    #expect(bootOutput.contains("PTY ready"))
    #expect(bootOutput.contains("Last key: none"))

    try writeAll("x", to: slaveFD)

    let updatedOutput = try await readFromPTY(
      fileDescriptor: slaveFD,
      until: { output in
        output.contains("\u{001B}[2;11H") && output.contains("x")
      }
    )

    #expect(updatedOutput.contains("\u{001B}[2;11H"))
    #expect(updatedOutput.contains("x"))

    try await waitUntil("pty key recorder updates") {
      recorder.lastCharacter == "x"
    }

    sceneClose(slaveFD)
    slaveFD = -1

    let result = try await task.value
    #expect(result.exitReason == .inputEnded)
    #expect(result.renderedFrames >= 2)
    #expect(recorder.recordedKeys == [KeyPress(.character("x"))])
  }
}

private final class PTYKeyRecorder: Sendable {
  private let keys = Mutex<[KeyPress]>([])
  private let last = Mutex<String>("none")

  var recordedKeys: [KeyPress] {
    keys.withLock { $0 }
  }

  var lastCharacter: String {
    last.withLock { $0 }
  }

  func record(_ keyPress: KeyPress, character: String) {
    keys.withLock { recorded in
      recorded.append(keyPress)
    }
    last.withLock { current in
      current = character
    }
  }
}

private struct PTYProbeView: View {
  let recorder: PTYKeyRecorder

  @State private var lastKey = "none"

  var body: some View {
    VStack(alignment: .leading) {
      Text("PTY ready")
      Text("Last key: \(lastKey)")
    }
    .onKeyPress { keyPress in
      guard keyPress.modifiers.isEmpty else {
        return .ignored
      }
      guard case .character(let character) = keyPress.key else {
        return .ignored
      }

      let value = String(character)
      lastKey = value
      recorder.record(keyPress, character: value)
      return .handled
    }
  }
}

@MainActor
private func runRealPTYSceneSession<S: Scene>(
  scene: S,
  sessionName: String,
  masterFD: Int32,
  fallbackSize: Size
) async throws -> RunLoopResult<TerminalUISceneSessionState> {
  let selections = collectWindowSceneSelections(from: scene)
  guard selections.count == 1, let selection = selections.first else {
    throw RealPTYIntegrationError.invalidSceneCount(selections.count)
  }

  return try await selection.run(
    sessionName: sessionName,
    resources: SceneSessionResources(
      terminalHost: TerminalHost(
        inputFileDescriptor: masterFD,
        outputFileDescriptor: masterFD,
        fallbackSize: fallbackSize
      ),
      terminalInputReader: InputReader(fileDescriptor: masterFD)
    ),
    stateContainer: StateContainer(
      initialState: TerminalUISceneSessionState(),
      invalidationIdentities: [selection.rootIdentity]
    ),
    focusTracker: FocusTracker(
      invalidationIdentities: [selection.rootIdentity]
    )
  )
}

private func configureWindowSize(
  of fileDescriptor: Int32,
  to size: Size
) throws {
  var windowSize = winsize(
    ws_row: UInt16(size.height),
    ws_col: UInt16(size.width),
    ws_xpixel: 0,
    ws_ypixel: 0
  )

  guard unsafe ioctl(fileDescriptor, UInt(TIOCSWINSZ), &windowSize) == 0 else {
    throw RealPTYIntegrationError.failedToSetWindowSize(errno)
  }
}

private func configureRawMode(on fileDescriptor: Int32) throws {
  var attributes = termios()
  guard unsafe tcgetattr(fileDescriptor, &attributes) == 0 else {
    throw RealPTYIntegrationError.failedToReadAttributes(errno)
  }

  unsafe cfmakeraw(&attributes)

  guard unsafe tcsetattr(fileDescriptor, TCSAFLUSH, &attributes) == 0 else {
    throw RealPTYIntegrationError.failedToSetAttributes(errno)
  }
}

private func writeAll(
  _ string: String,
  to fileDescriptor: Int32
) throws {
  let bytes = Array(string.utf8)

  try unsafe bytes.withUnsafeBytes { rawBuffer in
    guard let baseAddress = rawBuffer.baseAddress else {
      return
    }

    var bytesWritten = 0
    while bytesWritten < bytes.count {
      let pointer = unsafe baseAddress.advanced(by: bytesWritten)
      let result = unsafe sceneWrite(fileDescriptor, pointer, bytes.count - bytesWritten)
      if result > 0 {
        bytesWritten += result
        continue
      }
      if result < 0, errno == EINTR {
        continue
      }

      throw RealPTYIntegrationError.failedToWrite(errno)
    }
  }
}

private func readFromPTY(
  fileDescriptor: Int32,
  timeoutNanoseconds: UInt64 = 2_000_000_000,
  until condition: @escaping (String) -> Bool
) async throws -> String {
  let clock = ContinuousClock()
  let start = clock.now
  var bytes: [UInt8] = []

  while true {
    let output = String(decoding: bytes, as: UTF8.self)
    if condition(output) {
      return output
    }

    if start.duration(to: clock.now) >= .nanoseconds(Int64(timeoutNanoseconds)) {
      throw RealPTYIntegrationError.readTimedOut(output)
    }

    var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
    let ready = unsafe poll(&descriptor, 1, 50)
    if ready == 0 {
      continue
    }
    if ready < 0 {
      if errno == EINTR {
        continue
      }
      throw RealPTYIntegrationError.failedToRead(errno)
    }

    var buffer = [UInt8](repeating: 0, count: 4096)
    let bytesRead = unsafe sceneRead(fileDescriptor, &buffer, buffer.count)
    if bytesRead > 0 {
      bytes.append(contentsOf: buffer.prefix(bytesRead))
      continue
    }
    if bytesRead == 0 {
      throw RealPTYIntegrationError.unexpectedEOF(String(decoding: bytes, as: UTF8.self))
    }
    if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
      continue
    }

    throw RealPTYIntegrationError.failedToRead(errno)
  }
}

private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 2_000_000_000,
  pollNanoseconds: UInt64 = 20_000_000,
  condition: @escaping () -> Bool
) async throws {
  let clock = ContinuousClock()
  let start = clock.now

  while !condition() {
    if start.duration(to: clock.now) >= .nanoseconds(Int64(timeoutNanoseconds)) {
      throw RealPTYIntegrationError.conditionTimedOut(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private enum RealPTYIntegrationError: Error, CustomStringConvertible {
  case invalidSceneCount(Int)
  case failedToSetWindowSize(Int32)
  case failedToReadAttributes(Int32)
  case failedToSetAttributes(Int32)
  case failedToWrite(Int32)
  case failedToRead(Int32)
  case readTimedOut(String)
  case unexpectedEOF(String)
  case conditionTimedOut(String)

  var description: String {
    switch self {
    case .invalidSceneCount(let count):
      "Expected exactly one scene, but received \(count)."
    case .failedToSetWindowSize(let err):
      "Failed to set pty window size: \(unsafe String(cString: strerror(err)))"
    case .failedToReadAttributes(let err):
      "Failed to read pty attributes: \(unsafe String(cString: strerror(err)))"
    case .failedToSetAttributes(let err):
      "Failed to set pty attributes: \(unsafe String(cString: strerror(err)))"
    case .failedToWrite(let err):
      "Failed to write to pty: \(unsafe String(cString: strerror(err)))"
    case .failedToRead(let err):
      "Failed to read from pty: \(unsafe String(cString: strerror(err)))"
    case .readTimedOut(let output):
      "Timed out waiting for pty output. Collected output: \(output.debugDescription)"
    case .unexpectedEOF(let output):
      "Reached EOF before expected pty output arrived. Collected output: \(output.debugDescription)"
    case .conditionTimedOut(let label):
      "Timed out waiting for \(label)."
    }
  }
}
