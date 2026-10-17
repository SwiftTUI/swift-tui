/// Variable-length animatable storage for compound values that have no fixed size at the type level.
/// An array of ``Gradient`` stops is one example.
///
/// The empty array is the dimension-independent additive identity, so
/// generic zero tangents preserve the shape of nonempty vectors. Arithmetic
/// between two nonempty operands requires equal element counts; mismatched
/// counts return the empty zero. The animation controller calls ``isInterpolable(to:)`` before it composes arithmetic.
/// If the counts do not match, the controller changes directly to the target value.
/// This behavior matches SwiftUI gradient animations when the stop count changes between frames.
public struct AnimatableArray<Element: VectorArithmetic & Sendable>:
  VectorArithmetic, Sendable
{
  public var elements: [Element]

  public init(_ elements: [Element]) {
    self.elements = elements
  }

  public static var zero: Self { .init([]) }

  /// Returns `true` when this array and `other` have the same element
  /// count and can therefore be composed under `+` / `-`.
  public func isInterpolable(to other: Self) -> Bool {
    elements.count == other.elements.count
  }

  public static func + (lhs: Self, rhs: Self) -> Self {
    if lhs.elements.isEmpty { return rhs }
    if rhs.elements.isEmpty { return lhs }
    guard lhs.elements.count == rhs.elements.count else {
      return .init([])
    }
    var result: [Element] = []
    result.reserveCapacity(lhs.elements.count)
    for i in lhs.elements.indices {
      result.append(lhs.elements[i] + rhs.elements[i])
    }
    return .init(result)
  }

  public static func - (lhs: Self, rhs: Self) -> Self {
    if rhs.elements.isEmpty { return lhs }
    if lhs.elements.isEmpty { return .init(rhs.elements.map { .zero - $0 }) }
    guard lhs.elements.count == rhs.elements.count else {
      return .init([])
    }
    var result: [Element] = []
    result.reserveCapacity(lhs.elements.count)
    for i in lhs.elements.indices {
      result.append(lhs.elements[i] - rhs.elements[i])
    }
    return .init(result)
  }

  public static func += (lhs: inout Self, rhs: Self) {
    lhs = lhs + rhs
  }

  public static func -= (lhs: inout Self, rhs: Self) {
    lhs = lhs - rhs
  }

  public mutating func scale(by rhs: Double) {
    for i in elements.indices {
      elements[i].scale(by: rhs)
    }
  }

  public var magnitudeSquared: Double {
    elements.reduce(0) { $0 + $1.magnitudeSquared }
  }
}
