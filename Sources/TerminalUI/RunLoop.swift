import Core
import Synchronization
import View

// AnyView policy: retain this internal erased builder as typed runtime plumbing
// for the run loop while keeping the public authoring surface generic.
package typealias ErasedStateBodyBuilder<State: Equatable & Sendable> =
  (_ state: State, _ focusedIdentity: Identity?) -> AnyView

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
public enum RunLoopExitReason: Equatable, Sendable {
  case quitKey
  case ctrlC
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
public final class InProcessSignalReader: SignalReading, @unchecked Sendable {
  private let continuation = Mutex<AsyncStream<String>.Continuation?>(nil)

  public init() {}

  public func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      self.continuation.withLock { stored in
        stored = continuation
      }
    }
  }

  public func send(_ signalName: String) {
    _ = continuation.withLock { continuation in
      continuation?.yield(signalName)
    }
  }

  public func finish() {
    continuation.withLock { continuation in
      continuation?.finish()
      continuation = nil
    }
  }
}

@MainActor
/// Drives an interactive terminal session for a state-backed view tree.
public final class RunLoop<State: Equatable & Sendable> {
  package enum RuntimeEvent {
    case input(InputEvent)
    case signal(String)
  }

  package let rootIdentity: Identity
  package let renderer: DefaultRenderer
  package let terminalHost: any TerminalHosting
  package let terminalInputReader: any TerminalInputReading
  package let signalReader: (any SignalReading)?
  package let scheduler: any FrameScheduling
  package let stateContainer: StateContainer<State>
  package let focusTracker: FocusTracker
  package let keyHandler: StateKeyHandler<State>?
  package let viewBuilder: ErasedStateBodyBuilder<State>
  package let environment: EnvironmentSnapshot
  package let environmentValues: EnvironmentValues
  package let proposalOverride: ProposedSize?
  package let localActionRegistry = LocalActionRegistry()
  package let localPointerHandlerRegistry = LocalPointerHandlerRegistry()
  package let localFocusBindingRegistry = LocalFocusBindingRegistry()
  package let localFocusedValuesRegistry = LocalFocusedValuesRegistry()
  package let localPreferenceObservationRegistry = LocalPreferenceObservationRegistry()
  package let localKeyHandlerRegistry = LocalKeyHandlerRegistry()
  package let hotkeyRegistry = HotkeyRegistry()
  package let localLifecycleRegistry = LocalLifecycleRegistry()
  package let localTaskRegistry = LocalTaskRegistry()
  package let lifecycleCoordinator = LifecycleCoordinator()
  package let observationBridge = ObservationBridge()

  package var latestSemanticSnapshot = SemanticSnapshot()
  package var currentFocusedValues = FocusedValues()
  package var previousPreferenceObservations: [PreferenceObservationRegistrationSnapshot] = []
  package var pressedIdentity: Identity?
  package var transientPressedIdentity: Identity?
  package var armedPointerRouteID: RouteID?
  package var capturedPointerRouteID: RouteID?
  package var postActionInvalidationIdentities: Set<Identity> = []

  package init(
    rootIdentity: Identity,
    renderer: DefaultRenderer = .init(),
    terminalHost: any TerminalHosting,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    viewBuilder: @escaping ErasedStateBodyBuilder<State>
  ) {
    self.rootIdentity = rootIdentity
    self.renderer = renderer
    self.terminalHost = terminalHost
    self.terminalInputReader = terminalInputReader
    self.signalReader = signalReader
    self.scheduler = scheduler
    self.stateContainer = stateContainer
    self.focusTracker = focusTracker
    self.keyHandler = keyHandler
    self.environment = environment
    self.environmentValues = environmentValues
    self.proposalOverride = proposal
    self.viewBuilder = viewBuilder
  }

  package convenience init(
    rootIdentity: Identity,
    renderer: DefaultRenderer = .init(),
    terminalHost: any TerminalHosting,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    viewBuilder: @escaping ErasedStateBodyBuilder<State>
  ) {
    self.init(
      rootIdentity: rootIdentity,
      renderer: renderer,
      terminalHost: terminalHost,
      terminalInputReader: KeyboardInputAdapter(inputReader: inputReader),
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      viewBuilder: viewBuilder
    )
  }

  /// Creates a run loop from a strongly typed `View` builder.
  public convenience init<Content: View>(
    rootIdentity: Identity,
    renderer: DefaultRenderer = .init(),
    terminalHost: any TerminalHosting,
    terminalInputReader: any TerminalInputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    viewBuilder: @escaping (_ state: State, _ focusedIdentity: Identity?) -> Content
  ) {
    self.init(
      rootIdentity: rootIdentity,
      renderer: renderer,
      terminalHost: terminalHost,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      viewBuilder: { state, focusedIdentity in
        AnyView(viewBuilder(state, focusedIdentity))
      }
    )
  }

  /// Creates a run loop from a strongly typed `View` builder and a keyboard-only
  /// input source.
  public convenience init<Content: View>(
    rootIdentity: Identity,
    renderer: DefaultRenderer = .init(),
    terminalHost: any TerminalHosting,
    inputReader: any InputReading,
    signalReader: (any SignalReading)? = nil,
    scheduler: any FrameScheduling = FrameScheduler(),
    stateContainer: StateContainer<State>,
    focusTracker: FocusTracker,
    keyHandler: StateKeyHandler<State>? = nil,
    environment: EnvironmentSnapshot = .init(),
    environmentValues: EnvironmentValues = .init(),
    proposal: ProposedSize? = nil,
    viewBuilder: @escaping (_ state: State, _ focusedIdentity: Identity?) -> Content
  ) {
    self.init(
      rootIdentity: rootIdentity,
      renderer: renderer,
      terminalHost: terminalHost,
      terminalInputReader: KeyboardInputAdapter(inputReader: inputReader),
      signalReader: signalReader,
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      keyHandler: keyHandler,
      environment: environment,
      environmentValues: environmentValues,
      proposal: proposal,
      viewBuilder: viewBuilder
    )
  }

  @MainActor
  /// Runs the interactive session until input ends, a quit condition occurs, or
  /// the session is cancelled.
  public func run() async throws -> RunLoopResult<State> {
    stateContainer.invalidator = scheduler
    focusTracker.invalidator = scheduler
    observationBridge.attachInvalidator(scheduler)

    try terminalHost.enableRawMode()
    defer {
      lifecycleCoordinator.shutdown()
      try? terminalHost.disableRawMode()
    }

    scheduler.requestInvalidation(of: [rootIdentity])

    var renderedFrames = 0
    try renderPendingFrames(renderedFrames: &renderedFrames)

    let eventPump = makeEventPump()
    defer {
      eventPump.cancel()
    }

    var iterator = eventPump.stream.makeAsyncIterator()
    while await iterator.next() != nil {
      let pendingEvents = await drainPendingEvents(from: eventPump)
      guard !pendingEvents.isEmpty else {
        if scheduler.hasPendingFrame(at: .now()) {
          try renderPendingFrames(renderedFrames: &renderedFrames)
        }
        continue
      }

      var handledNonExitEvent = false
      for event in pendingEvents {
        let hadReadyFrameBeforeEvent = scheduler.hasPendingFrame(at: .now())
        if let exitReason = handle(event) {
          let shouldFlushBeforeExit =
            handledNonExitEvent
            || (hadReadyFrameBeforeEvent && {
              if case .signal = exitReason {
                return true
              }
              return false
            }())
          if shouldFlushBeforeExit {
            try renderPendingFrames(renderedFrames: &renderedFrames)
          }
          return RunLoopResult(
            finalState: stateContainer.state,
            renderedFrames: renderedFrames,
            exitReason: exitReason
          )
        }
        handledNonExitEvent = true
      }
      try renderPendingFrames(renderedFrames: &renderedFrames)
    }

    return RunLoopResult(
      finalState: stateContainer.state,
      renderedFrames: renderedFrames,
      exitReason: .inputEnded
    )
  }
}

private final class KeyboardInputAdapter: TerminalInputReading {
  private let inputReader: any InputReading

  init(inputReader: any InputReading) {
    self.inputReader = inputReader
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let keyEvents = self.inputReader.events()
      let task = Task {
        for await keyPress in keyEvents {
          continuation.yield(.key(keyPress))
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
