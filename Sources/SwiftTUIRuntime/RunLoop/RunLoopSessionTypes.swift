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
    var directHandler: (@Sendable (String) -> Void)?
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
    let (continuation, directHandler) = state.withLock { state in
      (state.continuation, state.directHandler)
    }
    if let directHandler {
      directHandler(signalName)
    } else {
      continuation?.yield(signalName)
    }
  }

  public func finish() {
    let continuation = state.withLock { state in
      let continuation = state.continuation
      state.continuation = nil
      state.directHandler = nil
      return continuation
    }
    continuation?.finish()
  }

  package func installDirectHandler(
    _ handler: @escaping @Sendable (String) -> Void
  ) {
    state.withLock { state in
      state.directHandler = handler
    }
  }

  package func clearDirectHandler() {
    state.withLock { state in
      state.directHandler = nil
    }
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
