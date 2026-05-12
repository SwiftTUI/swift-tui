import SwiftTUICore
import SwiftTUIViews
import Synchronization

package typealias ViewBuilderInput<State: Equatable & Sendable> = (
  state: State,
  focusedIdentity: Identity?
)

package typealias DeferredStateBodyBuilder<State: Equatable & Sendable, Content: View> =
  ScopedMapper<ViewBuilderInput<State>, Content>

/// Handles a key event and may mutate run-loop state.
public typealias StateKeyHandler<State: Equatable & Sendable> =
  (_ keyPress: KeyPress, _ focusedIdentity: Identity?, _ stateContainer: StateContainer<State>) ->
  KeyHandlingResult

/// The result of low-level key handling inside a ``RunLoop``.
public enum KeyHandlingResult: Equatable, Sendable {
  case ignored
  case handled
  case exit(RunLoopExitReason)
}

/// Why an interactive run loop stopped.
///
/// - ``userExit(_:)``: a key press configured in ``ExitKeyBindings``
///   was received. The associated `KeyPress` identifies which key.
/// - ``signal(_:)``: the run loop terminated in response to an OS
///   signal (for example `SIGTERM`).
/// - ``inputEnded``: the input stream reached end-of-file.
public enum RunLoopExitReason: Equatable, Sendable {
  case userExit(KeyPress)
  case signal(String)
  case inputEnded
}

/// Final summary data produced by a completed ``RunLoop`` session.
public struct RunLoopResult<State: Equatable & Sendable>: Equatable, Sendable {
  public var finalState: State
  public var renderedFrames: Int
  public var exitReason: RunLoopExitReason

  public init(
    finalState: State,
    renderedFrames: Int,
    exitReason: RunLoopExitReason
  ) {
    self.finalState = finalState
    self.renderedFrames = renderedFrames
    self.exitReason = exitReason
  }
}

/// Produces an asynchronous stream of terminal signal names.
public protocol SignalReading: AnyObject {
  func events() -> AsyncStream<String>
}

/// Emits runtime signals from an in-process source.
public final class InProcessSignalReader: SignalReading, Sendable {
  private struct State: Sendable {
    var continuation: AsyncStream<String>.Continuation?
    var continuationGeneration: UInt64 = 0
  }

  private let state = Mutex(State())

  public init() {}

  public func events() -> AsyncStream<String> {
    makeManagedAsyncStream { continuation in
      let generation = self.state.withLock { state in
        state.continuationGeneration &+= 1
        state.continuation = continuation
        return state.continuationGeneration
      }

      return { _ in
        self.state.withLock { state in
          guard state.continuationGeneration == generation else {
            return
          }
          state.continuation = nil
        }
      }
    }
  }

  public func send(_ signalName: String) {
    state.withLock { state in
      let continuation = state.continuation
      continuation?.yield(signalName)
    }
  }

  public func finish() {
    let continuation = state.withLock { state in
      let continuation = state.continuation
      state.continuation = nil
      return continuation
    }
    continuation?.finish()
  }
}

package final class RenderSuspensionDiagnostics: Sendable {
  private struct State: Sendable {
    var suspensionDepth = 0
    var inputEventsQueuedDuringSuspension = 0
  }

  private let state = Mutex(State())

  func beginSuspension() {
    state.withLock { state in
      state.suspensionDepth += 1
    }
  }

  func endSuspension() {
    state.withLock { state in
      state.suspensionDepth = max(0, state.suspensionDepth - 1)
    }
  }

  package var isSuspended: Bool {
    state.withLock { state in
      state.suspensionDepth > 0
    }
  }

  func recordInputEventQueuedIfSuspended() {
    state.withLock { state in
      if state.suspensionDepth > 0 {
        state.inputEventsQueuedDuringSuspension += 1
      }
    }
  }

  func drainInputEventsQueuedDuringSuspension() -> Int {
    state.withLock { state in
      let value = state.inputEventsQueuedDuringSuspension
      state.inputEventsQueuedDuringSuspension = 0
      return value
    }
  }
}

@MainActor
/// Drives an interactive terminal session for a state-backed view tree.
public final class RunLoop<State: Equatable & Sendable, Content: View> {
  package enum RuntimeEvent {
    case input(InputEvent)
    case signal(String)
  }

  package let rootIdentity: Identity
  package let renderer: DefaultRenderer
  package let presentationSurface: any PresentationSurface
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
  package var liveRegionAnnouncer = LiveRegionAnnouncer()
  package var pendingAccessibilityAnnouncements: [AccessibilityAnnouncement] = []
  package let observationBridge = ObservationBridge()
  package let renderSuspensionDiagnostics = RenderSuspensionDiagnostics()

  package var runtimeRegistrations: RuntimeRegistrationSet {
    RuntimeRegistrationSet(
      actionRegistry: localActionRegistry,
      keyHandlerRegistry: localKeyHandlerRegistry,
      terminationRegistry: localTerminationRegistry,
      pointerHandlerRegistry: localPointerHandlerRegistry,
      gestureRegistry: localGestureRegistry,
      gestureStateRegistry: localGestureStateRegistry,
      defaultFocusRegistry: localDefaultFocusRegistry,
      focusBindingRegistry: localFocusBindingRegistry,
      focusedValuesRegistry: localFocusedValuesRegistry,
      scrollPositionRegistry: localScrollPositionRegistry,
      lifecycleRegistry: localLifecycleRegistry,
      taskRegistry: localTaskRegistry,
      preferenceObservationRegistry: localPreferenceObservationRegistry,
      commandRegistry: commandRegistry,
      dropDestinationRegistry: dropDestinationRegistry
    )
  }

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
  package var nextRenderIntentGeneration: UInt64 = 1
  package var pendingCoalescedEventBatches = 0
  package var pendingCoalescedWakeCauses: Set<WakeCause> = []
  package var cancelledRenderCount = 0
  package var deferredLifecycleCarryForward: [LifecycleCommitEntry] = []
  package var reportedRuntimeIssues: Set<RuntimeIssue> = []

  /// Optional file-based diagnostics logger. When set, every rendered frame
  /// emits a tab-separated record to the configured output file.
  public var diagnosticsLogger: FrameDiagnosticsLogger?

  /// Optional host channel for runtime issue notifications.
  public var runtimeIssueSink: RuntimeIssueSink?

  /// Rendering pipeline used by the interactive run loop.
  public var renderMode: RuntimeRenderMode

  package init(
    rootIdentity: Identity,
    renderer: DefaultRenderer = .init(),
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
  }

  @MainActor
  package func reportRuntimeIssue(_ issue: RuntimeIssue) {
    guard reportedRuntimeIssues.insert(issue).inserted else {
      return
    }
    runtimeIssueSink?.report(issue)
  }

  package func reportRuntimeIssues(_ issues: [RuntimeIssue]) {
    for issue in issues {
      reportRuntimeIssue(issue)
    }
  }

  package convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer = .init(),
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

  /// Creates a run loop from a strongly typed `View` builder.
  public convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer = .init(),
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

  /// Creates a run loop from a strongly typed `View` builder and a keyboard-only
  /// input source.
  public convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer = .init(),
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
    if usesRawTerminalMode {
      try presentationSurface.enableRawMode()
      synchronizeInputCapabilities()
    }
    defer {
      lifecycleCoordinator.shutdown()
      if usesRawTerminalMode {
        try? presentationSurface.disableRawMode()
      }
    }

    scheduler.requestInvalidation(of: [rootIdentity])

    var renderedFrames = 0
    try await renderPendingFramesAsync(renderedFrames: &renderedFrames)

    // After the initial render establishes the view tree and evaluator
    // closures, enable selective dirty evaluation for subsequent frames.
    // This avoids full root re-evaluation when only small subtrees change.
    renderer.enableSelectiveEvaluation()

    let eventPump = makeEventPump()
    defer {
      eventPump.cancel()
    }
    var iterator = eventPump.stream.makeAsyncIterator()

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

  package func scheduleNextWakeIfNeeded(
    using eventPump: EventPump
  ) {
    let now = MonotonicInstant.now()
    guard let nextWake = scheduler.nextWakeInstant(after: now),
      nextWake > now
    else {
      return
    }

    let sleepDuration = now.duration(to: nextWake)
    if sleepDuration > .zero {
      eventPump.scheduleDeadlineWake(sleepDuration)
    }
  }

  package func terminationDisposition(
    for exitReason: RunLoopExitReason
  ) -> TerminationDisposition {
    localTerminationRegistry.dispatch(
      TerminationRequest(exitReason),
      preferredPath: currentFocusScopePath()
    )
  }
}

extension TerminationRequest {
  package init(_ exitReason: RunLoopExitReason) {
    switch exitReason {
    case .userExit(let keyPress):
      self = .userExit(keyPress)
    case .signal(let name):
      self = .signal(name)
    case .inputEnded:
      self = .inputEnded
    }
  }
}

extension RunLoop {
  package func updateFocusPresentation(
    _ presentation: FocusPresentation
  ) {
    guard currentFocusPresentation != presentation else {
      return
    }

    currentFocusPresentation = presentation
    focusPresentationHandler?(presentation)
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
