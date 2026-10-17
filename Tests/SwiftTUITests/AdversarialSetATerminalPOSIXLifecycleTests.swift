#if canImport(Darwin) || canImport(Glibc)
  import Foundation
  import Testing
  @_spi(Testing) import SwiftTUITestSupport
  @testable import SwiftTUIRuntime

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Android)
    import Android
  #elseif canImport(Musl)
    import Musl
  #endif

  @Suite(.serialized, .timeLimit(.minutes(1)))
  struct AdversarialSetATerminalPOSIXLifecycleTests {
    @Test func setA1076RawReadThresholdsUseThePlatformsActualControlCharacterIndices() throws {
      // Hypothesis: hard-coded c_cc tuple offsets configure unrelated controls on a different POSIX platform.
      try withPair { pair in
        var before = try attributes(pair.slave)
        withUnsafeMutableBytes(of: &before.c_cc) { bytes in
          unsafe bytes[Int(VMIN)] = 7
          unsafe bytes[Int(VTIME)] = 9
        }
        try #require(unsafe tcsetattr(pair.slave, TCSANOW, &before) == 0)
        let controller = POSIXTerminalController()
        let snapshot = try controller.enterRawMode(input: pair.slave, output: pair.slave)
        defer { try? controller.restore(snapshot, input: pair.slave, output: pair.slave) }
        let raw = try attributes(pair.slave)
        let controls = withUnsafeBytes(of: raw.c_cc) { unsafe Array($0) }
        #expect(controls[Int(VMIN)] == 1)
        #expect(controls[Int(VTIME)] == 0)
        #expect(raw.c_lflag & tcflag_t(ICANON | ECHO | ISIG | IEXTEN) == 0)
      }
    }

    @Test func setA1077RestorationPreservesAuthoredControlCharactersAndPreexistingNonblocking()
      throws
    {
      // Hypothesis: restoration reconstructs defaults instead of restoring the complete captured mode and status flags.
      try withPair { pair in
        var original = try attributes(pair.slave)
        withUnsafeMutableBytes(of: &original.c_cc) { bytes in
          unsafe bytes[Int(VERASE)] = 0x08
          unsafe bytes[Int(VINTR)] = 0x1D
          unsafe bytes[Int(VEOF)] = 0x05
        }
        try #require(unsafe tcsetattr(pair.slave, TCSANOW, &original) == 0)
        try #require(fcntl(pair.slave, F_SETFL, fcntl(pair.slave, F_GETFL) | O_NONBLOCK) == 0)
        let flags = fcntl(pair.slave, F_GETFL)
        let controller = POSIXTerminalController()
        let snapshot = try controller.enterRawMode(input: pair.slave, output: pair.slave)
        try controller.restore(snapshot, input: pair.slave, output: pair.slave)
        #expect(signature(try attributes(pair.slave)) == signature(original))
        #expect(fcntl(pair.slave, F_GETFL) == flags)
      }
    }

    @Test func setA1078SplitInputAndOutputTerminalsKeepIndependentModes() throws {
      // Hypothesis: entering raw input also mutates the separately supplied output terminal's attributes or flags.
      try withPair { input in
        try withPair { output in
          let outputMode = signature(try attributes(output.slave))
          let outputFlags = fcntl(output.slave, F_GETFL)
          let controller = POSIXTerminalController()
          let snapshot = try controller.enterRawMode(input: input.slave, output: output.slave)
          defer { try? controller.restore(snapshot, input: input.slave, output: output.slave) }
          #expect(try attributes(input.slave).c_lflag & tcflag_t(ICANON) == 0)
          #expect(signature(try attributes(output.slave)) == outputMode)
          #expect(fcntl(output.slave, F_GETFL) == outputFlags)
        }
      }
    }

    @Test func setA1079NestedRawSnapshotsRestoreTheImmediatePredecessor() throws {
      // Hypothesis: snapshots share mutable storage, so a nested activation overwrites the outer restore target.
      try withPair { pair in
        let controller = POSIXTerminalController()
        let original = signature(try attributes(pair.slave))
        let outer = try controller.enterRawMode(input: pair.slave, output: pair.slave)
        let outerRaw = signature(try attributes(pair.slave))
        let inner = try controller.enterRawMode(input: pair.slave, output: pair.slave)
        try controller.restore(inner, input: pair.slave, output: pair.slave)
        #expect(signature(try attributes(pair.slave)) == outerRaw)
        #expect(fcntl(pair.slave, F_GETFL) & O_NONBLOCK != 0)
        try controller.restore(outer, input: pair.slave, output: pair.slave)
        #expect(signature(try attributes(pair.slave)) == original)
      }
    }

    @Test func setA1080FailedNonTTYActivationPreservesPendingInputAndDescriptorFlags() throws {
      // Hypothesis: raw-mode failure changes a borrowed pipe's flags or consumes bytes before rejecting its mode.
      let pipe = try makePipe()
      defer {
        _ = close(pipe.read)
        _ = close(pipe.write)
      }
      try writeAllBytes(Array("pending".utf8), to: pipe.write)
      let flags = fcntl(pipe.read, F_GETFL)
      #expect(throws: TerminalHostError.self) {
        _ = try POSIXTerminalController().enterRawMode(input: pipe.read, output: pipe.write)
      }
      #expect(fcntl(pipe.read, F_GETFL) == flags)
      #expect(try readExactly(pipe.read, count: 7) == Array("pending".utf8))
    }

    @Test func setA1081RawTerminalInputPreservesSignalFlowControlAndNULBytes() throws {
      // Hypothesis: a remaining termios transformation consumes signal/flow-control bytes or changes carriage return.
      try withPair { pair in
        let controller = POSIXTerminalController()
        let snapshot = try controller.enterRawMode(input: pair.slave, output: pair.slave)
        defer { try? controller.restore(snapshot, input: pair.slave, output: pair.slave) }
        let bytes: [UInt8] = [0, 3, 4, 13, 17, 19, 26, 127, 0xC3, 0xA9]
        try writeAllBytes(bytes, to: pair.master)
        #expect(try readExactly(pair.slave, count: bytes.count) == bytes)
      }
    }

    @Test func setA1082RawOutputDoesNotApplyCanonicalNewlineExpansion() throws {
      // Hypothesis: raw input setup leaves OPOST enabled and changes the renderer's exact output byte stream.
      try withPair { pair in
        let controller = POSIXTerminalController()
        let snapshot = try controller.enterRawMode(input: pair.slave, output: pair.slave)
        defer { try? controller.restore(snapshot, input: pair.slave, output: pair.slave) }
        let bytes = Array("a\nb\r\nc\0".utf8)
        try controller.write(String(decoding: bytes, as: UTF8.self), to: pair.slave)
        #expect(try readExactly(pair.master, count: bytes.count) == bytes)
      }
    }

    @Test func setA1083RestorationDoesNotDiscardAlreadyQueuedTerminalInput() throws {
      // Hypothesis: restoration uses a flushing termios operation and loses a complete input line already in the kernel.
      try withPair { pair in
        let controller = POSIXTerminalController()
        let snapshot = try controller.enterRawMode(input: pair.slave, output: pair.slave)
        let bytes = Array("queued line\n".utf8)
        try writeAllBytes(bytes, to: pair.master)
        var ready = pollfd(fd: pair.slave, events: Int16(POLLIN), revents: 0)
        try #require(unsafe poll(&ready, 1, 1000) == 1)
        try controller.restore(snapshot, input: pair.slave, output: pair.slave)
        #expect(try readExactly(pair.slave, count: bytes.count) == bytes)
      }
    }

    @Test func setA1084WindowQueriesObserveRepeatedKernelResizesWithoutChangingModes() throws {
      // Hypothesis: a raw-mode controller caches the initial kernel dimensions or modifies mode state while refreshing them.
      try withPair { pair in
        let controller = POSIXTerminalController()
        let snapshot = try controller.enterRawMode(input: pair.slave, output: pair.slave)
        defer { try? controller.restore(snapshot, input: pair.slave, output: pair.slave) }
        let mode = signature(try attributes(pair.slave))
        for (width, height) in [(17, 9), (110, 31), (17, 9)] {
          var size = winsize(
            ws_row: UInt16(height), ws_col: UInt16(width), ws_xpixel: 0, ws_ypixel: 0)
          try #require(unsafe ioctl(pair.master, UInt(TIOCSWINSZ), &size) == 0)
          #expect(try controller.windowSize(of: pair.slave) == .init(width: width, height: height))
          #expect(signature(try attributes(pair.slave)) == mode)
        }
      }
    }

    @Test func setA1085IncompletePixelMetricsNeverReuseAnEarlierCompleteMeasurement() throws {
      // Hypothesis: losing one physical dimension leaves stale cell metrics advertised after a terminal resize.
      try withPair { pair in
        let controller = POSIXTerminalController()
        var size = winsize(ws_row: 10, ws_col: 20, ws_xpixel: 160, ws_ypixel: 160)
        try #require(unsafe ioctl(pair.master, UInt(TIOCSWINSZ), &size) == 0)
        #expect(try controller.cellPixelSize(of: pair.slave) == .init(width: 8, height: 16))
        size.ws_ypixel = 0
        try #require(unsafe ioctl(pair.master, UInt(TIOCSWINSZ), &size) == 0)
        #expect(try controller.cellPixelSize(of: pair.slave) == nil)
        size.ws_ypixel = 240
        try #require(unsafe ioctl(pair.master, UInt(TIOCSWINSZ), &size) == 0)
        #expect(try controller.cellPixelSize(of: pair.slave) == .init(width: 8, height: 24))
      }
    }

    @Test func setA1086FailedLowLevelWriteRestoresTheBorrowedDescriptorsStatusFlags() throws {
      // Hypothesis: a write error leaves temporary O_NONBLOCK installed on a caller-owned descriptor.
      let descriptor = unsafe open("/dev/null", O_RDONLY)
      try #require(descriptor >= 0)
      defer { _ = close(descriptor) }
      let flags = fcntl(descriptor, F_GETFL)
      #expect(throws: TerminalHostError.failedToWrite(errno: EBADF)) {
        try POSIXTerminalController().write("not writable", to: descriptor)
      }
      #expect(fcntl(descriptor, F_GETFL) == flags)
      #expect(fcntl(descriptor, F_GETFD) >= 0)
    }

    @Test func setA1087ExpiredWriteBudgetCannotEmitEvenItsFirstChunk() throws {
      // Hypothesis: the shutdown deadline is checked only after a first write has escaped to the terminal.
      let pipe = try makePipe()
      defer {
        _ = close(pipe.read)
        _ = close(pipe.write)
      }
      let flags = fcntl(pipe.write, F_GETFL)
      #expect(throws: TerminalHostError.failedToWrite(errno: ETIMEDOUT)) {
        try POSIXTerminalController().write(
          "must not escape", to: pipe.write,
          budget: TerminalWriteBudget(deadline: .now - .seconds(1)))
      }
      var readiness = pollfd(fd: pipe.read, events: Int16(POLLIN), revents: 0)
      #expect(unsafe poll(&readiness, 1, 0) == 0)
      #expect(fcntl(pipe.write, F_GETFL) == flags)
    }

    @Test func setA1088MultiChunkWritesPreserveUTF8AndNULAcrossBackpressure() async throws {
      // Hypothesis: short writes advance a String index instead of the byte offset, duplicating or truncating multibyte/NUL content.
      let pipe = try makePipe()
      defer {
        _ = close(pipe.read)
        _ = close(pipe.write)
      }
      let text = String(repeating: "x雪\0👩‍💻", count: 8192)
      let expected = Array(text.utf8)
      let reader = Task.detached { try readExactly(pipe.read, count: expected.count) }
      do {
        try POSIXTerminalController().write(
          text, to: pipe.write,
          budget: TerminalWriteBudget(deadline: .now + .seconds(3)))
      } catch {
        _ = try? await reader.value
        throw error
      }
      let received = try await reader.value
      let matches = received == expected
      #expect(matches, "received \(received.count) bytes; expected \(expected.count)")
    }

    @Test func setA1089DisconnectedOutputCannotTerminateTheProcessWithSIGPIPE() async {
      // Hypothesis: the clean-EPIPE branch is unreachable because writing the disconnected pipe first raises SIGPIPE.
      do {
        await #expect(processExitsWith: .success) {
          _ = signal(SIGPIPE, SIG_DFL)
          var descriptors: [Int32] = [-1, -1]
          try #require(unsafe pipe(&descriptors) == 0)
          _ = close(descriptors[0])
          defer { _ = close(descriptors[1]) }
          let input = unsafe open("/dev/null", O_RDONLY)
          try #require(input >= 0)
          defer { _ = close(input) }
          let output = descriptors[1]
          try await MainActor.run {
            let host = TerminalHost(
              inputFileDescriptor: input, outputFileDescriptor: output,
              capabilityProfile: .previewUnicode, environment: [:])
            try host.write("peer gone")
          }
        }
      }
    }

    @Test func disconnectedWritePreservesCallerSignalMaskAndPendingSignal() async {
      await #expect(processExitsWith: .success) {
        // Darwin workqueue threads reject pthread_kill with ENOTSUP. Use a
        // dedicated pthread-backed Thread for this pending-signal contract.
        await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
          Thread {
            defer { finished.resume() }
            do {
              _ = signal(SIGPIPE, SIG_DFL)
              var blocked = sigset_t()
              var original = sigset_t()
              _ = unsafe sigemptyset(&blocked)
              _ = unsafe sigaddset(&blocked, SIGPIPE)
              try #require(unsafe pthread_sigmask(SIG_BLOCK, &blocked, &original) == 0)
              defer { _ = unsafe pthread_sigmask(SIG_SETMASK, &original, nil) }
              // A caller-owned pending signal must survive our suppression scope.
              let signalResult = unsafe pthread_kill(pthread_self(), SIGPIPE)
              try #require(signalResult == 0, "pthread_kill returned \(signalResult)")
              var descriptors: [Int32] = [-1, -1]
              try #require(unsafe pipe(&descriptors) == 0)
              _ = close(descriptors[0])
              defer { _ = close(descriptors[1]) }
              try POSIXTerminalController().write("closed", to: descriptors[1])
              var current = sigset_t()
              _ = unsafe pthread_sigmask(SIG_BLOCK, nil, &current)
              #expect(unsafe sigismember(&current, SIGPIPE) == 1)
              _ = unsafe sigpending(&current)
              #expect(unsafe sigismember(&current, SIGPIPE) == 1)
              var received: Int32 = 0
              try #require(unsafe sigwait(&blocked, &received) == 0)
              #expect(received == SIGPIPE)
            } catch { Issue.record(error) }
          }.start()
        }
      }
    }

    @Test func setA1090ExitCleanupRestoresInputEvenWhenItsOutputDescriptorIsInvalid() throws {
      // Hypothesis: a failed reset-output setup returns before restoring a still-live input terminal's mode.
      try withPair { pair in
        let original = signature(try attributes(pair.slave))
        let flags = fcntl(pair.slave, F_GETFL)
        let snapshot = try POSIXTerminalController().enterRawMode(
          input: pair.slave, output: pair.slave)
        TerminalProcessExitResetAction(
          inputFileDescriptor: pair.slave, outputFileDescriptor: -1,
          savedSnapshot: snapshot, resetBytes: Array("reset".utf8)
        ).perform()
        #expect(signature(try attributes(pair.slave)) == original)
        #expect(fcntl(pair.slave, F_GETFL) == flags)
      }
    }

    private func withPair<T>(_ body: (RealTerminalPTYPair) throws -> T) throws -> T {
      let pair = try RealTerminalPTYPair.open(size: .init(width: 80, height: 24), stallBudget: nil)
      defer {
        pair.closeMaster()
        pair.closeSlave()
      }
      return try body(pair)
    }

    private func attributes(_ fd: Int32) throws -> termios {
      var result = termios()
      try #require(unsafe tcgetattr(fd, &result) == 0)
      return result
    }

    private func signature(_ value: termios) -> [UInt64] {
      // Darwin sets PENDIN when returning to canonical mode, even with no queued
      // input. It is kernel state, not an authored mode that restore can preserve.
      let localFlags: tcflag_t
      #if canImport(Darwin)
        localFlags = value.c_lflag & ~tcflag_t(PENDIN)
      #else
        localFlags = value.c_lflag
      #endif
      return [
        UInt64(value.c_iflag), UInt64(value.c_oflag), UInt64(value.c_cflag), UInt64(localFlags),
      ]
        + withUnsafeBytes(of: value.c_cc) { unsafe $0.map(UInt64.init) }
    }

    private func makePipe() throws -> (read: Int32, write: Int32) {
      var descriptors: [Int32] = [-1, -1]
      try #require(unsafe pipe(&descriptors) == 0)
      return (descriptors[0], descriptors[1])
    }
  }

  private enum SetAPOSIXReadError: Error {
    case timedOut, closed
    case failed(Int32)
  }

  private func readExactly(_ descriptor: Int32, count: Int) throws -> [UInt8] {
    let deadline = ContinuousClock.now + .seconds(4)
    var result: [UInt8] = []
    var storage = [UInt8](repeating: 0, count: 4096)
    while result.count < count {
      guard ContinuousClock.now < deadline else { throw SetAPOSIXReadError.timedOut }
      var readiness = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
      let ready = unsafe poll(&readiness, 1, 20)
      if ready == 0 || (ready < 0 && errno == EINTR) { continue }
      if ready < 0 { throw SetAPOSIXReadError.failed(errno) }
      let readCount = unsafe read(descriptor, &storage, min(storage.count, count - result.count))
      if readCount > 0 {
        result.append(contentsOf: storage.prefix(readCount))
      } else if readCount == 0 {
        throw SetAPOSIXReadError.closed
      } else if errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK {
        throw SetAPOSIXReadError.failed(errno)
      }
    }
    return result
  }
#endif
