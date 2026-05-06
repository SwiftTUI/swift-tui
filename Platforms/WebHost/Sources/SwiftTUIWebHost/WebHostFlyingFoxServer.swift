import FlyingFox
import FlyingSocks
import Foundation

package struct WebHostFlyingFoxServer: WebHostServer {
  package init() {}

  package func start(
    configuration: WebHostConfig,
    token: WebHostToken,
    scene: WebHostSceneDescriptor
  ) async throws -> WebHostServerSession {
    let requestedPort = try UInt16(webHostPort: configuration.port)
    let address = try sockaddr_in.inet(ip4: configuration.bind, port: requestedPort)
    let channel = WebHostSceneChannel()
    let server = HTTPServer(address: address, logger: .disabled)
    let serverTask = Task {
      try await server.run()
    }

    let routeContext = RouteContext(
      bind: configuration.bind,
      token: token,
      scene: scene,
      channel: channel
    )

    await server.appendRoute("GET /") { request in
      routeContext.authorizedResponse(for: request) {
        do {
          return httpResponse(
            body: try WebHostBrowserBundle.indexHTML(token: token),
            contentType: "text/html; charset=utf-8"
          )
        } catch {
          return notFoundResponse()
        }
      }
    }
    await server.appendRoute("GET /scene-manifest.json") { request in
      routeContext.authorizedResponse(for: request) {
        httpResponse(
          body: Self.sceneManifest(scene),
          contentType: "application/json; charset=utf-8"
        )
      }
    }
    await server.appendRoute(HTTPRoute("GET /ws/scene/\(scene.id)")) { request in
      guard routeContext.isAuthorized(request) else {
        return forbiddenResponse()
      }

      let port = await selectedPort(from: server)
      let originPolicy = WebHostOriginPolicy(bind: configuration.bind)
      guard originPolicy.allows(origin: request.headers[HTTPHeader("Origin")], port: port ?? 0)
      else {
        return forbiddenResponse()
      }

      return
        try await WebSocketHTTPHandler
        .webSocket(WebHostFlyingFoxWebSocketHandler(channel: channel))
        .handleRequest(request)
    }
    await server.appendRoute("GET /*") { request in
      routeContext.authorizedResponse(for: request) {
        do {
          let resource = try WebHostBrowserBundle.resource(for: request.path)
          return httpResponse(body: resource.data, contentType: resource.contentType)
        } catch {
          return notFoundResponse()
        }
      }
    }

    do {
      try await server.waitUntilListening()
      guard let port = await selectedPort(from: server) else {
        await server.stop()
        serverTask.cancel()
        throw WebHostServerError.unableToDetermineListeningPort
      }

      return WebHostServerSession(
        baseURL: url(scheme: "http", bind: configuration.bind, port: port, path: "/"),
        webSocketURL: url(
          scheme: "ws",
          bind: configuration.bind,
          port: port,
          path: "/ws/scene/\(scene.id)",
          token: token
        ),
        token: token,
        channel: channel,
        stopHandler: {
          await server.stop()
          serverTask.cancel()
        }
      )
    } catch {
      await server.stop()
      serverTask.cancel()
      throw error
    }
  }

  private static func sceneManifest(
    _ scene: WebHostSceneDescriptor
  ) -> String {
    let title = scene.title.map { ",\"title\":\(jsonString($0))" } ?? ""
    return """
      {"defaultSceneId":\(jsonString(scene.id)),"scenes":[{"id":\(jsonString(scene.id))\(title),"isDefault":true}]}
      """
  }
}

private struct RouteContext: Sendable {
  var bind: String
  var token: WebHostToken
  var scene: WebHostSceneDescriptor
  var channel: WebHostSceneChannel

  func isAuthorized(
    _ request: HTTPRequest
  ) -> Bool {
    request.query["token"] == token.rawValue
  }

  func authorizedResponse(
    for request: HTTPRequest,
    response: () -> HTTPResponse
  ) -> HTTPResponse {
    guard isAuthorized(request) else {
      return forbiddenResponse()
    }
    return response()
  }
}

private struct WebHostFlyingFoxWebSocketHandler: WSMessageHandler {
  var channel: WebHostSceneChannel

  func makeMessages(
    for client: AsyncStream<WSMessage>
  ) async throws -> AsyncStream<WSMessage> {
    let mappedClient = AsyncStream<WebHostSocketMessage> { continuation in
      let task = Task {
        for await message in client {
          continuation.yield(webHostMessage(from: message))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
    let output = await channel.attach(client: mappedClient)
    return AsyncStream { continuation in
      let task = Task {
        for await message in output {
          continuation.yield(flyingFoxMessage(from: message))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private func webHostMessage(
  from message: WSMessage
) -> WebHostSocketMessage {
  switch message {
  case .text(let text):
    return .text(text)
  case .data(let data):
    return .data(Array(data))
  case .close:
    return .close
  }
}

private func flyingFoxMessage(
  from message: WebHostSocketMessage
) -> WSMessage {
  switch message {
  case .text(let text):
    return .text(text)
  case .data(let bytes):
    return .data(Data(bytes))
  case .close:
    return .close()
  }
}

private func httpResponse(
  body: String,
  contentType: String
) -> HTTPResponse {
  httpResponse(body: Data(body.utf8), contentType: contentType)
}

private func httpResponse(
  body: Data,
  contentType: String
) -> HTTPResponse {
  HTTPResponse(
    statusCode: .ok,
    headers: [.contentType: contentType],
    body: body
  )
}

private func forbiddenResponse() -> HTTPResponse {
  HTTPResponse(
    statusCode: .forbidden,
    headers: [.contentType: "text/plain; charset=utf-8"],
    body: Data("Forbidden\n".utf8)
  )
}

private func notFoundResponse() -> HTTPResponse {
  HTTPResponse(
    statusCode: .notFound,
    headers: [.contentType: "text/plain; charset=utf-8"],
    body: Data("Not Found\n".utf8)
  )
}

private func selectedPort(
  from server: HTTPServer
) async -> Int? {
  guard let address = await server.listeningAddress else {
    return nil
  }
  switch address {
  case .ip4(_, let port), .ip6(_, let port):
    return Int(port)
  case .unix:
    return nil
  }
}

private func url(
  scheme: String,
  bind: String,
  port: Int,
  path: String,
  token: WebHostToken? = nil
) -> URL {
  var components = URLComponents()
  components.scheme = scheme
  components.host = bind == "0.0.0.0" ? "127.0.0.1" : bind
  components.port = port
  components.path = path
  if let token {
    components.queryItems = [
      URLQueryItem(name: "token", value: token.rawValue)
    ]
  }
  return components.url!
}

private func jsonString(
  _ text: String
) -> String {
  var result = "\""
  for scalar in text.unicodeScalars {
    switch scalar.value {
    case 0x22:
      result += "\\\""
    case 0x5C:
      result += "\\\\"
    case 0x08:
      result += "\\b"
    case 0x0C:
      result += "\\f"
    case 0x0A:
      result += "\\n"
    case 0x0D:
      result += "\\r"
    case 0x09:
      result += "\\t"
    case 0x00...0x1F:
      var hex = String(scalar.value, radix: 16, uppercase: true)
      while hex.count < 4 {
        hex = "0" + hex
      }
      result += "\\u\(hex)"
    default:
      result.unicodeScalars.append(scalar)
    }
  }
  result += "\""
  return result
}

extension UInt16 {
  fileprivate init(
    webHostPort port: Int
  ) throws {
    guard port >= 0, port <= Int(UInt16.max) else {
      throw WebHostServerError.unsupportedPort(port)
    }
    self = UInt16(port)
  }
}
