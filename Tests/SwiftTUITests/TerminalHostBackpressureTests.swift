#if canImport(Darwin) || canImport(Glibc)
  import Dispatch
  import Synchronization
  import Testing
  @_spi(Testing) import SwiftTUITestSupport
  @testable import SwiftTUIRuntime
  #if canImport(Darwin)
    import Darwin
  #else
    import Glibc
  #endif

  @MainActor
  @Suite(.serialized)
  struct TerminalHostBackpressureTests {
    @Test(
      "PTY teardown restores attributes and flags with an unread output peer",
      arguments: [false, true])
    func stalledPTY(presentation: Bool) throws {
      let completed = Mutex(false)
      DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
        precondition(completed.withLock { $0 }, "terminal teardown watchdog expired")
      }
      defer { completed.withLock { $0 = true } }
      var master: Int32 = -1
      var slave: Int32 = -1
      #expect(unsafe openpty(&master, &slave, nil, nil, nil) == 0)
      defer {
        _ = close(master)
        _ = close(slave)
      }
      var original = termios()
      #expect(unsafe tcgetattr(slave, &original) == 0)
      let flags = fcntl(slave, F_GETFL)
      let host = TerminalHost(
        inputFileDescriptor: slave, outputFileDescriptor: slave,
        fallbackSize: .init(width: 80, height: 24), controller: POSIXTerminalController(),
        capabilityProfile: .previewUnicode, environment: [:])
      try host.enableRawMode()
      var bytes = [UInt8](repeating: 0x61, count: 4096)
      while unsafe write(slave, &bytes, bytes.count) > 0 {}
      #expect(errno == EAGAIN || errno == EWOULDBLOCK)
      // Linux may move queued bytes into another kernel buffer after EAGAIN.
      // Freeze output flow so even a small reset remains backpressured.
      #expect(tcflow(slave, TCOOFF) == 0)
      if presentation {
        _ = try host.present(RasterSurface(size: .init(width: 1, height: 1), lines: ["x"]))
      }
      let start = ContinuousClock.now
      #expect(throws: TerminalHostError.self) { try host.disableRawMode() }
      #expect(start.duration(to: .now) < .seconds(1))
      var restored = termios()
      #expect(unsafe tcgetattr(slave, &restored) == 0)
      let modeMask = tcflag_t(ICANON | ECHO | ISIG | IEXTEN)
      #expect(restored.c_lflag & modeMask == original.c_lflag & modeMask)
      #expect(restored.c_iflag == original.c_iflag)
      #expect(fcntl(slave, F_GETFL) & O_NONBLOCK == flags & O_NONBLOCK)
      // Idempotent after output timeout; the writer has joined before returning.
      try host.disableRawMode()
    }

    @Test("process-exit restoration does not wait on blocked reset output")
    func stalledExitReset() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      #expect(unsafe openpty(&master, &slave, nil, nil, nil) == 0)
      defer {
        _ = close(master)
        _ = close(slave)
      }
      let snapshot = try POSIXTerminalController().enterRawMode(input: slave, output: slave)
      var bytes = [UInt8](repeating: 0x61, count: 4096)
      while unsafe write(slave, &bytes, bytes.count) > 0 {}
      #expect(tcflow(slave, TCOOFF) == 0)
      let start = ContinuousClock.now
      TerminalProcessExitResetAction(
        inputFileDescriptor: slave, outputFileDescriptor: slave,
        savedSnapshot: snapshot, resetBytes: Array("reset".utf8)
      ).perform()
      #expect(start.duration(to: .now) < .seconds(1))
      var restored = termios()
      #expect(unsafe tcgetattr(slave, &restored) == 0)
      #expect(
        restored.c_lflag & tcflag_t(ICANON | ECHO) == snapshot.attributes.c_lflag
          & tcflag_t(ICANON | ECHO))
      #expect(fcntl(slave, F_GETFL) & O_NONBLOCK == snapshot.inputFileStatusFlags & O_NONBLOCK)
    }

    @Test("retrying failed activation does not release another host's screen ownership")
    func failedActivationOwnership() throws {
      let goodController = RestoreFailureController()
      let badController = RestoreFailureController()
      let good = TerminalHost(
        inputFileDescriptor: 0, outputFileDescriptor: 1,
        fallbackSize: .init(width: 80, height: 24), controller: goodController,
        capabilityProfile: .previewUnicode, environment: [:])
      let bad = TerminalHost(
        inputFileDescriptor: 0, outputFileDescriptor: 1,
        fallbackSize: .init(width: 80, height: 24), controller: badController,
        capabilityProfile: .previewUnicode, environment: [:])
      try good.enableRawMode()
      defer { try? good.disableRawMode() }
      badController.failures.withLock { $0 = (true, true) }
      #expect(throws: TerminalHostError.self) { try bad.enableRawMode() }
      badController.failures.withLock { $0 = (false, false) }
      try bad.disableRawMode()
      #expect(TerminalScreenOwnership.isScreenOwned)
    }

    @Test("write failure restores modes; failed restoration can be retried")
    func failedOutputAndRestore() throws {
      let controller = RestoreFailureController()
      let host = TerminalHost(
        inputFileDescriptor: 0, outputFileDescriptor: 1,
        fallbackSize: .init(width: 80, height: 24), controller: controller,
        capabilityProfile: .previewUnicode, environment: [:])
      try host.enableRawMode()
      controller.failures.withLock { $0 = (true, true) }
      #expect(throws: TerminalHostError.self) { try host.disableRawMode() }
      #expect(controller.restores.withLock { $0 } == 1)
      controller.failures.withLock { $0 = (false, false) }
      try host.disableRawMode()
      #expect(controller.restores.withLock { $0 } == 2)
      try host.disableRawMode()
      #expect(controller.restores.withLock { $0 } == 2)
    }
  }

  private final class RestoreFailureController: TerminalControlling {
    let failures = Mutex((false, false))
    let restores = Mutex(0)
    func isATTY(_: Int32) -> Bool { true }
    func windowSize(of _: Int32) throws -> CellSize { .init(width: 80, height: 24) }
    func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot { .init() }
    func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {
      restores.withLock { $0 += 1 }
      if failures.withLock({ $0.1 }) { throw TerminalHostError.failedToSetAttributes(errno: EIO) }
    }
    func write(_: String, to _: Int32) throws {
      if failures.withLock({ $0.0 }) { throw TerminalHostError.failedToWrite(errno: EIO) }
    }
    func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] { [] }
  }
#endif
