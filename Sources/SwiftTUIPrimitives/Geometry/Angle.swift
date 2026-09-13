/// An unnormalized angle. A full turn is `2 * .pi` radians or 360 degrees.
public struct Angle: Hashable, Comparable, Sendable {
  public var radians: Double

  public var degrees: Double {
    get { radians * (180 / .pi) }
    set { radians = newValue * (.pi / 180) }
  }

  public init(radians: Double) { self.radians = radians }
  public init(degrees: Double) { radians = degrees * (.pi / 180) }
  public static func radians(_ value: Double) -> Self { Self(radians: value) }
  public static func degrees(_ value: Double) -> Self { Self(degrees: value) }
  public static let zero = Self(radians: 0)
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.radians < rhs.radians }
}
