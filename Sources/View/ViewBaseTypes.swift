public import Core
public import Observation

/// A normalized point within a rectangle, used for layout anchors.
public typealias UnitPoint = Alignment
/// A proposed size passed into layout and rendering operations.
public typealias ProposedViewSize = ProposedSize
/// A layout-space point.
public typealias LayoutPoint = Point
/// A layout-space size.
public typealias LayoutSize = Size
/// A layout-space rectangle.
public typealias LayoutRect = Rect

@dynamicMemberLookup
@propertyWrapper
/// A mutable projection into another owned value.
public struct Binding<Value> {
  private let getter: () -> Value
  private let setter: (Value) -> Void

  /// Creates a binding from explicit getter and setter closures.
  public init(
    get: @escaping () -> Value,
    set: @escaping (Value) -> Void
  ) {
    getter = get
    setter = set
  }

  public var wrappedValue: Value {
    get { getter() }
    nonmutating set { setter(newValue) }
  }

  public var projectedValue: Self {
    self
  }

  /// Returns a read-only binding that ignores writes.
  public static func constant(_ value: Value) -> Self {
    Self(
      get: { value },
      set: { _ in }
    )
  }

  public subscript<Member>(
    dynamicMember keyPath: WritableKeyPath<Value, Member>
  ) -> Binding<Member> {
    Binding<Member>(
      get: { wrappedValue[keyPath: keyPath] },
      set: { wrappedValue[keyPath: keyPath] = $0 }
    )
  }
}

extension Binding: Equatable where Value: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.wrappedValue == rhs.wrappedValue
  }
}

// SAFETY: Binding stores non-Sendable closures (getter/setter), but when Value is Sendable
// the closures are typically created from @MainActor state accessors that are safe to transfer.
// This mirrors SwiftUI's own Binding Sendable conformance. The @unchecked is required because
// the compiler cannot prove closure Sendability through the conditional conformance.
extension Binding: @unchecked Sendable where Value: Sendable {}

@dynamicMemberLookup
@propertyWrapper
/// A bindable projection for observable reference types.
///
/// TerminalUI provides its own `@Bindable` so observable reads and writes stay
/// on the same invalidation path as the rest of the runtime.
public struct Bindable<Model> where Model: AnyObject, Model: Observable {
  public var wrappedValue: Model

  public init(wrappedValue: Model) {
    self.wrappedValue = wrappedValue
  }

  public init(_ wrappedValue: Model) {
    self.wrappedValue = wrappedValue
  }

  public var projectedValue: Self {
    self
  }

  public subscript<Value>(
    dynamicMember keyPath: ReferenceWritableKeyPath<Model, Value>
  ) -> Binding<Value> {
    // Register the observable property access while the enclosing body is
    // being built so writes map back into the existing invalidation pipeline.
    _ = wrappedValue[keyPath: keyPath]
    return Binding(
      get: { wrappedValue[keyPath: keyPath] },
      set: { wrappedValue[keyPath: keyPath] = $0 }
    )
  }
}

/// The primary axis used by directional layout and scrolling APIs.
public enum Axis {
  case horizontal
  case vertical

  /// Option set that can contain one or both axes.
  public typealias Set = AxisSet
}

/// A scroll offset in terminal cell coordinates.
public struct ScrollPosition: Equatable, Sendable {
  public var x: Int
  public var y: Int

  public init(
    x: Int = 0,
    y: Int = 0
  ) {
    self.x = x
    self.y = y
  }

  public static let zero = Self()

  /// Returns a copy offset by the supplied deltas.
  public func scrolledBy(
    x deltaX: Int = 0,
    y deltaY: Int = 0
  ) -> Self {
    .init(
      x: x + deltaX,
      y: y + deltaY
    )
  }

  /// Mutates this position by the supplied deltas.
  public mutating func scrollBy(
    x deltaX: Int = 0,
    y deltaY: Int = 0
  ) {
    self = scrolledBy(x: deltaX, y: deltaY)
  }

  /// Mutates this position to the supplied absolute coordinates.
  public mutating func scrollTo(
    x: Int? = nil,
    y: Int? = nil
  ) {
    if let x {
      self.x = x
    }
    if let y {
      self.y = y
    }
  }
}

/// Preferred spacing metadata exchanged between layout participants.
public struct ViewSpacing: Sendable, Equatable {
  public var horizontal: Int?
  public var vertical: Int?

  public init(horizontal: Int? = nil, vertical: Int? = nil) {
    self.horizontal = horizontal
    self.vertical = vertical
  }

  /// Returns the preferred distance between this spacing value and the next
  /// spacing value along `axis`.
  public func distance(to next: Self, along axis: Axis) -> Int {
    max(preferredDistance(along: axis), next.preferredDistance(along: axis))
  }

  private func preferredDistance(along axis: Axis) -> Int {
    switch axis {
    case .horizontal:
      return horizontal ?? 1
    case .vertical:
      return vertical ?? 0
    }
  }
}
