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
/// to runtime services.
///
/// The type is `public` so it appears in the `_makeRecognizer` signature
/// of `public` gesture types, but its stored fields and initializer are
/// `package` — only the SwiftTUI runtime constructs this. External
/// gesture authors receive it as a parameter and forward it to child
/// gestures; they never construct it directly.
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

  /// Indicates the recognizer has begun processing a pointer interaction
  /// and has not yet reached a terminal phase. The runtime uses this to
  /// preserve recognizer state across view re-resolves that would
  /// otherwise rebuild and discard the recognizer mid-gesture.
  ///
  /// Default: `phase != .possible && !phase.isTerminal` (began/changed).
  /// Primitives that capture interaction state while still in `.possible`
  /// — e.g. `DragGesture` records `startLocation` on `.down` but stays
  /// in `.possible` until `minimumDistance` is crossed — should override
  /// to include their "has started tracking" condition.
  var isActive: Bool { get }

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

extension GestureRecognizer {
  package var isActive: Bool {
    phase != .possible && !phase.isTerminal
  }
}

/// Type-erasing wrapper so the `Gesture` protocol can be used without
/// exposing Value at the registry level.
@MainActor
public final class AnyGestureRecognizer {
  private let _phase: () -> GestureRecognizerPhase
  private let _isActive: () -> Bool
  private let _handleEvent: (LocalPointerEvent) -> GestureRecognizerEventDisposition
  private let _handleDeadline: (MonotonicInstant) -> Bool
  private let _tearDown: () -> Void
  /// Boxes the recognizer's currentValue() — callers cast to their
  /// expected type via `currentValue(as:)`.
  private let _currentValue: () -> Any?
  public let valueType: Any.Type

  package init<R: GestureRecognizer>(_ recognizer: R) {
    self._phase = { recognizer.phase }
    self._isActive = { recognizer.isActive }
    self._handleEvent = { recognizer.handle(event: $0) }
    self._handleDeadline = { recognizer.handleDeadline(at: $0) }
    self._tearDown = { recognizer.tearDown() }
    self._currentValue = { recognizer.currentValue() }
    self.valueType = R.Value.self
  }

  public var phase: GestureRecognizerPhase { _phase() }

  /// Whether the recognizer is mid-interaction. `LocalGestureRegistry`
  /// uses this to preserve state when `.gesture(_:)` re-resolves during
  /// an active gesture.
  public var isActive: Bool { _isActive() }

  package func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    _handleEvent(event)
  }

  package func handleDeadline(at instant: MonotonicInstant) -> Bool {
    _handleDeadline(instant)
  }

  package func tearDown() {
    _tearDown()
  }

  /// Reads the inner recognizer's `currentValue()` and casts to `T`.
  /// Returns `nil` if the inner value is nil or the type doesn't match.
  public func currentValue<T>(as type: T.Type = T.self) -> T? {
    _currentValue() as? T
  }
}
