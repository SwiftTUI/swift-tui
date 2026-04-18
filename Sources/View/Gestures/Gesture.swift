public import Core

/// An input handler that produces values of `Value` over time.
///
/// Conforms to SwiftUI's `Gesture` protocol shape: primitives declare
/// `typealias Body = Never` and implement `_makeRecognizer(context:)`;
/// composed gestures (combinators and `.onEnded`/`.updating` modifiers)
/// have a body expressed in terms of other gestures.
@MainActor
public protocol Gesture<Value> {
  associatedtype Value
  associatedtype Body: Gesture

  @GestureBuilder var body: Body { get }

  /// Builds the primitive recognizer tree for this gesture. Composed
  /// gestures forward to their body; primitives return a recognizer
  /// directly.
  func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer
}

extension Gesture where Body: Gesture, Body.Value == Value {
  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    body._makeRecognizer(context: context)
  }
}

/// Escape hatch for primitives that have no body.
public func neverBody() -> Never {
  fatalError("A primitive Gesture has no body — _makeRecognizer was not called.")
}

// `Never` already conforms to `View` in ViewFoundation.swift, providing
// `typealias Body = Never` and `var body: Never`. The same witnesses satisfy
// `Gesture`'s `body` and `Body` requirements.
//
// `Never.Value = Never` makes `Body.Value == Value` vacuously true for the
// recursive `Never: Gesture` conformance. Primitives that declare
// `typealias Body = Never` but have a non-Never `Value` do not get the
// default `_makeRecognizer` (which requires `Body.Value == Value`); they
// must — and do — provide their own implementation.
extension Never: Gesture {
  public typealias Value = Never

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    neverBody()
  }
}

/// Result builder for `Gesture.body`, matching SwiftUI's `@GestureBuilder`.
@resultBuilder
public enum GestureBuilder {
  public static func buildBlock<G: Gesture>(_ gesture: G) -> G { gesture }
}
