import Foundation
import Testing

@testable import SwiftTUIWebHost

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct WebHostServerTests {
  @Test("default port policy uses preferred range while explicit zero is kernel assigned")
  func defaultPortPolicyUsesPreferredRangeWhileExplicitZeroIsKernelAssigned() {
    #expect(WebHostConfig().candidatePorts == Array(9123...9132))
    #expect(WebHostConfig(port: 0).candidatePorts == [0])
    #expect(WebHostConfig().sceneID == nil)
  }

  @Test("binding to port 0 produces a reachable loopback URL")
  func bindingToPortZeroProducesReachableLoopbackURL() async throws {
    try await withServer { session in
      #expect(session.baseURL.host == "127.0.0.1")
      #expect(session.baseURL.port != nil)

      let (data, response) = try await serverData(from: session.url(path: "/"))
      #expect(try statusCode(from: response) == 200)
      let html = String(decoding: data, as: UTF8.self)
      #expect(html.contains("<main id=\"webhost-root\"></main>"))
      #expect(html.contains("?token=test-token"))
    }
  }

  @Test("static resource content types are stable")
  func staticResourceContentTypesAreStable() async throws {
    try await withServer { session in
      let (_, htmlResponse) = try await serverData(from: session.url(path: "/"))
      let (_, scriptResponse) = try await serverData(
        from: session.url(path: "/static/webhost.js")
      )
      let (manifestData, manifestResponse) = try await serverData(
        from: session.url(path: "/scene-manifest.json")
      )

      #expect(try contentType(from: htmlResponse)?.hasPrefix("text/html") == true)
      #expect(try contentType(from: scriptResponse)?.hasPrefix("application/javascript") == true)
      #expect(try contentType(from: manifestResponse)?.hasPrefix("application/json") == true)
      #expect(String(decoding: manifestData, as: UTF8.self).contains("\"defaultSceneId\""))
    }
  }

  @Test("WebSocket upgrade receives output and forwards input")
  func webSocketUpgradeReceivesOutputAndForwardsInput() async throws {
    try await withServer { session in
      var events = session.channel.inboundEvents().makeAsyncIterator()
      let webSocket = try WebSocketTestClient.connect(to: session.webSocketURL)

      // A non-surface record reaches a pre-capabilities client immediately;
      // surface records wait for its capability declaration.
      try await session.channel.send(Array("clipboard-record".utf8))
      let received = try webSocket.receiveMessage()
      #expect(String(decoding: received, as: UTF8.self) == "clipboard-record")

      guard case .connectionOpened(let openedToken) = try #require(await events.next()) else {
        Issue.record("expected the attach to open a tagged connection")
        return
      }
      #expect(openedToken == 1)

      try webSocket.sendBinary(Data("input-record".utf8))
      guard case .bytes(let token, let bytes) = try #require(await events.next()) else {
        Issue.record("expected tagged inbound bytes")
        return
      }
      #expect(token == openedToken)
      #expect(String(decoding: bytes, as: UTF8.self) == "input-record")

      webSocket.close()
    }
  }

  @Test("WebSocket close messages preserve close code and reason")
  func webSocketCloseMessagesPreserveCloseCodeAndReason() async throws {
    let channel = WebHostSceneChannel()
    let output = await channel.attach(
      client: AsyncStream { continuation in
        continuation.yield(.close(code: 1009, reason: "too large"))
        continuation.finish()
      }
    )
    var iterator = output.makeAsyncIterator()

    #expect(await iterator.next() == .close(code: 1009, reason: "too large"))
  }

  @Test("a detached channel drops surface records and bounds the rest")
  func detachedChannelDropsSurfaceRecordsAndBoundsTheRest() async throws {
    // The D11 regression pin, inverted. Before S3b this queued all 100 stale
    // surface records unboundedly and flushed them into the next client ahead
    // of its capability declaration — records naming an epoch that ended with
    // the previous client.
    let channel = WebHostSceneChannel()
    for sequence in 0..<100 {
      try await channel.send(Array("\u{001E}surface:{\"sequence\":\(sequence)}\n".utf8))
    }
    let overflowingNonSurface = (0..<(WebHostSceneChannel.detachedNonSurfaceBacklogLimit + 8))
      .map { index in
        Array("\u{001E}runtimeIssue:{\"index\":\(index)}\n".utf8)
      }
    for record in overflowingNonSurface {
      try await channel.send(record)
    }

    let detachedObservations = await channel.consumeObservations()
    #expect(detachedObservations.phase == .detached)
    #expect(detachedObservations.suppressedSurfaceRecords.isEmpty)
    #expect(
      detachedObservations.detachedNonSurfaceBacklogCount
        == WebHostSceneChannel.detachedNonSurfaceBacklogLimit)

    let client = AsyncStream<WebHostSocketMessage> { continuation in
      continuation.yield(.data(Array("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n".utf8)))
    }
    let output = await channel.attach(client: client)
    var outputIterator = output.makeAsyncIterator()

    // Only the newest bounded non-surface records survive, in order, and not
    // one surface record among them.
    var flushed: [[UInt8]] = []
    for _ in 0..<WebHostSceneChannel.detachedNonSurfaceBacklogLimit {
      guard case .data(let bytes) = try #require(await outputIterator.next()) else {
        Issue.record("expected a flushed non-surface record")
        return
      }
      flushed.append(bytes)
    }
    #expect(flushed == overflowingNonSurface.suffix(flushed.count))

    let attachedObservations = await channel.consumeObservations()
    #expect(attachedObservations.phase == .preCapabilities)
    #expect(attachedObservations.currentToken == 1)
    #expect(attachedObservations.detachedNonSurfaceBacklogCount == 0)
    #expect(attachedObservations.detachedNonSurfaceBacklogBytes == 0)
    #expect(!attachedObservations.sceneInputFinished)
  }
}

func withServer(
  _ body: (WebHostServerSession) async throws -> Void
) async throws {
  await webHostNetworkTestGate.enter()
  do {
    let server = WebHostFlyingFoxServer()
    let session = try await server.start(
      configuration: .init(bind: "127.0.0.1", port: 0),
      token: WebHostToken(rawValue: "test-token"),
      scene: .init(id: "main", title: "Main")
    )

    do {
      try await body(session)
      await session.stop()
    } catch {
      await session.stop()
      throw error
    }
    await webHostNetworkTestGate.leave()
  } catch {
    await webHostNetworkTestGate.leave()
    throw error
  }
}

private let webHostNetworkTestGate = WebHostNetworkTestGate()

private actor WebHostNetworkTestGate {
  private var isLocked = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func enter() async {
    guard isLocked else {
      isLocked = true
      return
    }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      waiters.append(continuation)
    }
  }

  func leave() {
    guard !waiters.isEmpty else {
      isLocked = false
      return
    }

    waiters.removeFirst().resume()
  }
}

func serverData(
  from url: URL
) async throws -> (Data, URLResponse) {
  let session = webHostTestURLSession()
  defer { session.finishTasksAndInvalidate() }
  return try await session.data(from: url)
}

func serverData(
  for request: URLRequest
) async throws -> (Data, URLResponse) {
  let session = webHostTestURLSession()
  defer { session.finishTasksAndInvalidate() }
  return try await session.data(for: request)
}

private func webHostTestURLSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.timeoutIntervalForRequest = 5
  configuration.timeoutIntervalForResource = 10
  configuration.httpShouldSetCookies = false
  return URLSession(configuration: configuration)
}

func statusCode(
  from response: URLResponse
) throws -> Int {
  try #require(response as? HTTPURLResponse).statusCode
}

func contentType(
  from response: URLResponse
) throws -> String? {
  try #require(response as? HTTPURLResponse).value(forHTTPHeaderField: "Content-Type")
}
