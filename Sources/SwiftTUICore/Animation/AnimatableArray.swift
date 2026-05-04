/// Variable-length animatable storage for compound values whose size
/// isn't fixed at type level — e.g. ``Gradient`` stop arrays.
///
/// Arithmetic operations require both operands to have the same
/// element count. With mismatched counts, `+`, `-`, `+=`, `-=`
/// return a zero-element result (which propagates through subsequent
/// arithmetic as zero).  The animation controller checks
/// ``isInterpolable(to:)`` before composing arithmetic and snaps to
/// the target value when the counts don't match — this matches
/// SwiftUI's behavior of snapping gradient animations when the stop
/// count changes between frames.
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
