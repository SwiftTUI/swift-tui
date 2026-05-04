import Synchronization
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

private protocol HostedScenePresentationSurface: PresentationSurface, DamageAwarePresentationSurface, Sendable {
  func updateSurfaceSize(_ surfaceSize: CellSize)
  func updateAppearance(_ appearance: TerminalAppearance)
  func updateTheme(_ theme: Theme?)
  func updateStyle(_ style: TerminalRenderStyle)
  func updateSurfaceCapabilities(_ capabilities: TerminalSurfaceCapabilities)
}

extension StreamingTerminalHost: HostedScenePresentationSurface {}

@MainActor
public final class HostedSceneSession {
  public let descriptor: SceneDescriptor
  public private(set) var currentFocusPresentation: FocusPresentation = .none

  private let sessionName: String
  private let host: any HostedScenePresentationSurface
  private let inputReader: InjectedTerminalInputReader
  private let signalReader: InProcessSignalReader
  private let scheduler: any FrameScheduling
  private let stateContainer: StateContainer<SceneSessionState>
  private let focusTracker: FocusTracker
  private let runScene: HostedSceneRunner
  private let onFocusPresentationChange: (@MainActor @Sendable (FocusPresentation) -> Void)?
  private var runTask: Task<RunLoopExitReason, any Error>?
  private var shutdownWaiter: Task<Void, Never>?

  public convenience init<A: App>(
    for app: A,
    sceneID: WindowIdentifier,
    initialSize: CellSize,
    appearance: TerminalAppearance,
    theme: Theme? = nil,
    capabilityProfile: TerminalCapabilityProfile = .trueColor,
    onOutput: @escaping @Sendable (String) -> Void,
    onFocusPresentationChange:
      (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
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
      host: StreamingTerminalHost(
        surfaceSize: initialSize,
        appearance: appearance,
        theme: theme,
        capabilityProfile: capabilityProfile,
        outputHandler: onOutput
      ),
      runScene: selection.runScene,
      onFocusPresentationChange: onFocusPresentationChange
    )
  }

  package convenience init(
    descriptor: SceneDescriptor,
    rootIdentity: Identity,
    sessionName: String,
    initialSize: CellSize,
    appearance: TerminalAppearance,
    theme: Theme? = nil,
    capabilityProfile: TerminalCapabilityProfile,
    runScene: @escaping HostedSceneRunner,
    onOutput: @escaping @Sendable (String) -> Void,
    onFocusPresentationChange:
      (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    self.init(
      descriptor: descriptor,
      rootIdentity: rootIdentity,
      sessionName: sessionName,
      host: StreamingTerminalHost(
        surfaceSize: initialSize,
        appearance: appearance,
        theme: theme,
        capabilityProfile: capabilityProfile,
        outputHandler: onOutput
      ),
      runScene: runScene,
      onFocusPresentationChange: onFocusPresentationChange
    )
  }

  public convenience init<A: App>(
    for app: A,
    sceneID: WindowIdentifier,
    initialSize: CellSize,
    appearance: TerminalAppearance,
    theme: Theme? = nil,
    capabilityProfile: TerminalCapabilityProfile = .trueColor,
    onSurface: @escaping @MainActor @Sendable (RasterSurface) -> Void,
    onFocusPresentationChange:
      (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
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
      host: HostedRasterSurface(
        surfaceSize: initialSize,
        appearance: appearance,
        theme: theme,
        capabilityProfile: capabilityProfile
      ) { surface in
        Task { @MainActor in
          onSurface(surface)
        }
      },
      runScene: selection.runScene,
      onFocusPresentationChange: onFocusPresentationChange
    )
  }

  private init(
    descriptor: SceneDescriptor,
    rootIdentity: Identity,
    sessionName: String,
    host: any HostedScenePresentationSurface,
    runScene: @escaping HostedSceneRunner,
    onFocusPresentationChange:
      (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    self.descriptor = descriptor
    self.sessionName = sessionName
    self.runScene = runScene
    signalReader = InProcessSignalReader()
    self.host = host
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
      initialState: SceneSessionState(),
      invalidationIdentities: [rootIdentity]
    )
    focusTracker = FocusTracker(
      invalidationIdentities: [rootIdentity]
    )
    self.onFocusPresentationChange = onFocusPresentationChange
  }

  public func start() async throws -> RunLoopExitReason {
    if let runTask {
      return try await runTask.value
    }

    let resources = SceneSessionResources(
      presentationSurface: host,
      terminalInputReader: inputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      surfaceName: "hosted-\(descriptor.id.rawValue)",
      focusPresentationHandler: { [weak self] presentation in
        self?.updateCurrentFocusPresentation(presentation)
      }
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

  public func resize(
    to size: CellSize
  ) {
    host.updateSurfaceSize(size)
    signalReader.send("SIGWINCH")
  }

  public func resize(
    to size: CellSize,
    cellPixelSize: PixelSize?
  ) {
    resize(
      to: size,
      cellPixelSize: cellPixelSize,
      pointerInputCapabilities: .cellOnly
    )
  }

  public func resize(
    to size: CellSize,
    cellPixelSize: PixelSize?,
    pointerInputCapabilities: PointerInputCapabilities
  ) {
    host.updateSurfaceSize(size)
    host.updateSurfaceCapabilities(
      TerminalSurfaceCapabilities(
        cellPixelSize: cellPixelSize,
        pointerInputCapabilities: pointerInputCapabilities
      )
    )
    signalReader.send("SIGWINCH")
  }

  package var hostGraphicsCapabilitiesForTesting: TerminalGraphicsCapabilities {
    host.graphicsCapabilities
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

private final class HostedRasterSurface: HostedScenePresentationSurface, Sendable {
  private struct State: Sendable {
    var surfaceSize: CellSize
    var renderStyle: TerminalRenderStyle
    var graphicsCapabilities: TerminalGraphicsCapabilities
    var pointerInputCapabilities: PointerInputCapabilities
    var lastSubmittedSurface: RasterSurface?
  }

  private let state: Mutex<State>
  private let surfaceHandler: @Sendable (RasterSurface) -> Void

  let capabilityProfile: TerminalCapabilityProfile

  var surfaceSize: CellSize {
    state.withLock(\.surfaceSize)
  }

  var appearance: TerminalAppearance {
    state.withLock(\.renderStyle.appearance)
  }

  var theme: Theme? {
    state.withLock(\.renderStyle.theme)
  }

  var graphicsCapabilities: TerminalGraphicsCapabilities {
    state.withLock(\.graphicsCapabilities)
  }

  var pointerInputCapabilities: PointerInputCapabilities {
    state.withLock(\.pointerInputCapabilities)
  }

  init(
    surfaceSize: CellSize,
    appearance: TerminalAppearance,
    theme: Theme?,
    capabilityProfile: TerminalCapabilityProfile,
    surfaceHandler: @escaping @Sendable (RasterSurface) -> Void
  ) {
    self.capabilityProfile = capabilityProfile
    self.surfaceHandler = surfaceHandler
    state = Mutex(
      State(
        surfaceSize: surfaceSize,
        renderStyle: .init(
          appearance: appearance,
          theme: theme
        ),
        graphicsCapabilities: .none,
        pointerInputCapabilities: .cellOnly,
        lastSubmittedSurface: nil
      )
    )
  }

  func updateSurfaceSize(
    _ surfaceSize: CellSize
  ) {
    state.withLock { state in
      state.surfaceSize = surfaceSize
      state.lastSubmittedSurface = nil
    }
  }

  func updateAppearance(
    _ appearance: TerminalAppearance
  ) {
    state.withLock { state in
      state.renderStyle.appearance = appearance
      state.lastSubmittedSurface = nil
    }
  }

  func updateTheme(
    _ theme: Theme?
  ) {
    state.withLock { state in
      state.renderStyle.theme = theme
      state.lastSubmittedSurface = nil
    }
  }

  func updateStyle(
    _ style: TerminalRenderStyle
  ) {
    state.withLock { state in
      state.renderStyle = style
      state.lastSubmittedSurface = nil
    }
  }

  func updateSurfaceCapabilities(
    _ capabilities: TerminalSurfaceCapabilities
  ) {
    state.withLock { state in
      state.graphicsCapabilities.cellPixelSize = capabilities.cellPixelSize
      state.pointerInputCapabilities = capabilities.pointerInputCapabilities
      state.lastSubmittedSurface = nil
    }
  }

  func enableRawMode() throws {}

  func disableRawMode() throws {}

  func write(_: String) throws {}

  func clearScreen() throws {}

  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(
    _ surface: RasterSurface
  ) throws -> TerminalPresentationMetrics {
    try present(surface, damage: nil)
  }

  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    let previousSurface = state.withLock(\.lastSubmittedSurface)
    surfaceHandler(surface)
    state.withLock { state in
      state.lastSubmittedSurface = surface
    }

    let strategy: TerminalPresentationMetrics.Strategy =
      previousSurface == nil || previousSurface?.size != surface.size
      ? .fullRepaint
      : .incremental
    let linesTouched = damage?.dirtyRows.count ?? max(0, surface.size.height)
    let cellsChanged =
      damage?.textRows.reduce(0) { partial, row in
        partial + row.columnRanges.reduce(0) { $0 + $1.count }
      } ?? max(0, surface.size.width) * max(0, surface.size.height)

    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: linesTouched,
      cellsChanged: cellsChanged,
      strategy: strategy
    )
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

@MainActor
private struct HostedSceneSelection {
  let descriptor: SceneDescriptor
  let rootIdentity: Identity
  let runScene: HostedSceneRunner
}

@MainActor
private struct HostedSceneSelectionVisitor: WindowSceneConfigurationVisitor {
  let sessionName: String

  mutating func visit<Content: View>(
    descriptor: SceneDescriptor,
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
