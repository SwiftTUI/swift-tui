@_spi(Runners) public import SwiftTUIRuntime

/// Errors thrown while selecting or launching a WebHost scene.
public enum WebHostRunnerError: Error, Equatable, Sendable, CustomStringConvertible {
  @available(
    *, deprecated, message: "WebHost now retains all app scenes; this error is no longer thrown."
  )
  case multipleScenesUnsupported(count: Int)
  case sceneNotFound(WindowIdentifier, available: [WindowIdentifier])

  public var description: String {
    switch self {
    case .multipleScenesUnsupported(let count):
      return "Legacy single-scene WebHost could not launch \(count) scenes."
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

/// Launches a SwiftTUI app through the localhost WebHost runtime.
public enum WebHostRunner {
  /// Constructs an app on the main actor and runs it through WebHost.
  @MainActor
  public static func run<A: App>(_ appType: A.Type) async throws {
    try await run(appType.init())
  }

  /// Constructs an app on the main actor and runs it with explicit runtime configuration.
  @MainActor
  public static func run<A: App>(
    _ appType: A.Type,
    configuration: RuntimeConfiguration
  ) async throws {
    try await run(appType.init(), configuration: configuration)
  }

  /// Runs an app through WebHost with the default runtime configuration.
  @MainActor
  public static func run<A: App>(_ app: A) async throws {
    try await run(app, configuration: .default)
  }

  /// Runs an app through WebHost with explicit runtime configuration.
  @MainActor
  public static func run<A: App>(
    _ app: A,
    configuration: RuntimeConfiguration
  ) async throws {
    try await run(
      app,
      configuration: configuration,
      server: WebHostLoopbackServer(),
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
    try validateWindowSceneIdentifiers(selections.map(\.descriptor))
    guard !selections.isEmpty else {
      throw AppLaunchError.noScenes
    }

    let webConfiguration = configuration.web.map(WebHostConfig.init) ?? WebHostConfig()
    let selection = try selectedScene(
      from: selections,
      requestedSceneID: webConfiguration.sceneID
    )
    let scenes = selections.map { candidate in
      WebHostSceneDescriptor(
        id: candidate.identifier.rawValue, title: candidate.title,
        isDefault: candidate.identifier == selection.identifier)
    }
    let session = try await server.start(
      configuration: webConfiguration, token: token, scenes: scenes)

    bannerWriter.write(WebHostBanner.message(for: session, configuration: webConfiguration))
    if webConfiguration.openBrowser {
      do { try browserOpener.open(session.url(path: "/")) } catch {
        await session.stop()
        throw error
      }
    }

    // Every scene keeps one graph owner for the app lifetime. Browser visibility
    // and connection changes attach presentation/input to these existing owners.
    let sceneTasks = selections.map { selection in
      Task { @MainActor in
        let channel = session.channels[selection.identifier.rawValue]!
        let transport = WebSocketSurfaceTransport(
          surfaceSize: CellSize(width: 80, height: 24), sink: channel)
        let signalReader = InProcessSignalReader()
        let inputReader = WebSocketInputReader(
          channel: channel, transport: transport, signalReader: signalReader)
        let resources = SceneSessionResources(
          presentationSurface: transport, terminalInputReader: inputReader,
          signalReader: signalReader, surfaceName: "web", runtimeConfiguration: configuration)
        resources.runtimeIssueSink = RuntimeIssueSink { issue in
          try? transport.notifyRuntimeIssue(issue)
        }
        _ = try await runSelectedScene(
          selection: selection, sessionName: String(reflecting: A.self), resources: resources)
      }
    }

    do {
      try await withTaskCancellationHandler {
        try await withThrowingTaskGroup(of: Void.self) { group in
          defer {
            for task in sceneTasks { task.cancel() }
            group.cancelAll()
          }
          for task in sceneTasks { group.addTask { try await task.value } }
          _ = try await group.next()
        }
      } onCancel: {
        for task in sceneTasks { task.cancel() }
        Task {
          await session.stop()
        }
      }
      await session.stop()
    } catch {
      for task in sceneTasks { task.cancel() }
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
