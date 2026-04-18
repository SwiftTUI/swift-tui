public import Core

// MARK: - .onEnded

public struct _EndedGesture<Child: Gesture>: Gesture {
  public typealias Value = Child.Value
  public typealias Body = Never

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

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    let disposition = inner.handle(event: event)
    if let value: V = inner.currentValue(as: V.self), value != lastValue {
      action(value)
      lastValue = value
    }
    return disposition
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    let didTerminate = inner.handleDeadline(at: instant)
    if let value: V = inner.currentValue(as: V.self), value != lastValue {
      action(value)
      lastValue = value
    }
    return didTerminate
  }

  func currentValue() -> V? { inner.currentValue(as: V.self) }

  func tearDown() { inner.tearDown() }
}

// MARK: - .map

public struct _MapGesture<Child: Gesture, NewValue>: Gesture {
  public typealias Value = NewValue
  public typealias Body = Never

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

public struct GestureStateGesture<Child: Gesture, State>: Gesture {
  public typealias Value = Child.Value
  public typealias Body = Never

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

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    let disposition = inner.handle(event: event)
    if disposition == .handled,
      let value: V = inner.currentValue(as: V.self)
    {
      var state = box.currentValue()
      var transaction = Transaction()
      updater(value, &state, &transaction)
      box.setValue(state)
    }
    if inner.phase.isTerminal {
      box.resetToSeed()
    }
    return disposition
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    let didTerminate = inner.handleDeadline(at: instant)
    if didTerminate {
      box.resetToSeed()
    }
    return didTerminate
  }

  func currentValue() -> V? { inner.currentValue(as: V.self) }

  func tearDown() {
    inner.tearDown()
    box.resetToSeed()
  }
}
