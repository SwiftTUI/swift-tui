// Campaign two, wave-3 regression hunt part FA (STUI-1167): the attach-discovery
// and Linux facade neighbours of FW3-A (3af7dd55, STUI-1227). The rest of the
// part is in Tests/SwiftTUITests/Wave3HuntFATests.swift; contracts and
// predictions are in the coordination root's
// docs/reports/evidence/2026-10-25-campaign-two-wave-3-hunt/fa/.
//
// Excluded from Windows builds like the other attach tests.
#if !os(Windows)

  import Foundation
  import SwiftTUIPlatformIO
  import Testing

  @testable import SwiftTUICLIAttach

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  private let w3faCLIIsLinux: Bool = {
    #if os(Linux)
      return true
    #else
      return false
    #endif
  }()

  @Suite("Wave-3 hunt part FA: attach discovery and facade", .serialized)
  struct Wave3HuntFACLITests {
    // w3fa005: discovery removes only stale sockets; a FIFO named *.sock is
    // neither listed nor removed (SocketClient.swift:61, 93-96, 217-223).
    @Test func w3fa005DiscoveryKeepsSockNamedFIFO() throws {
      let appName = "w3fa005-\(UUID().uuidString)"
      let directory = "/tmp/swifttui/\(appName)"
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: directory) }
      let fifo = directory + "/pipe.sock"
      try #require(fifo.withCString { unsafe mkfifo($0, 0o600) } == 0)
      #expect(SocketClient.discoverInstances(appName: appName).isEmpty)
      var information = stat()
      #expect(unsafe lstat(fifo, &information) == 0)
      #expect(information.st_mode & S_IFMT == S_IFIFO)
    }

    // w3fa006: a dangling symlink named *.sock is kept; lstat(2) reports the
    // link itself (SocketClient.swift:217-223).
    @Test func w3fa006DiscoveryKeepsDanglingSockNamedSymlink() throws {
      let appName = "w3fa006-\(UUID().uuidString)"
      let directory = "/tmp/swifttui/\(appName)"
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: directory) }
      let link = directory + "/dead.sock"
      try #require(unsafe symlink(directory + "/missing-target", link) == 0)
      #expect(SocketClient.discoverInstances(appName: appName).isEmpty)
      var information = stat()
      #expect(unsafe lstat(link, &information) == 0)
      #expect(information.st_mode & S_IFMT == S_IFLNK)
    }

    // w3fa010 (blocked: linux): a caller that already blocks SIGPIPE keeps
    // its mask, and the facade consumes the SIGPIPE its own write generated
    // (PlatformPOSIX.swift:132-162). The Darwin arm never touches the mask.
    @Test(.enabled(if: w3faCLIIsLinux, "blocked: linux (non-Darwin facade arm)"))
    func w3fa010FacadeWriteKeepsACallerBlockedSIGPIPEMaskAndPendingSetClean() async {
      #if os(Linux)
        await #expect(processExitsWith: .success) {
          var pipeSignal = sigset_t()
          _ = unsafe sigemptyset(&pipeSignal)
          _ = unsafe sigaddset(&pipeSignal, SIGPIPE)
          try #require(unsafe pthread_sigmask(SIG_BLOCK, &pipeSignal, nil) == 0)
          let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("w3fa010-\(UUID().uuidString)", isDirectory: true)
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
          let written = [UInt8(0x41)].withUnsafeBytes {
            unsafe sceneWrite(writer, $0.baseAddress, 1)
          }
          let failure = errno
          #expect(written == -1)
          #expect(failure == EPIPE)
          var mask = sigset_t()
          _ = unsafe pthread_sigmask(SIG_BLOCK, nil, &mask)
          #expect(unsafe sigismember(&mask, SIGPIPE) == 1)
          var pending = sigset_t()
          _ = unsafe sigpending(&pending)
          #expect(unsafe sigismember(&pending, SIGPIPE) == 0)
        }
      #endif
    }
  }
#endif
