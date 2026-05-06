import Foundation
import Testing

@testable import SwiftTUIWebHost

struct WebHostSecurityTests {
  @Test("valid token sets a cookie that authorizes subsequent resources and WebSockets")
  func validTokenSetsCookieThatAuthorizesSubsequentResourcesAndWebSockets() async throws {
    try await withServer { session in
      let (_, firstResponse) = try await URLSession.shared.data(from: session.url(path: "/"))
      let cookie = try #require(
        (firstResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Set-Cookie")
      )
      #expect(cookie.contains("SwiftTUIWebHostToken=test-token"))

      var scriptRequest = URLRequest(
        url: session.url(path: "/static/webhost.js", includeToken: false))
      scriptRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
      let (_, scriptResponse) = try await URLSession.shared.data(for: scriptRequest)
      #expect(try statusCode(from: scriptResponse) == 200)

      var components = URLComponents(url: session.webSocketURL, resolvingAgainstBaseURL: false)!
      components.queryItems = nil
      var webSocketRequest = URLRequest(url: try #require(components.url))
      webSocketRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
      let webSocket = URLSession.shared.webSocketTask(with: webSocketRequest)
      webSocket.resume()

      try await session.channel.send(Array("cookie-authorized".utf8))
      let received = try await webSocket.receive()
      switch received {
      case .data(let data):
        #expect(String(decoding: data, as: UTF8.self) == "cookie-authorized")
      case .string(let text):
        #expect(text == "cookie-authorized")
      @unknown default:
        Issue.record("Unexpected WebSocket message: \(received)")
      }

      webSocket.cancel(with: .normalClosure, reason: nil)
    }
  }

  @Test("token-protected endpoints reject missing and wrong tokens")
  func tokenProtectedEndpointsRejectMissingAndWrongTokens() async throws {
    try await withServer { session in
      let (_, missingResponse) = try await URLSession.shared.data(
        from: session.url(path: "/", includeToken: false)
      )
      #expect(try statusCode(from: missingResponse) == 403)

      var wrongTokenURL = session.url(path: "/")
      var components = URLComponents(url: wrongTokenURL, resolvingAgainstBaseURL: false)!
      components.queryItems = [URLQueryItem(name: "token", value: "wrong-token")]
      wrongTokenURL = components.url!

      let (_, wrongResponse) = try await URLSession.shared.data(from: wrongTokenURL)
      #expect(try statusCode(from: wrongResponse) == 403)
    }
  }

  @Test("invalid WebSocket origins are rejected")
  func invalidWebSocketOriginsAreRejected() async throws {
    try await withServer { session in
      var request = URLRequest(url: session.webSocketURL)
      request.setValue("http://evil.example", forHTTPHeaderField: "Origin")

      let (_, response) = try await URLSession.shared.data(for: request)
      #expect(try statusCode(from: response) == 403)
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
