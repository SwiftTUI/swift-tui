// MARK: - VectorArithmetic

/// A type that can be interpolated by the animation system.
///
/// Matches SwiftUI's `VectorArithmetic` protocol.
public protocol VectorArithmetic: AdditiveArithmetic, Sendable {
  /// Scales the value in place.
  mutating func scale(by rhs: Double)

  /// The dot-product of the vector with itself.
  var magnitudeSquared: Double { get }
}

// MARK: - Animatable

/// A type whose properties can be animated.
///
/// Matches SwiftUI's `Animatable` protocol.
public protocol Animatable: Sendable {
  associatedtype AnimatableData: VectorArithmetic
  var animatableData: AnimatableData { get set }
}

// MARK: - EmptyAnimatableData

/// Placeholder for types that declare `Animatable` conformance but have
/// nothing to interpolate.
public struct EmptyAnimatableData: VectorArithmetic, Sendable {
  public init() {}

  public static var zero: EmptyAnimatableData { .init() }

  public static func + (
    lhs: EmptyAnimatableData,
    rhs: EmptyAnimatableData
  ) -> EmptyAnimatableData { .init() }

  public static func - (
    lhs: EmptyAnimatableData,
    rhs: EmptyAnimatableData
  ) -> EmptyAnimatableData { .init() }

  public static func += (
    lhs: inout EmptyAnimatableData,
    rhs: EmptyAnimatableData
  ) {}

  public static func -= (
    lhs: inout EmptyAnimatableData,
    rhs: EmptyAnimatableData
  ) {}

  public mutating func scale(by rhs: Double) {}

  public var magnitudeSquared: Double { 0 }
}

// MARK: - AnimatablePair

/// Pairs two `VectorArithmetic` values so composite animatable data can be
/// expressed as a single associated type.
public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>:
  VectorArithmetic, Sendable
{
  public var first: First
  public var second: Second

  public init(_ first: First, _ second: Second) {
    self.first = first
    self.second = second
  }

  public static var zero: AnimatablePair {
    .init(.zero, .zero)
  }

  public static func + (lhs: Self, rhs: Self) -> Self {
    .init(lhs.first + rhs.first, lhs.second + rhs.second)
  }

  public static func - (lhs: Self, rhs: Self) -> Self {
    .init(lhs.first - rhs.first, lhs.second - rhs.second)
  }

  public static func += (lhs: inout Self, rhs: Self) {
    lhs.first += rhs.first
    lhs.second += rhs.second
  }

  public static func -= (lhs: inout Self, rhs: Self) {
    lhs.first -= rhs.first
    lhs.second -= rhs.second
  }

  public mutating func scale(by rhs: Double) {
    first.scale(by: rhs)
    second.scale(by: rhs)
  }

  public var magnitudeSquared: Double {
    first.magnitudeSquared + second.magnitudeSquared
  }
}

// MARK: - Double + VectorArithmetic

extension Double: VectorArithmetic {
  public mutating func scale(by rhs: Double) {
    self *= rhs
  }

  public var magnitudeSquared: Double {
    self * self
  }
}

// MARK: - Int + VectorArithmetic

/// Integer scaling truncates toward zero: `scale(by: t)` computes
/// `self = Int(Double(self) * t)`.  This has two notable quirks for
/// animation call sites:
///
/// 1. **Sub-unit deltas are lost.** A delta of `1` scaled by
///    `t = 0.4` produces `Int(0.4) = 0`, so small integer deltas
///    animate as a single jump at the end of the curve rather than
///    a smooth per-frame step.  Acceptable for terminal cell
///    coordinates (which are inherently integer-quantized), but
///    callers that need sub-cell precision should use `Double`
///    instead.
///
/// 2. **Asymmetric rounding.** Truncation toward zero means `-1`
///    scaled by `0.5` yields `0`, while `+1` scaled by `0.5` also
///    yields `0`.  Both are off-by-one from round-to-nearest, but
///    symmetrically so — no sign-dependent drift.
///
/// The composed interpolation primitive used by the animation
/// controller produces `from + (to - from).scaled(by: progress)` at
/// the ``VectorArithmetic`` level; the `scale`-then-add sequence is
/// what matters for rounding analysis.
extension Int: VectorArithmetic {
  public mutating func scale(by rhs: Double) {
    self = Int(Double(self) * rhs)
  }

  public var magnitudeSquared: Double {
    Double(self * self)
  }
}

// MARK: - Animatable bridges for primitive VectorArithmetic types

/// A ``VectorArithmetic`` value is trivially ``Animatable`` — its own
/// value is its animatable data.  SwiftUI exposes the same identity on
/// `Double`/`CGFloat`/`Float` so `AnyAnimatable(1.5)` works at the
/// type-erased wrapper level.
extension Double: Animatable {
  public var animatableData: Double {
    get { self }
    set { self = newValue }
  }
}

extension Int: Animatable {
  public var animatableData: Int {
    get { self }
    set { self = newValue }
  }
}

/// ``AnimatablePair`` is trivially ``Animatable``: its animatable data
/// is itself.  This lets the controller wrap pair-valued slots (offset,
/// position) in ``AnyAnimatable`` directly.
extension AnimatablePair: Animatable {
  public var animatableData: AnimatablePair<First, Second> {
    get { self }
    set { self = newValue }
  }
}
