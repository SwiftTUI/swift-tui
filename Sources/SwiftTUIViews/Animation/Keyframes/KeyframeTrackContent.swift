public import SwiftTUICore

// MARK: - KeyframeTrackContent

/// One or more keyframes inside a ``KeyframeTrack``.
///
/// Matches SwiftUI's `KeyframeTrackContent`. The built-in keyframes are
/// ``LinearKeyframe``, ``CubicKeyframe``, ``SpringKeyframe``, and
/// ``MoveKeyframe``; conform your own type to reuse a keyframe run.
public protocol KeyframeTrackContent<Value> {
  /// The animated property type.
  associatedtype Value
  /// The composed keyframes this type expands to.
  associatedtype Body: KeyframeTrackContent
  /// The composed keyframes.
  @KeyframeTrackContentBuilder<Value> var body: Body { get }
}

extension KeyframeTrackContent where Body == Never {
  public var body: Never {
    fatalError("\(Self.self) is a primitive keyframe and has no composed body.")
  }
}

/// See the `Never: Keyframes` note: `Value`, `Body`, and `body` are reused
/// from the `Gesture` and `View` conformances.
extension Never: KeyframeTrackContent {}

// MARK: - Lowering

/// Internal lowering hook for primitive keyframes.
package protocol KeyframeTrackContentLowering<Value> {
  associatedtype Value: Animatable
  func lowerTrackContent(into specs: inout [KeyframeSegmentSpec<Value>])
}

/// Expands `content` into segment specs: primitives lower themselves,
/// composed types expand their body first.
package func lowerKeyframeTrackContent<Content: KeyframeTrackContent, Value: Animatable>(
  _ content: Content,
  into specs: inout [KeyframeSegmentSpec<Value>]
) {
  if let primitive = content as? any KeyframeTrackContentLowering<Value> {
    primitive.lowerTrackContent(into: &specs)
    return
  }
  lowerKeyframeTrackContent(content.body, into: &specs)
}

/// One keyframe as authored: its target, an optional duration, and the
/// interpolation it requests. `KeyframeTrackTimeline` resolves the defaults.
package struct KeyframeSegmentSpec<Value: Animatable> {
  package enum Kind {
    case linear(UnitCurve)
    case cubic(startVelocity: Value?, endVelocity: Value?)
    case spring(Spring, startVelocity: Value?)
    case move
  }

  package var to: Value
  package var duration: Duration?
  package var kind: Kind

  package init(to: Value, duration: Duration?, kind: Kind) {
    self.to = to
    self.duration = duration
    self.kind = kind
  }
}

/// A type-erased keyframe run held by ``KeyframeTrackContentSequence``.
package struct AnyKeyframeTrackContent<Value: Animatable> {
  package let lower: (inout [KeyframeSegmentSpec<Value>]) -> Void

  package init<Content: KeyframeTrackContent>(_ content: Content) where Content.Value == Value {
    lower = { specs in
      lowerKeyframeTrackContent(content, into: &specs)
    }
  }
}

// MARK: - KeyframeTrackContentSequence

/// The keyframe run a ``KeyframeTrackContentBuilder`` block produces: every
/// keyframe listed in the block, in order. Not spelled directly in app code.
public struct KeyframeTrackContentSequence<Value: Animatable>: KeyframeTrackContent {
  public typealias Body = Never

  package var entries: [AnyKeyframeTrackContent<Value>]

  package init(entries: [AnyKeyframeTrackContent<Value>]) {
    self.entries = entries
  }
}

extension KeyframeTrackContentSequence: KeyframeTrackContentLowering {
  package func lowerTrackContent(into specs: inout [KeyframeSegmentSpec<Value>]) {
    for entry in entries {
      entry.lower(&specs)
    }
  }
}

// MARK: - KeyframeTrackContentBuilder

/// The result builder for ``KeyframeTrack`` contents and
/// ``KeyframeTrackContent`` bodies.
@resultBuilder
public enum KeyframeTrackContentBuilder<Value> {}

extension KeyframeTrackContentBuilder where Value: Animatable {
  public static func buildExpression<Content: KeyframeTrackContent>(
    _ expression: Content
  ) -> Content where Content.Value == Value {
    expression
  }

  public static func buildPartialBlock<Content: KeyframeTrackContent>(
    first: Content
  ) -> KeyframeTrackContentSequence<Value> where Content.Value == Value {
    KeyframeTrackContentSequence(entries: [AnyKeyframeTrackContent(first)])
  }

  public static func buildPartialBlock<Content: KeyframeTrackContent>(
    accumulated: KeyframeTrackContentSequence<Value>,
    next: Content
  ) -> KeyframeTrackContentSequence<Value> where Content.Value == Value {
    var sequence = accumulated
    sequence.entries.append(AnyKeyframeTrackContent(next))
    return sequence
  }

  public static func buildBlock() -> KeyframeTrackContentSequence<Value> {
    KeyframeTrackContentSequence(entries: [])
  }

  public static func buildOptional(
    _ component: KeyframeTrackContentSequence<Value>?
  ) -> KeyframeTrackContentSequence<Value> {
    component ?? KeyframeTrackContentSequence(entries: [])
  }

  public static func buildEither(
    first component: KeyframeTrackContentSequence<Value>
  ) -> KeyframeTrackContentSequence<Value> {
    component
  }

  public static func buildEither(
    second component: KeyframeTrackContentSequence<Value>
  ) -> KeyframeTrackContentSequence<Value> {
    component
  }

  public static func buildArray(
    _ components: [KeyframeTrackContentSequence<Value>]
  ) -> KeyframeTrackContentSequence<Value> {
    KeyframeTrackContentSequence(entries: components.flatMap(\.entries))
  }
}

// MARK: - Built-in keyframes

/// A keyframe that interpolates to its value along a ``UnitCurve`` over a
/// fixed duration.
///
/// Matches SwiftUI's `LinearKeyframe`, with a `Duration` in place of
/// `TimeInterval` like the rest of the animation surface.
public struct LinearKeyframe<Value: Animatable>: KeyframeTrackContent {
  public typealias Body = Never

  package let to: Value
  package let duration: Duration
  package let timingCurve: UnitCurve

  /// Creates a keyframe that reaches `to` after `duration`, eased by
  /// `timingCurve`.
  public init(_ to: Value, duration: Duration, timingCurve: UnitCurve = .linear) {
    self.to = to
    self.duration = duration
    self.timingCurve = timingCurve
  }
}

extension LinearKeyframe: KeyframeTrackContentLowering {
  package func lowerTrackContent(into specs: inout [KeyframeSegmentSpec<Value>]) {
    specs.append(.init(to: to, duration: duration, kind: .linear(timingCurve)))
  }
}

/// A keyframe that interpolates to its value along a cubic curve whose end
/// velocities default to a smooth (Catmull-Rom) estimate from the
/// neighboring keyframes.
///
/// Matches SwiftUI's `CubicKeyframe`. Velocities are in value units per
/// second; the first and last keyframes of a track start and end at rest
/// unless a velocity is given.
public struct CubicKeyframe<Value: Animatable>: KeyframeTrackContent {
  public typealias Body = Never

  package let to: Value
  package let duration: Duration
  package let startVelocity: Value?
  package let endVelocity: Value?

  /// Creates a keyframe that reaches `to` after `duration`.
  public init(
    _ to: Value,
    duration: Duration,
    startVelocity: Value? = nil,
    endVelocity: Value? = nil
  ) {
    self.to = to
    self.duration = duration
    self.startVelocity = startVelocity
    self.endVelocity = endVelocity
  }
}

extension CubicKeyframe: KeyframeTrackContentLowering {
  package func lowerTrackContent(into specs: inout [KeyframeSegmentSpec<Value>]) {
    specs.append(
      .init(
        to: to,
        duration: duration,
        kind: .cubic(startVelocity: startVelocity, endVelocity: endVelocity)
      )
    )
  }
}

/// A keyframe that moves to its value with a ``Spring``.
///
/// Matches SwiftUI's `SpringKeyframe`. With no `duration` the segment lasts
/// the spring's ``Spring/settlingDuration``; a shorter duration cuts the
/// spring off and the track lands on `to` at the segment's end.
public struct SpringKeyframe<Value: Animatable>: KeyframeTrackContent {
  public typealias Body = Never

  package let to: Value
  package let duration: Duration?
  package let spring: Spring
  package let startVelocity: Value?

  /// Creates a spring keyframe toward `to`.
  public init(
    _ to: Value,
    duration: Duration? = nil,
    spring: Spring = Spring(),
    startVelocity: Value? = nil
  ) {
    self.to = to
    self.duration = duration
    self.spring = spring
    self.startVelocity = startVelocity
  }
}

extension SpringKeyframe: KeyframeTrackContentLowering {
  package func lowerTrackContent(into specs: inout [KeyframeSegmentSpec<Value>]) {
    specs.append(
      .init(to: to, duration: duration, kind: .spring(spring, startVelocity: startVelocity))
    )
  }
}

/// A keyframe that jumps to its value with no duration.
///
/// Matches SwiftUI's `MoveKeyframe`.
public struct MoveKeyframe<Value: Animatable>: KeyframeTrackContent {
  public typealias Body = Never

  package let to: Value

  /// Creates a keyframe that jumps to `to`.
  public init(_ to: Value) {
    self.to = to
  }
}

extension MoveKeyframe: KeyframeTrackContentLowering {
  package func lowerTrackContent(into specs: inout [KeyframeSegmentSpec<Value>]) {
    specs.append(.init(to: to, duration: .zero, kind: .move))
  }
}
