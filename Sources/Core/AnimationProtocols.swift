/// How animation intent flows through a transaction.
package enum AnimationRequest: Equatable, Sendable {
  /// Use whatever the parent transaction says.
  case inherit
  /// Explicitly suppress animation in this subtree.
  case disabled
  /// Animate with this curve (type-erased box used to avoid depending on
  /// View-layer ``Animation`` from Core).
  case animate(AnimationBox)

  /// Returns the underlying animation box when the request carries one.
  package var animationBoxIfAny: AnimationBox? {
    if case .animate(let box) = self {
      return box
    }
    return nil
  }
}

/// Type-erased animation storage that Core can carry without depending on
/// the View module's ``Animation`` type.
///
/// The View module creates concrete instances; Core only stores and
/// compares them by identity.
package typealias AnimationBox = AnyHashableSendable

private protocol HashableBox: Sendable {
  func hash(into hasher: inout Hasher)
  func isEqual(to other: any HashableBox) -> Bool
  func unwrap<H: Hashable & Sendable>(as _: H.Type) -> H?
}

private struct ConcreteHashableBox<T: Hashable & Sendable>: HashableBox {
  let value: T

  func hash(into hasher: inout Hasher) {
    value.hash(into: &hasher)
  }

  func isEqual(to other: any HashableBox) -> Bool {
    guard let other = other as? ConcreteHashableBox<T> else { return false }
    return value == other.value
  }

  func unwrap<H: Hashable & Sendable>(as _: H.Type) -> H? {
    if let v = value as? H {
      v
    } else {
      nil
    }
  }
}

/// Wrapper that asserts Sendable for AnyHashable values known to be
/// Sendable at construction time.
public struct AnyHashableSendable: Hashable, Sendable {
  private let box: any HashableBox

  public init<Item: Hashable & Sendable>(_ item: Item) {
    box = ConcreteHashableBox(value: item)
  }

  public func hash(into hasher: inout Hasher) {
    box.hash(into: &hasher)
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.box.isEqual(to: rhs.box)
  }

  package func unwrap<H: Hashable & Sendable>(as _: H.Type = H.self) -> H? {
    box.unwrap(as: H.self)
  }
}

// MARK: - AnimationAwareInvalidating

/// Extended invalidation interface that carries animation intent alongside
/// identity invalidation.
///
/// `FrameScheduler` conforms and stores a pending coalesced animation
/// request on `ScheduledFrame`.
package protocol AnimationAwareInvalidating: Invalidating {
  func requestInvalidation(
    of identities: Set<Identity>,
    animation: AnimationRequest,
    batchID: AnimationBatchID?
  )
}

extension AnimationAwareInvalidating {
  /// Back-compat shim for call sites that do not carry a batch ID.
  package func requestInvalidation(
    of identities: Set<Identity>,
    animation: AnimationRequest
  ) {
    requestInvalidation(of: identities, animation: animation, batchID: nil)
  }
}

// MARK: - AnimationBatchID

/// Identifies one logical animation batch — every animation enqueued
/// under the same ``withAnimation(_:_:completion:)`` scope shares the
/// same batch ID, so the controller can fire one completion closure
/// once the whole batch has settled.
///
/// Batch IDs are opaque and never exposed to user code.  They are
/// allocated monotonically by whichever component creates the batch
/// (in practice: ``withAnimation`` on the View side).
package struct AnimationBatchID: Hashable, Sendable {
  package let value: UInt64

  package init(_ value: UInt64) {
    self.value = value
  }
}

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

/// Integer interpolation truncates: `from + Int(Double(to - from) * progress)`.
extension Int: VectorArithmetic {
  public mutating func scale(by rhs: Double) {
    self = Int(Double(self) * rhs)
  }

  public var magnitudeSquared: Double {
    Double(self * self)
  }
}
