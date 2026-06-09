#if os(Android)
  @_spi(MainActorUtilities) import _Concurrency
#endif
import SwiftTUIViews

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
    StateContainer<SceneSessionState>,
    FocusTracker
  ) async throws -> RunLoopResult<SceneSessionState>

@MainActor
public final class HostedSceneSession {
  public let descriptor: SceneDescriptor
  public let surface: HostedRasterSurface
  public private(set) var currentFocusPresentation: FocusPresentation = .none

  private let sessionName: String
  private let inputReader: InjectedTerminalInputReader
  private let signalReader: InProcessSignalReader
  private let scheduler: any FrameScheduling
  private let stateContainer: StateContainer<SceneSessionState>
  private let focusTracker: FocusTracker
  private let runScene: HostedSceneRunner
  private let renderMode: RuntimeRenderMode?
  private let onFocusPresentationChange: (@MainActor @Sendable (FocusPresentation) -> Void)?
  private let runtimeIssueSink: RuntimeIssueSink?
  private var runTask: Task<RunLoopExitReason, any Error>?
  private var shutdownWaiter: Task<Void, Never>?

  public convenience init<A: App>(
    for app: A,
    sceneID: WindowIdentifier,
    surface: HostedRasterSurface,
    runtimeIssueSink: RuntimeIssueSink? = nil,
    onFocusPresentationChange:
      (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) throws {
    let sessionName = "\(String(reflecting: A.self)).\(sceneID.rawValue)"
    guard
      let selection = collectWindowSceneSelections(from: app.body).first(where: {
        $0.identifier == sceneID
      })
    else {
      throw HostedSceneSessionError.sceneNotFound(sceneID)
    }

    self.init(
      descriptor: selection.descriptor,
      rootIdentity: selection.rootIdentity,
      sessionName: sessionName,
      surface: surface,
      runScene: { resources, stateContainer, focusTracker in
        try await selection.run(
          sessionName: sessionName,
          resources: resources,
          stateContainer: stateContainer,
          focusTracker: focusTracker
        )
      },
      renderMode: nil,
      runtimeIssueSink: runtimeIssueSink,
      onFocusPresentationChange: onFocusPresentationChange
    )
  }

  @_spi(Runners)
  public convenience init<A: App>(
    for app: A,
    sceneID: WindowIdentifier,
    surface: HostedRasterSurface,
    renderMode: RuntimeRenderMode?,
    runtimeIssueSink: RuntimeIssueSink? = nil,
    onFocusPresentationChange:
      (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) throws {
    let sessionName = "\(String(reflecting: A.self)).\(sceneID.rawValue)"
    guard
      let selection = collectWindowSceneSelections(from: app.body).first(where: {
        $0.identifier == sceneID
      })
    else {
      throw HostedSceneSessionError.sceneNotFound(sceneID)
    }

    self.init(
      descriptor: selection.descriptor,
      rootIdentity: selection.rootIdentity,
      sessionName: sessionName,
      surface: surface,
      runScene: { resources, stateContainer, focusTracker in
        try await selection.run(
          sessionName: sessionName,
          resources: resources,
          stateContainer: stateContainer,
          focusTracker: focusTracker
        )
      },
      renderMode: renderMode,
      runtimeIssueSink: runtimeIssueSink,
      onFocusPresentationChange: onFocusPresentationChange
    )
  }

  package init(
    descriptor: SceneDescriptor,
    rootIdentity: Identity,
    sessionName: String,
    surface: HostedRasterSurface,
    runScene: @escaping HostedSceneRunner,
    renderMode: RuntimeRenderMode? = nil,
    runtimeIssueSink: RuntimeIssueSink? = nil,
    onFocusPresentationChange:
      (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    self.descriptor = descriptor
    self.sessionName = sessionName
    self.runScene = runScene
    self.renderMode = renderMode
    signalReader = InProcessSignalReader()
    self.surface = surface
    inputReader = InjectedTerminalInputReader { [signalReader, surface] message in
      switch message {
      case .resize(let size):
        surface.updateSurfaceSize(size)
        signalReader.send("SIGWINCH")
      case .style(let style):
        surface.updateStyle(style)
        signalReader.send("SIGWINCH")
      }
    }
    scheduler = FrameScheduler()
    stateContainer = StateContainer(
      initialState: SceneSessionState(),
      invalidationIdentities: [rootIdentity]
    )
    focusTracker = FocusTracker(
      invalidationIdentities: [rootIdentity]
    )
    self.runtimeIssueSink = runtimeIssueSink
    self.onFocusPresentationChange = onFocusPresentationChange
  }

  public func start() async throws -> RunLoopExitReason {
    if let runTask {
      return try await runTask.value
    }

    let resources = SceneSessionResources(
      presentationSurface: surface,
      terminalInputReader: inputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      surfaceName: "hosted-\(descriptor.id.rawValue)",
      renderMode: renderMode,
      focusPresentationHandler: { [weak self] presentation in
        self?.updateCurrentFocusPresentation(presentation)
      }
    )
    resources.runtimeIssueSink = runtimeIssueSink

    #if os(Android)
      let task = Task.immediate {
        @MainActor [runScene, stateContainer, focusTracker, resources] in
        let result = try await runScene(
          resources,
          stateContainer,
          focusTracker
        )
        return result.exitReason
      }
    #else
      let task = Task {
        @MainActor [runScene, stateContainer, focusTracker, resources] in
        let result = try await runScene(
          resources,
          stateContainer,
          focusTracker
        )
        return result.exitReason
      }
    #endif

    runTask = task

    do {
      let exitReason = try await task.value
      runTask = nil
      shutdownWaiter = nil
      updateCurrentFocusPresentation(.none)
      return exitReason
    } catch {
      runTask = nil
      shutdownWaiter = nil
      updateCurrentFocusPresentation(.none)
      throw error
    }
  }

  public func sendInput(
    _ bytes: [UInt8]
  ) {
    inputReader.send(bytes)
  }

  public func send(
    _ event: InputEvent
  ) {
    inputReader.send(event)
  }

  public func send(
    _ events: [InputEvent]
  ) {
    inputReader.send(events)
  }

  @_spi(Runners) @discardableResult public func flushPendingInputEventsForTesting()
    -> [InputEvent]
  {
    inputReader.flushPendingCoalescedMouseEvents()
  }

  public func requestSurfaceRefresh() {
    signalReader.send("SIGWINCH")
  }

  public func stop() {
    _ = beginStop()
  }

  public func stopAndWait() async throws -> RunLoopExitReason? {
    guard let runTask = beginStop() else {
      return nil
    }
    let exitReason = try await runTask.value
    await shutdownWaiter?.value
    return exitReason
  }
}

extension HostedSceneSession {
  private func beginStop() -> Task<RunLoopExitReason, any Error>? {
    inputReader.finish()
    signalReader.finish()
    updateCurrentFocusPresentation(.none)
    guard let runTask else {
      return nil
    }
    if shutdownWaiter == nil {
      shutdownWaiter = Task { _ = await runTask.result }
    }
    return runTask
  }
}

extension HostedSceneSession {
  private func updateCurrentFocusPresentation(
    _ presentation: FocusPresentation
  ) {
    guard currentFocusPresentation != presentation else {
      return
    }

    currentFocusPresentation = presentation
    onFocusPresentationChange?(presentation)
  }
}
