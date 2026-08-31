public import Observation
public import SwiftTUICore

/// A proposed size passed into layout and rendering operations.
public typealias ProposedViewSize = ProposedSize
/// A layout-space point.
public typealias LayoutPoint = CellPoint
/// A layout-space size.
public typealias LayoutSize = CellSize
/// A layout-space rectangle.
public typealias LayoutRect = CellRect

@dynamicMemberLookup
@propertyWrapper
/// A mutable projection into another owned value.
public struct Binding<Value> {
  private let getter: @MainActor @Sendable () -> Value
  private let setter: @MainActor @Sendable (Value) -> Void
  /// A stable token naming the binding's backing storage, when the producer
  /// supplies one. `Binding` itself is a pair of closures with no identity
  /// across renders; consumers that must distinguish "same authored binding
  /// re-created by a re-resolve" from "a different binding swapped in"
  /// (scroll-momentum retirement) read this. Nil — the default — leaves
  /// those consumers with no distinction, preserving prior behavior.
  package var bindingSourceID: AnyID?

  /// The transaction applied to writes made through this binding.
  ///
  /// Verified against real SwiftUI (2026-08-05): an explicit ambient scope
  /// (a surrounding `withAnimation(_:_:)` or `withTransaction(_:_:)`) wins
  /// over the stored transaction, including a stored `disablesAnimations`
  /// losing to an ambient animation. The stored transaction governs only
  /// writes made outside any explicit scope, which is exactly how every
  /// built-in control writes (`Toggle`, `Slider`, `Stepper`, text input all
  /// set `wrappedValue` with no animation context of their own).
  public var transaction: Transaction = Transaction()

  package init(
    mainActorGet getter: @escaping @MainActor @Sendable () -> Value,
    set setter: @escaping @MainActor @Sendable (Value) -> Void
  ) {
    self.getter = getter
    self.setter = setter
  }

  /// The same binding carrying a stable source token (see
  /// ``bindingSourceID``).
  package func withBindingSource<ID: Hashable & Sendable>(_ id: ID) -> Self {
    var copy = self
    copy.bindingSourceID = AnyID(id)
    return copy
  }

  /// Creates a binding from explicit getter and setter closures.
  public init(
    get: @escaping @MainActor @Sendable () -> Value,
    set: @escaping @MainActor @Sendable (Value) -> Void
  ) {
    self.getter = get
    self.setter = set
  }

  /// Creates a binding from another binding's projected value.
  ///
  /// Enables `@Binding var value` declarations to be initialized directly
  /// from an existing binding: `SomeView(value: $source)` forwarding into
  /// `Binding(projectedValue:)`. The copy carries the source's stored
  /// ``transaction``.
  public init(projectedValue: Binding<Value>) {
    self = projectedValue
  }

  /// Creates a binding by unwrapping an optional base, failing when the
  /// base value is currently nil.
  ///
  /// Reads through the returned binding trap with a diagnostic once the
  /// base has become nil; the same read traps in SwiftUI (verified
  /// 2026-08-05). Author the optional check at the *reading* view, not
  /// above it: an unwrap performed high in the tree attributes the
  /// binding read to the high resolve and widens the invalidation cone
  /// (see the reader-attribution note on the presentation trigger leaf).
  @MainActor
  public init?(_ base: Binding<Value?>) {
    guard base.wrappedValue != nil else {
      return nil
    }
    self.init(
      mainActorGet: {
        guard let value = base.wrappedValue else {
          fatalError(
            """
            Binding<\(Value.self)> was read after its optional base became \
            nil. An unwrapping binding (Binding.init?(_:)) is only valid \
            while the base holds a value — re-derive it inside the view \
            that checks the optional instead of retaining it across the \
            value's lifetime.
            """
          )
        }
        return value
      },
      set: { base.wrappedValue = $0 }
    )
    self.transaction = base.transaction
    self.bindingSourceID = base.bindingSourceID
  }

  /// Creates a binding that projects a non-optional base as an optional
  /// value.
  ///
  /// Writing nil through the projection is ignored: the base keeps its
  /// current value (matches SwiftUI, verified 2026-08-05).
  @MainActor
  public init<V>(_ base: Binding<V>) where Value == V? {
    self.init(
      mainActorGet: { base.wrappedValue },
      set: { newValue in
        guard let newValue else {
          return
        }
        base.wrappedValue = newValue
      }
    )
    self.transaction = base.transaction
    self.bindingSourceID = base.bindingSourceID
  }

  @MainActor
  public var wrappedValue: Value {
    get { getter() }
    nonmutating set {
      guard shouldApplyStoredTransaction else {
        setter(newValue)
        return
      }
      withTransaction(transaction) { setter(newValue) }
    }
  }

  /// Whether this write should run inside the stored transaction: the
  /// stored transaction must carry intent, and no explicit ambient scope
  /// may be active — an active `withAnimation`/`withTransaction` (or a
  /// completion batch) wins over the stored transaction (SwiftUI probe,
  /// 2026-08-05).
  @MainActor
  private var shouldApplyStoredTransaction: Bool {
    guard !transaction.isInert else {
      return false
    }
    return AnimationContextStorage.currentRequest == .inherit
      && AnimationContextStorage.currentBatchID == nil
  }

  public var projectedValue: Self {
    self
  }

  /// Returns a binding that applies `animation` to writes made through it.
  ///
  /// Passing `nil` disables animation for those writes, mirroring
  /// ``Transaction/animation``'s nil-means-disabled contract.
  public func animation(_ animation: Animation? = .default) -> Binding<Value> {
    var copy = self
    copy.transaction.animation = animation
    return copy
  }

  /// Returns a binding that applies `transaction` to writes made through
  /// it.
  public func transaction(_ transaction: Transaction) -> Binding<Value> {
    var copy = self
    copy.transaction = transaction
    return copy
  }

  /// Returns a read-only binding that ignores writes.
  @MainActor
  public static func constant(_ value: Value) -> Self {
    Self(
      mainActorGet: { value },
      set: { _ in }
    )
  }

  @MainActor
  public subscript<Member>(
    dynamicMember keyPath: WritableKeyPath<Value, Member>
  ) -> Binding<Member> {
    // The member projection carries the stored transaction (SwiftUI
    // propagates it), so reading `.transaction` off a member binding stays
    // truthful. The write path would apply it either way: the member setter
    // funnels through this binding's `wrappedValue` setter. The source
    // token deliberately does NOT propagate — pre-existing behavior;
    // consumers key momentum retirement on the *whole-value* binding.
    var projected = Binding<Member>(
      mainActorGet: { wrappedValue[keyPath: keyPath] },
      set: { wrappedValue[keyPath: keyPath] = $0 }
    )
    projected.transaction = transaction
    return projected
  }
}

extension Binding: Sendable where Value: Sendable {}

extension Binding: DynamicProperty {
  public func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    .unchanged
  }
}

@dynamicMemberLookup
@propertyWrapper
/// A bindable projection for observable reference types.
///
/// SwiftTUI provides its own `@Bindable` so observable reads and writes stay
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

  @MainActor
  public subscript<Value>(
    dynamicMember keyPath: ReferenceWritableKeyPath<Model, Value>
  ) -> Binding<Value> {
    let model = wrappedValue
    // Register the observable property access while the enclosing body is being
    // built so writes map back into the existing invalidation pipeline. Precise
    // observation firing dirties only the node whose tracking pass read the
    // mutated property, so the coarse object token is all that is needed here.
    ViewNodeContext.current?.recordObservableRead(ObjectIdentifier(model))
    _ = model[keyPath: keyPath]
    return Binding(
      mainActorGet: { model[keyPath: keyPath] },
      set: { model[keyPath: keyPath] = $0 }
    )
  }
}

/// `Bindable` stores an observable reference directly. There is no location
/// to bind during update; observable accesses retain their existing tracked
/// invalidation path.
extension Bindable: DynamicProperty {
  public func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    .unchanged
  }
}

/// The primary axis used by directional layout and scrolling APIs.
public enum Axis: Sendable {
  case horizontal
  case vertical

  /// Option set that can contain one or both axes.
  public typealias Set = AxisSet
}

/// A scroll offset in terminal cell coordinates.
public struct ScrollCellOffset: Equatable, Sendable {
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
///
/// A `nil` axis means "no preference": when a stack negotiates the gap
/// between two siblings it substitutes its defaults — one cell between
/// horizontal neighbours, none between vertical ones. Spacing is per axis
/// rather than per edge; SwiftTUI has no layout direction, so there is no
/// leading/trailing distinction to keep.
public struct ViewSpacing: Sendable, Equatable {
  public var horizontal: Int?
  public var vertical: Int?

  /// A spacing that asks for no gap on either axis.
  public static let zero = ViewSpacing(horizontal: 0, vertical: 0)

  public init(horizontal: Int? = nil, vertical: Int? = nil) {
    self.horizontal = horizontal
    self.vertical = vertical
  }

  /// The core-layer spacing this value carries, or comes from.
  package init(_ spacing: Spacing) {
    self.init(horizontal: spacing.horizontal, vertical: spacing.vertical)
  }

  package var coreSpacing: Spacing {
    Spacing(horizontal: horizontal, vertical: vertical)
  }

  /// The union of two preferences: on each axis, the larger of the two
  /// requests, or the one that exists when only one side has a preference.
  /// This is how a container combines its subviews' preferences into its own
  /// (the default ``Layout/spacing(subviews:cache:)``).
  public func union(_ other: ViewSpacing) -> ViewSpacing {
    ViewSpacing(
      horizontal: Self.unionAxis(horizontal, other.horizontal),
      vertical: Self.unionAxis(vertical, other.vertical)
    )
  }

  /// Replaces this value with its ``union(_:)`` with `other`.
  public mutating func formUnion(_ other: ViewSpacing) {
    self = union(other)
  }

  private static func unionAxis(_ lhs: Int?, _ rhs: Int?) -> Int? {
    switch (lhs, rhs) {
    case (let lhs?, let rhs?):
      return max(lhs, rhs)
    case (let lhs?, nil):
      return lhs
    case (nil, let rhs?):
      return rhs
    case (nil, nil):
      return nil
    }
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
