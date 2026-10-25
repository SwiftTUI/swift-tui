#if canImport(Darwin)
  import Darwin
  import Dispatch
  import Synchronization
  import Testing

  @testable import SwiftTUIRuntime

  @Suite(.serialized, .timeLimit(.minutes(1)))
  private struct TerminalBorrowedOutputTests {
    @Test(
      "native writes preserve borrowed descriptor policy and bytes",
      arguments: BorrowedOutputKind.allCases, [Int32(0), Int32(1)])
    func connectedOutput(kind: BorrowedOutputKind, initialPolicy: Int32) throws {
      let transport = try BorrowedOutputTransport(kind: kind)
      defer { transport.close() }
      try transport.setPolicy(initialPolicy)
      try transport.primeOutput()
      let duplicate = dup(transport.output)
      try #require(duplicate >= 0)
      defer { _ = Darwin.close(duplicate) }
      let originalFlags = fcntl(transport.output, F_GETFL)

      try POSIXTerminalController().write("borrowed-é", to: duplicate)

      #expect(try transport.read(count: Array("borrowed-é".utf8).count) == Array("borrowed-é".utf8))
      #expect(fcntl(transport.output, F_GETNOSIGPIPE) == initialPolicy)
      #expect(fcntl(duplicate, F_GETNOSIGPIPE) == initialPolicy)
      #expect(fcntl(transport.output, F_GETFL) == originalFlags)
    }

    @Test(
      "failed native writes retain EBADF and the caller's policy", arguments: [Int32(0), Int32(1)])
    func readOnlyOutput(initialPolicy: Int32) throws {
      let transport = try BorrowedOutputTransport(kind: .pipe)
      defer { transport.close() }
      try #require(fcntl(transport.peer, F_SETNOSIGPIPE, initialPolicy) == 0)
      #expect(throws: TerminalHostError.failedToWrite(errno: EBADF)) {
        try POSIXTerminalController().write("x", to: transport.peer)
      }
      #expect(fcntl(transport.peer, F_GETNOSIGPIPE) == initialPolicy)
      #expect(throws: TerminalHostError.failedToWrite(errno: EBADF)) {
        try POSIXTerminalController().write("x", to: -1)
      }
    }

    @Test(
      "closed peers retain their native error without terminating the process",
      arguments: BorrowedOutputKind.allCases, [Int32(0), Int32(1)])
    func closedOutput(kind: BorrowedOutputKind, initialPolicy: Int32) async {
      await #expect(processExitsWith: .success) { [kind, initialPolicy] in
        prepareBorrowedOutputChild()
        let transport = try BorrowedOutputTransport(kind: kind)
        defer { _ = Darwin.close(transport.output) }
        try transport.setPolicy(initialPolicy)
        try #require(Darwin.close(transport.peer) == 0)
        let result = nativeBorrowedOutputWrite(to: transport.output)
        let writeError = errno
        #expect(result == -1)
        switch kind {
        case .pty:
          #expect(writeError == EIO)
        case .pipe, .socket:
          #expect(writeError == EPIPE)
        }
        // The controller treats peer disconnection as an orderly end of output.
        try POSIXTerminalController().write("x", to: transport.output)
        #expect(fcntl(transport.output, F_GETNOSIGPIPE) == initialPolicy)
      }
    }

    @Test(
      "a later plain writer still receives default SIGPIPE",
      arguments: [BorrowedOutputKind.pipe, .socket])
    func laterPlainWriter(kind: BorrowedOutputKind) async {
      await #expect(processExitsWith: .signal(SIGPIPE)) { [kind] in
        prepareBorrowedOutputChild()
        let transport = try BorrowedOutputTransport(kind: kind)
        try transport.setPolicy(0)
        let duplicate = dup(transport.output)
        try #require(duplicate >= 0)
        try POSIXTerminalController().write("x", to: duplicate)
        try #require(try transport.read(count: 1) == [UInt8(ascii: "x")])
        try #require(Darwin.close(transport.peer) == 0)
        let writeError = plainBorrowedOutputWriteAwaitingSIGPIPE(to: transport.output)
        Issue.record("the plain write returned without EPIPE (errno \(writeError))")
      }
    }

    @Test(
      "a later plain writer retains an existing no-SIGPIPE policy",
      arguments: [BorrowedOutputKind.pipe, .socket])
    func laterSuppressedPlainWriter(kind: BorrowedOutputKind) async {
      await #expect(processExitsWith: .success) { [kind] in
        prepareBorrowedOutputChild()
        let transport = try BorrowedOutputTransport(kind: kind)
        defer { _ = Darwin.close(transport.output) }
        try transport.setPolicy(1)
        try POSIXTerminalController().write("x", to: transport.output)
        try #require(try transport.read(count: 1) == [UInt8(ascii: "x")])
        try #require(Darwin.close(transport.peer) == 0)
        let result = plainBorrowedOutputWrite(to: transport.output)
        let writeError = errno
        #expect(result == -1)
        #expect(writeError == EPIPE)
      }
    }

    @Test(
      "concurrent native writers through dup retain bytes and shared policy",
      arguments: [BorrowedOutputKind.pipe, .socket], [Int32(0), Int32(1)])
    func concurrentWriters(kind: BorrowedOutputKind, initialPolicy: Int32) async {
      await #expect(processExitsWith: .success) { [kind, initialPolicy] in
        prepareBorrowedOutputChild()
        let transport = try BorrowedOutputTransport(kind: kind)
        defer { transport.close() }
        try transport.setPolicy(initialPolicy)
        let duplicate = dup(transport.output)
        try #require(duplicate >= 0)
        defer { _ = Darwin.close(duplicate) }
        let group = DispatchGroup()
        for descriptor in [transport.output, duplicate] {
          group.enter()
          DispatchQueue.global().async {
            defer { group.leave() }
            for _ in 0..<32 {
              #expect(nativeBorrowedOutputWrite(to: descriptor) == 1)
            }
          }
        }
        try #require(waitForBorrowedOutputWriters(group) == .success)
        #expect(try transport.read(count: 64) == Array(repeating: UInt8(ascii: "x"), count: 64))
        #expect(fcntl(transport.output, F_GETNOSIGPIPE) == initialPolicy)
        #expect(fcntl(duplicate, F_GETNOSIGPIPE) == initialPolicy)
      }
    }

    @Test(
      "concurrent broken native writers survive default SIGPIPE",
      arguments: [BorrowedOutputKind.pipe, .socket])
    func concurrentBrokenWriters(kind: BorrowedOutputKind) async {
      await #expect(processExitsWith: .success) { [kind] in
        prepareBorrowedOutputChild()
        let transport = try BorrowedOutputTransport(kind: kind)
        defer { _ = Darwin.close(transport.output) }
        try transport.setPolicy(0)
        try #require(Darwin.close(transport.peer) == 0)
        let group = DispatchGroup()
        for _ in 0..<2 {
          group.enter()
          DispatchQueue.global().async {
            defer { group.leave() }
            for _ in 0..<32 {
              let result = nativeBorrowedOutputWrite(to: transport.output)
              let writeError = errno
              #expect(result == -1)
              #expect(writeError == EPIPE)
            }
          }
        }
        try #require(waitForBorrowedOutputWriters(group) == .success)
        #expect(fcntl(transport.output, F_GETNOSIGPIPE) == 0)
      }
    }

    @Test(
      "runtime and diagnostic writers preserve shared output flags and policy",
      arguments: BorrowedOutputKind.allCases, [Int32(0), Int32(1)])
    func concurrentRuntimeAndDiagnosticWriters(kind: BorrowedOutputKind, initialPolicy: Int32) async
    {
      await #expect(processExitsWith: .success) { [kind, initialPolicy] in
        prepareBorrowedOutputChild()
        let transport = try BorrowedOutputTransport(kind: kind)
        defer { transport.close() }
        try transport.setPolicy(initialPolicy)
        try transport.primeOutput()
        let duplicate = dup(transport.output)
        try #require(duplicate >= 0)
        defer { _ = Darwin.close(duplicate) }
        let originalFlags = fcntl(transport.output, F_GETFL)
        let acceptedDiagnostics = Mutex(0)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
          defer { group.leave() }
          for _ in 0..<64 {
            #expect(throws: Never.self) {
              try POSIXTerminalController().write("x", to: transport.output)
            }
          }
        }
        group.enter()
        DispatchQueue.global().async {
          defer { group.leave() }
          for _ in 0..<64 {
            if DebugLogRouter.writeDiagnostic("x", to: duplicate) {
              acceptedDiagnostics.withLock { $0 += 1 }
            } else {
              let writeError = errno
              #expect(writeError == EAGAIN || writeError == EWOULDBLOCK || writeError == EINTR)
            }
          }
        }
        try #require(waitForBorrowedOutputWriters(group) == .success)
        // Diagnostics are best-effort: transient contention may reject a write.
        // Every accepted byte, and every runtime byte, must still arrive.
        let expectedCount = 64 + acceptedDiagnostics.withLock { $0 }
        #expect(
          try transport.read(count: expectedCount)
            == Array(repeating: UInt8(ascii: "x"), count: expectedCount))
        #expect(fcntl(transport.output, F_GETNOSIGPIPE) == initialPolicy)
        #expect(fcntl(duplicate, F_GETNOSIGPIPE) == initialPolicy)
        #expect(fcntl(transport.output, F_GETFL) == originalFlags)
      }
    }

    @Test(
      "runtime and diagnostic writers survive a shared closed peer",
      arguments: [BorrowedOutputKind.pipe, .socket], [Int32(0), Int32(1)])
    func concurrentBrokenRuntimeAndDiagnosticWriters(
      kind: BorrowedOutputKind, initialPolicy: Int32
    ) async {
      await #expect(processExitsWith: .success) { [kind, initialPolicy] in
        prepareBorrowedOutputChild()
        let transport = try BorrowedOutputTransport(kind: kind)
        defer { _ = Darwin.close(transport.output) }
        try transport.setPolicy(initialPolicy)
        let duplicate = dup(transport.output)
        try #require(duplicate >= 0)
        defer { _ = Darwin.close(duplicate) }
        let originalFlags = fcntl(transport.output, F_GETFL)
        try #require(Darwin.close(transport.peer) == 0)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
          defer { group.leave() }
          for _ in 0..<64 {
            #expect(throws: Never.self) {
              try POSIXTerminalController().write("x", to: transport.output)
            }
          }
        }
        group.enter()
        DispatchQueue.global().async {
          defer { group.leave() }
          for _ in 0..<64 {
            #expect(!DebugLogRouter.writeDiagnostic("x", to: duplicate))
          }
        }
        try #require(waitForBorrowedOutputWriters(group) == .success)
        #expect(fcntl(transport.output, F_GETNOSIGPIPE) == initialPolicy)
        #expect(fcntl(duplicate, F_GETNOSIGPIPE) == initialPolicy)
        #expect(fcntl(transport.output, F_GETFL) == originalFlags)
      }
    }

    @Test(
      "full borrowed output does not block independent output",
      arguments: [BorrowedOutputKind.pipe, .socket])
    func independentOutputDuringBackpressure(kind: BorrowedOutputKind) async {
      await #expect(processExitsWith: .success) { [kind] in
        prepareBorrowedOutputChild()
        let stalled = try BorrowedOutputTransport(kind: kind)
        let independent = try BorrowedOutputTransport(kind: .pipe)
        let started = try BorrowedOutputTransport(kind: .pipe)
        defer {
          stalled.close()
          independent.close()
          started.close()
        }
        try stalled.setPolicy(0)
        try independent.setPolicy(0)
        let capacity = try stalled.fill()
        // This handshake exercises real contention; it does not control the
        // scheduler's exact entry into the blocked write.
        let blockedWriter = DispatchGroup()
        blockedWriter.enter()
        DispatchQueue.global().async {
          defer { blockedWriter.leave() }
          #expect(plainBorrowedOutputWrite(to: started.output) == 1)
          #expect(nativeBorrowedOutputWrite(to: stalled.output) == 1)
        }
        try #require(try started.read(count: 1) == [UInt8(ascii: "x")])

        let independentWriter = DispatchGroup()
        independentWriter.enter()
        DispatchQueue.global().async {
          defer { independentWriter.leave() }
          #expect(nativeBorrowedOutputWrite(to: independent.output) == 1)
        }
        let independentCompleted = waitForBorrowedOutputWriters(independentWriter)
        // Drain even after a liveness failure so both writers can finish before the child exits.
        let drained = try stalled.read(count: capacity + 1)
        try #require(waitForBorrowedOutputWriters(blockedWriter) == .success)
        try #require(waitForBorrowedOutputWriters(independentWriter) == .success)
        #expect(independentCompleted == .success)
        #expect(try independent.read(count: 1) == [UInt8(ascii: "x")])
        #expect(drained == Array(repeating: UInt8(ascii: "x"), count: capacity + 1))
        #expect(fcntl(stalled.output, F_GETNOSIGPIPE) == 0)
        #expect(fcntl(independent.output, F_GETNOSIGPIPE) == 0)
      }
    }

    @Test(
      "saturated sockets preserve bounded writes and borrowed descriptor policy",
      arguments: BorrowedSocketWrite.allCases, [Int32(0), Int32(1)])
    func saturatedSocket(operation: BorrowedSocketWrite, initialPolicy: Int32) async {
      await #expect(processExitsWith: .success) { [operation, initialPolicy] in
        prepareBorrowedOutputChild()
        for initiallyNonBlocking in [false, true] {
          let transport = try BorrowedOutputTransport(kind: .socket)
          defer { transport.close() }
          try transport.setPolicy(initialPolicy)
          if initiallyNonBlocking {
            let flags = fcntl(transport.output, F_GETFL)
            try #require(fcntl(transport.output, F_SETFL, flags | O_NONBLOCK) == 0)
          }
          _ = try transport.fill()
          let originalFlags = fcntl(transport.output, F_GETFL)
          let duplicate = dup(transport.output)
          try #require(duplicate >= 0)
          defer { _ = Darwin.close(duplicate) }
          switch operation {
          case .runtime:
            #expect(throws: TerminalHostError.failedToWrite(errno: ETIMEDOUT)) {
              try POSIXTerminalController().write(
                "x", to: duplicate,
                budget: TerminalWriteBudget(deadline: .now + .milliseconds(100)))
            }
          case .diagnostic:
            #expect(!DebugLogRouter.writeDiagnostic("x", to: duplicate))
          case .exitReset:
            let input = try BorrowedOutputTransport(kind: .pty)
            defer { input.close() }
            let controller = POSIXTerminalController()
            let snapshot = try controller.enterRawMode(input: input.output, output: duplicate)
            defer { try? controller.restore(snapshot, input: input.output, output: duplicate) }
            TerminalProcessExitResetAction(
              inputFileDescriptor: input.output, outputFileDescriptor: duplicate,
              savedSnapshot: snapshot, resetBytes: [UInt8(ascii: "x")]
            ).perform()
            var attributes = termios()
            try #require(unsafe tcgetattr(input.output, &attributes) == 0)
            #expect(
              attributes.c_lflag & ~tcflag_t(PENDIN)
                == snapshot.attributes.c_lflag & ~tcflag_t(PENDIN))
            #expect(fcntl(input.output, F_GETFL) == snapshot.inputFileStatusFlags)
          }
          #expect(fcntl(transport.output, F_GETNOSIGPIPE) == initialPolicy)
          #expect(fcntl(duplicate, F_GETNOSIGPIPE) == initialPolicy)
          #expect(fcntl(transport.output, F_GETFL) == originalFlags)
          #expect(fcntl(duplicate, F_GETFL) == originalFlags)
        }
      }
    }

    @MainActor
    @Test(
      "normal shutdown preserves a borrowed PTY's signal policy", arguments: [Int32(0), Int32(1)])
    func shutdown(initialPolicy: Int32) throws {
      let transport = try BorrowedOutputTransport(kind: .pty)
      defer { transport.close() }
      try transport.setPolicy(initialPolicy)
      let host = TerminalHost(
        inputFileDescriptor: transport.output, outputFileDescriptor: transport.output,
        fallbackSize: .init(width: 80, height: 24), controller: POSIXTerminalController(),
        capabilityProfile: .previewUnicode, environment: [:])
      try host.enableRawMode()
      try host.disableRawMode()
      #expect(fcntl(transport.output, F_GETNOSIGPIPE) == initialPolicy)
    }

    @Test(
      "process-exit reset preserves policy, reset bytes and terminal restoration",
      arguments: [Int32(0), Int32(1)])
    func processExitReset(initialPolicy: Int32) throws {
      let input = try BorrowedOutputTransport(kind: .pty)
      let output = try BorrowedOutputTransport(kind: .pipe)
      defer {
        input.close()
        output.close()
      }
      try output.setPolicy(initialPolicy)
      try output.primeOutput()
      let controller = POSIXTerminalController()
      let snapshot = try controller.enterRawMode(input: input.output, output: output.output)
      defer { try? controller.restore(snapshot, input: input.output, output: output.output) }
      let originalFlags = fcntl(output.output, F_GETFL)
      TerminalProcessExitResetAction(
        inputFileDescriptor: input.output, outputFileDescriptor: output.output,
        savedSnapshot: snapshot, resetBytes: Array("reset".utf8)
      ).perform()
      #expect(try output.read(count: 5) == Array("reset".utf8))
      #expect(fcntl(output.output, F_GETNOSIGPIPE) == initialPolicy)
      #expect(fcntl(output.output, F_GETFL) == originalFlags)
      var attributes = termios()
      try #require(unsafe tcgetattr(input.output, &attributes) == 0)
      // Returning to canonical mode sets Darwin's pending-input state bit.
      #expect(
        attributes.c_lflag & ~tcflag_t(PENDIN)
          == snapshot.attributes.c_lflag & ~tcflag_t(PENDIN))
      #expect(fcntl(input.output, F_GETFL) == snapshot.inputFileStatusFlags)
    }
  }

  private struct BorrowedOutputTransport: Sendable {
    let output: Int32
    let peer: Int32

    init(kind: BorrowedOutputKind) throws {
      var descriptors: [Int32] = [-1, -1]
      switch kind {
      case .pipe:
        try #require(unsafe Darwin.pipe(&descriptors) == 0)
        peer = descriptors[0]
        output = descriptors[1]
      case .socket:
        try #require(unsafe socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        peer = descriptors[0]
        output = descriptors[1]
      case .pty:
        var master: Int32 = -1
        var slave: Int32 = -1
        try #require(unsafe openpty(&master, &slave, nil, nil, nil) == 0)
        peer = master
        output = slave
      }
    }

    func primeOutput() throws {
      // Darwin records FWASWRITTEN after the first ordinary write. Prime that
      // kernel-owned bit before comparing the complete F_GETFL value.
      try #require(plainBorrowedOutputWrite(to: output) == 1)
      try #require(try read(count: 1) == [UInt8(ascii: "x")])
    }

    func setPolicy(_ policy: Int32) throws {
      try #require(fcntl(output, F_SETNOSIGPIPE, policy) == 0)
      try #require(fcntl(output, F_GETNOSIGPIPE) == policy)
    }

    func close() {
      _ = Darwin.close(output)
      _ = Darwin.close(peer)
    }

    func fill() throws -> Int {
      let originalFlags = fcntl(output, F_GETFL)
      try #require(originalFlags >= 0)
      try #require(fcntl(output, F_SETFL, originalFlags | O_NONBLOCK) == 0)
      defer { _ = fcntl(output, F_SETFL, originalFlags) }
      var count = 0
      let deadline = ContinuousClock.now + .seconds(5)
      while true {
        try #require(ContinuousClock.now < deadline, "output did not fill")
        let result = plainBorrowedOutputWrite(to: output)
        let writeError = errno
        if result == 1 {
          count += 1
          continue
        }
        if result < 0, writeError == EINTR { continue }
        try #require(result == -1 && writeError == EAGAIN)
        try #require(count > 0)
        return count
      }
    }

    func read(count: Int) throws -> [UInt8] {
      var bytes: [UInt8] = []
      let deadline = ContinuousClock.now + .seconds(5)
      while bytes.count < count {
        try #require(ContinuousClock.now < deadline, "output peer did not receive expected bytes")
        var readiness = pollfd(fd: peer, events: Int16(POLLIN), revents: 0)
        let remaining = ContinuousClock.now.duration(to: deadline)
        let milliseconds = Int32(
          max(
            1,
            min(
              5000,
              remaining.components.seconds * 1000
                + remaining.components.attoseconds / 1_000_000_000_000_000)))
        let ready = unsafe Darwin.poll(&readiness, 1, milliseconds)
        if ready < 0, errno == EINTR { continue }
        try #require(ready > 0, "output peer did not become readable")
        var buffer = [UInt8](repeating: 0, count: count - bytes.count)
        let received = buffer.withUnsafeMutableBytes { rawBuffer in
          unsafe Darwin.read(peer, rawBuffer.baseAddress, rawBuffer.count)
        }
        try #require(received > 0)
        bytes.append(contentsOf: buffer.prefix(received))
      }
      return bytes
    }
  }

  // Swift Testing encodes captured values when launching exit-test processes.
  private enum BorrowedOutputKind: CaseIterable, Codable, Sendable {
    case pipe
    case socket
    case pty
  }

  private enum BorrowedSocketWrite: CaseIterable, Codable, Sendable {
    case runtime
    case diagnostic
    case exitReset
  }

  private func waitForBorrowedOutputWriters(_ group: DispatchGroup) -> DispatchTimeoutResult {
    group.wait(timeout: .now() + 5)
  }

  private func prepareBorrowedOutputChild() {
    _ = signal(SIGPIPE, SIG_DFL)
    var signals = sigset_t()
    _ = unsafe sigemptyset(&signals)
    _ = unsafe sigaddset(&signals, SIGPIPE)
    _ = unsafe pthread_sigmask(SIG_UNBLOCK, &signals, nil)
    // Bound a stuck syscall or writer without sleeping or changing the test runner's signals.
    _ = alarm(10)
  }

  private func nativeBorrowedOutputWrite(to descriptor: Int32) -> Int {
    let bytes = [UInt8(ascii: "x")]
    return bytes.withUnsafeBytes { rawBuffer in
      unsafe terminalPlatformWrite(descriptor, rawBuffer.baseAddress, rawBuffer.count)
    }
  }

  /// Darwin posts a write's SIGPIPE to the process (`psignal`), pending it on
  /// the first eligible non-workqueue thread (xnu `get_signalthread`), which
  /// is usually not the exit-test body's workqueue thread. Returning after
  /// the write let the child exit 0 before that thread took the signal
  /// (STUI-1193). The write therefore runs on its own pthread, which waits in
  /// `pause()` after EPIPE so only the pending signal can end the child.
  /// Returns the write's errno if it did not fail with EPIPE.
  private func plainBorrowedOutputWriteAwaitingSIGPIPE(to descriptor: Int32) -> Int32 {
    var thread: pthread_t?
    let context = unsafe UnsafeMutableRawPointer(bitPattern: Int(descriptor) + 1)
    let created = unsafe pthread_create(
      &thread, nil,
      { context in
        let descriptor = Int32(truncatingIfNeeded: Int(bitPattern: context) - 1)
        let result = plainBorrowedOutputWrite(to: descriptor)
        let writeError = errno
        if result == -1, writeError == EPIPE {
          while true { _ = pause() }
        }
        return unsafe UnsafeMutableRawPointer(bitPattern: Int(writeError) + 1)
      }, context)
    guard created == 0, let thread = unsafe thread else { return created }
    var value: UnsafeMutableRawPointer?
    _ = unsafe pthread_join(thread, &value)
    return Int32(truncatingIfNeeded: Int(bitPattern: value) - 1)
  }

  private func plainBorrowedOutputWrite(to descriptor: Int32) -> Int {
    let bytes = [UInt8(ascii: "x")]
    return bytes.withUnsafeBytes { rawBuffer in
      unsafe Darwin.write(descriptor, rawBuffer.baseAddress, rawBuffer.count)
    }
  }
#endif
