#if os(macOS) || os(Linux)
  import Dispatch
  import Testing

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

  struct LinkOpeningTests {
    @Test(
      "Link helpers are reaped after both successful and failed exits", arguments: [false, true],
      [0, 17])
    func reapsHelper(searchPath: Bool, exitStatus: Int) async throws {
      let (exits, continuation) = AsyncStream<pid_t>.makeStream()
      // A missing completion fails instead of wedging the test process. The
      // completion callback, not this watchdog, synchronizes the assertion.
      let watchdog = DispatchWorkItem { continuation.finish() }
      DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
      defer {
        watchdog.cancel()
        continuation.finish()
      }
      let command = searchPath ? "sh" : "/bin/sh"
      let spawned = spawnDetachedProcess(
        command: command,
        arguments: [command, "-c", "exit \(exitStatus)"],
        searchPath: searchPath,
        onExit: { pid in
          continuation.yield(pid)
          continuation.finish()
        }
      )
      try #require(spawned)
      var iterator = exits.makeAsyncIterator()
      let pid = try #require(await iterator.next())
      var status: Int32 = 0
      let result = unsafe waitpid(pid, &status, WNOHANG)
      let error = errno
      #expect(result == -1)
      #expect(error == ECHILD, "The helper must already have been reaped")
    }

    @Test("Failure to spawn a link helper is reported", arguments: [false, true])
    func failedSpawn(searchPath: Bool) {
      let command = "/swift-tui-no-such-link-helper"
      #expect(
        !spawnDetachedProcess(command: command, arguments: [command], searchPath: searchPath))
    }
  }
#endif
