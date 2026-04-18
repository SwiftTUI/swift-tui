/// Lifecycle phases of a gesture recognizer, matching UIKit's
/// `UIGestureRecognizer.State` and SwiftUI's internal state model.
public enum GestureRecognizerPhase: Equatable, Sendable {
  /// No event yet relevant to this recognizer.
  case possible
  /// Recognition has begun but isn't yet final (e.g. first drag event).
  case began
  /// Recognizer has produced an intermediate value.
  case changed
  /// Recognizer produced a final value. Terminal.
  case ended
  /// Recognizer will not produce a value. Terminal.
  case failed
  /// Recognizer was externally cancelled (subtree teardown, etc.). Terminal.
  case cancelled

  public var isTerminal: Bool {
    switch self {
    case .ended, .failed, .cancelled: return true
    case .possible, .began, .changed: return false
    }
  }
}

/// Outcome of delivering a pointer event to a recognizer.
public enum GestureRecognizerEventDisposition: Equatable, Sendable {
  /// Recognizer consumed the event. The event must not bubble.
  case handled
  /// Recognizer inspected the event but didn't claim it (e.g. below
  /// minimumDistance for a drag). The event may bubble to parent routes.
  case ignored
  /// Recognizer explicitly failed on this event. Terminal for this
  /// recognizer; the registry removes it and the event may bubble.
  case failed
}

/// Environment used by `Gesture._makeRecognizer` to wire the recognizer
/// to runtime services. Opaque to authors.
public struct GestureRecognizerBuildContext: Sendable {
  public let attachingIdentity: Identity
  package let gestureStateRegistry: LocalGestureStateRegistry?
  public let requestDeadline: @MainActor @Sendable (MonotonicInstant) -> Void

  package init(
    attachingIdentity: Identity,
    gestureStateRegistry: LocalGestureStateRegistry?,
    requestDeadline: @escaping @MainActor @Sendable (MonotonicInstant) -> Void
  ) {
    self.attachingIdentity = attachingIdentity
    self.gestureStateRegistry = gestureStateRegistry
    self.requestDeadline = requestDeadline
  }
}

/// Core recognizer protocol. Implementations own a state machine and
/// optionally a deadline timer. All calls happen on the main actor.
@MainActor
package protocol GestureRecognizer: AnyObject {
  associatedtype Value

  var phase: GestureRecognizerPhase { get }

  /// Delivers an event. Returns whether the event was consumed.
  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition

  /// Invoked by the runtime when a deadline the recognizer scheduled
  /// has arrived. Returns `true` if the recognizer transitioned to a
  /// terminal phase as a result.
  func handleDeadline(at instant: MonotonicInstant) -> Bool

  /// Reads the recognizer's current value, if any. Called after
  /// `handle(event:)` returns `.handled` to propagate to `.onChanged`
  /// and `.onEnded` callbacks.
  func currentValue() -> Value?

  /// Releases any held runtime resources (deadline timers, GestureState
  /// bindings). Called on subtree teardown or after terminal phase.
  func tearDown()
}

/// Type-erasing wrapper so the `Gesture` protocol can be used without
/// exposing Value at the registry level.
@MainActor
public final class AnyGestureRecognizer {
  private let _phase: () -> GestureRecognizerPhase
  private let _handleEvent: (LocalPointerEvent) -> GestureRecognizerEventDisposition
  private let _handleDeadline: (MonotonicInstant) -> Bool
  private let _tearDown: () -> Void

  package init<R: GestureRecognizer>(_ recognizer: R) {
    self._phase = { recognizer.phase }
    self._handleEvent = { recognizer.handle(event: $0) }
    self._handleDeadline = { recognizer.handleDeadline(at: $0) }
    self._tearDown = { recognizer.tearDown() }
  }

  public var phase: GestureRecognizerPhase { _phase() }

  package func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    _handleEvent(event)
  }

  package func handleDeadline(at instant: MonotonicInstant) -> Bool {
    _handleDeadline(instant)
  }

  package func tearDown() {
    _tearDown()
  }
}
