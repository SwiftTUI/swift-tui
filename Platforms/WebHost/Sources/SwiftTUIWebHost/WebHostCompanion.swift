import Foundation
@_spi(Runners) import SwiftTUIRuntime

/// Attaches transport to existing scene owners; never constructs app state.
package enum WebHostCompanion {
  @MainActor
  package static func start(
    endpoints: [SharedSceneEndpoint], configuration: RuntimeConfiguration,
    server: any WebHostServer = WebHostLoopbackServer(), token: WebHostToken = WebHostToken()
  ) async throws -> SharedSceneCompanionSession {
    let session = try await server.start(
      configuration: WebHostConfig(bind: "127.0.0.1", port: configuration.companionPort),
      token: token,
      scenes: endpoints.enumerated().map { index, endpoint in
        .init(
          id: endpoint.descriptor.id.rawValue, title: endpoint.descriptor.title,
          isDefault: index == 0)
      })
    for endpoint in endpoints {
      let channel = session.channels[endpoint.descriptor.id.rawValue]!
      let transport = WebSocketSurfaceTransport(
        surfaceSize: endpoint.surface.surfaceSize, sink: channel)
      endpoint.surface.attachBrowser(transport, isConnected: { transport.isConnected })
      endpoint.input.attachBrowser(
        WebSocketInputReader(
          channel: channel, transport: transport, signalReader: endpoint.browserSignals,
          sharedViewportRequired: true))
      let terminalIssues = endpoint.resources.runtimeIssueSink
      endpoint.resources.runtimeIssueSink = RuntimeIssueSink { issue in
        terminalIssues?.report(issue)
        if transport.isConnected { try? transport.notifyRuntimeIssue(issue) }
      }
    }
    var url = URLComponents(url: session.url(path: "/"), resolvingAgainstBaseURL: false)!
    url.queryItems = (url.queryItems ?? []) + [URLQueryItem(name: "renderer", value: "canvas")]
    return SharedSceneCompanionSession(
      url: url.url!.absoluteString, stop: { await session.stop() })
  }
}
