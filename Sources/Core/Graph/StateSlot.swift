package struct AnyStateSlot {
  private enum Storage {
    case uninitialized
    case value(Any, Any.Type, (Any, Any) -> Bool)
  }

  private var storage: Storage

  package init() {
    storage = .uninitialized
  }

  package init<T>(_ value: T) {
    storage = .value(
      value,
      T.self,
      { _, _ in false }
    )
  }

  package init<T: Equatable>(_ value: T) {
    storage = .value(
      value,
      T.self,
      { lhs, rhs in
        guard let lhs = lhs as? T, let rhs = rhs as? T else {
          return false
        }
        return lhs == rhs
      }
    )
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
    self = AnyStateSlot(value)
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
