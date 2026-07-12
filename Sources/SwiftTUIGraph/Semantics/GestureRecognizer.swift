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

  /// Adopts the user-authored callbacks from `replacement` — a recognizer
  /// built by a re-resolve of the same gesture declaration — while keeping
  /// this recognizer's interaction state. The registry calls this when it
  /// preserves a mid-interaction recognizer and discards the fresh
  /// replacement: without adoption the preserved tree keeps firing the
  /// closures captured when the interaction began, writing through bindings
  /// the view has since re-authored. Returns `false` when the trees'
  /// types/shapes diverge; the preserved recognizer then keeps its closures.
  func adoptAuthoredCallbacks(from replacement: AnyObject) -> Bool
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

  /// See ``GestureRecognizer/adoptAuthoredCallbacks(from:)``.
  package func adoptAuthoredCallbacks(from replacement: AnyGestureRecognizer) -> Bool {
    guard base !== replacement.base else {
      return true
    }
    return _adoptAuthoredCallbacks(replacement.base)
  }
}
