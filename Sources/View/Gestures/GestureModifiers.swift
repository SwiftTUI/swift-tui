public import Core

// MARK: - .onEnded

public struct _EndedGesture<Child: Gesture>: Gesture {
  public typealias Value = Child.Value
  public typealias Body = Never

  public static var _needsPointerCapture: Bool { Child._needsPointerCapture }

  public let child: Child
  public let action: @MainActor (Child.Value) -> Void

  public init(
    child: Child,
    action: @escaping @MainActor (Child.Value) -> Void
  ) {
    self.child = child
    self.action = action
  }

  public var body: Never { neverBody() }

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    let inner = child._makeRecognizer(context: context)
    return AnyGestureRecognizer(
      OnEndedDecorator<Child.Value>(inner: inner, action: action)
    )
  }
}

extension Gesture {
  public func onEnded(
    _ action: @escaping @MainActor (Value) -> Void
  ) -> _EndedGesture<Self> {
    _EndedGesture(child: self, action: action)
  }
}

@MainActor
final class OnEndedDecorator<V>: GestureRecognizer {
  typealias Value = V
  let inner: AnyGestureRecognizer
  let action: @MainActor (V) -> Void
  private var didFire = false

  init(inner: AnyGestureRecognizer, action: @escaping @MainActor (V) -> Void) {
    self.inner = inner
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
      action(value)
      didFire = true
    }
  }
}

// MARK: - .onChanged

public struct _ChangedGesture<Child: Gesture>: Gesture where Child.Value: Equatable {
  public typealias Value = Child.Value
  public typealias Body = Never

  public static var _needsPointerCapture: Bool { Child._needsPointerCapture }

  public let child: Child
  public let action: @MainActor (Child.Value) -> Void

  public init(
    child: Child,
    action: @escaping @MainActor (Child.Value) -> Void
  ) {
    self.child = child
    self.action = action
  }

  public var body: Never { neverBody() }

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    let inner = child._makeRecognizer(context: context)
    return AnyGestureRecognizer(
      OnChangedDecorator<Child.Value>(inner: inner, action: action)
    )
  }
}

extension Gesture where Value: Equatable {
  public func onChanged(
    _ action: @escaping @MainActor (Value) -> Void
  ) -> _ChangedGesture<Self> {
    _ChangedGesture(child: self, action: action)
  }
}

@MainActor
final class OnChangedDecorator<V: Equatable>: GestureRecognizer {
  typealias Value = V
  let inner: AnyGestureRecognizer
  let action: @MainActor (V) -> Void
  private var lastValue: V?

  init(inner: AnyGestureRecognizer, action: @escaping @MainActor (V) -> Void) {
    self.inner = inner
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
      action(value)
      lastValue = value
    }
  }
}

// MARK: - .map

public struct _MapGesture<Child: Gesture, NewValue>: Gesture {
  public typealias Value = NewValue
  public typealias Body = Never

  public static var _needsPointerCapture: Bool { Child._needsPointerCapture }

  public let child: Child
  public let transform: @MainActor (Child.Value) -> NewValue

  public init(
    child: Child,
    transform: @escaping @MainActor (Child.Value) -> NewValue
  ) {
    self.child = child
    self.transform = transform
  }

  public var body: Never { neverBody() }

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    let inner = child._makeRecognizer(context: context)
    return AnyGestureRecognizer(
      MapDecorator<Child.Value, NewValue>(inner: inner, transform: transform)
    )
  }
}

extension Gesture {
  public func map<NewValue>(
    _ transform: @escaping @MainActor (Value) -> NewValue
  ) -> _MapGesture<Self, NewValue> {
    _MapGesture(child: self, transform: transform)
  }
}

@MainActor
final class MapDecorator<From, To>: GestureRecognizer {
  typealias Value = To
  let inner: AnyGestureRecognizer
  let transform: @MainActor (From) -> To

  init(inner: AnyGestureRecognizer, transform: @escaping @MainActor (From) -> To) {
    self.inner = inner
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
    return transform(from)
  }

  func tearDown() { inner.tearDown() }
}

// MARK: - .updating($gestureState)

/// A gesture that threads a value into `@GestureState` with automatic reset
/// on gesture termination.
///
/// > Warning: The `inout Transaction` parameter passed to the updater
/// > closure is currently a no-op stand-in; mutations to the transaction
/// > are silently discarded. See `Gesture.updating(_:body:)` documentation
/// > for details and tracking information.
public struct GestureStateGesture<Child: Gesture, State>: Gesture {
  public typealias Value = Child.Value
  public typealias Body = Never

  public static var _needsPointerCapture: Bool { Child._needsPointerCapture }

  public let child: Child
  public let state: GestureStateBinding<State>
  public let updater: @MainActor (Child.Value, inout State, inout Transaction) -> Void

  public init(
    child: Child,
    state: GestureStateBinding<State>,
    updater: @escaping @MainActor (Child.Value, inout State, inout Transaction) -> Void
  ) {
    self.child = child
    self.state = state
    self.updater = updater
  }

  public var body: Never { neverBody() }

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    let inner = child._makeRecognizer(context: context)

    // Register this @GestureState with the runtime so the registry can
    // reset on subtree teardown.
    context.gestureStateRegistry?.register(
      identity: context.attachingIdentity,
      binding: state.box.eraseToAnyBinding()
    )

    return AnyGestureRecognizer(
      UpdatingDecorator<Child.Value, State>(
        inner: inner,
        box: state.box,
        updater: updater
      )
    )
  }
}

extension Gesture {
  /// Threads the gesture's value into a `@GestureState`-backed cell
  /// during the gesture, with automatic reset on gesture end.
  ///
  /// > Warning: The `inout Transaction` parameter is currently a
  /// > no-op stand-in. SwiftUI threads the frame's active transaction
  /// > (from `withAnimation` or the frame scheduler) here so authors
  /// > can inspect or mutate animation semantics. TerminalUI does
  /// > not yet plumb this through; mutations to the transaction
  /// > inside the closure are silently discarded.
  ///
  /// Full transaction threading is tracked in
  /// `docs/proposals/GESTURES_IMPLEMENTATION.md` as a deferred
  /// enhancement.
  public func updating<State>(
    _ state: GestureStateBinding<State>,
    body: @escaping @MainActor (Value, inout State, inout Transaction) -> Void
  ) -> GestureStateGesture<Self, State> {
    GestureStateGesture(child: self, state: state, updater: body)
  }
}

@MainActor
final class UpdatingDecorator<V, S>: GestureRecognizer {
  typealias Value = V

  let inner: AnyGestureRecognizer
  let box: GestureStateBox<S>
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
    updater: @escaping @MainActor (V, inout S, inout Transaction) -> Void
  ) {
    self.inner = inner
    self.box = box
    self.updater = updater
  }

  var phase: GestureRecognizerPhase { inner.phase }
  var isActive: Bool { inner.isActive }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    let disposition = inner.handle(event: event)
    if disposition == .handled,
      let value: V = inner.currentValue(as: V.self)
    {
      var state = box.currentValue()
      var transaction = Transaction()
      updater(value, &state, &transaction)
      box.setValue(state)
      didFire = true
    }
    if inner.phase.isTerminal, didFire {
      box.resetToSeed()
      didFire = false
    }
    return disposition
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    let didTerminate = inner.handleDeadline(at: instant)
    if didTerminate, didFire {
      box.resetToSeed()
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
