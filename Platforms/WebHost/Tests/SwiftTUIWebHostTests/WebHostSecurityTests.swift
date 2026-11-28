import Foundation
import Testing

@testable import SwiftTUIWebHost

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct WebHostSecurityTests {
  @Test("the packaged browser uses an explicit session token and loads static assets directly")
  func bundledAssetsNeedNoCookie() async throws {
    try await withServer { session in
      let (_, response) = try await serverData(from: session.url(path: "/"))
      let http = try #require(response as? HTTPURLResponse)
      #expect(http.value(forHTTPHeaderField: "Set-Cookie") == nil)
      #expect(http.value(forHTTPHeaderField: "Referrer-Policy") == "no-referrer")
      let (_, script) = try await serverData(
        from: session.url(path: "/static/webhost.js", includeToken: false))
      #expect(try statusCode(from: script) == 200)
    }
  }

  @Test("two custom bundles keep their static credentials separate from live session routes")
  func customAssetCookiesAreIndependent() throws {
    let routes = [9123, 9124].map { port in
      WebHostRouteTable(
        bind: "127.0.0.1", token: WebHostToken(), scenes: [.init(id: "main")],
        port: port, maxMessageBytes: 1024, customAssetToken: WebHostToken())
    }
    func response(
      _ table: WebHostRouteTable, _ path: String, query: [String: String] = [:], cookie: String = ""
    ) throws -> WebHostHTTPResponse {
      let head = WebHostHTTPRequestHead(
        method: "GET", path: path, query: query,
        headers: [("Host", "127.0.0.1:\(table.port)"), ("Cookie", cookie)])
      guard case .plain(let response) = table.route(head) else {
        throw TestFailure.unexpectedUpgrade
      }
      return response
    }
    var cookies: [String] = []
    for table in routes {
      let page = try response(table, "/", query: ["token": table.token.rawValue])
      let cookie = try #require(page.headers.first { $0.name == "Set-Cookie" }?.value)
      #expect(!cookie.contains(table.token.rawValue))
      cookies.append(String(try #require(cookie.split(separator: ";").first)))
    }
    for (index, table) in routes.enumerated() {
      let both = cookies.joined(separator: "; ")
      #expect(try response(table, "/static/webhost.js", cookie: both).status == 200)
      #expect(try response(table, "/static/webhost.js", cookie: cookies[1 - index]).status == 403)
      for path in ["/", "/scene-manifest.json", "/ws/scene/main"] {
        #expect(try response(table, path, cookie: both).status == 403)
      }
      #expect(
        try response(table, "/scene-manifest.json", query: ["token": table.token.rawValue]).status
          == 200)
    }
  }

  private enum TestFailure: Error { case unexpectedUpgrade }

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
    let channel = WebHostSceneChannel()
    let session = WebHostServerSession(
      baseURL: URL(string: "http://127.0.0.1:9123/")!,
      webSocketURL: URL(string: "ws://127.0.0.1:9123/ws/scene/main?token=test-token")!,
      token: WebHostToken(rawValue: "test-token"),
      channel: channel, channels: ["main": channel],
      stopHandler: {}
    )

    let message = WebHostBanner.message(
      for: session,
      configuration: WebHostConfig(bind: "0.0.0.0", port: 0)
    )

    #expect(message.contains("reachable from the local network"))
  }
}
