import Foundation
import Testing

@testable import SwiftTUIWebHost

struct WebHostSecurityTests {
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
}
