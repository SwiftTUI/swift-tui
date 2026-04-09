public import Core

/// Keyed storage for custom animation state.
public struct AnimationState: Sendable {
  private var storage: [String: any AnySendableValue] = [:]

  public init() {}

  public subscript<T: Sendable>(key: String, as type: T.Type = T.self) -> T? {
    get { (storage[key] as? TypedValue<T>)?.value }
    set {
      if let newValue {
        storage[key] = TypedValue(value: newValue)
      } else {
        storage.removeValue(forKey: key)
      }
    }
  }
}

private protocol AnySendableValue: Sendable {}

private struct TypedValue<T: Sendable>: AnySendableValue {
  let value: T
}

/// Snapshot of environment state available to custom animations.
public struct AnimationEnvironmentSnapshot: Sendable {
  public init() {}
}

/// Context provided to custom animation implementations.
public struct AnimationContext<Value: VectorArithmetic>: Sendable {
  public var state: AnimationState
  public var environment: AnimationEnvironmentSnapshot

  public init(
    state: AnimationState = .init(),
    environment: AnimationEnvironmentSnapshot = .init()
  ) {
    self.state = state
    self.environment = environment
  }
}

/// Protocol for user-defined animation curves.
public protocol CustomAnimation: Hashable, Sendable {
  /// Returns the animated value at the given time, or `nil` if complete.
  func animate<V: VectorArithmetic>(
    value: V, time: Duration, context: inout AnimationContext<V>
  ) -> V?

  /// Whether this animation should merge with a previous one.
  func shouldMerge<V: VectorArithmetic>(
    previous: Animation, value: V, time: Duration,
    context: inout AnimationContext<V>
  ) -> Bool

  /// Returns the current velocity for interrupted animation handoff.
  func velocity<V: VectorArithmetic>(
    value: V, time: Duration, context: AnimationContext<V>
  ) -> V?
}

extension CustomAnimation {
  public func shouldMerge<V: VectorArithmetic>(
    previous: Animation, value: V, time: Duration,
    context: inout AnimationContext<V>
  ) -> Bool { false }

  public func velocity<V: VectorArithmetic>(
    value: V, time: Duration, context: AnimationContext<V>
  ) -> V? { nil }
}
