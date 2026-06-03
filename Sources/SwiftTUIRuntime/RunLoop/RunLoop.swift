import SwiftTUICore
import SwiftTUIViews

@MainActor
/// Drives an interactive terminal session for a state-backed view tree.
public final class RunLoop<State: Equatable & Sendable, Content: View> {
  package enum RuntimeEvent {
    case input(InputEvent)
    case signal(String)
  }

  package let rootIdentity: Identity
  package let renderer: DefaultRenderer
  package let presentationSurface: any PresentationSurfaceMetricsProvider
  package let terminalInputReader: any TerminalInputReading
  package let signalReader: (any SignalReading)?
  package let scheduler: any FrameScheduling
  package let stateContainer: StateContainer<State>
  package let focusTracker: FocusTracker
  package let focusPresentationHandler: (@MainActor @Sendable (FocusPresentation) -> Void)?
  package let keyHandler: StateKeyHandler<State>?
  package let viewBuilder: DeferredStateBodyBuilder<State, Content>
  package let environment: EnvironmentSnapshot
  package let environmentValues: EnvironmentValues
  package let runtimeConfiguration: RuntimeConfiguration
  package let proposalOverride: ProposedSize?
  package let exitKeyBindings: ExitKeyBindings
  package let localActionRegistry = LocalActionRegistry()
  package let localPointerHandlerRegistry = LocalPointerHandlerRegistry()
  package let localGestureRegistry = LocalGestureRegistry()
  package let localGestureStateRegistry = LocalGestureStateRegistry()
  package let localDefaultFocusRegistry = LocalDefaultFocusRegistry()
  package let localFocusBindingRegistry = LocalFocusBindingRegistry()
  package let localFocusedValuesRegistry = LocalFocusedValuesRegistry()
  package let localScrollPositionRegistry = LocalScrollPositionRegistry()
  package let localPreferenceObservationRegistry = LocalPreferenceObservationRegistry()
  package let localKeyHandlerRegistry = LocalKeyHandlerRegistry()
  package let localTerminationRegistry = LocalTerminationRegistry()
  package let localLifecycleRegistry = LocalLifecycleRegistry()
  package let localTaskRegistry = LocalTaskRegistry()
  package let commandRegistry = CommandRegistry()
  package let dropDestinationRegistry = DropDestinationRegistry()
  package let lifecycleCoordinator = LifecycleCoordinator()
  package var progressProbe: RunLoopProgressProbe?
  package var liveRegionAnnouncer = LiveRegionAnnouncer()
  package var pendingAccessibilityAnnouncements: [AccessibilityAnnouncement] = []
  package let observationBridge = ObservationBridge()
  package let renderSuspensionDiagnostics = RenderSuspensionDiagnostics()

  package var latestSemanticSnapshot = SemanticSnapshot()
  package var currentFocusPresentation: FocusPresentation = .none
  package var currentFocusedValues = FocusedValues()
  package var previousPreferenceObservations: [PreferenceObservationRegistrationSnapshot] = []
  package var pressedIdentity: Identity?
  package var transientPressedIdentity: Identity?
  package var armedPointerRouteID: RouteID?
  package var armedPointerRouteUsesPointerHandler = false
  package var capturedPointerRouteID: RouteID?
  package var hoveredPointerRouteID: RouteID?
  package var terminalPointerHoverEnabled = false
  package var postActionInvalidationIdentities: Set<Identity> = []
  package var previousRenderedState: State?
  /// Focus identity committed by the previous frame. Compared at the start of
  /// each frame to detect a focus move, which gates retained `ViewNode` reuse
  /// off (see ``shouldSuppressRetainedReuseForFrameSafety()``): focus is
  /// deliberately excluded from `EnvironmentSnapshot` equality, so a reused
  /// focus-reading subtree would otherwise show stale focus.
  package var previousFrameFocusIdentity: Identity?
  /// Press identity committed by the previous frame. Tracked for the same
  /// scoped retained-reuse safety gate as focus.
  package var previousFramePressedIdentity: Identity?
  package var nextRenderIntentGeneration: UInt64 = 1
  package var pendingCoalescedEventBatches = 0
  package var pendingCoalescedWakeCauses: Set<WakeCause> = []
  package var cancelledRenderCount = 0
  package var nextSemanticHostFrameSequence: UInt64 = 0
  package var previousPresentedRasterSurface: RasterSurface?
  package var deferredLifecycleCarryForward: [LifecycleCommitEntry] = []
  package var reportedRuntimeIssues: Set<RuntimeIssue> = []

  /// Test seam for the **frame-readiness clock**: the instant the drain compares
  /// against pending scheduler deadlines when deciding which frames are ready to
  /// consume (`scheduler.consumeReadyFrame(at:)`). Production reads the real
  /// monotonic clock. A runtime test can pin it to a frozen instant to drive
  /// virtual time deterministically — an off-screen animation's auto-rescheduled
  /// deadlines all land in the real future relative to a frozen `t0`, so they
  /// stay invisible to the drain and cannot perturb frame counts under load.
  /// Only *frame readiness* routes through this seam; real-time waiting (the
  /// event-pump sleeps) still uses the wall clock. See `docs/KNOWN-TEST-FLAKES.md`.
  package var frameReadinessClock: () -> MonotonicInstant = { .now() }

  /// Active per-frame diagnostics sink. Installed by the profiling product (via
  /// ``ProfilingRegistry``) or by a runner (via `SceneSessionResources.frameSink`)
  /// when the session is constructed. When `nil` the per-frame emit path is a
  /// single branch and no diagnostics work runs.
  package var frameSink: (any FrameDiagnosticSink)?

  /// Registration tokens for this session's graph-scoped occupancy providers.
  /// Released on deinit, which deregisters them — so a leaked run loop keeps its
  /// providers registered and shows up in `MemoryMetricRegistry.providerCount`.
  private var memoryMetricTokens: [MemoryMetricRegistry.Token] = []

  /// Optional host channel for runtime issue notifications.
  public var runtimeIssueSink: RuntimeIssueSink?

  /// Rendering pipeline used by the interactive run loop.
  public var renderMode: RuntimeRenderMode

  package init(
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
    runtimeConfiguration: RuntimeConfiguration = .default,
    proposal: ProposedSize? = nil,
    exitKeyBindings: ExitKeyBindings = .default,
    viewBuilder: DeferredStateBodyBuilder<State, Content>
  ) {
    self.rootIdentity = rootIdentity
    self.renderer = renderer
    self.presentationSurface = presentationSurface
    self.terminalInputReader = terminalInputReader
    self.signalReader = signalReader
    self.scheduler = scheduler
    self.stateContainer = stateContainer
    self.focusTracker = focusTracker
    self.focusPresentationHandler = focusPresentationHandler
    self.keyHandler = keyHandler
    self.environment = environment
    self.environmentValues = environmentValues
    self.runtimeConfiguration = runtimeConfiguration
    self.proposalOverride = proposal
    self.exitKeyBindings = exitKeyBindings
    self.viewBuilder = viewBuilder
    renderMode = .environmentDefault()
    let renderSuspensionDiagnostics = self.renderSuspensionDiagnostics
    self.renderer.setFrameRenderSuspensionHooks(
      .init(
        onBegin: { [renderSuspensionDiagnostics] in
          renderSuspensionDiagnostics.beginSuspension()
        },
        onEnd: { [renderSuspensionDiagnostics] in
          renderSuspensionDiagnostics.endSuspension()
        }
      )
    )
    registerMemoryMetricProviders()
  }

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
      renderer: DefaultRenderer(),
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

  private func registerMemoryMetricProviders() {
    let viewGraph = renderer.viewGraph
    memoryMetricTokens.append(
      MemoryMetricRegistry.shared.register(
        ClosureMemoryMetricProvider { [weak viewGraph] in
          guard let viewGraph else {
            return MemoryMetricSnapshot(name: "ViewGraph.nodesByIdentity", count: 0)
          }
          return viewGraph.memoryMetricSnapshot
        }
      )
    )

    let animationController = renderer.internalAnimationController
    memoryMetricTokens.append(
      MemoryMetricRegistry.shared.register(
        ClosureMemoryMetricProvider { [weak animationController] in
          guard let animationController else {
            return MemoryMetricSnapshot(name: "AnimationController.activeAnimations", count: 0)
          }
          return animationController.memoryMetricSnapshot
        }
      )
    )

    if let measurementCache = renderer.layoutEngine.cache {
      memoryMetricTokens.append(
        MemoryMetricRegistry.shared.register(
          ClosureMemoryMetricProvider { [weak measurementCache] in
            guard let measurementCache else {
              return MemoryMetricSnapshot(name: "MeasurementCache.entriesByNodeID", count: 0)
            }
            let metrics = measurementCache.metrics
            return MemoryMetricSnapshot(
              name: "MeasurementCache.entriesByNodeID",
              count: measurementCache.count,
              detail: [
                "lookups": metrics.lookups,
                "hits": metrics.hits,
                "misses": metrics.misses,
              ]
            )
          }
        )
      )
    }

    let frameTailRenderer = renderer.frameTailRenderer
    memoryMetricTokens.append(
      MemoryMetricRegistry.shared.register(
        ClosureMemoryMetricProvider { [weak frameTailRenderer] in
          guard let frameTailRenderer else {
            return MemoryMetricSnapshot(name: "RetainedFrameIndex.placedByNodeID", count: 0)
          }
          return frameTailRenderer.memoryMetricSnapshot
        }
      )
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
      renderer: DefaultRenderer(),
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

  @MainActor
  /// Runs the interactive session until input ends, a quit condition occurs, or
  /// the session is cancelled.
  public func run() async throws -> RunLoopResult<State> {
    // Install the renderer's animation controller as task-local
    // registration storage so concurrent hosted scenes cannot steal
    // each other's animation, transition, or completion registrations.
    let animationController = renderer.internalAnimationController
    return try await AccessibilityAnnouncementStorage.withSink(self) {
      try await AnimationRegistrationStorage.withSink(animationController) {
        try await TransitionRegistrationStorage.withSink(animationController) {
          try await AnimationCompletionStorage.withSink(animationController) {
            try await runWithInstalledAnimationSinks()
          }
        }
      }
    }
  }

  private func runWithInstalledAnimationSinks() async throws -> RunLoopResult<State> {
    stateContainer.invalidator = scheduler
    focusTracker.invalidator = scheduler
    observationBridge.attachInvalidator(scheduler)

    let usesRawTerminalMode = runtimeConfiguration.output == .tui
    let terminalCommandSurface =
      presentationSurface as? any TerminalCommandPresentationSurface
    if usesRawTerminalMode {
      try terminalCommandSurface?.enableRawMode()
      synchronizeInputCapabilities()
    }
    defer {
      lifecycleCoordinator.shutdown()
      if usesRawTerminalMode {
        try? terminalCommandSurface?.disableRawMode()
      }
    }

    let eventPump = makeEventPump()
    defer {
      eventPump.cancel()
    }
    var iterator = eventPump.stream.makeAsyncIterator()

    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try await renderPendingFramesAsync(renderedFrames: &renderedFrames)

    // After the initial render establishes the view tree and evaluator
    // closures, enable selective dirty evaluation for subsequent frames.
    // This avoids full root re-evaluation when only small subtrees change.
    renderer.enableSelectiveEvaluation()

    scheduleNextWakeIfNeeded(using: eventPump)

    if scheduler.hasPendingFrame(at: .now()) {
      if let exitReason = try await renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: eventPump
      ) {
        return RunLoopResult(
          finalState: stateContainer.state,
          renderedFrames: renderedFrames,
          exitReason: exitReason
        )
      }
      scheduleNextWakeIfNeeded(using: eventPump)
    }

    while await iterator.next() != nil {
      let pendingEvents = await drainPendingEvents(from: eventPump)
      guard !pendingEvents.isEmpty else {
        if scheduler.hasPendingFrame(at: .now()) {
          if let exitReason = try await renderPendingFramesAsync(
            renderedFrames: &renderedFrames,
            eventPump: eventPump
          ) {
            return RunLoopResult(
              finalState: stateContainer.state,
              renderedFrames: renderedFrames,
              exitReason: exitReason
            )
          }
        }
        if let nextWake = scheduler.nextWakeInstant(after: .now()),
          nextWake > .now()
        {
          let sleepDuration = MonotonicInstant.now().duration(to: nextWake)
          if sleepDuration > .zero {
            eventPump.scheduleDeadlineWake(sleepDuration)
          }
        }
        continue
      }
      let renderEventDrain = drainPendingRenderEvents(
        from: eventPump,
        initialEvents: pendingEvents
      )
      progressProbe?.record(
        .eventDrain,
        frameNumber: renderedFrames + 1,
        eventCount: renderEventDrain.events.count,
        coalescedEventBatches: renderEventDrain.coalescedEventBatches
      )
      pendingCoalescedEventBatches += renderEventDrain.coalescedEventBatches

      var handledNonExitEvent = false
      for event in renderEventDrain.events {
        let hadReadyFrameBeforeEvent = scheduler.hasPendingFrame(at: .now())
        if let exitReason = handle(event) {
          let shouldFlushBeforeExit =
            handledNonExitEvent
            || (hadReadyFrameBeforeEvent
              && {
                if case .signal = exitReason {
                  return true
                }
                return false
              }())
          if shouldFlushBeforeExit {
            if let flushedExitReason = try await renderPendingFramesAsync(
              renderedFrames: &renderedFrames,
              eventPump: eventPump
            ) {
              return RunLoopResult(
                finalState: stateContainer.state,
                renderedFrames: renderedFrames,
                exitReason: flushedExitReason
              )
            }
          }
          if terminationDisposition(for: exitReason) == .cancel {
            scheduler.requestInvalidation(of: [rootIdentity])
            handledNonExitEvent = true
            continue
          }
          return RunLoopResult(
            finalState: stateContainer.state,
            renderedFrames: renderedFrames,
            exitReason: exitReason
          )
        }
        handledNonExitEvent = true
      }
      if let exitReason = try await renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: eventPump
      ) {
        return RunLoopResult(
          finalState: stateContainer.state,
          renderedFrames: renderedFrames,
          exitReason: exitReason
        )
      }
      if let nextWake = scheduler.nextWakeInstant(after: .now()),
        nextWake > .now()
      {
        let sleepDuration = MonotonicInstant.now().duration(to: nextWake)
        if sleepDuration > .zero {
          eventPump.scheduleDeadlineWake(sleepDuration)
        }
      }
    }

    _ = terminationDisposition(for: .inputEnded)
    return RunLoopResult(
      finalState: stateContainer.state,
      renderedFrames: renderedFrames,
      exitReason: .inputEnded
    )
  }

  private func synchronizeInputCapabilities() {
    guard let provider = presentationSurface as? any TerminalInputCapabilityProviding,
      let configurableReader = terminalInputReader as? any TerminalInputCapabilityConfiguring
    else {
      return
    }
    configurableReader.updateInputCapabilities(provider.resolvedInputCapabilities)
  }

}

private final class KeyboardInputAdapter: TerminalInputReading {
  private let inputReader: any InputReading

  init(inputReader: any InputReading) {
    self.inputReader = inputReader
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    let keyEvents = inputReader.events()
    return makeTaskBackedAsyncStream { continuation in
      for await keyPress in keyEvents {
        continuation.yield(InputEvent.key(keyPress))
      }
      continuation.finish()
    }
  }
}
