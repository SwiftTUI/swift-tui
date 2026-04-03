package struct TerminalUISceneSessionState: Equatable, Sendable {
  package init() {}
}

package struct SceneSessionResources {
  package let terminalHost: any TerminalHosting
  package let terminalInputReader: any TerminalInputReading
  package let signalReader: (any SignalReading)?
  package let scheduler: any FrameScheduling
  package let surfaceName: String
  package let environmentValues: [String: String]

  package init(
    terminalHost: any TerminalHosting,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    surfaceName: String = "terminal",
    environmentValues: [String: String] = [:]
  ) {
    self.terminalHost = terminalHost
    self.terminalInputReader = terminalInputReader
    self.signalReader = signalReader
    self.scheduler = scheduler
    self.surfaceName = surfaceName
    self.environmentValues = environmentValues
  }
}

package enum SceneSession {
  @MainActor
  package static func run(
    configuration: WindowSceneConfiguration,
    sessionName: String,
    stateContainer: StateContainer<TerminalUISceneSessionState>,
    focusTracker: FocusTracker,
    resources: SceneSessionResources
  ) async throws -> RunLoopResult<TerminalUISceneSessionState> {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = resources.terminalHost.appearance
    environmentValues.themeOverride = resources.terminalHost.theme

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
      terminalHost: resources.terminalHost,
      terminalInputReader: resources.terminalInputReader,
      signalReader: resources.signalReader,
      scheduler: resources.scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      environment: environmentSnapshot,
      environmentValues: environmentValues,
      viewBuilder: { (_: TerminalUISceneSessionState, _: Identity?) in
        WindowHostView(content: configuration.makeRootView())
      }
    )

    return try await runLoop.run()
  }
}
