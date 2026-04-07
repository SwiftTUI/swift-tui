import View

public enum HostedSceneSessionError: Error, Equatable, Sendable, CustomStringConvertible {
  case sceneNotFound(WindowIdentifier)

  public var description: String {
    switch self {
    case .sceneNotFound(let identifier):
      return "No scene found for identifier \(identifier.rawValue)."
    }
  }
}

package typealias HostedSceneRunner =
  (
    SceneSessionResources,
    StateContainer<TerminalUISceneSessionState>,
    FocusTracker
  ) async throws -> RunLoopResult<TerminalUISceneSessionState>

@MainActor
public final class HostedSceneSession {
  public let descriptor: TerminalUISceneDescriptor

  private let sessionName: String
  private let host: StreamingTerminalHost
  private let inputReader: InjectedTerminalInputReader
  private let signalReader: InProcessSignalReader
  private let scheduler: any FrameScheduling
  private let stateContainer: StateContainer<TerminalUISceneSessionState>
  private let focusTracker: FocusTracker
  private let runScene: HostedSceneRunner
  private var runTask: Task<RunLoopExitReason, any Error>?

  public convenience init<A: App>(
    for app: A,
    sceneID: WindowIdentifier,
    initialSize: Size,
    appearance: TerminalAppearance,
    theme: Theme? = nil,
    capabilityProfile: TerminalCapabilityProfile = .trueColor,
    onOutput: @escaping @Sendable (String) -> Void
  ) throws {
    let sessionName = "\(String(reflecting: A.self)).\(sceneID.rawValue)"
    var visitor = HostedSceneSelectionVisitor(
      sessionName: sessionName
    )
    guard
      let selection = withWindowSceneConfiguration(
        in: app.body,
        matching: sceneID,
        visitor: &visitor
      )
    else {
      throw HostedSceneSessionError.sceneNotFound(sceneID)
    }

    self.init(
      descriptor: selection.descriptor,
      rootIdentity: selection.rootIdentity,
      sessionName: sessionName,
      initialSize: initialSize,
      appearance: appearance,
      theme: theme,
      capabilityProfile: capabilityProfile,
      runScene: selection.runScene,
      onOutput: onOutput
    )
  }

  package init(
    descriptor: TerminalUISceneDescriptor,
    rootIdentity: Identity,
    sessionName: String,
    initialSize: Size,
    appearance: TerminalAppearance,
    theme: Theme? = nil,
    capabilityProfile: TerminalCapabilityProfile,
    runScene: @escaping HostedSceneRunner,
    onOutput: @escaping @Sendable (String) -> Void
  ) {
    self.descriptor = descriptor
    self.sessionName = sessionName
    self.runScene = runScene
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
      invalidationIdentities: [rootIdentity]
    )
    focusTracker = FocusTracker(
      invalidationIdentities: [rootIdentity]
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
      surfaceName: "hosted-\(descriptor.id.rawValue)"
    )

    let task = Task {
      @MainActor [runScene, stateContainer, focusTracker, resources] in
      let result = try await runScene(
        resources,
        stateContainer,
        focusTracker
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
    _ theme: Theme?
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

@MainActor
private struct HostedSceneSelection {
  let descriptor: TerminalUISceneDescriptor
  let rootIdentity: Identity
  let runScene: HostedSceneRunner
}

@MainActor
private struct HostedSceneSelectionVisitor: WindowSceneConfigurationVisitor {
  let sessionName: String

  mutating func visit<Content: View>(
    descriptor: TerminalUISceneDescriptor,
    configuration: WindowSceneConfiguration<Content>
  ) -> WindowSceneConfigurationVisitResult<HostedSceneSelection> {
    let sessionName = self.sessionName

    return .finish(
      HostedSceneSelection(
        descriptor: descriptor,
        rootIdentity: configuration.rootIdentity,
        runScene: { resources, stateContainer, focusTracker in
          try await SceneSession.run(
            configuration: configuration,
            sessionName: sessionName,
            stateContainer: stateContainer,
            focusTracker: focusTracker,
            resources: resources
          )
        }
      )
    )
  }
}
