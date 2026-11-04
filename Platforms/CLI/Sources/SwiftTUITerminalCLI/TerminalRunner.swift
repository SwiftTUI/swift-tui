import Foundation
public import SwiftTUIArguments
@_spi(Runners) import SwiftTUIRuntime

// The attach subsystem (PTY + Unix sockets) is POSIX-only; its dependency
// edge is platform-conditional, and these gates mirror that allowlist as a
// platform test rather than `canImport`: the whole-file-guarded attach
// module still builds (empty) on excluded platforms, so a stale module in
// the shared build directory makes `canImport` answer by build history.
#if os(macOS) || os(iOS) || os(Linux) || os(Android)
  import SwiftTUICLIAttach
#endif

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(ucrt)
  import CRT
#endif

/// Orchestrates scene-based app launch, CLI mode routing, and scene lifecycle.
///
/// This is the public CLI launch entry point for scene-based SwiftTUI apps.
public enum TerminalRunner {
  /// Constructs an app on the main actor and runs it through the terminal
  /// launcher flow.
  ///
  /// This is the recommended API to call from a standalone `main.swift` or a
  /// custom `static main()` implementation.
  @MainActor
  public static func run<A: App>(_ appType: A.Type) async throws {
    try await run(appType.init())
  }

  /// Runs a scene-based app. Call this from your app type's `main()`.
  @MainActor
  public static func run<A: App>(_ app: A) async throws {
    try await launch(app, configuration: .default)
  }

  /// Runs a scene-based app with explicit runtime configuration.
  ///
  /// Use this overload after an external parser parses CLI flags or environment variables.
  /// For example, `SwiftTUIArguments` can parse these values.
  @MainActor
  public static func run<A: App>(_ app: A, configuration: RuntimeConfiguration) async throws {
    try await launch(app, configuration: configuration)
  }

  @MainActor
  static func launch<A: App>(
    _ app: A,
    configuration: RuntimeConfiguration,
    arguments: [String] = CommandLine.arguments
  ) async throws {
    if configuration.printCompanionURL {
      try printCompanionURLs(appName: appNameFromType(A.self))
      return
    }
    let sessionName = String(reflecting: A.self)
    let appName = appNameFromType(A.self)
    let mode = CLIMode.parse(arguments)

    switch mode {
    case .app(let instanceName):
      guard configuration.web == nil else { throw TerminalRunnerError.webHostNotLinked }
      let selections = collectWindowSceneSelections(from: app.body)
      try validateWindowSceneIdentifiers(selections.map(\.descriptor))
      guard !selections.isEmpty else {
        throw AppLaunchError.noScenes
      }

      // Report deferred runtime issues after teardown restores the primary screen.
      defer {
        RuntimeIssueSink.flushDeferredStandardErrorIssues()
      }
      try await launchApp(
        selections: selections,
        sessionName: sessionName,
        appName: appName,
        instanceName: instanceName,
        configuration: configuration
      )
    case .listInstances:
      listInstances(appName: appName)
    case .listScenes(let selector):
      try listScenes(appName: appName, selector: selector)
    case .attach(let sceneID, let selector):
      try await attach(appName: appName, sceneID: sceneID, selector: selector)
    }
  }

  /// Runs a scene-based app type with explicit runtime configuration.
  @MainActor
  public static func run<A: App>(_ appType: A.Type, configuration: RuntimeConfiguration)
    async throws
  {
    try await run(appType.init(), configuration: configuration)
  }

  @MainActor
  private static func launchApp(
    selections: [SelectedWindowScene],
    sessionName: String,
    appName: String,
    instanceName: String?,
    configuration: RuntimeConfiguration
  ) async throws {
    let startsCompanion = shouldStartCompanion(
      configuration: configuration, isInteractive: interactiveTerminal)
    // Create scene runtimes
    var sceneRuntimes: [SceneRuntime] = []
    for (index, selection) in selections.enumerated() {
      let runtime = try SceneRuntime(
        selection: selection,
        isPrimary: index == 0,
        configuration: configuration,
        browserOnlySecondary: startsCompanion || configuration.output == .tui
      )
      sceneRuntimes.append(runtime)
    }

    // The local reader must reach every scene even with the browser companion disabled.
    let readerEndpoints =
      configuration.output == .tui ? sceneRuntimes.map { $0.enableCompanion() } : []
    let readerHub = TerminalReaderSceneHub(endpoints: readerEndpoints)
    sceneRuntimes.first?.connectReader(to: readerHub)
    defer { readerHub.reset() }

    let companion: SharedSceneCompanionSession?
    if startsCompanion {
      guard let start = SwiftTUILaunchRegistry.companionRunner else {
        throw TerminalRunnerError.webHostNotLinked
      }
      do {
        companion = try await start(sceneRuntimes.map { $0.enableCompanion() }, configuration)
      } catch {
        for runtime in sceneRuntimes { runtime.shutdown() }
        throw CompanionLaunchError(underlying: String(describing: error))
      }
    } else {
      companion = nil
    }

    #if os(Windows)
      let discovery: WindowsCompanionRegistration?
      do {
        discovery = try companion.map {
          try WindowsCompanionRegistration(app: appName, url: $0.url)
        }
      } catch {
        await companion?.stop()
        for runtime in sceneRuntimes { runtime.shutdown() }
        throw CompanionLaunchError(underlying: String(describing: error))
      }
      defer { discovery?.remove() }
    #endif

    #if os(macOS) || os(iOS) || os(Linux) || os(Android)
      let registry = SceneInfoRegistry(
        entries: sceneRuntimes.map { runtime in
          .init(
            id: runtime.selection.identifier,
            title: runtime.selection.title,
            ptyPath: runtime.attachPtyPath,
            isPrimary: runtime.isPrimary
          )
        }
      )

      // Start socket server
      let identifier = instanceName ?? String(getpid())
      let server = SceneDiscoveryServer(
        appName: appName,
        identifier: identifier,
        sceneProvider: {
          registry.scenes()
        },
        companionURL: companion?.url,
        attachHandler: { sceneID in
          registry.attachResponse(for: sceneID)
        }
      )
    #endif

    var sceneTasks: [Task<RunLoopResult<SceneSessionState>, any Error>] = []
    for runtime in sceneRuntimes {
      let sceneID = runtime.selection.identifier
      let task = Task { @MainActor in
        #if os(macOS) || os(iOS) || os(Linux) || os(Android)
          try await runtime.run(
            sessionName: sessionName,
            onAttachmentChanged: { isAttached in
              if isAttached {
                registry.markAttached(sceneID: sceneID)
              } else {
                registry.markDetached(sceneID: sceneID)
              }
            }
          )
        #else
          _ = sceneID
          return try await runtime.run(sessionName: sessionName)
        #endif
      }
      sceneTasks.append(task)
    }

    defer {
      for task in sceneTasks {
        task.cancel()
      }
      for runtime in sceneRuntimes {
        runtime.shutdown()
      }
    }

    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        #if os(macOS) || os(iOS) || os(Linux) || os(Android)
          group.addTask {
            try await server.run()
          }
        #endif
        for sceneTask in sceneTasks {
          group.addTask {
            _ = try await sceneTask.value
          }
        }

        do {
          _ = try await group.next()
        } catch {
          for task in sceneTasks {
            task.cancel()
          }
          for runtime in sceneRuntimes {
            runtime.shutdown()
          }
          group.cancelAll()
          throw error
        }

        for task in sceneTasks {
          task.cancel()
        }
        for runtime in sceneRuntimes {
          runtime.shutdown()
        }
        group.cancelAll()
      }
    } catch {
      await companion?.stop()
      throw error
    }
    await companion?.stop()
  }

  package static func shouldStartCompanion(configuration: RuntimeConfiguration, isInteractive: Bool)
    -> Bool
  {
    guard configuration.web == nil, configuration.output == .tui else { return false }
    switch configuration.companion {
    case .off: return false
    case .on: return true
    case .auto: return isInteractive && SwiftTUILaunchRegistry.companionRunner != nil
    }
  }

  private static var interactiveTerminal: Bool {
    #if os(Windows)
      _isatty(STDIN_FILENO) != 0 && _isatty(STDOUT_FILENO) != 0
    #else
      isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
    #endif
  }

  #if os(macOS) || os(iOS) || os(Linux) || os(Android)
    private static func printCompanionURLs(appName: String) throws {
      let instances = SocketClient.discoverInstances(appName: appName)
      guard !instances.isEmpty else { throw SocketClientError.noRunningInstances }
      for instance in instances {
        switch try discoveryRequest(.companion, socketPath: instance.socketPath) {
        case .companionURL(let url): print("Instance \(instance.identifier): \(url)")
        case .error(let message): print("Instance \(instance.identifier): ERR \(message)")
        default: throw SocketClientError.unexpectedResponse("Expected companion URL")
        }
      }
    }

    private static func listInstances(appName: String) {
      let instances = SocketClient.discoverInstances(appName: appName)
      if instances.isEmpty {
        print("No running instances found.")
        return
      }

      for instance in instances {
        if let name = instance.name {
          print("  \(name)  (PID \(instance.pid.map(String.init) ?? "?"))")
        } else {
          print("  PID \(instance.identifier)")
        }
      }
    }

    /// Selects a specific instance by selector strategy.
    ///
    /// Lives on the portable side (moved out of `SocketClient`) because the
    /// selector vocabulary is CLI-parsing state this module owns; the attach
    /// module only discovers instances. Internal (not private) so the
    /// selection strategy stays testable.
    static func selectInstance(
      appName: String,
      selector: InstanceSelector
    ) throws(SocketClientError) -> InstanceInfo {
      let instances = SocketClient.discoverInstances(appName: appName)
      guard !instances.isEmpty else { throw .noRunningInstances }

      switch selector {
      case .mostRecent:
        guard let instance = instances.last else { throw .noRunningInstances }
        return instance
      case .pid(let pid):
        let pidString = String(pid)
        guard let instance = instances.first(where: { $0.identifier == pidString }) else {
          throw .instanceNotFound("pid:\(pid)")
        }
        return instance
      case .name(let name):
        guard let instance = instances.first(where: { $0.identifier == name || $0.name == name })
        else {
          throw .instanceNotFound(name)
        }
        return instance
      }
    }

    private static func listScenes(
      appName: String,
      selector: InstanceSelector
    ) throws {
      let instance = try selectInstance(
        appName: appName,
        selector: selector
      )

      let response = try discoveryRequest(.list, socketPath: instance.socketPath)
      if case .error(let message) = response {
        print("ERR \(message)")
        return
      }
      guard case .sceneList(let scenes) = response else {
        throw SocketClientError.unexpectedResponse("Expected scene list")
      }

      for scene in scenes {
        let status = scene.isAttached ? "(attached)" : "(no client)"
        let title = scene.title.map { " — \($0)" } ?? ""
        print("  \(scene.id)\(title)  \(status)")
      }
    }

    private static func attach(
      appName: String,
      sceneID: String,
      selector: InstanceSelector
    ) async throws {
      let instance = try selectInstance(
        appName: appName,
        selector: selector
      )

      let response = try discoveryRequest(
        .attach(sceneID: WindowIdentifier(sceneID)), socketPath: instance.socketPath)
      if case .error(let message) = response {
        print("ERR \(message)")
        return
      }
      guard case .attachOK(let ptyPath) = response else {
        throw SocketClientError.unexpectedResponse("Expected PTY path")
      }
      try await AttachProxy.run(slavePath: ptyPath)
    }
  #else
    @MainActor
    private static func printCompanionURLs(appName: String) throws {
      #if os(Windows)
        let urls = try WindowsCompanionRegistration.urls(app: appName)
        guard !urls.isEmpty else { throw WindowsCompanionNotRunningError() }
        for url in urls { print(url) }
      #else
        throw SceneAttachUnavailableError()
      #endif
    }

    private static func listInstances(appName: String) {
      print(SceneAttachUnavailableError().description)
    }

    private static func listScenes(
      appName: String,
      selector: InstanceSelector
    ) throws {
      throw SceneAttachUnavailableError()
    }

    private static func attach(
      appName: String,
      sceneID: String,
      selector: InstanceSelector
    ) async throws {
      throw SceneAttachUnavailableError()
    }
  #endif

  // MARK: - Helpers

  private static func appNameFromType<A>(_ type: A.Type) -> String {
    let fullName = String(reflecting: type)
    if let lastDot = fullName.lastIndex(of: ".") {
      return String(fullName[fullName.index(after: lastDot)...])
    }
    return fullName
  }

  #if os(macOS) || os(iOS) || os(Linux) || os(Android)
    private static func discoveryRequest(_ request: SocketRequest, socketPath: String) throws
      -> SocketResponse
    {
      let reply = try SocketClient.sendRequest(socketPath: socketPath, request: request.encode())
      return try SocketResponse.parse(reply, for: request) {
        try JSONDecoder().decode([SceneInfo].self, from: Data($0.utf8))
      }
    }
  #endif
}

/// Thrown (or printed, for the non-throwing verb) when an attach-bearing verb
/// runs on a platform without the POSIX-only `SwiftTUICLIAttach` module.
private struct SceneAttachUnavailableError: Error, CustomStringConvertible {
  var description: String {
    "Scene attach is not supported on this platform: instance discovery and "
      + "attachment need the POSIX-only attach subsystem (PTY + Unix sockets)."
  }
}

// The `App.main()` terminal launch entry points (and their `exitLaunch`
// failure path) live in `App+TerminalLaunch.swift`.

public enum TerminalRunnerError: Error, Equatable, Sendable, CustomStringConvertible {
  case webHostNotLinked

  public var description: String {
    switch self {
    case .webHostNotLinked:
      return "--web requires the opt-in WebHost runner, but this executable was built with "
        + "terminal-only SwiftTUICLI. Link the SwiftTUI" + "WebHostCLI product and call "
        + "WebHostCLIRunner.run(...), or remove --web."
    }
  }
}

private struct CompanionLaunchError: Error, CustomStringConvertible {
  var underlying: String
  var description: String {
    "Unable to start the loopback browser accessibility companion: \(underlying) "
      + "Retry with --companion-port 0, or explicitly choose --companion off for terminal-only operation."
  }
}
