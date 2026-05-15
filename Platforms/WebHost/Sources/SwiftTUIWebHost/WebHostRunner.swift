@_spi(Runners) public import SwiftTUIRuntime

public enum WebHostRunnerError: Error, Equatable, Sendable, CustomStringConvertible {
  case multipleScenesUnsupported(count: Int)
  case sceneNotFound(WindowIdentifier, available: [WindowIdentifier])

  public var description: String {
    switch self {
    case .multipleScenesUnsupported(let count):
      return "SwiftTUIWebHost V1 supports exactly one scene, but received \(count)."
    case .sceneNotFound(let identifier, let available):
      let availableList = available.map(\.rawValue).joined(separator: ", ")
      if availableList.isEmpty {
        return "No WebHost scene found for identifier \(identifier.rawValue)."
      }
      return
        "No WebHost scene found for identifier \(identifier.rawValue). Available scenes: \(availableList)."
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

    let webConfiguration = configuration.web.map(WebHostConfig.init) ?? WebHostConfig()
    let selection = try selectedScene(
      from: selections,
      requestedSceneID: webConfiguration.sceneID
    )
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
      let resources = SceneSessionResources(
        presentationSurface: transport,
        terminalInputReader: inputReader,
        surfaceName: "web",
        runtimeConfiguration: configuration
      )
      resources.runtimeIssueSink = RuntimeIssueSink { issue in
        try? transport.notifyRuntimeIssue(issue)
      }
      _ = try await runSelectedScene(
        selection: selection,
        sessionName: String(reflecting: A.self),
        resources: resources
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
  private static func selectedScene(
    from selections: [SelectedWindowScene],
    requestedSceneID: WindowIdentifier?
  ) throws -> SelectedWindowScene {
    if let requestedSceneID {
      guard let selection = selections.first(where: { $0.identifier == requestedSceneID }) else {
        throw WebHostRunnerError.sceneNotFound(
          requestedSceneID,
          available: selections.map(\.identifier)
        )
      }
      return selection
    }

    return selections.first(where: \.isDefault) ?? selections[0]
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
