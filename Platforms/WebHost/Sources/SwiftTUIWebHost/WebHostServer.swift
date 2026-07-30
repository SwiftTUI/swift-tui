package import Foundation

package struct WebHostSceneDescriptor: Equatable, Sendable {
  package var id: String
  package var title: String?
  package var isDefault: Bool

  package init(
    id: String,
    title: String? = nil,
    isDefault: Bool = true
  ) {
    self.id = id
    self.title = title
    self.isDefault = isDefault
  }
}

package struct WebHostServerSession: Sendable {
  package var baseURL: URL
  package var webSocketURL: URL
  package var token: WebHostToken
  package var channel: WebHostSceneChannel

  private let stopHandler: @Sendable () async -> Void

  package init(
    baseURL: URL,
    webSocketURL: URL,
    token: WebHostToken,
    channel: WebHostSceneChannel,
    stopHandler: @escaping @Sendable () async -> Void
  ) {
    self.baseURL = baseURL
    self.webSocketURL = webSocketURL
    self.token = token
    self.channel = channel
    self.stopHandler = stopHandler
  }

  /// Stops the session, terminating the channel first.
  ///
  /// Channel shutdown lives here rather than in each server's stop handler so
  /// no stop path can omit it: a stop that left the channel alive would leak
  /// the reader and output tasks and leave the scene input continuation
  /// unfinished forever. It runs *before* the server stops, so no client can
  /// attach into a channel the session is tearing down.
  package func stop() async {
    await channel.shutdown()
    await stopHandler()
  }

  package func url(
    path: String,
    includeToken: Bool = true
  ) -> URL {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.path = path
    if includeToken {
      components.queryItems = [
        URLQueryItem(name: "token", value: token.rawValue)
      ]
    }
    return components.url!
  }
}

package protocol WebHostServer: Sendable {
  func start(
    configuration: WebHostConfig,
    token: WebHostToken,
    scene: WebHostSceneDescriptor
  ) async throws -> WebHostServerSession
}

package enum WebHostServerError: Error, Equatable, Sendable, CustomStringConvertible {
  case unsupportedPort(Int)
  case unsupportedBindAddress(String)
  case unableToDetermineListeningPort

  package var description: String {
    switch self {
    case .unsupportedPort(let port):
      return "Unsupported WebHost port: \(port)."
    case .unsupportedBindAddress(let address):
      return "Unsupported WebHost bind address: \(address)."
    case .unableToDetermineListeningPort:
      return "Unable to determine WebHost listening port."
    }
  }
}

package enum WebHostSocketMessage: Equatable, Sendable {
  case text(String)
  case data([UInt8])
  case close(code: UInt16, reason: String)

  package static var normalClose: WebHostSocketMessage {
    .close(code: 1000, reason: "")
  }
}
