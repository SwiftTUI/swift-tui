import Core
public import TerminalUI
import View

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#endif

/// Orchestrates scene-based app launch, CLI mode routing, and scene lifecycle.
///
/// This is currently the public launch entry point for scene-based TerminalUI
/// apps, including the single-window case.
public enum MultiSceneLauncher {
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
    let configurations = collectWindowSceneConfigurations(from: app.body)
    if requestedManifestMode() {
      print(TerminalUIScenes.sceneManifest(from: configurations).jsonString)
      return
    }
    guard !configurations.isEmpty else {
      throw AppLaunchError.noScenes
    }

    let sessionName = String(reflecting: A.self)

    #if canImport(WASILibc)
      try await launchWASIApp(
        configurations: configurations,
        sessionName: sessionName
      )
    #else
      let appName = appNameFromType(A.self)
      let mode = try CLIMode.parse(CommandLine.arguments)

      switch mode {
      case .app(let instanceName):
        try await launchApp(
          configurations: configurations,
          sessionName: sessionName,
          appName: appName,
          instanceName: instanceName
        )
      case .listInstances:
        listInstances(appName: appName)
      case .listScenes(let selector):
        try listScenes(appName: appName, selector: selector)
      case .attach(let sceneID, let selector):
        try await attach(appName: appName, sceneID: sceneID, selector: selector)
      }
    #endif
  }

  @MainActor
  public static func sceneManifest<A: App>(
    for app: A
  ) -> TerminalUISceneManifest {
    TerminalUIScenes.sceneManifest(
      from: collectWindowSceneConfigurations(from: app.body)
    )
  }

  @MainActor
  public static func makeHostedSceneSession<A: App>(
    for app: A,
    sceneID: WindowIdentifier,
    initialSize: Size,
    appearance: TerminalAppearance,
    theme: ThemeColors? = nil,
    capabilityProfile: TerminalCapabilityProfile = .trueColor,
    onOutput: @escaping @Sendable (String) -> Void
  ) throws -> HostedSceneSession {
    let configurations = collectWindowSceneConfigurations(from: app.body)
    guard let configuration = configurations.first(where: { $0.identifier == sceneID }) else {
      throw HostedSceneSessionError.sceneNotFound(sceneID)
    }

    let sessionName = "\(String(reflecting: A.self)).\(sceneID.rawValue)"
    return HostedSceneSession(
      configuration: configuration,
      isDefault: configuration.identifier == configurations.first?.identifier,
      sessionName: sessionName,
      initialSize: initialSize,
      appearance: appearance,
      theme: theme,
      capabilityProfile: capabilityProfile,
      onOutput: onOutput
    )
  }

  @MainActor
  package static func run<S: Scene>(
    scene: S,
    sessionName: String,
    terminalHost: any TerminalHosting,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler()
  ) async throws -> RunLoopResult<MultiSceneRuntimeState> {
    let configuration = try primaryWindowSceneConfiguration(from: scene)
    let terminalInputReader: any TerminalInputReading =
      if let terminalInputReader = inputReader as? any TerminalInputReading {
        terminalInputReader
      } else {
        KeyboardOnlyInputAdapter(inputReader: inputReader)
      }

    return try await run(
      configuration: configuration,
      sessionName: sessionName,
      resources: .init(
        terminalHost: terminalHost,
        terminalInputReader: terminalInputReader,
        signalReader: signalReader,
        scheduler: scheduler
      )
    )
  }

  #if !canImport(WASILibc)
    @MainActor
    private static func launchApp(
      configurations: [WindowSceneConfiguration],
      sessionName: String,
      appName: String,
      instanceName: String?
    ) async throws {
      if configurations.count == 1 {
        _ = try await run(
          configuration: configurations[0],
          sessionName: sessionName,
          resources: .init(
            terminalHost: TerminalHost(),
            terminalInputReader: InputReader(),
            signalReader: defaultSignalReader()
          )
        )
        return
      }

      // Create scene runtimes
      var sceneRuntimes: [SceneRuntime] = []
      for (index, config) in configurations.enumerated() {
        let runtime = try SceneRuntime(
          configuration: config,
          isPrimary: index == 0
        )
        sceneRuntimes.append(runtime)
      }

      let registry = SceneInfoRegistry(runtimes: sceneRuntimes)

      // Start socket server
      let identifier = instanceName ?? String(getpid())
      let server = SceneDiscoveryServer(
        appName: appName,
        identifier: identifier,
        sceneProvider: {
          registry.scenes()
        },
        attachHandler: { sceneID in
          registry.attachResponse(for: sceneID)
        }
      )

      var sceneTasks: [Task<RunLoopResult<MultiSceneRuntimeState>, any Error>] = []
      for runtime in sceneRuntimes {
        let sceneID = runtime.configuration.identifier.rawValue
        let task = Task { @MainActor in
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

      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await server.run()
        }
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
    }
  #endif

  #if canImport(WASILibc)
    @MainActor
    private static func launchWASIApp(
      configurations: [WindowSceneConfiguration],
      sessionName: String
    ) async throws {
      let configuration = selectedWASIConfiguration(from: configurations)
      _ = try await run(
        configuration: configuration,
        sessionName: sessionName,
        resources: wasiSceneResources()
      )
    }
  #endif

  @MainActor
  private static func run(
    configuration: WindowSceneConfiguration,
    sessionName: String,
    resources: SceneSessionResources
  ) async throws -> RunLoopResult<MultiSceneRuntimeState> {
    let stateContainer = StateContainer(
      initialState: MultiSceneRuntimeState(),
      invalidationIdentities: [configuration.rootIdentity]
    )
    let focusTracker = FocusTracker(
      invalidationIdentities: [configuration.rootIdentity]
    )

    defer {
      if let inProcessSignalReader = resources.signalReader as? InProcessSignalReader {
        inProcessSignalReader.finish()
      }
    }

    return try await SceneSession.run(
      configuration: configuration,
      sessionName: sessionName,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      resources: resources
    )
  }

  #if !canImport(WASILibc)
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

    private static func listScenes(
      appName: String,
      selector: InstanceSelector
    ) throws {
      let instance = try SocketClient.selectInstance(
        appName: appName,
        selector: selector
      )

      let response = try SocketClient.sendRequest(
        socketPath: instance.socketPath,
        request: "LIST\n"
      )

      guard response.hasPrefix("OK ") else {
        print(response)
        return
      }

      let json = String(response.dropFirst(3))
      let scenes = parseSceneList(json)

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
      let instance = try SocketClient.selectInstance(
        appName: appName,
        selector: selector
      )

      let response = try SocketClient.sendRequest(
        socketPath: instance.socketPath,
        request: "ATTACH \(sceneID)\n"
      )

      guard response.hasPrefix("OK ") else {
        print(trimmed(response))
        return
      }

      let ptyPath = trimmed(String(response.dropFirst(3)))
      try await AttachProxy.run(slavePath: ptyPath)
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

  #if canImport(WASILibc)
    private static func selectedWASIConfiguration(
      from configurations: [WindowSceneConfiguration]
    ) -> WindowSceneConfiguration {
      guard let selector = wasiSceneSelector() else {
        return configurations[0]
      }

      return configurations.first(where: { $0.identifier.rawValue == selector })
        ?? configurations[0]
    }

    @MainActor
    private static func wasiSceneResources() -> SceneSessionResources {
      let signalReader = InProcessSignalReader()
      let initialStyle = wasiRenderStyle()
      let host = WebTerminalHost(
        surfaceSize: wasiSurfaceSize(),
        theme: initialStyle?.theme
      )
      if let initialStyle {
        host.updateStyle(initialStyle)
      }
      let inputReader = InputReader { message in
        switch message {
        case .resize(let size):
          host.updateSurfaceSize(size)
          signalReader.send("SIGWINCH")
        case .style(let style):
          host.updateStyle(style)
          signalReader.send("SIGWINCH")
        }
      }

      return .init(
        terminalHost: host,
        terminalInputReader: inputReader,
        signalReader: signalReader,
        surfaceName: "ghostty-web"
      )
    }

    private static func wasiRenderStyle() -> TerminalRenderStyle? {
      guard let encoded = environmentValue(named: "TUIGUI_RENDER_STYLE"),
        !encoded.isEmpty
      else {
        return nil
      }

      return TerminalRenderStyleCodec.decodeBase64(encoded)
    }

    private static func wasiSceneSelector() -> String? {
      if let selector = environmentValue(named: "TUIGUI_SCENE"), !selector.isEmpty {
        return selector
      }

      if let selector = environmentValue(named: "WEBAPP_SCENE"), !selector.isEmpty {
        return selector
      }

      return CommandLine.arguments.dropFirst().first
    }

    private static func wasiSurfaceSize() -> Size {
      let width = max(
        40,
        integerEnvironmentValue(named: "COLUMNS")
          ?? integerEnvironmentValue(named: "TUIGUI_COLUMNS")
          ?? integerEnvironmentValue(named: "WEBAPP_COLUMNS")
          ?? 120
      )
      let height = max(
        20,
        integerEnvironmentValue(named: "LINES")
          ?? integerEnvironmentValue(named: "TUIGUI_ROWS")
          ?? integerEnvironmentValue(named: "WEBAPP_ROWS")
          ?? 36
      )

      return .init(width: width, height: height)
    }

  #endif

  #if !canImport(WASILibc)
    /// Strips ASCII whitespace and newlines from both ends of a string.
    /// Foundation-free alternative to `.trimmingCharacters(in: .whitespacesAndNewlines)`.
    private static func trimmed(_ s: String) -> String {
      var chars = Array(s.unicodeScalars)
      while let first = chars.first, isAsciiWhitespace(first) { chars.removeFirst() }
      while let last = chars.last, isAsciiWhitespace(last) { chars.removeLast() }
      return String(String.UnicodeScalarView(chars))
    }

    private static func isAsciiWhitespace(_ scalar: Unicode.Scalar) -> Bool {
      switch scalar.value {
      case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20: true
      default: false
      }
    }

    /// Parses the JSON array of SceneInfo objects returned by the LIST command.
    ///
    /// Expected format: `[{"id":"...","title":...,"ptyPath":...,"isAttached":...}, ...]`
    ///
    /// This is a minimal hand-rolled parser — no Foundation required.
    private static func parseSceneList(_ json: String) -> [SceneInfo] {
      // Tokenise the JSON into a flat stream of tokens, then extract objects.
      var scenes: [SceneInfo] = []
      var index = json.startIndex

      func skipWhitespace() {
        while index < json.endIndex, isAsciiWhitespace(json.unicodeScalars[index]) {
          index = json.index(after: index)
        }
      }

      func peek() -> Character? {
        guard index < json.endIndex else { return nil }
        return json[index]
      }

      func consume(_ ch: Character) -> Bool {
        guard peek() == ch else { return false }
        index = json.index(after: index)
        return true
      }

      func parseString() -> String? {
        skipWhitespace()
        guard consume("\"") else { return nil }
        var result = ""
        while index < json.endIndex {
          let ch = json[index]
          index = json.index(after: index)
          if ch == "\"" { return result }
          if ch == "\\" {
            guard index < json.endIndex else { break }
            let escaped = json[index]
            index = json.index(after: index)
            switch escaped {
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "/": result.append("/")
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            default: result.append(escaped)
            }
          } else {
            result.append(ch)
          }
        }
        return nil  // unterminated string
      }

      func parseBool() -> Bool? {
        if json[index...].hasPrefix("true") {
          index = json.index(index, offsetBy: 4)
          return true
        }
        if json[index...].hasPrefix("false") {
          index = json.index(index, offsetBy: 5)
          return false
        }
        return nil
      }

      func parseNull() -> Bool {
        if json[index...].hasPrefix("null") {
          index = json.index(index, offsetBy: 4)
          return true
        }
        return false
      }

      func parseObject() -> SceneInfo? {
        skipWhitespace()
        guard consume("{") else { return nil }

        var id: String?
        var title: String?
        var ptyPath: String?
        var isAttached = false

        while true {
          skipWhitespace()
          if consume("}") { break }
          _ = consume(",")
          skipWhitespace()

          guard let key = parseString() else { break }
          skipWhitespace()
          guard consume(":") else { break }
          skipWhitespace()

          switch key {
          case "id":
            id = parseString()
          case "title":
            if !parseNull() { title = parseString() }
          case "ptyPath":
            if !parseNull() { ptyPath = parseString() }
          case "isAttached":
            isAttached = parseBool() ?? false
          default:
            // Skip unknown value (simple: read until , or })
            break
          }
        }

        guard let resolvedID = id else { return nil }
        return SceneInfo(id: resolvedID, title: title, ptyPath: ptyPath, isAttached: isAttached)
      }

      // Expect outer array
      skipWhitespace()
      guard consume("[") else { return [] }

      while true {
        skipWhitespace()
        if consume("]") { break }
        _ = consume(",")
        skipWhitespace()
        if let scene = parseObject() {
          scenes.append(scene)
        } else {
          break
        }
      }

      return scenes
    }
  #endif
}

private func requestedManifestMode() -> Bool {
  environmentValue(named: "TUIGUI_MODE") == "manifest"
}

private func integerEnvironmentValue(
  named name: String
) -> Int? {
  guard let value = environmentValue(named: name) else {
    return nil
  }
  return Int(value)
}

private func environmentValue(
  named name: String
) -> String? {
  unsafe name.withCString { cName in
    guard let rawValue = unsafe getenv(cName) else {
      return nil
    }
    return unsafe String(cString: rawValue)
  }
}

extension App {
  /// Default entry point for terminal-native `TerminalUI` apps.
  ///
  /// Mark a terminal-only app with `@main` to use this automatically, or call
  /// `MultiSceneLauncher.run(Self.self)` from a custom launcher when you need
  /// explicit error handling.
  public static func main() async throws {
    try await MultiSceneLauncher.run(Self.self)
  }
}

private final class KeyboardOnlyInputAdapter: TerminalInputReading {
  private let inputReader: any InputReading

  init(inputReader: any InputReading) {
    self.inputReader = inputReader
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let keyEvents = inputReader.events()
      let task = Task {
        for await keyPress in keyEvents {
          continuation.yield(.key(keyPress))
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
