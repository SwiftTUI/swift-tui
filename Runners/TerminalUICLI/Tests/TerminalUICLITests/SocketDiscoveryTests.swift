import Foundation
import Testing

@testable import TerminalUICLI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct SocketDiscoveryTests {
  @Test("Duplicate live instance identifiers are rejected")
  func duplicateIdentifiersRejected() async throws {
    let appName = uniqueAppName()
    let identifier = "shared"

    let firstServer = makeServer(appName: appName, identifier: identifier)
    let firstTask = Task {
      try await firstServer.run()
    }
    defer {
      firstTask.cancel()
    }

    try await waitForServer(at: firstServer.socketPath)

    let secondServer = makeServer(appName: appName, identifier: identifier)
    let secondTask = Task {
      try await secondServer.run()
    }

    do {
      try await value(of: secondTask, timeoutNanoseconds: 2_000_000_000)
      Issue.record("Expected duplicate instance startup to fail")
    } catch let error as SceneDiscoveryServerError {
      switch error {
      case .identifierAlreadyInUse(let path):
        #expect(path == firstServer.socketPath)
      default:
        Issue.record("Unexpected discovery server error: \(error)")
      }
    }

    let response = try SocketClient.sendRequest(
      socketPath: firstServer.socketPath,
      request: "LIST\n"
    )
    #expect(response.hasPrefix("OK "))

    firstTask.cancel()
    _ = try? await value(of: firstTask, timeoutNanoseconds: 2_000_000_000)
  }

  @Test("Stale socket paths are replaced on startup")
  func staleSocketPathsReplaced() async throws {
    let appName = uniqueAppName()
    let identifier = "stale"
    let server = makeServer(appName: appName, identifier: identifier)

    try FileManager.default.createDirectory(
      atPath: (server.socketPath as NSString).deletingLastPathComponent,
      withIntermediateDirectories: true
    )
    let staleFD = sceneSocket()
    #expect(staleFD >= 0)

    var addr = sceneSocketAddress(for: server.socketPath)

    let bindResult = sceneBind(staleFD, &addr)
    #expect(bindResult == 0)
    sceneClose(staleFD)

    let task = Task {
      try await server.run()
    }
    defer {
      task.cancel()
    }

    try await waitForServer(at: server.socketPath)
    let response = try SocketClient.sendRequest(
      socketPath: server.socketPath,
      request: "LIST\n"
    )
    #expect(response.hasPrefix("OK "))

    task.cancel()
    _ = try? await value(of: task, timeoutNanoseconds: 2_000_000_000)
  }

  @Test("Most recent instance selection uses socket timestamps")
  func mostRecentSelectionUsesTimestamps() async throws {
    let appName = uniqueAppName()

    let firstServer = makeServer(appName: appName, identifier: "first")
    let firstTask = Task {
      try await firstServer.run()
    }
    defer { firstTask.cancel() }
    try await waitForServer(at: firstServer.socketPath)

    try await Task.sleep(nanoseconds: 200_000_000)

    let secondServer = makeServer(appName: appName, identifier: "second")
    let secondTask = Task {
      try await secondServer.run()
    }
    defer { secondTask.cancel() }
    try await waitForServer(at: secondServer.socketPath)

    let instances = SocketClient.discoverInstances(appName: appName)
    #expect(instances.map(\.identifier) == ["first", "second"])

    let selected = try SocketClient.selectInstance(
      appName: appName,
      selector: .mostRecent
    )
    #expect(selected.identifier == "second")

    firstTask.cancel()
    secondTask.cancel()
    _ = try? await value(of: firstTask, timeoutNanoseconds: 2_000_000_000)
    _ = try? await value(of: secondTask, timeoutNanoseconds: 2_000_000_000)
  }

  @Test("Server shutdown removes its socket path")
  func shutdownRemovesSocketPath() async throws {
    let appName = uniqueAppName()
    let server = makeServer(appName: appName, identifier: "cleanup")
    let task = Task {
      try await server.run()
    }

    try await waitForServer(at: server.socketPath)
    #expect(FileManager.default.fileExists(atPath: server.socketPath))

    task.cancel()
    _ = try? await value(of: task, timeoutNanoseconds: 2_000_000_000)

    try await waitUntilSocketRemoved(server.socketPath)
    #expect(!FileManager.default.fileExists(atPath: server.socketPath))
  }

  @Test("Socket writes return EPIPE instead of raising SIGPIPE")
  func socketWritesReturnEPipeInsteadOfSigPipe() throws {
    var descriptors = [Int32](repeating: -1, count: 2)
    let status = unsafe descriptors.withUnsafeMutableBufferPointer { buffer in
      unsafe socketpair(AF_UNIX, streamSocketType(), 0, buffer.baseAddress)
    }
    #expect(status == 0)
    defer {
      if descriptors[0] >= 0 {
        sceneClose(descriptors[0])
      }
      if descriptors[1] >= 0 {
        sceneClose(descriptors[1])
      }
    }

    sceneClose(descriptors[1])
    descriptors[1] = -1

    errno = 0
    let bytesWritten = unsafe "LIST\n".withCString { pointer in
      unsafe sceneWrite(descriptors[0], pointer, unsafe strlen(pointer))
    }

    #expect(bytesWritten == -1)
    #expect(errno == EPIPE || errno == ECONNRESET)
  }
}

private func makeServer(appName: String, identifier: String) -> SceneDiscoveryServer {
  SceneDiscoveryServer(
    appName: appName,
    identifier: identifier,
    sceneProvider: {
      [
        SceneInfo(
          id: "primary",
          title: "Primary",
          ptyPath: nil,
          isAttached: true
        )
      ]
    },
    attachHandler: { _ in
      .error("unsupported")
    }
  )
}

private func uniqueAppName() -> String {
  "terminaluiscenes-tests-\(UUID().uuidString)"
}

private func streamSocketType() -> Int32 {
  #if canImport(Darwin)
    SOCK_STREAM
  #elseif canImport(Glibc)
    Int32(SOCK_STREAM.rawValue)
  #endif
}

private func waitForServer(at socketPath: String) async throws {
  try await waitUntilSocketCondition("server readiness") {
    do {
      let response = try SocketClient.sendRequest(
        socketPath: socketPath,
        request: "LIST\n",
        timeoutMilliseconds: 100
      )
      return response.hasPrefix("OK ")
    } catch {
      return false
    }
  }
}

private func waitUntilSocketRemoved(_ socketPath: String) async throws {
  try await waitUntilSocketCondition("server shutdown cleanup") {
    !FileManager.default.fileExists(atPath: socketPath)
  }
}

private func waitUntilSocketCondition(
  _ label: String,
  timeoutNanoseconds: UInt64 = 2_000_000_000,
  pollNanoseconds: UInt64 = 20_000_000,
  condition: @escaping () async -> Bool
) async throws {
  let start = DispatchTime.now().uptimeNanoseconds
  while !(await condition()) {
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    if elapsed >= timeoutNanoseconds {
      throw SocketDiscoveryTimeout(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private func value<Success>(
  of task: Task<Success, any Error>,
  timeoutNanoseconds: UInt64
) async throws -> Success {
  try await withThrowingTaskGroup(of: Success.self) { group in
    group.addTask {
      try await task.value
    }
    group.addTask {
      try await Task.sleep(nanoseconds: timeoutNanoseconds)
      throw SocketDiscoveryTimeout("task completion")
    }

    let value = try await group.next()
    group.cancelAll()
    guard let value else {
      throw SocketDiscoveryTimeout("task completion")
    }
    return value
  }
}

private struct SocketDiscoveryTimeout: Error, CustomStringConvertible {
  let label: String

  init(_ label: String) {
    self.label = label
  }

  var description: String {
    "Timed out waiting for \(label)"
  }
}
