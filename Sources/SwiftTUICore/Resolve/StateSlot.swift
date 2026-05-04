package struct AnyStateSlot {
  private enum Storage {
    case uninitialized
    case value(Any, Any.Type, (Any, Any) -> Bool)
  }

  private var storage: Storage

  package init() {
    storage = .uninitialized
  }

  /// Creates an initialized slot. If `T` conforms to `Equatable` at
  /// runtime, the slot stores a type-safe equality comparator so later
  /// `set(_:)` calls can report `didChange` correctly. Otherwise the
  /// comparator conservatively reports every write as a change.
  ///
  /// Historically this type had both an `init<T>` and an
  /// `init<T: Equatable>` overload, but the Equatable overload was
  /// unreachable from most callers (including `initializeIfNeeded` and
  /// `set`) because Swift resolves overloads based on statically-known
  /// constraints. Every slot silently ended up with the always-false
  /// comparator, which in turn caused `setStateSlot` to treat every
  /// write as a change — a latent source of spurious invalidations
  /// (notably: `@GestureState` reset-on-teardown writing the same seed
  /// value to a slot whose previous value was already seed would still
  /// dirty the view and schedule another frame, producing an infinite
  /// resolve loop). The fix: detect Equatable via `any Equatable`
  /// existential opening at init time and build the right comparator
  /// regardless of static constraint context.
  package init<T>(_ value: T) {
    storage = Self.makeStorage(value: value, valueType: T.self)
  }

  private static func makeStorage<T>(
    value: T,
    valueType: Any.Type
  ) -> Storage {
    if let equatable = value as? any Equatable {
      return .value(value, valueType, makeEquatableComparator(equatable))
    }
    return .value(value, valueType, { _, _ in false })
  }

  /// Accepts an `any Equatable` existential and returns a comparator
  /// closure bound to the existential's concrete static type via
  /// Swift's implicit existential opening.
  private static func makeEquatableComparator(
    _ sample: any Equatable
  ) -> (Any, Any) -> Bool {
    return makeEquatableComparatorImpl(sample)
  }

  /// The implicit-existential-opening trampoline: when called with an
  /// `any Equatable` argument, Swift 5.7+ binds `T` to the concrete
  /// underlying type, so the returned closure captures a proper
  /// type-safe `==`.
  private static func makeEquatableComparatorImpl<T: Equatable>(
    _ sample: T
  ) -> (Any, Any) -> Bool {
    return { lhs, rhs in
      guard let l = lhs as? T, let r = rhs as? T else {
        return false
      }
      return l == r
    }
  }

  package func stores<T>(_ type: T.Type) -> Bool {
    guard case .value(_, let valueType, _) = storage else {
      return false
    }
    return valueType == T.self
  }

  package var storedTypeDescription: String {
    switch storage {
    case .uninitialized:
      return "uninitialized"
    case .value(_, let valueType, _):
      return String(reflecting: valueType)
    }
  }

  package func value<T>(as type: T.Type) -> T {
    guard case .value(let value, let valueType, _) = storage else {
      fatalError("State slot accessed before initialization.")
    }
    guard valueType == T.self, let typed = value as? T else {
      fatalError(
        "State slot type mismatch. Expected \(T.self), found \(valueType)."
      )
    }
    return typed
  }

  package mutating func set<T>(_ value: T) -> Bool {
    guard case .value(let existingValue, let valueType, let equals) = storage else {
      self = AnyStateSlot(value)
      return true
    }
    guard valueType == T.self else {
      fatalError(
        "State slot type mismatch. Expected \(valueType), found \(T.self)."
      )
    }

    let didChange = !equals(existingValue, value)
    // Preserve the existing `equals` closure — equality semantics are
    // fixed at initial-store time and must not be reset to the
    // non-Equatable always-false comparator when the value updates.
    storage = .value(value, valueType, equals)
    return didChange
  }

  package mutating func initializeIfNeeded<T>(
    with value: @autoclosure () -> T
  ) {
    guard case .uninitialized = storage else {
      return
    }
    self = AnyStateSlot(value())
  }
}
