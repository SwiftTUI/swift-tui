public import SwiftTUICore

// MARK: - Keyframes

/// A description of how a value changes over time, composed of one or more
/// ``KeyframeTrack``s.
///
/// Matches SwiftUI's `Keyframes`. Build one with a ``KeyframesBuilder``
/// closure, either directly in ``KeyframeTimeline/init(initialValue:content:)``
/// or as the `keyframes:` closure of ``KeyframeAnimator``. Conform your own
/// type to reuse a keyframe set:
///
/// ```swift
/// struct Bounce: Keyframes {
///   var body: some Keyframes<Marker> {
///     KeyframeTrack(\.y) {
///       CubicKeyframe(-3, duration: .milliseconds(400))
///       SpringKeyframe(0, spring: .bouncy)
///     }
///   }
/// }
/// ```
public protocol Keyframes<Value> {
  /// The type whose properties the tracks animate.
  associatedtype Value
  /// The composed keyframes this type expands to.
  associatedtype Body: Keyframes
  /// The composed keyframes.
  @KeyframesBuilder<Value> var body: Body { get }
}

extension Keyframes where Body == Never {
  public var body: Never {
    fatalError("\(Self.self) is a primitive keyframe collection and has no composed body.")
  }
}

/// `Never` is the body type of primitive keyframe collections. Its `Value`
/// typealias comes from the `Gesture` conformance and `Body`/`body` from the
/// `View` conformance in `ViewProtocols.swift`; an explicit redeclaration
/// here would be a duplicate.
extension Never: Keyframes {}

// MARK: - Lowering

/// Internal lowering hook: primitive keyframe collections append their
/// tracks directly instead of expanding a body. Mirrors the
/// `PrimitiveView`/`ResolvableView` split on the view side.
package protocol KeyframesLowering<Value> {
  associatedtype Value
  func lowerKeyframes(
    initialValue: Value,
    into tracks: inout [AnyKeyframeTrack<Value>]
  )
}

/// Expands `keyframes` into erased tracks: primitives lower themselves,
/// composed types expand their body first.
package func lowerKeyframes<K: Keyframes, Value>(
  _ keyframes: K,
  initialValue: Value,
  into tracks: inout [AnyKeyframeTrack<Value>]
) {
  if let primitive = keyframes as? any KeyframesLowering<Value> {
    primitive.lowerKeyframes(initialValue: initialValue, into: &tracks)
    return
  }
  lowerKeyframes(keyframes.body, initialValue: initialValue, into: &tracks)
}

/// A type-erased keyframe collection held by ``KeyframeSequence``.
package struct AnyKeyframes<Value> {
  package let lower: (Value, inout [AnyKeyframeTrack<Value>]) -> Void

  package init<K: Keyframes>(_ keyframes: K) where K.Value == Value {
    lower = { initialValue, tracks in
      lowerKeyframes(keyframes, initialValue: initialValue, into: &tracks)
    }
  }
}

// MARK: - KeyframeSequence

/// The keyframe collection a ``KeyframesBuilder`` block produces: every
/// track listed in the block, in order. Not spelled directly in app code.
public struct KeyframeSequence<Value>: Keyframes {
  public typealias Body = Never

  package var entries: [AnyKeyframes<Value>]

  package init(entries: [AnyKeyframes<Value>]) {
    self.entries = entries
  }
}

extension KeyframeSequence: KeyframesLowering {
  package func lowerKeyframes(
    initialValue: Value,
    into tracks: inout [AnyKeyframeTrack<Value>]
  ) {
    for entry in entries {
      entry.lower(initialValue, &tracks)
    }
  }
}

// MARK: - KeyframesBuilder

/// The result builder for ``Keyframes`` bodies and
/// ``KeyframeTimeline/init(initialValue:content:)``.
///
/// Lists ``KeyframeTrack``s for a composite value. When `Value` is itself
/// ``Animatable``, bare keyframes (`LinearKeyframe`, `CubicKeyframe`,
/// `SpringKeyframe`, `MoveKeyframe`) are accepted directly and animate the
/// whole value.
@resultBuilder
public enum KeyframesBuilder<Value> {
  public static func buildExpression<K: Keyframes>(_ expression: K) -> K
  where K.Value == Value {
    expression
  }

  public static func buildPartialBlock<K: Keyframes>(first: K) -> KeyframeSequence<Value>
  where K.Value == Value {
    KeyframeSequence(entries: [AnyKeyframes(first)])
  }

  public static func buildPartialBlock<K: Keyframes>(
    accumulated: KeyframeSequence<Value>,
    next: K
  ) -> KeyframeSequence<Value> where K.Value == Value {
    var sequence = accumulated
    sequence.entries.append(AnyKeyframes(next))
    return sequence
  }

  public static func buildBlock() -> KeyframeSequence<Value> {
    KeyframeSequence(entries: [])
  }

  public static func buildOptional(_ component: KeyframeSequence<Value>?) -> KeyframeSequence<Value>
  {
    component ?? KeyframeSequence(entries: [])
  }

  public static func buildEither(first component: KeyframeSequence<Value>) -> KeyframeSequence<
    Value
  > {
    component
  }

  public static func buildEither(second component: KeyframeSequence<Value>) -> KeyframeSequence<
    Value
  > {
    component
  }

  public static func buildArray(_ components: [KeyframeSequence<Value>]) -> KeyframeSequence<Value>
  {
    KeyframeSequence(entries: components.flatMap(\.entries))
  }
}

extension KeyframesBuilder where Value: Animatable {
  /// The single `\.self` track that bare keyframes in a block accumulate
  /// into when `Value` is itself ``Animatable``.
  public typealias WholeValueTrack = KeyframeTrack<
    Value, Value, KeyframeTrackContentSequence<Value>
  >

  /// Accepts a bare keyframe for an ``Animatable`` value.
  public static func buildExpression<Content: KeyframeTrackContent>(
    _ expression: Content
  ) -> Content where Content.Value == Value {
    expression
  }

  /// Bare keyframes in one block form one track that animates the whole
  /// value, in order (SwiftUI's `KeyframeTimeline(initialValue: 0.0) { ... }`
  /// spelling).
  public static func buildPartialBlock<Content: KeyframeTrackContent>(
    first: Content
  ) -> WholeValueTrack where Content.Value == Value {
    KeyframeTrack(
      keyPath: \.self,
      content: KeyframeTrackContentSequence(entries: [AnyKeyframeTrackContent(first)])
    )
  }

  public static func buildPartialBlock<Content: KeyframeTrackContent>(
    accumulated: WholeValueTrack,
    next: Content
  ) -> WholeValueTrack where Content.Value == Value {
    var entries = accumulated.content.entries
    entries.append(AnyKeyframeTrackContent(next))
    return KeyframeTrack(
      keyPath: \.self,
      content: KeyframeTrackContentSequence(entries: entries)
    )
  }
}
