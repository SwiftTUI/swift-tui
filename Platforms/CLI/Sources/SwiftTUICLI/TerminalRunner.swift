import Foundation
public import SwiftTUIArguments
@_spi(Runners) import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
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
  /// Use this overload when CLI flags or env vars have been parsed externally
  /// (e.g., by `SwiftTUIArguments`).
  @MainActor
  public static func run<A: App>(_ app: A, configuration: RuntimeConfiguration) async throws {
    try await launch(app, configuration: configuration)
  }

  @MainActor
  private static func launch<A: App>(
    _ app: A,
    configuration: RuntimeConfiguration
  ) async throws {
    if configuration.web != nil {
      throw TerminalRunnerError.webHostNotLinked
    }

    let selections = collectWindowSceneSelections(from: app.body)
    guard !selections.isEmpty else {
      throw AppLaunchError.noScenes
    }

    let sessionName = String(reflecting: A.self)
    let appName = appNameFromType(A.self)
    let mode = CLIMode.parse(CommandLine.arguments)

    switch mode {
    case .app(let instanceName):
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
  static func run<S: Scene>(
    scene: S,
    sessionName: String,
    presentationSurface: any PresentationSurface,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler()
  ) async throws -> RunLoopResult<SceneSessionState> {
    let selections = collectWindowSceneSelections(from: scene)
    guard !selections.isEmpty else {
      throw AppLaunchError.noScenes
    }
    guard selections.count == 1 else {
      throw SingleSceneRuntimeError.multipleScenesUnsupported(count: selections.count)
    }
    let selection = selections[0]
    let terminalInputReader: any TerminalInputReading =
      if let terminalInputReader = inputReader as? any TerminalInputReading {
        terminalInputReader
      } else {
        KeyboardOnlyInputAdapter(inputReader: inputReader)
      }

    let resources = SceneSessionResources(
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler
    )
    resources.runtimeIssueSink = .standardError
    return try await runSelectedScene(
      selection: selection,
      sessionName: sessionName,
      resources: resources
    )
  }

  @MainActor
  private static func launchApp(
    selections: [SelectedWindowScene],
    sessionName: String,
    appName: String,
    instanceName: String?,
    configuration: RuntimeConfiguration
  ) async throws {
    // Create scene runtimes
    var sceneRuntimes: [SceneRuntime] = []
    for (index, selection) in selections.enumerated() {
      let runtime = try SceneRuntime(
        selection: selection,
        isPrimary: index == 0,
        configuration: configuration
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

    var sceneTasks: [Task<RunLoopResult<SceneSessionState>, any Error>] = []
    for runtime in sceneRuntimes {
      let sceneID = runtime.selection.identifier.rawValue
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

    defer {
      if let inProcessSignalReader = resources.signalReader as? InProcessSignalReader {
        inProcessSignalReader.finish()
      }
    }

    return try await selection.run(
      sessionName: sessionName,
      resources: resources,
      stateContainer: stateContainer,
      focusTracker: focusTracker
    )
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

  // MARK: - Helpers

  private static func appNameFromType<A>(_ type: A.Type) -> String {
    let fullName = String(reflecting: type)
    if let lastDot = fullName.lastIndex(of: ".") {
      return String(fullName[fullName.index(after: lastDot)...])
    }
    return fullName
  }

  /// Strips ASCII whitespace and newlines from both ends of a string.
  /// Hand-rolled trim helper kept for symmetry with parseSceneList. Foundation is imported in this
  /// file but the helper predates the import and works fine; not worth churning.
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
  /// Minimal hand-rolled JSON parser. Foundation is imported in this file (for ProcessInfo) and
  /// JSONDecoder could replace this, but the parser is small and tested; deferred to avoid scope creep.
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
}

private enum SingleSceneRuntimeError: Error, Equatable, Sendable, CustomStringConvertible {
  case multipleScenesUnsupported(count: Int)

  var description: String {
    switch self {
    case .multipleScenesUnsupported(let count):
      return "Expected exactly one scene, but received \(count)."
    }
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
