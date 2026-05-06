import Foundation
import Testing

@testable import SwiftTUIWebHost

struct WebHostServerTests {
  @Test("binding to port 0 produces a reachable loopback URL")
  func bindingToPortZeroProducesReachableLoopbackURL() async throws {
    try await withServer { session in
      #expect(session.baseURL.host == "127.0.0.1")
      #expect(session.baseURL.port != nil)

      let (data, response) = try await URLSession.shared.data(from: session.url(path: "/"))
      #expect(try statusCode(from: response) == 200)
      #expect(String(decoding: data, as: UTF8.self).contains("<main id=\"app\"></main>"))
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
      let webSocket = URLSession.shared.webSocketTask(with: session.webSocketURL)
      webSocket.resume()

      try await session.channel.send(Array("surface-frame".utf8))
      let received = try await webSocket.receive()
      switch received {
      case .data(let data):
        #expect(String(decoding: data, as: UTF8.self) == "surface-frame")
      case .string(let text):
        #expect(text == "surface-frame")
      @unknown default:
        Issue.record("Unexpected WebSocket message: \(received)")
      }

      try await webSocket.send(.data(Data("input-record".utf8)))
      let chunk = try #require(await chunks.next())
      #expect(String(decoding: chunk, as: UTF8.self) == "input-record")

      webSocket.cancel(with: .normalClosure, reason: nil)
    }
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
