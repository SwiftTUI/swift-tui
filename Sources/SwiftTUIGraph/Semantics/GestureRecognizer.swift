/// Lifecycle phases of a gesture recognizer, matching UIKit's
/// `UIGestureRecognizer.State` and SwiftUI's internal state model.
public enum GestureRecognizerPhase: Equatable, Sendable {
  /// No event yet relevant to this recognizer.
  case possible
  /// Recognition started but is not final, such as after the first drag event.
  case began
  /// Recognizer has produced an intermediate value.
  case changed
  /// Recognizer produced a final value. Terminal.
  case ended
  /// Recognizer will not produce a value. Terminal.
  case failed
  /// An external action canceled recognition, such as a subtree teardown. This state is terminal.
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
  /// The recognizer examined the event but did not claim it.
  /// For example, the drag distance can be less than `minimumDistance`.
  /// The event can continue to parent routes.
  case ignored
  /// The recognizer explicitly failed on this event. This state is terminal for this recognizer.
  /// The registry removes the recognizer, and the event can continue to a parent route.
  case failed
}

/// The environment that `Gesture._makeRecognizer` uses to connect the recognizer to runtime services.
///
/// The type is `public`, so it appears in the `_makeRecognizer` signature of `public` gesture types.
/// Its stored fields and initializer are `package`.
/// Only the SwiftTUI runtime creates this value.
/// External gesture authors receive it as a parameter and pass it to child gestures.
/// They do not create it directly.
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

  /// Adopts the user-authored callbacks from `replacement` — a recognizer
  /// built by a re-resolve of the same gesture declaration — while keeping
  /// this recognizer's interaction state. The registry calls this when it
  /// preserves a mid-interaction recognizer and discards the fresh
  /// replacement: without adoption the preserved tree keeps firing the
  /// closures captured when the interaction began, writing through bindings
  /// the view has since re-authored. Returns `false` when the trees'
  /// types/shapes diverge; the preserved recognizer then keeps its closures.
  func adoptAuthoredCallbacks(from replacement: AnyObject) -> Bool

  /// Resets a TERMINAL recognizer to its initial state so the next
  /// interaction can begin (F128). One-shot recognizers park in absorbing
  /// terminal phases after firing or failing; when the fired action mutates
  /// no state, no re-resolve re-authors a fresh recognizer and the view
  /// would otherwise stay gesture-dead. The dispatch site calls this on a
  /// fresh `.down`. Implementations MUST no-op while non-terminal — an
  /// active interaction's state is never discarded — and wrappers forward
  /// to their wrapped recognizers.
  func reArm()
}

extension GestureRecognizer {
  package var isActive: Bool {
    phase != .possible && !phase.isTerminal
  }

  package func adoptAuthoredCallbacks(from replacement: AnyObject) -> Bool {
    // Callback-free recognizers (the primitive state machines) adopt
    // successfully from any same-type replacement: their interaction state
    // is theirs to keep and there are no closures to refresh. Primitives
    // with authored VALUE parameters (thresholds, counts, coordinate
    // spaces) override to copy them — a preserved mid-interaction
    // recognizer must honor the re-authored tuning, not the one captured
    // when the interaction began.
    replacement is Self
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
  private let _adoptAuthoredCallbacks: (AnyObject) -> Bool
  private let _reArm: () -> Void
  /// The wrapped recognizer instance, exposed so a preserved recognizer can
  /// adopt authored callbacks from a discarded replacement's base.
  package let base: AnyObject
  public let valueType: Any.Type

  /// Monotonic authoring order across every recognizer the process builds.
  /// A recognizer authored by a later resolve pass carries a strictly
  /// greater mint, giving `LocalGestureRegistry.restore` a freshness order
  /// between a preserved mid-interaction recognizer and the committed
  /// record being re-installed over it: authored callbacks are adopted only
  /// from a strictly fresher record, never from a stale one re-published on
  /// a cache-hit frame (which would regress callbacks backward).
  private static var authoredMintCounter: UInt64 = 0

  /// The freshest authoring mint whose user callbacks this recognizer
  /// carries: its own construction mint, advanced when a restore or pass
  /// reconciliation adopts a fresher registration's callbacks.
  package private(set) var carriedAuthoredMintGeneration: UInt64

  package init<R: GestureRecognizer>(_ recognizer: R) {
    self._phase = { recognizer.phase }
    self._isActive = { recognizer.isActive }
    self._handleEvent = { recognizer.handle(event: $0) }
    self._handleDeadline = { recognizer.handleDeadline(at: $0) }
    self._tearDown = { recognizer.tearDown() }
    self._currentValue = { recognizer.currentValue() }
    self._adoptAuthoredCallbacks = { recognizer.adoptAuthoredCallbacks(from: $0) }
    self._reArm = { recognizer.reArm() }
    self.base = recognizer
    self.valueType = R.Value.self
    // 64-bit wraparound is deliberately unguarded (F122): unreachable in
    // practice, and the freshness comparisons assume no value reuse.
    Self.authoredMintCounter &+= 1
    self.carriedAuthoredMintGeneration = Self.authoredMintCounter
  }

  /// Records that this recognizer's callbacks now reflect the authoring
  /// mint of an adopted registration. Never moves backward.
  package func noteCarriedAuthoredMint(_ mint: UInt64) {
    carriedAuthoredMintGeneration = max(carriedAuthoredMintGeneration, mint)
  }

  public var phase: GestureRecognizerPhase { _phase() }

  /// Whether the recognizer is mid-interaction. `LocalGestureRegistry`
  /// uses this to preserve state when `.gesture(_:)` re-resolves during
  /// an active gesture.
  public var isActive: Bool { _isActive() }

  package func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    _handleEvent(event)
  }

  package func handleClassified(event: LocalPointerEvent) -> PointerDispatchOutcome {
    if let roleAware = base as? any RoleAwarePointerDispatching {
      return roleAware.handleClassified(event: event)
    }
    switch handle(event: event) {
    case .handled:
      return .claimed
    case .failed:
      return .failed
    case .ignored:
      return .ignored
    }
  }

  /// See ``GestureRecognizer/reArm()``.
  package func reArm() {
    _reArm()
  }

  package func handleDeadline(at instant: MonotonicInstant) -> Bool {
    _handleDeadline(instant)
  }

  /// Drains a scheduled gesture deadline while retaining attachment-role
  /// currency for the eventual pointer release.
  package func handleDeadlineClassified(
    at instant: MonotonicInstant
  ) -> PointerDispatchOutcome {
    if let roleAware = base as? any RoleAwarePointerDispatching {
      return roleAware.handleDeadlineClassified(at: instant)
    }
    guard _handleDeadline(instant) else {
      return .ignored
    }
    return _phase() == .ended ? .claimed : .failed
  }

  package func tearDown() {
    _tearDown()
  }

  /// Reads `currentValue()` from the inner recognizer and casts the value to `T`.
  /// If the inner value is `nil` or has a different type, returns `nil`.
  public func currentValue<T>(as type: T.Type = T.self) -> T? {
    _currentValue() as? T
  }

  /// See ``GestureRecognizer/adoptAuthoredCallbacks(from:)``.
  package func adoptAuthoredCallbacks(from replacement: AnyGestureRecognizer) -> Bool {
    guard base !== replacement.base else {
      return true
    }
    return _adoptAuthoredCallbacks(replacement.base)
  }
}
