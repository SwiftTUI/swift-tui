import SwiftTUICore

// The gesture-recognizer decorators.
//
// Each public gesture combinator in `GestureModifiers.swift` (`onEnded`,
// `onChanged`, `map`, `updating`) lowers to a `GestureRecognizer` that wraps
// an inner recognizer and observes its phase transitions:
//
// - `OnEndedDecorator` fires its action once when the inner gesture ends.
// - `OnChangedDecorator` fires whenever the inner value changes.
// - `MapDecorator` transforms the inner value lazily on read.
// - `UpdatingDecorator` threads the value into a `@GestureState` cell and
//   resets it on termination.
//
// Split out of `GestureModifiers.swift` so that file stays focused on the
// public `_XGesture` combinator types and their `Gesture` extensions.

// MARK: - .onEnded

@MainActor
final class OnEndedDecorator<V>: GestureRecognizer {
  typealias Value = V
  let inner: AnyGestureRecognizer
  let authoringContext: ImperativeAuthoringContextSnapshot?
  let action: @MainActor (V) -> Void
  private var didFire = false

  init(
    inner: AnyGestureRecognizer,
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping @MainActor (V) -> Void
  ) {
    self.inner = inner
    self.authoringContext = authoringContext
    self.action = action
  }

  var phase: GestureRecognizerPhase { inner.phase }
  var isActive: Bool { inner.isActive }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    let disposition = inner.handle(event: event)
    fireIfNeeded()
    return disposition
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    let didTerminate = inner.handleDeadline(at: instant)
    fireIfNeeded()
    return didTerminate
  }

  func currentValue() -> V? { inner.currentValue(as: V.self) }

  func tearDown() { inner.tearDown() }

  private func fireIfNeeded() {
    guard !didFire, inner.phase == .ended else { return }
    if let value: V = inner.currentValue(as: V.self) {
      withImperativeAuthoringContext(authoringContext) {
        action(value)
      }
      didFire = true
    }
  }
}

// MARK: - .onChanged

@MainActor
final class OnChangedDecorator<V: Equatable>: GestureRecognizer {
  typealias Value = V
  let inner: AnyGestureRecognizer
  let authoringContext: ImperativeAuthoringContextSnapshot?
  let action: @MainActor (V) -> Void
  private var lastValue: V?

  init(
    inner: AnyGestureRecognizer,
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping @MainActor (V) -> Void
  ) {
    self.inner = inner
    self.authoringContext = authoringContext
    self.action = action
  }

  var phase: GestureRecognizerPhase { inner.phase }
  var isActive: Bool { inner.isActive }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    let disposition = inner.handle(event: event)
    fireIfNeeded()
    return disposition
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    let didTerminate = inner.handleDeadline(at: instant)
    fireIfNeeded()
    return didTerminate
  }

  func currentValue() -> V? { inner.currentValue(as: V.self) }

  func tearDown() { inner.tearDown() }

  private func fireIfNeeded() {
    if let value: V = inner.currentValue(as: V.self), value != lastValue {
      withImperativeAuthoringContext(authoringContext) {
        action(value)
      }
      lastValue = value
    }
  }
}

// MARK: - .map

@MainActor
final class MapDecorator<From, To>: GestureRecognizer {
  typealias Value = To
  let inner: AnyGestureRecognizer
  let authoringContext: ImperativeAuthoringContextSnapshot?
  let transform: @MainActor (From) -> To

  init(
    inner: AnyGestureRecognizer,
    authoringContext: ImperativeAuthoringContextSnapshot?,
    transform: @escaping @MainActor (From) -> To
  ) {
    self.inner = inner
    self.authoringContext = authoringContext
    self.transform = transform
  }

  var phase: GestureRecognizerPhase { inner.phase }
  var isActive: Bool { inner.isActive }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    inner.handle(event: event)
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    inner.handleDeadline(at: instant)
  }

  func currentValue() -> To? {
    guard let from: From = inner.currentValue(as: From.self) else { return nil }
    return withImperativeAuthoringContext(authoringContext) {
      transform(from)
    }
  }

  func tearDown() { inner.tearDown() }
}

// MARK: - .updating($gestureState)

@MainActor
final class UpdatingDecorator<V, S>: GestureRecognizer {
  typealias Value = V

  let inner: AnyGestureRecognizer
  let box: GestureStateBox<S>
  let authoringContext: ImperativeAuthoringContextSnapshot?
  let updater: @MainActor (V, inout S, inout Transaction) -> Void

  /// Tracks whether this decorator's updater has actually written to
  /// `box` during the gesture's lifetime. Guards `box.resetToSeed()`:
  /// resetting an already-seed box is surprisingly consequential
  /// because `.gesture(_:)` rebuilds its recognizer tree on every
  /// resolve, and `LocalGestureRegistry.register` tears down the
  /// previous recognizer on replace — if `tearDown` unconditionally
  /// called `resetToSeed`, an attached gesture that never fired would
  /// still write to the `@GestureState` slot every frame, dirtying the
  /// owning view and scheduling another resolve pass ad infinitum.
  private var didFire = false

  init(
    inner: AnyGestureRecognizer,
    box: GestureStateBox<S>,
    authoringContext: ImperativeAuthoringContextSnapshot?,
    updater: @escaping @MainActor (V, inout S, inout Transaction) -> Void
  ) {
    self.inner = inner
    self.box = box
    self.authoringContext = authoringContext
    self.updater = updater
  }

  var phase: GestureRecognizerPhase { inner.phase }
  var isActive: Bool { inner.isActive }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    let disposition = inner.handle(event: event)
    if disposition == .handled,
      let value: V = inner.currentValue(as: V.self)
    {
      let nextState = withImperativeAuthoringContext(authoringContext) { () -> S in
        var state = box.currentValue()
        var transaction = Transaction()
        updater(value, &state, &transaction)
        return state
      }
      withImperativeAuthoringContext(authoringContext) {
        box.setValue(nextState)
      }
      didFire = true
    }
    if inner.phase.isTerminal, didFire {
      withImperativeAuthoringContext(authoringContext) {
        box.resetToSeed()
      }
      didFire = false
    }
    return disposition
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    let didTerminate = inner.handleDeadline(at: instant)
    if didTerminate, didFire {
      withImperativeAuthoringContext(authoringContext) {
        box.resetToSeed()
      }
      didFire = false
    }
    return didTerminate
  }

  func currentValue() -> V? { inner.currentValue(as: V.self) }

  func tearDown() {
    inner.tearDown()
    if didFire {
      box.resetToSeed()
      didFire = false
    }
  }
}
