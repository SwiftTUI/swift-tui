import TerminalUI

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
  private let stateContainer: StateContainer<MultiSceneRuntimeState>
  private let focusTracker: FocusTracker
  private let dynamicStateStore: DynamicStateStore
  private var runTask: Task<RunLoopExitReason, any Error>?

  package init(
    configuration: WindowSceneConfiguration,
    isDefault: Bool,
    sessionName: String,
    initialSize: Size,
    appearance: TerminalAppearance,
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
      capabilityProfile: capabilityProfile,
      outputHandler: onOutput
    )
    inputReader = InjectedTerminalInputReader { [signalReader, host] message in
      switch message {
      case .resize(let size):
        host.updateSurfaceSize(size)
        signalReader.send("SIGWINCH")
      }
    }
    scheduler = FrameScheduler()
    stateContainer = StateContainer(
      initialState: MultiSceneRuntimeState(),
      invalidationIdentities: [configuration.rootIdentity]
    )
    focusTracker = FocusTracker(
      invalidationIdentities: [configuration.rootIdentity]
    )
    dynamicStateStore = DynamicStateStore(
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

    let task = Task { @MainActor [configuration, sessionName, stateContainer, focusTracker, dynamicStateStore, resources] in
      let result = try await SceneSession.run(
        configuration: configuration,
        sessionName: sessionName,
        stateContainer: stateContainer,
        focusTracker: focusTracker,
        dynamicStateStore: dynamicStateStore,
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

  public func stop() {
    inputReader.finish()
    signalReader.finish()
  }
}
