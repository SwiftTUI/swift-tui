public import SwiftTUICore

// The public gesture combinators. Each `_XGesture` lowers to a
// `GestureRecognizer` decorator; those decorators live in
// `GestureModifierDecorators.swift`.

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
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    return AnyGestureRecognizer(
      OnEndedDecorator<Child.Value>(
        inner: inner,
        authoringContext: authoringContext,
        action: action
      )
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
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    return AnyGestureRecognizer(
      OnChangedDecorator<Child.Value>(
        inner: inner,
        authoringContext: authoringContext,
        action: action
      )
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
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    return AnyGestureRecognizer(
      MapDecorator<Child.Value, NewValue>(
        inner: inner,
        authoringContext: authoringContext,
        transform: transform
      )
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
    let authoringContext = currentImperativeAuthoringContextSnapshot()

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
        authoringContext: authoringContext,
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
  /// > can inspect or mutate animation semantics. SwiftTUI does
  /// > not yet plumb this through; mutations to the transaction
  /// > inside the closure are silently discarded.
  ///
  /// Full transaction threading is a deferred enhancement; mutations to
  /// the transaction inside the closure are currently silently discarded.
  public func updating<State>(
    _ state: GestureStateBinding<State>,
    body: @escaping @MainActor (Value, inout State, inout Transaction) -> Void
  ) -> GestureStateGesture<Self, State> {
    GestureStateGesture(child: self, state: state, updater: body)
  }
}
