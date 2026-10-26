#if canImport(Darwin) || canImport(Glibc)
  import Foundation
  @_spi(Testing) import SwiftTUITestSupport
  import Synchronization
  import Testing

  @testable import SwiftTUICore
  @_spi(Runners) @testable import SwiftTUIRuntime
  @testable import SwiftTUIViews

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  // Campaign two F3 pass 2 (setE129–setE135): raw-mode entry failure. The run
  // loop's session cleanup is installed before raw-mode entry, and a surface
  // whose entry failed rolled itself back (STUI-1182, STUI-1121). These cases
  // drive the real TerminalHost under RunLoop with a recording controller, and
  // the real POSIX controller on a PTY inside disposable exit-test children.

  @MainActor
  @Suite("Campaign F3 pass 2 raw-mode entry failure", .serialized)
  struct AdversarialSetERawEntryTests {
    static let newFour =
      "NEW-4: a raw-mode entry whose rollback reset write also fails leaves TerminalHost reporting raw mode, so a retry or a later RunLoop session performs no raw-mode entry; the entry defer deactivates the session only after a successful reset write (TerminalHost.swift:259) and enableRawMode returns early while isEnabled (:213); contract: STUI-1182 fix (a failed entry rolled itself back), pass-1 brief 06 (a later enable performs a fresh entry); adjacent STUI-1182, STUI-1121"

    @Test(arguments: [129, 130, 131, 132, 135])
    func rawEntryFailure(id: Int) async throws {
      let sink = try FileHandle(forUpdating: URL(fileURLWithPath: "/dev/null"))
      let controller = SetERawController()
      let host = TerminalHost(
        inputFileDescriptor: sink.fileDescriptor, outputFileDescriptor: sink.fileDescriptor,
        fallbackSize: .init(width: 20, height: 4), controller: controller,
        capabilityProfile: .trueColor, environment: [:])
      defer {
        controller.clearErrors()
        do { try host.disableRawMode() } catch { Issue.record("fixture cleanup failed: \(error)") }
        do { try sink.close() } catch { Issue.record("fixture descriptor close failed: \(error)") }
      }
      host.readerMode = id == 135
      let ownedBefore = DiagnosticScreenOwnership.isScreenOwned
      switch id {
      case 129: controller.state.withLock { $0.enterErrors = 1 }
      case 135: controller.failWrite(TerminalHostEscapeSequences.showCursor)
      default:
        controller.failWrite(TerminalHostEscapeSequences.enterAlternateScreen)
        if id == 131 || id == 132 {
          // The rollback's reset bytes fail too: a dead output descriptor.
          controller.failWrite(TerminalHostEscapeSequences.exitAlternateScreen)
        }
      }
      if id == 131 {
        #expect(throws: SetERawError.write) { try host.enableRawMode() }
        #expect(controller.snapshot.enters == 1)
        #expect(controller.snapshot.restores == 1)
        controller.clearErrors()
        try host.enableRawMode()
        setEKnown(Self.newFour) {
          #expect(controller.snapshot.enters == 2, "the retry performed no raw-mode entry")
        }
        return
      }
      let first = try await SetERawSession.run(host: host, id: id)
      #expect(first.threw == (id == 129 ? SetERawError.entry : SetERawError.write))
      #expect(!first.sessionActiveAfter)
      #expect(!first.acceptsTerminationAfter)
      #expect(first.tasksStarted == 0)
      #expect(controller.snapshot.enters == 1)
      #expect(controller.snapshot.restores == (id == 129 ? 0 : 1))
      #expect(DiagnosticScreenOwnership.isScreenOwned == ownedBefore)
      if id == 129 {
        #expect(controller.snapshot.writes.isEmpty, "\(controller.snapshot.writes)")
      } else {
        // Nothing follows the host's own rollback reset: the run loop does not
        // ask a surface to leave a mode it never entered.
        let writes = controller.snapshot.writes
        let resetIndex = try #require(
          writes.lastIndex {
            $0.contains(TerminalHostEscapeSequences.showCursor)
              && $0.contains(TerminalHostEscapeSequences.disableBracketedPaste)
          })
        #expect(resetIndex == writes.count - 1, "\(writes)")
      }
      if id == 132 {
        controller.clearErrors()
        let second = try await SetERawSession.run(host: host, id: id)
        #expect(second.threw == nil)
        setEKnown(Self.newFour) {
          #expect(controller.snapshot.enters == 2, "the second session never entered raw mode")
        }
        #expect(controller.snapshot.restores == 2)
      }
    }

    // Real POSIX controller on a PTY in a disposable child with a lowered
    // descriptor limit: VMIN/VTIME are written at their named indices and
    // disable restores the saved attributes exactly (termios(3), STUI-1227).
    @Test func setE133RealPTYRawModeRoundTripsTermios() async {
      await #expect(processExitsWith: .success) {
        try await MainActor.run {
          try setELowerDescriptorLimit(headroom: 32)
          var master: Int32 = -1
          var slave: Int32 = -1
          try #require(unsafe openpty(&master, &slave, nil, nil, nil) == 0)
          defer { for fd in [master, slave] { _ = close(fd) } }
          var saved = termios()
          try #require(unsafe tcgetattr(slave, &saved) == 0)
          let host = TerminalHost(
            inputFileDescriptor: slave, outputFileDescriptor: slave,
            fallbackSize: .init(width: 20, height: 4), capabilityProfile: .trueColor,
            environment: ["SWIFTTUI_KITTY_KEYBOARD": "0"])
          try host.enableRawMode()
          var raw = termios()
          try #require(unsafe tcgetattr(slave, &raw) == 0)
          #expect(raw.c_lflag & tcflag_t(ICANON | ECHO) == 0)
          let rawControls = setEControlCharacters(raw)
          #expect(rawControls.vmin == 1)
          #expect(rawControls.vtime == 0)
          try host.disableRawMode()
          var restored = termios()
          try #require(unsafe tcgetattr(slave, &restored) == 0)
          // PENDIN is kernel-maintained state (termios(4)): the line
          // discipline may set it when canonical mode returns.
          let pending = tcflag_t(PENDIN)
          #expect(restored.c_lflag & ~pending == saved.c_lflag & ~pending)
          #expect(restored.c_iflag == saved.c_iflag)
          #expect(restored.c_oflag == saved.c_oflag)
          #expect(restored.c_cflag == saved.c_cflag)
          let savedControls = setEControlCharacters(saved)
          let restoredControls = setEControlCharacters(restored)
          #expect(restoredControls.vmin == savedControls.vmin)
          #expect(restoredControls.vtime == savedControls.vtime)
        }
      }
    }

    // Real POSIX controller with a pipe as the terminal in a disposable
    // child: entry is refused before any byte is written.
    @Test func setE134RealControllerRefusesPipeInput() async {
      await #expect(processExitsWith: .success) {
        try await MainActor.run {
          try setELowerDescriptorLimit(headroom: 32)
          var input: [Int32] = [-1, -1]
          var output: [Int32] = [-1, -1]
          try #require(unsafe pipe(&input) == 0)
          try #require(unsafe pipe(&output) == 0)
          defer { for fd in input + output { _ = close(fd) } }
          let flags = fcntl(output[0], F_GETFL)
          try #require(fcntl(output[0], F_SETFL, flags | O_NONBLOCK) == 0)
          let host = TerminalHost(
            inputFileDescriptor: input[0], outputFileDescriptor: output[1],
            fallbackSize: .init(width: 20, height: 4), capabilityProfile: .trueColor,
            environment: ["SWIFTTUI_KITTY_KEYBOARD": "0"])
          #expect(throws: TerminalHostError.self) { try host.enableRawMode() }
          var byte: UInt8 = 0
          let count = unsafe read(output[0], &byte, 1)
          #expect(count == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))
        }
      }
    }
  }

  /// Lowers RLIMIT_NOFILE to the current highest open descriptor plus
  /// `headroom`, so the child cannot exhaust the machine's descriptors.
  private func setELowerDescriptorLimit(headroom: Int) throws {
    #if canImport(Glibc)
      let resource = __rlimit_resource_t(RLIMIT_NOFILE.rawValue)
    #else
      let resource = RLIMIT_NOFILE
    #endif
    var highest: Int32 = 0
    for fd in Int32(0)..<Int32(1024) where fcntl(fd, F_GETFD) != -1 { highest = fd }
    var limit = rlimit()
    try #require(unsafe getrlimit(resource, &limit) == 0)
    limit.rlim_cur = rlim_t(Int(highest) + headroom)
    try #require(unsafe setrlimit(resource, &limit) == 0)
  }

  private func setEControlCharacters(_ attributes: termios) -> (vmin: UInt8, vtime: UInt8) {
    var copy = attributes
    return withUnsafeBytes(of: &copy.c_cc) { controls in
      unsafe (controls[Int(VMIN)], controls[Int(VTIME)])
    }
  }

  private enum SetERawError: Error, Equatable { case entry, write, restore }

  /// One RunLoop session over `host` with finished input and signals.
  @MainActor
  private struct SetERawSession {
    var threw: SetERawError?
    var sessionActiveAfter: Bool
    var acceptsTerminationAfter: Bool
    var tasksStarted: Int

    static func run(host: TerminalHost, id: Int) async throws -> SetERawSession {
      let probe = SetERawProbe()
      let input = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
      let signals = InProcessSignalReader()
      let identity = testIdentity("setE", String(id))
      let loop = RunLoop(
        rootIdentity: identity, presentationSurface: host, terminalInputReader: input,
        signalReader: signals, scheduler: FrameScheduler(),
        stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
        focusTracker: FocusTracker(invalidationIdentities: [identity]),
        viewBuilder: { _, _ in Text("Session").task { probe.started += 1 } })
      input.finish()
      signals.finish()
      var threw: SetERawError?
      do {
        _ = try await loop.run()
      } catch let error as SetERawError {
        threw = error
      }
      loop.lifecycleCoordinator.shutdown()
      return SetERawSession(
        threw: threw, sessionActiveAfter: loop.isSessionActive,
        acceptsTerminationAfter: loop.runtimeRequestTerminationAction()(),
        tasksStarted: probe.started)
    }
  }

  @MainActor
  private final class SetERawProbe {
    var started = 0
  }

  /// Records entry, restore and every write; fails the configured calls once.
  private final class SetERawController: TerminalControlling {
    struct State: Sendable {
      var enters = 0
      var restores = 0
      var writes: [String] = []
      var enterErrors = 0
      var writeNeedles: [String] = []
    }
    let state = Mutex(State())
    var snapshot: State { state.withLock { $0 } }
    func clearErrors() {
      state.withLock {
        $0.enterErrors = 0
        $0.writeNeedles = []
      }
    }
    func failWrite(_ needle: String) {
      state.withLock { $0.writeNeedles.append(needle) }
    }
    func isATTY(_: Int32) -> Bool { true }
    func windowSize(of _: Int32) throws -> CellSize { .init(width: 20, height: 4) }
    func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot {
      let fails = state.withLock { value in
        value.enters += 1
        if value.enterErrors > 0 {
          value.enterErrors -= 1
          return true
        }
        return false
      }
      if fails { throw SetERawError.entry }
      return .init()
    }
    func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {
      state.withLock { $0.restores += 1 }
    }
    func write(_ output: String, to _: Int32) throws {
      let fails = state.withLock { value in
        value.writes.append(output)
        if let index = value.writeNeedles.firstIndex(where: { output.contains($0) }) {
          value.writeNeedles.remove(at: index)
          return true
        }
        return false
      }
      if fails { throw SetERawError.write }
    }
    func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] { [] }
  }
#endif
