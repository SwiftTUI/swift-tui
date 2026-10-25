// Adversarial set H, pass 1 (F6 platform edges): the SwiftTUIPlatformIO
// facade, PTY primitives and attach discovery (setH021–setH036, setH075).
// Pass 1 found that the Glibc arm of the facade had no SIGPIPE suppression
// and that discovery unlinked whatever it could not connect to (both
// repaired, STUI-1227); the PTY helpers answer platform errnos. Each case
// names its contract in the F6 brief.
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

  @Suite("Adversarial set H: platform facade", .serialized)
  struct AdversarialSetHPlatformFacadeTests {
    // sceneWrite tries send(MSG_NOSIGNAL) and falls back to write(2) for
    // anything that is not a socket. Darwin's sceneOpen installs
    // F_SETNOSIGPIPE on the descriptor it opens; the other POSIX arms block
    // SIGPIPE around the write, so every arm returns EPIPE (STUI-1227).
    @Test func setH021FacadeWriteToClosedFIFOReaderRaisesSIGPIPEOnLinux() async {
      await setH021ClosedFIFOWrite()
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

    // FW3-A neighbors (STUI-1227, setH021): a facade write that fails with
    // EPIPE leaves the caller's signal mask and pending set as it found them,
    // keeps a SIGPIPE that was already pending, and leaves the process-wide
    // default SIGPIPE in place for plain writers.
    @Test func wave3a05FacadeEPIPELeavesSignalMaskAndPendingSetUnchanged() async {
      await #expect(processExitsWith: .success) {
        var pipeSignal = setHSIGPIPESet()
        _ = unsafe pthread_sigmask(SIG_UNBLOCK, &pipeSignal, nil)
        let fifo = try SetHClosedFIFO()
        defer { fifo.remove() }
        let written = [UInt8(0x41)].withUnsafeBytes {
          unsafe sceneWrite(fifo.writer, $0.baseAddress, 1)
        }
        let failure = errno
        #expect(written == -1)
        #expect(failure == EPIPE)
        var mask = sigset_t()
        _ = unsafe pthread_sigmask(SIG_BLOCK, nil, &mask)
        #expect(unsafe sigismember(&mask, SIGPIPE) == 0)
        var pending = sigset_t()
        _ = unsafe sigpending(&pending)
        #expect(unsafe sigismember(&pending, SIGPIPE) == 0)
      }
    }

    #if os(Linux)
      // Linux only: Darwin's pthread_kill refuses workqueue threads (ENOTSUP),
      // so an exit-test body there cannot pend a thread-directed signal, and
      // the Darwin arm never changes the mask.
      @Test func wave3a06PendingSIGPIPEBeforeFacadeWriteStaysPending() async {
        await #expect(processExitsWith: .success) {
          var pipeSignal = setHSIGPIPESet()
          var original = sigset_t()
          try #require(unsafe pthread_sigmask(SIG_BLOCK, &pipeSignal, &original) == 0)
          defer { _ = unsafe pthread_sigmask(SIG_SETMASK, &original, nil) }
          try #require(pthread_kill(pthread_self(), SIGPIPE) == 0)
          let fifo = try SetHClosedFIFO()
          defer { fifo.remove() }
          let written = [UInt8(0x41)].withUnsafeBytes {
            unsafe sceneWrite(fifo.writer, $0.baseAddress, 1)
          }
          let failure = errno
          #expect(written == -1)
          #expect(failure == EPIPE)
          var mask = sigset_t()
          _ = unsafe pthread_sigmask(SIG_BLOCK, nil, &mask)
          #expect(unsafe sigismember(&mask, SIGPIPE) == 1)
          var pending = sigset_t()
          _ = unsafe sigpending(&pending)
          #expect(unsafe sigismember(&pending, SIGPIPE) == 1)
          var delivered: Int32 = 0
          #expect(unsafe sigwait(&pipeSignal, &delivered) == 0)
          #expect(delivered == SIGPIPE)
        }
      }
    #endif

    #if os(Linux)
      // Linux directs a write's SIGPIPE to the writing thread, so the plain
      // write ends the child before `pause()`; the wait only keeps a missing
      // signal from passing as a normal exit (the alarm bounds it).
      @Test func wave3a07LaterPlainWriterStillReceivesDefaultSIGPIPE() async {
        await #expect(processExitsWith: .signal(SIGPIPE)) {
          _ = signal(SIGPIPE, SIG_DFL)
          var pipeSignal = setHSIGPIPESet()
          _ = unsafe pthread_sigmask(SIG_UNBLOCK, &pipeSignal, nil)
          _ = alarm(10)
          let fifo = try SetHClosedFIFO()
          let written = [UInt8(0x41)].withUnsafeBytes {
            unsafe sceneWrite(fifo.writer, $0.baseAddress, 1)
          }
          let failure = errno
          fifo.remove()
          try #require(written == -1 && failure == EPIPE)
          var descriptors: [Int32] = [-1, -1]
          try #require(unsafe pipe(&descriptors) == 0)
          _ = close(descriptors[0])
          _ = [UInt8(0x41)].withUnsafeBytes { unsafe write(descriptors[1], $0.baseAddress, 1) }
          while true { _ = pause() }
        }
      }
    #endif

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

    // Discovery unlinks a non-connectable "*.sock" entry only when lstat(2)
    // reports a socket; a regular file with the suffix survives (STUI-1227).
    @Test func setH031DiscoveryUnlinksRegularSockNamedFile() throws {
      let appName = "setH031-\(UUID().uuidString)"
      let directory = "/tmp/swifttui/\(appName)"
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: directory) }
      let file = directory + "/note.sock"
      try Data("keep".utf8).write(to: URL(fileURLWithPath: file))
      let instances = SocketClient.discoverInstances(appName: appName)
      #expect(instances.isEmpty)
      #expect(FileManager.default.fileExists(atPath: file))
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

    // FW3-A neighbors (STUI-1227, setH031): a stale bound socket is still
    // removed; a symlink named *.sock is neither removed nor followed.
    @Test func wave3a08DiscoveryStillRemovesStaleSocket() throws {
      let appName = "wave3a08-\(UUID().uuidString)"
      let directory = "/tmp/swifttui/\(appName)"
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: directory) }
      let path = directory + "/stale.sock"
      let descriptor = sceneSocket()
      try #require(descriptor >= 0)
      var address = try #require(sceneSocketAddress(for: path))
      try #require(sceneBind(descriptor, &address) == 0)
      sceneClose(descriptor)
      var information = stat()
      try #require(unsafe lstat(path, &information) == 0)
      try #require(information.st_mode & S_IFMT == S_IFSOCK)
      #expect(SocketClient.discoverInstances(appName: appName).isEmpty)
      #expect(unsafe lstat(path, &information) == -1)
    }

    @Test func wave3a09DiscoveryKeepsSockNamedSymlink() throws {
      let appName = "wave3a09-\(UUID().uuidString)"
      let directory = "/tmp/swifttui/\(appName)"
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: directory) }
      let target = directory + "/target.txt"
      try Data("keep".utf8).write(to: URL(fileURLWithPath: target))
      let link = directory + "/link.sock"
      try #require(unsafe symlink(target, link) == 0)
      #expect(SocketClient.discoverInstances(appName: appName).isEmpty)
      var information = stat()
      #expect(unsafe lstat(link, &information) == 0)
      #expect(information.st_mode & S_IFMT == S_IFLNK)
      #expect(FileManager.default.fileExists(atPath: target))
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

  private func setHSIGPIPESet() -> sigset_t {
    var set = sigset_t()
    _ = unsafe sigemptyset(&set)
    _ = unsafe sigaddset(&set, SIGPIPE)
    return set
  }

  /// A facade-opened FIFO writer whose only reader has closed.
  private struct SetHClosedFIFO {
    let directory: URL
    let writer: Int32

    init() throws {
      directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("setHFIFO-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let path = directory.appendingPathComponent("fifo").path
      try #require(path.withCString { unsafe mkfifo($0, 0o600) } == 0)
      let reader = sceneOpen(path, O_RDONLY | O_NONBLOCK)
      try #require(reader >= 0)
      writer = sceneOpen(path, O_WRONLY)
      try #require(writer >= 0)
      sceneClose(reader)
    }

    func remove() {
      sceneClose(writer)
      try? FileManager.default.removeItem(at: directory)
    }
  }
#endif
