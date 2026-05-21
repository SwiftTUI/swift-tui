import Foundation
import Testing

@testable import SwiftTUIWebHost

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct WebHostSecurityTests {
  @Test("valid token sets a cookie that authorizes subsequent resources and WebSockets")
  func validTokenSetsCookieThatAuthorizesSubsequentResourcesAndWebSockets() async throws {
    try await withServer { session in
      let (_, firstResponse) = try await serverData(from: session.url(path: "/"))
      let cookie = try #require(
        (firstResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Set-Cookie")
      )
      #expect(cookie.contains("SwiftTUIWebHostToken=test-token"))

      var scriptRequest = URLRequest(
        url: session.url(path: "/static/webhost.js", includeToken: false))
      scriptRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
      let (_, scriptResponse) = try await serverData(for: scriptRequest)
      #expect(try statusCode(from: scriptResponse) == 200)

      var components = URLComponents(url: session.webSocketURL, resolvingAgainstBaseURL: false)!
      components.queryItems = nil
      let webSocket = try WebSocketTestClient.connect(
        to: try #require(components.url),
        headers: [("Cookie", cookie)]
      )

      try await session.channel.send(Array("cookie-authorized".utf8))
      let received = try webSocket.receiveMessage()
      #expect(String(decoding: received, as: UTF8.self) == "cookie-authorized")

      webSocket.close()
    }
  }

  @Test("token-protected endpoints reject missing and wrong tokens")
  func tokenProtectedEndpointsRejectMissingAndWrongTokens() async throws {
    try await withServer { session in
      let (_, missingResponse) = try await serverData(
        from: session.url(path: "/", includeToken: false)
      )
      #expect(try statusCode(from: missingResponse) == 403)

      var wrongTokenURL = session.url(path: "/")
      var components = URLComponents(url: wrongTokenURL, resolvingAgainstBaseURL: false)!
      components.queryItems = [URLQueryItem(name: "token", value: "wrong-token")]
      wrongTokenURL = components.url!

      let (_, wrongResponse) = try await serverData(from: wrongTokenURL)
      #expect(try statusCode(from: wrongResponse) == 403)
    }
  }

  @Test("invalid WebSocket origins are rejected")
  func invalidWebSocketOriginsAreRejected() async throws {
    try await withServer { session in
      let status = try WebSocketTestClient.requestUpgradeStatus(
        to: session.webSocketURL,
        headers: [("Origin", "http://evil.example")]
      )
      #expect(status == 403)
    }
  }

  @Test("external bind banner warns about local-network reachability")
  func externalBindBannerWarnsAboutLocalNetworkReachability() {
    let session = WebHostServerSession(
      baseURL: URL(string: "http://127.0.0.1:9123/")!,
      webSocketURL: URL(string: "ws://127.0.0.1:9123/ws/scene/main?token=test-token")!,
      token: WebHostToken(rawValue: "test-token"),
      channel: WebHostSceneChannel(),
      stopHandler: {}
    )

    let message = WebHostBanner.message(
      for: session,
      configuration: WebHostConfig(bind: "0.0.0.0", port: 0)
    )

    #expect(message.contains("reachable from the local network"))
  }
}
