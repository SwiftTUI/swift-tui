import SwiftTUICore
import SwiftTUIViews
import Synchronization

package typealias ViewBuilderInput<State: Equatable & Sendable> = (
  state: State,
  focusedIdentity: Identity?
)

package typealias DeferredStateBodyBuilder<State: Equatable & Sendable, Content: View> =
  ScopedMapper<ViewBuilderInput<State>, Content>

/// Handles a key event and can change the run-loop state.
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
/// - ``programmatic``: authored content requested termination through the
///   environment's termination action.
/// - ``userExit(_:)``: a key press configured in ``ExitKeyBindings``
///   was received. The associated `KeyPress` identifies which key.
/// - ``signal(_:)``: the run loop terminated in response to an OS
///   signal (for example `SIGTERM`).
/// - ``inputEnded``: the input stream reached end-of-file.
public enum RunLoopExitReason: Equatable, Sendable {
  case programmatic
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

/// A signal reader whose OS signal sources can be installed ahead of
/// run-loop startup.
///
/// When the sources instead register lazily on the run loop's own startup
/// path, they race the first frame render; a SIGINT/SIGTERM delivered while
/// registration is still in flight is discarded by the kernel. Session
/// bootstrap arms conforming readers before rendering begins.
package protocol SignalSourceArming: SignalReading {
  /// Installs the OS signal sources and returns once they are registered
  /// with the kernel.
  func armSignalSources() async
}

/// Emits runtime signals from an in-process source.
public final class InProcessSignalReader: SignalReading, Sendable {
  private struct State: Sendable {
    var continuation: AsyncStream<String>.Continuation?
    var continuationGeneration: UInt64 = 0
    var directHandler: (@Sendable (String) -> Void)?
    // Hosted transports can publish their initial resize while the run loop
    // is still installing its event streams. Preserve that wake instead of
    // leaving the first frame at the fallback grid until unrelated input.
    var pendingSignals: [String] = []
    var isFinished = false
  }

  private let state = Mutex(State())

  public init() {}

  public func events() -> AsyncStream<String> {
    makeManagedAsyncStream { continuation in
      let generation = self.state.withLock { state in
        state.continuationGeneration &+= 1
        guard !state.isFinished else {
          continuation.finish()
          return state.continuationGeneration
        }
        state.continuation = continuation
        for signalName in state.pendingSignals {
          continuation.yield(signalName)
        }
        state.pendingSignals.removeAll(keepingCapacity: true)
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
    // The direct handler is arbitrary code: the Android direct pump
    // dispatches run-loop event processing synchronously from it, and that
    // processing can re-enter send() (a host callback requesting a surface
    // refresh). The Mutex is not recursive, so the handler must be invoked
    // OUTSIDE the lock. Continuation yields stay in-lock — AsyncStream's
    // yield is non-blocking and runs no consumer code inline. A handler
    // invocation that races clearDirectHandler()/finish() can still deliver
    // one in-flight signal after the clear, matching the pre-buffering
    // behavior of this type.
    let directHandler = state.withLock { state -> (@Sendable (String) -> Void)? in
      guard !state.isFinished else {
        return nil
      }
      if let directHandler = state.directHandler {
        return directHandler
      }
      if let continuation = state.continuation {
        continuation.yield(signalName)
      } else {
        state.pendingSignals.append(signalName)
      }
      return nil
    }
    directHandler?(signalName)
  }

  public func finish() {
    let continuation = state.withLock { state in
      let continuation = state.continuation
      state.continuation = nil
      state.directHandler = nil
      state.pendingSignals.removeAll(keepingCapacity: false)
      state.isFinished = true
      return continuation
    }
    continuation?.finish()
  }

  package func installDirectHandler(
    _ handler: @escaping @Sendable (String) -> Void
  ) {
    // Flush outside the lock for the same re-entrancy reason as send(): a
    // buffered signal's synchronous handling can send follow-up signals.
    let pendingSignals = state.withLock { state -> [String] in
      guard !state.isFinished else {
        return []
      }
      state.directHandler = handler
      let pending = state.pendingSignals
      state.pendingSignals.removeAll(keepingCapacity: true)
      return pending
    }
    for signalName in pendingSignals {
      handler(signalName)
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
