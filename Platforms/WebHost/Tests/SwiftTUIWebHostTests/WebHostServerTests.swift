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

      let (data, response) = try await URLSession.shared.data(from: session.url(path: "/"))
      #expect(try statusCode(from: response) == 200)
      let html = String(decoding: data, as: UTF8.self)
      #expect(html.contains("<main id=\"webhost-root\"></main>"))
      #expect(html.contains("?token=test-token"))
    }
  }

  @Test("static resource content types are stable")
  func staticResourceContentTypesAreStable() async throws {
    try await withServer { session in
      let (_, htmlResponse) = try await URLSession.shared.data(from: session.url(path: "/"))
      let (_, scriptResponse) = try await URLSession.shared.data(
        from: session.url(path: "/static/webhost.js")
      )
      let (manifestData, manifestResponse) = try await URLSession.shared.data(
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
      var chunks = session.channel.chunks().makeAsyncIterator()
      let webSocket = try WebSocketTestClient.connect(to: session.webSocketURL)

      try await session.channel.send(Array("surface-frame".utf8))
      let received = try webSocket.receiveMessage()
      #expect(String(decoding: received, as: UTF8.self) == "surface-frame")

      try webSocket.sendBinary(Data("input-record".utf8))
      let chunk = try #require(await chunks.next())
      #expect(String(decoding: chunk, as: UTF8.self) == "input-record")

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
}

func withServer(
  _ body: (WebHostServerSession) async throws -> Void
) async throws {
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
