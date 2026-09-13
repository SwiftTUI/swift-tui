import SwiftTUIViews

@_spi(Runners) public struct SceneSessionState: Equatable, Sendable {
  @_spi(Runners) public init() {}
}

@_spi(Runners) public final class SceneSessionResources {
  @_spi(Runners) public let presentationSurface: any PresentationSurfaceMetricsProvider
  @_spi(Runners) public let terminalInputReader: any TerminalInputReading
  @_spi(Runners) public let signalReader: (any SignalReading)?
  @_spi(Runners) public let scheduler: any FrameScheduling
  @_spi(Runners) public let surfaceName: String
  @_spi(Runners) public let environmentValues: [String: String]
  @_spi(Runners) public let frameSink: (any FrameDiagnosticSink)?
  @_spi(Runners) public let progressProbe: RunLoopProgressProbe?
  @_spi(Runners) public var runtimeIssueSink: RuntimeIssueSink?
  @_spi(Runners) public let runtimeConfiguration: RuntimeConfiguration
  @_spi(Runners) public let renderMode: RuntimeRenderMode?
  @_spi(Runners) public let focusPresentationHandler:
    (@MainActor @Sendable (FocusPresentation) -> Void)?

  @_spi(Runners) public init(
    presentationSurface: any PresentationSurfaceMetricsProvider,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    surfaceName: String = "terminal",
    environmentValues: [String: String] = [:],
    frameSink: (any FrameDiagnosticSink)? = nil,
    progressProbe: RunLoopProgressProbe?,
    runtimeConfiguration: RuntimeConfiguration = .default,
    renderMode: RuntimeRenderMode?,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    self.presentationSurface = presentationSurface
    self.terminalInputReader = terminalInputReader
    self.signalReader = signalReader
    self.scheduler = scheduler
    self.surfaceName = surfaceName
    self.environmentValues = environmentValues
    self.frameSink = frameSink
    self.progressProbe = progressProbe
    self.runtimeIssueSink = nil
    self.runtimeConfiguration = runtimeConfiguration
    self.renderMode = renderMode
    self.focusPresentationHandler = focusPresentationHandler
  }

  @_spi(Runners) public convenience init(
    presentationSurface: any PresentationSurfaceMetricsProvider,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    surfaceName: String = "terminal",
    environmentValues: [String: String] = [:],
    frameSink: (any FrameDiagnosticSink)? = nil,
    progressProbe: RunLoopProgressProbe?,
    runtimeConfiguration: RuntimeConfiguration = .default,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    self.init(
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      surfaceName: surfaceName,
      environmentValues: environmentValues,
      frameSink: frameSink,
      progressProbe: progressProbe,
      runtimeConfiguration: runtimeConfiguration,
      renderMode: nil,
      focusPresentationHandler: focusPresentationHandler
    )
  }

  @_spi(Runners) public convenience init(
    presentationSurface: any PresentationSurfaceMetricsProvider,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    surfaceName: String = "terminal",
    environmentValues: [String: String] = [:],
    frameSink: (any FrameDiagnosticSink)? = nil,
    runtimeConfiguration: RuntimeConfiguration = .default,
    renderMode: RuntimeRenderMode?,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    self.init(
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      surfaceName: surfaceName,
      environmentValues: environmentValues,
      frameSink: frameSink,
      progressProbe: nil,
      runtimeConfiguration: runtimeConfiguration,
      renderMode: renderMode,
      focusPresentationHandler: focusPresentationHandler
    )
  }

  @_spi(Runners) public convenience init(
    presentationSurface: any PresentationSurfaceMetricsProvider,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    surfaceName: String = "terminal",
    environmentValues: [String: String] = [:],
    frameSink: (any FrameDiagnosticSink)? = nil,
    runtimeConfiguration: RuntimeConfiguration = .default,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    self.init(
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      surfaceName: surfaceName,
      environmentValues: environmentValues,
      frameSink: frameSink,
      progressProbe: nil,
      runtimeConfiguration: runtimeConfiguration,
      renderMode: nil,
      focusPresentationHandler: focusPresentationHandler
    )
  }

  @_spi(Runners) public convenience init(
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    surfaceName: String = "terminal",
    environmentValues: [String: String] = [:],
    frameSink: (any FrameDiagnosticSink)? = nil,
    progressProbe: RunLoopProgressProbe?,
    runtimeConfiguration: RuntimeConfiguration = .default,
    renderMode: RuntimeRenderMode?,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      presentationSurface: metricsSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      surfaceName: surfaceName,
      environmentValues: environmentValues,
      frameSink: frameSink,
      progressProbe: progressProbe,
      runtimeConfiguration: runtimeConfiguration,
      renderMode: renderMode,
      focusPresentationHandler: focusPresentationHandler
    )
  }

  @_spi(Runners) public convenience init(
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    surfaceName: String = "terminal",
    environmentValues: [String: String] = [:],
    frameSink: (any FrameDiagnosticSink)? = nil,
    progressProbe: RunLoopProgressProbe?,
    runtimeConfiguration: RuntimeConfiguration = .default,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      presentationSurface: metricsSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      surfaceName: surfaceName,
      environmentValues: environmentValues,
      frameSink: frameSink,
      progressProbe: progressProbe,
      runtimeConfiguration: runtimeConfiguration,
      renderMode: nil,
      focusPresentationHandler: focusPresentationHandler
    )
  }

  @_spi(Runners) public convenience init(
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    surfaceName: String = "terminal",
    environmentValues: [String: String] = [:],
    frameSink: (any FrameDiagnosticSink)? = nil,
    runtimeConfiguration: RuntimeConfiguration = .default,
    renderMode: RuntimeRenderMode?,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      presentationSurface: metricsSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      surfaceName: surfaceName,
      environmentValues: environmentValues,
      frameSink: frameSink,
      progressProbe: nil,
      runtimeConfiguration: runtimeConfiguration,
      renderMode: renderMode,
      focusPresentationHandler: focusPresentationHandler
    )
  }

  @_spi(Runners) public convenience init(
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    surfaceName: String = "terminal",
    environmentValues: [String: String] = [:],
    frameSink: (any FrameDiagnosticSink)? = nil,
    runtimeConfiguration: RuntimeConfiguration = .default,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      presentationSurface: metricsSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      surfaceName: surfaceName,
      environmentValues: environmentValues,
      frameSink: frameSink,
      progressProbe: nil,
      runtimeConfiguration: runtimeConfiguration,
      renderMode: nil,
      focusPresentationHandler: focusPresentationHandler
    )
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
    #if DEBUG && (os(macOS) || os(Linux))
      if resources.surfaceName == "terminal",
        let spool = FeatureFlags.environmentValue(named: "SWIFTTUI_HOT_RELOAD_SPOOL"),
        !spool.isEmpty
      {
        let loader = try HotReloadLoader(spoolPath: spool,
          logicalModule: FeatureFlags.environmentValue(named: "SWIFTTUI_HOT_RELOAD_MODULE"))
        let session = HotReloadSession(content: HotReloadGeneration {
          configuration.makeScopedRootView()
        })
        let loop = makeRunLoop(configuration: configuration, sessionName: sessionName,
          stateContainer: stateContainer, focusTracker: focusTracker, resources: resources
        ) { HotReloadHost(session: session) }
        loop.installHotReloadSession(session)
        loop.hotReloadLoader = loader
        return try await loop.run()
      }
    #endif
    let loop = makeRunLoop(configuration: configuration, sessionName: sessionName,
      stateContainer: stateContainer, focusTracker: focusTracker, resources: resources
    ) { configuration.makeScopedRootView() }
    return try await loop.run()
  }

  @MainActor
  private static func makeRunLoop<Content: View, Root: View>(
    configuration: WindowSceneConfiguration<Content>,
    sessionName: String,
    stateContainer: StateContainer<SceneSessionState>,
    focusTracker: FocusTracker,
    resources: SceneSessionResources,
    @ViewBuilder content: @escaping @MainActor () -> Root
  ) -> RunLoop<SceneSessionState, WindowHostView<Root>> {
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

    let runLoop = RunLoop<SceneSessionState, WindowHostView<Root>>(
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
      runtimeConfiguration: resources.runtimeConfiguration,
      exitKeyBindings: configuration.exitKeyBindings,
      viewBuilder: ScopedMapper { _ in
        WindowHostView(content: content())
      }
    )
    DebugBundle.prepareIfNeeded(configuration: resources.runtimeConfiguration)
    runLoop.frameSink = resources.frameSink
    if let frameSink = ProfilingRegistry.shared.frameSink {
      // A profiled build installs a sink via `.profiling()`; it supersedes the
      // legacy per-session logger.
      runLoop.frameSink = frameSink
    } else if let traceSink = EnvFrameTraceSink.fromEnvironment(
      debug: resources.runtimeConfiguration.debug
    ) {
      // Opt-in diagnostic: `SWIFTTUI_FRAME_TRACE=<path>` (or the debug
      // bundle's `frames.tsv`) traces the frame pipeline to a file for
      // reproducing timing-sensitive interaction bugs (e.g. a slow /
      // momentarily blank tab switch) in a real terminal.
      runLoop.frameSink = traceSink
    }
    runLoop.runtimeIssueSink = resources.runtimeIssueSink
    runLoop.progressProbe = resources.progressProbe
    if let renderMode = resources.renderMode {
      runLoop.renderMode = renderMode
    }

    return runLoop
  }
}
