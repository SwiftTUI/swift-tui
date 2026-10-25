// Adversarial set H, pass 1 (F6 platform edges): the SwiftTUIPlatformIO
// facade, PTY primitives and attach discovery (setH021–setH036, setH075).
// The Glibc arm of the facade has no SIGPIPE suppression, discovery unlinks
// whatever it cannot connect to, and the PTY helpers answer platform errnos;
// each case names its contract in the F6 brief.
//
// Excluded from Windows builds like the other attach tests: the subsystem's
// POSIX half builds empty there.
#if !os(Windows)

  import Foundation
  import SwiftTUIPTYPrimitives
  import SwiftTUIPlatformIO
  @_spi(Testing) import SwiftTUITestSupport
  import Testing

  @testable import SwiftTUICLIAttach

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  #if canImport(Glibc)
    private let setHStreamSocketType = Int32(SOCK_STREAM.rawValue)
    private let setHDescriptorLimit = __rlimit_resource_t(RLIMIT_NOFILE.rawValue)
  #else
    private let setHStreamSocketType = SOCK_STREAM
    private let setHDescriptorLimit = RLIMIT_NOFILE
  #endif

  /// Keeps an unmarked reproduction path (`SWIFTTUI_SETH_UNMARKED=1`) while
  /// limiting each guard to its exact reproduced assertion.
  private func setHKnown(_ comment: Comment, _ body: () throws -> Void) rethrows {
    if ProcessInfo.processInfo.environment["SWIFTTUI_SETH_UNMARKED"] == "1" {
      try body()
    } else {
      withKnownIssue(comment) { try body() }
    }
  }

  private func setHKnown(_ comment: Comment, _ body: () async throws -> Void) async rethrows {
    if ProcessInfo.processInfo.environment["SWIFTTUI_SETH_UNMARKED"] == "1" {
      try await body()
    } else {
      await withKnownIssue(comment) { try await body() }
    }
  }

  @Suite("Adversarial set H: platform facade", .serialized)
  struct AdversarialSetHPlatformFacadeTests {
    // sceneWrite tries send(MSG_NOSIGNAL) and falls back to write(2) for
    // anything that is not a socket. Darwin's sceneOpen installs
    // F_SETNOSIGPIPE on the descriptor it opens; the Glibc arm is a no-op.
    @Test func setH021FacadeWriteToClosedFIFOReaderRaisesSIGPIPEOnLinux() async {
      #if os(Linux)
        await setHKnown(
          "STUI-1227: setH021: on Linux a sceneWrite to a facade-opened FIFO whose reader closed kills the process with SIGPIPE; the Glibc sceneConfigureNoSigPipe is a no-op and sceneWrite falls back to write(2) for non-sockets (PlatformPOSIX.swift:28-36, 105-118); contract: facade arms agree on an error return (Darwin F_SETNOSIGPIPE; PlatformWindows.swift:12-14); adjacent: none"
        ) {
          await setH021ClosedFIFOWrite()
        }
      #else
        await setH021ClosedFIFOWrite()
      #endif
    }

    private func setH021ClosedFIFOWrite() async {
      await #expect(processExitsWith: .success) {
        let directory = FileManager.default.temporaryDirectory
          .appendingPathComponent("setH021-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("fifo").path
        try #require(path.withCString { unsafe mkfifo($0, 0o600) } == 0)
        let reader = sceneOpen(path, O_RDONLY | O_NONBLOCK)
        try #require(reader >= 0)
        let writer = sceneOpen(path, O_WRONLY)
        try #require(writer >= 0)
        defer { sceneClose(writer) }
        sceneClose(reader)
        let payload: [UInt8] = [0x41]
        let written = payload.withUnsafeBytes { unsafe sceneWrite(writer, $0.baseAddress, 1) }
        let failure = errno
        #expect(written == -1)
        #expect(failure == EPIPE)
      }
    }

    @Test func setH022FacadeWriteToClosedSocketPeerReportsEPIPE() async {
      await #expect(processExitsWith: .success) {
        var descriptors: [Int32] = [-1, -1]
        try #require(unsafe socketpair(AF_UNIX, setHStreamSocketType, 0, &descriptors) == 0)
        _ = close(descriptors[0])
        defer { _ = close(descriptors[1]) }
        let payload: [UInt8] = [0x41]
        let written = payload.withUnsafeBytes {
          unsafe sceneWrite(descriptors[1], $0.baseAddress, 1)
        }
        let failure = errno
        #expect(written == -1)
        #expect(failure == EPIPE)
      }
    }

    @Test func setH023SocketAddressBoundary() throws {
      let size = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
      let fitting = String(repeating: "a", count: size - 1)
      let address = try #require(sceneSocketAddress(for: fitting))
      let lastByte = withUnsafeBytes(of: address.sun_path) { unsafe $0[size - 1] }
      #expect(lastByte == 0)
      #expect(sceneSocketAddress(for: String(repeating: "a", count: size)) == nil)
    }

    @Test func setH024SocketAddressCountsUTF8Bytes() {
      let size = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
      let accented = String(repeating: "\u{E9}", count: 52)
      #expect(accented.utf8.count == 104)
      #expect((sceneSocketAddress(for: accented) != nil) == (104 < size))
      #expect(sceneSocketAddress(for: "a\0b") == nil)
    }

    @Test func setH025OpenPTYUnderDescriptorExhaustionReportsEMFILE() async {
      await #expect(processExitsWith: .success) {
        var limit = rlimit()
        try #require(unsafe getrlimit(setHDescriptorLimit, &limit) == 0)
        var original = limit
        defer { _ = unsafe setrlimit(setHDescriptorLimit, &original) }
        limit.rlim_cur = 64
        try #require(unsafe setrlimit(setHDescriptorLimit, &limit) == 0)
        var held: [Int32] = []
        defer { for descriptor in held { _ = close(descriptor) } }
        var openFailure: Int32 = 0
        while held.count < 128 {
          let descriptor = "/dev/null".withCString { unsafe open($0, O_RDONLY) }
          if descriptor < 0 {
            openFailure = errno
            break
          }
          held.append(descriptor)
        }
        #expect(openFailure == EMFILE)
        #expect(throws: PTYError.allocationFailed(errno: EMFILE)) {
          try openPTY()
        }
      }
    }

    @Test func setH026SlaveOpenWithNOCTTYDoesNotAcquireControllingTerminal() throws {
      let handles = try openPTY()
      defer {
        closeFD(handles.masterFD)
        closeFD(handles.slaveFD)
      }
      let descriptor = sceneOpen(handles.slavePath, O_RDWR | O_NOCTTY)
      try #require(descriptor >= 0)
      defer { sceneClose(descriptor) }
      let group = tcgetpgrp(descriptor)
      let failure = errno
      #expect(group == -1)
      #expect(failure == ENOTTY)
    }

    @Test func setH027SlavePathIsPlatformDevice() throws {
      let handles = try openPTY()
      defer {
        closeFD(handles.masterFD)
        closeFD(handles.slaveFD)
      }
      #if os(Linux)
        #expect(handles.slavePath.hasPrefix("/dev/pts/"), "\(handles.slavePath)")
      #else
        #expect(handles.slavePath.hasPrefix("/dev/ttys"), "\(handles.slavePath)")
      #endif
      let descriptor = sceneOpen(handles.slavePath, O_RDWR | O_NOCTTY)
      #expect(descriptor >= 0)
      sceneClose(descriptor)
    }

    @Test func setH028PTYResizeReadsBackOnSlave() throws {
      let handles = try openPTY()
      defer {
        closeFD(handles.masterFD)
        closeFD(handles.slaveFD)
      }
      try ptyResize(masterFD: handles.masterFD, cols: 132, rows: 43)
      var size = winsize()
      try #require(unsafe ioctl(handles.slaveFD, UInt(TIOCGWINSZ), &size) == 0)
      #expect(size.ws_col == 132)
      #expect(size.ws_row == 43)
    }

    // PTYPair documents the split: Linux reports EIO on the master once the
    // last slave closes; Darwin reports end of file.
    @Test func setH029MasterReadAfterSlaveClosePlatformErrno() throws {
      let handles = try openPTY()
      defer { closeFD(handles.masterFD) }
      closeFD(handles.slaveFD)
      var buffer = [UInt8](repeating: 0, count: 8)
      let count = buffer.withUnsafeMutableBytes {
        unsafe sceneRead(handles.masterFD, $0.baseAddress, 8)
      }
      let failure = errno
      #if os(Linux)
        #expect(count == -1)
        #expect(failure == EIO)
      #else
        #expect(count == 0)
      #endif
    }

    @Test func setH030DiscoveryWithoutDirectoryIsEmpty() {
      let instances = SocketClient.discoverInstances(appName: "setH030-\(UUID().uuidString)")
      #expect(instances.isEmpty)
    }

    // Discovery keeps every "*.sock" name and treats a failed connection as a
    // stale socket to unlink, without asking whether the entry is a socket.
    @Test func setH031DiscoveryUnlinksRegularSockNamedFile() throws {
      let appName = "setH031-\(UUID().uuidString)"
      let directory = "/tmp/swifttui/\(appName)"
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: directory) }
      let file = directory + "/note.sock"
      try Data("keep".utf8).write(to: URL(fileURLWithPath: file))
      let instances = SocketClient.discoverInstances(appName: appName)
      #expect(instances.isEmpty)
      setHKnown(
        "STUI-1227: setH031: discoverInstances unlinks a regular file named note.sock; every non-connectable *.sock entry is treated as a stale socket and unlinked without a socket-type check (SocketClient.swift:78-96); contract: only stale sockets are removed; adjacent STUI-860 (discovery socket protocol)"
      ) {
        #expect(FileManager.default.fileExists(atPath: file))
      }
    }

    @Test func setH032DiscoveryIgnoresSockNamedDirectory() throws {
      let appName = "setH032-\(UUID().uuidString)"
      let directory = "/tmp/swifttui/\(appName)"
      let nested = directory + "/dir.sock"
      try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: directory) }
      let instances = SocketClient.discoverInstances(appName: appName)
      #expect(instances.isEmpty)
      var information = stat()
      #expect(unsafe stat(nested, &information) == 0)
      #expect(information.st_mode & S_IFMT == S_IFDIR)
    }

    @Test func setH033RequestToMissingSocketFailsFast() {
      let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("setH033-\(UUID().uuidString).sock").path
      do {
        _ = try SocketClient.sendRequest(socketPath: path, request: "LIST")
        Issue.record("a missing socket path accepted a request")
      } catch .connectionFailed(let code) {
        #expect(code == ENOENT)
      } catch {
        Issue.record("unexpected failure \(error)")
      }
    }

    @Test func setH034DirectoryAndAccessFacade() throws {
      let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("setH034-\(UUID().uuidString)").path
      try Data("x".utf8).write(to: URL(fileURLWithPath: file))
      defer { _ = sceneUnlink(file) }
      #expect(unsafe sceneOpenDirectory(file) == nil)
      let missing = file + "-missing"
      let access = sceneAccess(missing, F_OK)
      let failure = errno
      #expect(access == -1)
      #expect(failure == ENOENT)
    }

    @Test func setH035SocketTypeAndClosedWrite() throws {
      let descriptor = sceneSocket()
      try #require(descriptor >= 0)
      var type: Int32 = 0
      var length = socklen_t(MemoryLayout<Int32>.size)
      try #require(unsafe getsockopt(descriptor, SOL_SOCKET, SO_TYPE, &type, &length) == 0)
      #expect(type == setHStreamSocketType)
      sceneClose(descriptor)
      let payload: [UInt8] = [0x41]
      let written = payload.withUnsafeBytes { unsafe sceneWrite(descriptor, $0.baseAddress, 1) }
      let failure = errno
      #expect(written == -1)
      #expect(failure == EBADF)
    }

    @Test func setH036ConcurrentOpenPTYSucceeds() async throws {
      let first = Task.detached { try openPTY() }
      let second = Task.detached { try openPTY() }
      let a = try await first.value
      let b = try await second.value
      defer {
        closeFD(a.masterFD)
        closeFD(a.slaveFD)
        closeFD(b.masterFD)
        closeFD(b.slaveFD)
      }
      #expect(a.slavePath != b.slavePath)
      #expect(a.masterFD != b.masterFD)
    }

    @Test func setH075TerminalSignalValuesMatchLibc() {
      let expected: [(TerminalSignal, Int32, String)] = [
        (.sigabrt, SIGABRT, "SIGABRT"), (.sighup, SIGHUP, "SIGHUP"), (.sigill, SIGILL, "SIGILL"),
        (.sigint, SIGINT, "SIGINT"), (.sigquit, SIGQUIT, "SIGQUIT"), (.sigsegv, SIGSEGV, "SIGSEGV"),
        (.sigterm, SIGTERM, "SIGTERM"), (.sigusr1, SIGUSR1, "SIGUSR1"),
        (.sigusr2, SIGUSR2, "SIGUSR2"),
        (.sigalrm, SIGALRM, "SIGALRM"), (.sigwinch, SIGWINCH, "SIGWINCH"),
        (.sigbus, SIGBUS, "SIGBUS"),
        (.sigfpe, SIGFPE, "SIGFPE"), (.sigtrap, SIGTRAP, "SIGTRAP"), (.sigcont, SIGCONT, "SIGCONT"),
        (.sigpipe, SIGPIPE, "SIGPIPE"),
      ]
      for (signal, number, name) in expected {
        #expect(signal.rawValue == number, "\(name)")
        #expect(signal.description == name)
      }
      #expect(Set(expected.map { $0.0.rawValue }).count == 16)
    }
  }
#endif
