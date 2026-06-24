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

  package func stop() async {
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

package actor WebHostSceneChannel: WebHostByteSink, WebHostByteSource {
  nonisolated let inputStream: AsyncStream<[UInt8]>

  private let inputContinuation: AsyncStream<[UInt8]>.Continuation
  private var outputContinuation: AsyncStream<WebHostSocketMessage>.Continuation?
  private var pendingOutput: [WebHostSocketMessage] = []
  private var activeConnectionID: UInt64 = 0

  package init() {
    var continuation: AsyncStream<[UInt8]>.Continuation?
    inputStream = AsyncStream { continuation = $0 }
    inputContinuation = continuation!
  }

  package nonisolated func chunks() -> AsyncStream<[UInt8]> {
    inputStream
  }

  package func send(_ bytes: [UInt8]) async throws {
    let message = WebHostSocketMessage.data(bytes)
    if let outputContinuation {
      outputContinuation.yield(message)
    } else {
      pendingOutput.append(message)
    }
  }

  package func attach(
    client: AsyncStream<WebHostSocketMessage>
  ) -> AsyncStream<WebHostSocketMessage> {
    activeConnectionID += 1
    let connectionID = activeConnectionID

    if let previous = outputContinuation {
      previous.yield(.normalClose)
      previous.finish()
      outputContinuation = nil
    }

    return AsyncStream { continuation in
      outputContinuation = continuation
      for message in pendingOutput {
        continuation.yield(message)
      }
      pendingOutput.removeAll(keepingCapacity: true)

      let task = Task {
        for await message in client {
          self.receive(message)
        }
        self.detach(connectionID: connectionID)
      }

      continuation.onTermination = { _ in
        task.cancel()
        Task {
          await self.detach(connectionID: connectionID)
        }
      }
    }
  }

  private func receive(
    _ message: WebHostSocketMessage
  ) {
    switch message {
    case .text(let text):
      inputContinuation.yield(Array(text.utf8))
    case .data(let bytes):
      inputContinuation.yield(bytes)
    case .close(let code, let reason):
      outputContinuation?.yield(.close(code: code, reason: reason))
      inputContinuation.finish()
      outputContinuation?.finish()
    }
  }

  private func detach(
    connectionID: UInt64
  ) {
    guard activeConnectionID == connectionID else {
      return
    }
    outputContinuation = nil
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
