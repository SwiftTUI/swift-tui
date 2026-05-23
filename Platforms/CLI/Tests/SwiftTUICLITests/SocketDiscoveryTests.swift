import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICLI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite(.serialized)
struct SocketDiscoveryTests {
  @Test("Duplicate live instance identifiers are rejected")
  func duplicateIdentifiersRejected() async throws {
    let appName = uniqueAppName()
    let identifier = "shared"

    let firstServer = makeServer(appName: appName, identifier: identifier)
    let firstTask = await startServer(firstServer)
    defer {
      firstTask.cancel()
    }

    let secondServer = makeServer(appName: appName, identifier: identifier)
    let secondTask = Task {
      try await secondServer.run()
    }

    do {
      try await secondTask.value
      Issue.record("Expected duplicate instance startup to fail")
    } catch let error as SceneDiscoveryServerError {
      switch error {
      case .identifierAlreadyInUse(let path):
        #expect(path == firstServer.socketPath)
      default:
        Issue.record("Unexpected discovery server error: \(error)")
      }
    }

    let response = try sendListRequest(
      socketPath: firstServer.socketPath,
      request: "LIST\n"
    )
    #expect(response.hasPrefix("OK "))

    firstTask.cancel()
    _ = try? await firstTask.value
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

    let task = await startServer(server)
    defer {
      task.cancel()
    }

    let response = try sendListRequest(
      socketPath: server.socketPath,
      request: "LIST\n"
    )
    #expect(response.hasPrefix("OK "))

    task.cancel()
    _ = try? await task.value
  }

  @Test("Most recent instance selection uses socket timestamps")
  func mostRecentSelectionUsesTimestamps() async throws {
    let appName = uniqueAppName()

    let firstServer = makeServer(appName: appName, identifier: "first")
    let firstTask = await startServer(firstServer)
    defer { firstTask.cancel() }

    let secondServer = makeServer(appName: appName, identifier: "second")
    let secondTask = await startServer(secondServer)
    defer { secondTask.cancel() }

    // Make "most recent" deterministic by stamping the socket modification
    // times explicitly, instead of relying on a wall-clock sleep between the
    // two server starts to produce distinct timestamps.
    let now = Date()
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-2)],
      ofItemAtPath: firstServer.socketPath
    )
    try FileManager.default.setAttributes(
      [.modificationDate: now],
      ofItemAtPath: secondServer.socketPath
    )

    let instances = SocketClient.discoverInstances(appName: appName)
    #expect(instances.map(\.identifier) == ["first", "second"])

    let selected = try SocketClient.selectInstance(
      appName: appName,
      selector: .mostRecent
    )
    #expect(selected.identifier == "second")

    firstTask.cancel()
    secondTask.cancel()
    _ = try? await firstTask.value
    _ = try? await secondTask.value
  }

  @Test("Server shutdown removes its socket path")
  func shutdownRemovesSocketPath() async throws {
    let appName = uniqueAppName()
    let server = makeServer(appName: appName, identifier: "cleanup")
    let task = await startServer(server)

    #expect(FileManager.default.fileExists(atPath: server.socketPath))

    task.cancel()
    // `run()` unlinks the socket path in its `defer` before returning, so once
    // the task completes the path is already gone — no polling needed.
    _ = try? await task.value
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

private func sendListRequest(
  socketPath: String,
  request: String
) throws(SocketClientError) -> String {
  try SocketClient.sendRequest(
    socketPath: socketPath,
    request: request,
    timeoutMilliseconds: 5_000
  )
}

/// Starts `server` and returns once it is bound and listening.
///
/// `run(onReady:)` fires the readiness callback at the exact instant a client
/// connect would succeed, so the test `await`s that signal directly instead of
/// polling the socket under a timeout.
private func startServer(_ server: SceneDiscoveryServer) async -> Task<Void, any Error> {
  let ready = AsyncEvent()
  let task = Task {
    try await server.run(onReady: { ready.fire() })
  }
  await ready.wait()
  return task
}

private func uniqueAppName() -> String {
  "swifttuiscenes-tests-\(UUID().uuidString)"
}

private func streamSocketType() -> Int32 {
  #if canImport(Darwin)
    SOCK_STREAM
  #elseif canImport(Glibc)
    Int32(SOCK_STREAM.rawValue)
  #endif
}
