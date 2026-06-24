import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
  package convenience init(
    rootIdentity: Identity,
    presentationSurface: any PresentationSurfaceMetricsProvider,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    runtimeConfiguration: RuntimeConfiguration = .default,
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: DeferredStateBodyBuilder<State, Content>
  ) {
    self.init(
      rootIdentity: rootIdentity,
      renderer: DefaultRenderer(
        semanticExtractor: SemanticExtractor(
          extractsAccessibilityWarnings: runtimeConfiguration.output != .tui
        )
      ),
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      runtimeConfiguration: runtimeConfiguration,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  package convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer,
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    runtimeConfiguration: RuntimeConfiguration = .default,
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: DeferredStateBodyBuilder<State, Content>
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: metricsSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      runtimeConfiguration: runtimeConfiguration,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  package convenience init(
    rootIdentity: Identity,
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    runtimeConfiguration: RuntimeConfiguration = .default,
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: DeferredStateBodyBuilder<State, Content>
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      rootIdentity: rootIdentity,
      presentationSurface: metricsSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      runtimeConfiguration: runtimeConfiguration,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  package convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer,
    presentationSurface: any PresentationSurfaceMetricsProvider,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    runtimeConfiguration: RuntimeConfiguration = .default,
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: DeferredStateBodyBuilder<State, Content>
  ) {
    self.init(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: presentationSurface,
      terminalInputReader: KeyboardInputAdapter(inputReader: inputReader),
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      runtimeConfiguration: runtimeConfiguration,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  package convenience init(
    rootIdentity: Identity,
    presentationSurface: any PresentationSurfaceMetricsProvider,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    runtimeConfiguration: RuntimeConfiguration = .default,
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: DeferredStateBodyBuilder<State, Content>
  ) {
    self.init(
      rootIdentity: rootIdentity,
      presentationSurface: presentationSurface,
      terminalInputReader: KeyboardInputAdapter(inputReader: inputReader),
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      runtimeConfiguration: runtimeConfiguration,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  package convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer,
    presentationSurface: any PresentationSurface,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    runtimeConfiguration: RuntimeConfiguration = .default,
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: DeferredStateBodyBuilder<State, Content>
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: metricsSurface,
      inputReader: inputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      runtimeConfiguration: runtimeConfiguration,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  package convenience init(
    rootIdentity: Identity,
    presentationSurface: any PresentationSurface,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    runtimeConfiguration: RuntimeConfiguration = .default,
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: DeferredStateBodyBuilder<State, Content>
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      rootIdentity: rootIdentity,
      presentationSurface: metricsSurface,
      inputReader: inputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      runtimeConfiguration: runtimeConfiguration,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  /// Creates a run loop from a strongly typed `View` builder.
  public convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer,
    presentationSurface: any PresentationSurfaceMetricsProvider,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: @escaping (_ state: State, _ focusedIdentity: Identity?) -> Content
  ) {
    self.init(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: ScopedMapper { input in
        viewBuilder(input.state, input.focusedIdentity)
      }
    )
  }

  /// Creates a run loop from a strongly typed `View` builder.
  public convenience init(
    rootIdentity: Identity,
    presentationSurface: any PresentationSurfaceMetricsProvider,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: @escaping (_ state: State, _ focusedIdentity: Identity?) -> Content
  ) {
    self.init(
      rootIdentity: rootIdentity,
      renderer: DefaultRenderer(
        semanticExtractor: SemanticExtractor(
          extractsAccessibilityWarnings: RuntimeConfiguration.default.output != .tui
        )
      ),
      presentationSurface: presentationSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  /// Creates a run loop from a strongly typed `View` builder.
  public convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer,
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: @escaping (_ state: State, _ focusedIdentity: Identity?) -> Content
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: metricsSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  /// Creates a run loop from a strongly typed `View` builder.
  public convenience init(
    rootIdentity: Identity,
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: @escaping (_ state: State, _ focusedIdentity: Identity?) -> Content
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      rootIdentity: rootIdentity,
      presentationSurface: metricsSurface,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  /// Creates a run loop from a strongly typed `View` builder and a keyboard-only
  /// input source.
  public convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer,
    presentationSurface: any PresentationSurfaceMetricsProvider,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: @escaping (_ state: State, _ focusedIdentity: Identity?) -> Content
  ) {
    self.init(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: presentationSurface,
      terminalInputReader: KeyboardInputAdapter(inputReader: inputReader),
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  /// Creates a run loop from a strongly typed `View` builder and a keyboard-only
  /// input source.
  public convenience init(
    rootIdentity: Identity,
    presentationSurface: any PresentationSurfaceMetricsProvider,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: @escaping (_ state: State, _ focusedIdentity: Identity?) -> Content
  ) {
    self.init(
      rootIdentity: rootIdentity,
      presentationSurface: presentationSurface,
      terminalInputReader: KeyboardInputAdapter(inputReader: inputReader),
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  /// Creates a run loop from a strongly typed `View` builder and a keyboard-only
  /// input source.
  public convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer,
    presentationSurface: any PresentationSurface,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: @escaping (_ state: State, _ focusedIdentity: Identity?) -> Content
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: metricsSurface,
      inputReader: inputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }

  /// Creates a run loop from a strongly typed `View` builder and a keyboard-only
  /// input source.
  public convenience init(
    rootIdentity: Identity,
    presentationSurface: any PresentationSurface,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)? = nil,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: @escaping (_ state: State, _ focusedIdentity: Identity?) -> Content
  ) {
    let metricsSurface: any PresentationSurfaceMetricsProvider = presentationSurface
    self.init(
      rootIdentity: rootIdentity,
      presentationSurface: metricsSurface,
      inputReader: inputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      focusPresentationHandler: focusPresentationHandler,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      exitKeyBindings: exitKeyBindings,
      viewBuilder: viewBuilder
    )
  }
}
