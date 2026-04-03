public enum HostedSceneSessionError: Error, Equatable, Sendable, CustomStringConvertible {
  case sceneNotFound(WindowIdentifier)

  public var description: String {
    switch self {
    case .sceneNotFound(let identifier):
      return "No scene found for identifier \(identifier.rawValue)."
    }
  }
}

@MainActor
public final class HostedSceneSession {
  public let descriptor: TerminalUISceneDescriptor

  private let configuration: WindowSceneConfiguration
  private let sessionName: String
  private let host: StreamingTerminalHost
  private let inputReader: InjectedTerminalInputReader
  private let signalReader: InProcessSignalReader
  private let scheduler: any FrameScheduling
  private let stateContainer: StateContainer<TerminalUISceneSessionState>
  private let focusTracker: FocusTracker
  private var runTask: Task<RunLoopExitReason, any Error>?

  public convenience init<A: App>(
    for app: A,
    sceneID: WindowIdentifier,
    initialSize: Size,
    appearance: TerminalAppearance,
    theme: ThemeColors? = nil,
    capabilityProfile: TerminalCapabilityProfile = .trueColor,
    onOutput: @escaping @Sendable (String) -> Void
  ) throws {
    let configurations = collectWindowSceneConfigurations(from: app.body)
    guard let configuration = configurations.first(where: { $0.identifier == sceneID }) else {
      throw HostedSceneSessionError.sceneNotFound(sceneID)
    }

    let sessionName = "\(String(reflecting: A.self)).\(sceneID.rawValue)"
    self.init(
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

  package init(
    configuration: WindowSceneConfiguration,
    isDefault: Bool,
    sessionName: String,
    initialSize: Size,
    appearance: TerminalAppearance,
    theme: ThemeColors? = nil,
    capabilityProfile: TerminalCapabilityProfile,
    onOutput: @escaping @Sendable (String) -> Void
  ) {
    self.configuration = configuration
    self.sessionName = sessionName
    descriptor = TerminalUISceneDescriptor(
      id: configuration.identifier,
      title: configuration.title,
      isDefault: isDefault
    )
    signalReader = InProcessSignalReader()
    host = StreamingTerminalHost(
      surfaceSize: initialSize,
      appearance: appearance,
      theme: theme,
      capabilityProfile: capabilityProfile,
      outputHandler: onOutput
    )
    inputReader = InjectedTerminalInputReader { [signalReader, host] message in
      switch message {
      case .resize(let size):
        host.updateSurfaceSize(size)
        signalReader.send("SIGWINCH")
      case .style(let style):
        host.updateStyle(style)
        signalReader.send("SIGWINCH")
      }
    }
    scheduler = FrameScheduler()
    stateContainer = StateContainer(
      initialState: TerminalUISceneSessionState(),
      invalidationIdentities: [configuration.rootIdentity]
    )
    focusTracker = FocusTracker(
      invalidationIdentities: [configuration.rootIdentity]
    )
  }

  public func start() async throws -> RunLoopExitReason {
    if let runTask {
      return try await runTask.value
    }

    let resources = SceneSessionResources(
      terminalHost: host,
      terminalInputReader: inputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      surfaceName: "hosted-\(configuration.identifier.rawValue)"
    )

    let task = Task {
      @MainActor [configuration, sessionName, stateContainer, focusTracker, resources] in
      let result = try await SceneSession.run(
        configuration: configuration,
        sessionName: sessionName,
        stateContainer: stateContainer,
        focusTracker: focusTracker,
        resources: resources
      )
      return result.exitReason
    }

    runTask = task

    do {
      let exitReason = try await task.value
      runTask = nil
      return exitReason
    } catch {
      runTask = nil
      throw error
    }
  }

  public func sendInput(
    _ bytes: [UInt8]
  ) {
    inputReader.send(bytes)
  }

  public func resize(
    to size: Size
  ) {
    host.updateSurfaceSize(size)
    signalReader.send("SIGWINCH")
  }

  public func updateAppearance(
    _ appearance: TerminalAppearance
  ) {
    host.updateAppearance(appearance)
    signalReader.send("SIGWINCH")
  }

  public func updateTheme(
    _ theme: ThemeColors?
  ) {
    host.updateTheme(theme)
    signalReader.send("SIGWINCH")
  }

  public func updateStyle(
    _ style: TerminalRenderStyle
  ) {
    host.updateStyle(style)
    signalReader.send("SIGWINCH")
  }

  public func stop() {
    inputReader.finish()
    signalReader.finish()
  }
}
