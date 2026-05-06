@_spi(Runners) public import SwiftTUI

public enum WebHostRunnerError: Error, Equatable, Sendable, CustomStringConvertible {
  case multipleScenesUnsupported(count: Int)

  public var description: String {
    switch self {
    case .multipleScenesUnsupported(let count):
      return "SwiftTUIWebHost V1 supports exactly one scene, but received \(count)."
    }
  }
}

public enum WebHostRunner {
  @MainActor
  public static func run<A: App>(_ appType: A.Type) async throws {
    try await run(appType.init())
  }

  @MainActor
  public static func run<A: App>(
    _ appType: A.Type,
    configuration: RuntimeConfiguration
  ) async throws {
    try await run(appType.init(), configuration: configuration)
  }

  @MainActor
  public static func run<A: App>(_ app: A) async throws {
    try await run(app, configuration: .default)
  }

  @MainActor
  public static func run<A: App>(
    _ app: A,
    configuration: RuntimeConfiguration
  ) async throws {
    try await run(
      app,
      configuration: configuration,
      server: WebHostFlyingFoxServer(),
      token: WebHostToken(),
      browserOpener: SystemBrowserOpener(),
      bannerWriter: StandardWebHostBannerWriter()
    )
  }

  @MainActor
  package static func run<A: App>(
    _ app: A,
    configuration: RuntimeConfiguration,
    server: any WebHostServer,
    token: WebHostToken,
    browserOpener: any BrowserOpening,
    bannerWriter: any WebHostBannerWriting
  ) async throws {
    let selections = collectWindowSceneSelections(from: app.body)
    guard !selections.isEmpty else {
      throw AppLaunchError.noScenes
    }
    guard selections.count == 1 else {
      throw WebHostRunnerError.multipleScenesUnsupported(count: selections.count)
    }

    let selection = selections[0]
    let webConfiguration = configuration.web.map(WebHostConfig.init) ?? WebHostConfig()
    let scene = WebHostSceneDescriptor(
      id: selection.identifier.rawValue,
      title: selection.title,
      isDefault: selection.isDefault
    )
    let session = try await server.start(
      configuration: webConfiguration,
      token: token,
      scene: scene
    )

    bannerWriter.write(WebHostBanner.message(for: session, configuration: webConfiguration))
    if webConfiguration.openBrowser {
      try browserOpener.open(session.url(path: "/"))
    }

    let transport = WebSocketSurfaceTransport(
      surfaceSize: CellSize(width: 80, height: 24),
      sink: session.channel
    )
    let inputReader = WebSocketInputReader(source: session.channel, transport: transport)
    let sceneTask = Task { @MainActor in
      try await runSelectedScene(
        selection: selection,
        sessionName: String(reflecting: A.self),
        resources: SceneSessionResources(
          presentationSurface: transport,
          terminalInputReader: inputReader,
          surfaceName: "web",
          runtimeConfiguration: configuration
        )
      )
    }

    do {
      try await withTaskCancellationHandler {
        _ = try await sceneTask.value
      } onCancel: {
        sceneTask.cancel()
        Task {
          await session.stop()
        }
      }
      await session.stop()
    } catch {
      sceneTask.cancel()
      await session.stop()
      throw error
    }
  }

  @MainActor
  private static func runSelectedScene(
    selection: SelectedWindowScene,
    sessionName: String,
    resources: SceneSessionResources
  ) async throws -> RunLoopResult<SceneSessionState> {
    let stateContainer = StateContainer(
      initialState: SceneSessionState(),
      invalidationIdentities: [selection.rootIdentity]
    )
    let focusTracker = FocusTracker(
      invalidationIdentities: [selection.rootIdentity]
    )

    return try await selection.run(
      sessionName: sessionName,
      resources: resources,
      stateContainer: stateContainer,
      focusTracker: focusTracker
    )
  }
}
