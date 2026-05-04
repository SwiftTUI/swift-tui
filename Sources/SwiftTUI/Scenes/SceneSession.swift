import SwiftTUIViews

@_spi(Runners) public struct SceneSessionState: Equatable, Sendable {
  @_spi(Runners) public init() {}
}

@_spi(Runners) public struct SceneSessionResources {
  @_spi(Runners) public let presentationSurface: any PresentationSurface
  @_spi(Runners) public let terminalInputReader: any TerminalInputReading
  @_spi(Runners) public let signalReader: (any SignalReading)?
  @_spi(Runners) public let scheduler: any FrameScheduling
  @_spi(Runners) public let surfaceName: String
  @_spi(Runners) public let environmentValues: [String: String]
  @_spi(Runners) public let diagnosticsLogger: FrameDiagnosticsLogger?
  @_spi(Runners) public let focusPresentationHandler:
    (@MainActor @Sendable (FocusPresentation) -> Void)?

  @_spi(Runners) public init(
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    surfaceName: String = "terminal",
    environmentValues: [String: String] = [:],
    diagnosticsLogger: FrameDiagnosticsLogger? = nil,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    self.presentationSurface = presentationSurface
    self.terminalInputReader = terminalInputReader
    self.signalReader = signalReader
    self.scheduler = scheduler
    self.surfaceName = surfaceName
    self.environmentValues = environmentValues
    self.diagnosticsLogger = diagnosticsLogger
    self.focusPresentationHandler = focusPresentationHandler
  }
}

@_spi(Runners) public enum SceneSession {
  @MainActor
  @_spi(Runners) public static func run<Content: View>(
    configuration: WindowSceneConfiguration<Content>,
    sessionName: String,
    stateContainer: StateContainer<SceneSessionState>,
    focusTracker: FocusTracker,
    resources: SceneSessionResources
  ) async throws -> RunLoopResult<SceneSessionState> {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = resources.presentationSurface.appearance
    environmentValues.theme = resources.presentationSurface.theme

    var environmentSnapshot = EnvironmentSnapshot(
      debugSignature: sessionName,
      values: resources.environmentValues
    )
    environmentSnapshot.values["surface"] = resources.surfaceName
    environmentSnapshot.values["session"] = sessionName
    environmentSnapshot.values["scene"] = configuration.identifier.rawValue
    if let title = configuration.title {
      environmentSnapshot.values["windowTitle"] = title
    }

    let runLoop = RunLoop(
      rootIdentity: configuration.rootIdentity,
      presentationSurface: resources.presentationSurface,
      terminalInputReader: resources.terminalInputReader,
      signalReader: resources.signalReader,
      scheduler: resources.scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: resources.focusPresentationHandler,
      environment: environmentSnapshot,
      environmentValues: environmentValues,
      exitKeyBindings: configuration.exitKeyBindings,
      viewBuilder: { (_: SceneSessionState, _: Identity?) in
        WindowHostView(content: configuration.makeScopedRootView())
      }
    )
    runLoop.diagnosticsLogger = resources.diagnosticsLogger

    return try await runLoop.run()
  }
}
