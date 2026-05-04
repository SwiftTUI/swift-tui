/// Declares a typed focused value exported by the currently focused subtree.
public protocol FocusedValueKey {
  associatedtype Value: Sendable
}

private protocol FocusedValueBox: Sendable {
  var valueTypeDescription: String { get }

  func value<Value>(as type: Value.Type) -> Value?
  func isEqual(
    to other: any FocusedValueBox
  ) -> Bool
}

private struct TypedFocusedValueBox<Value: Sendable>: FocusedValueBox {
  let base: Value

  var valueTypeDescription: String {
    String(reflecting: Value.self)
  }

  func value<T>(as type: T.Type) -> T? {
    base as? T
  }

  func isEqual(
    to other: any FocusedValueBox
  ) -> Bool {
    guard let otherValue: Value = other.value(as: Value.self) else {
      return false
    }

    if let lhs = base as? AnyHashable,
      let rhs = otherValue as? AnyHashable
    {
      return lhs == rhs
    }

    // Non-equatable focused values still need stable "same shape" comparisons
    // so focused bindings do not force spurious rerender loops.
    return true
  }
}

/// A typed container of values exported by the currently focused subtree.
public struct FocusedValues: Equatable, Sendable {
  private var storage: [ObjectIdentifier: any FocusedValueBox]

  /// Creates an empty focused-value container.
  public init() {
    storage = [:]
  }

  public subscript<K: FocusedValueKey>(key: K.Type) -> K.Value? {
    get {
      let identifier = ObjectIdentifier(key)
      guard let boxed = storage[identifier] else {
        return nil
      }
      guard let typed: K.Value = boxed.value(as: K.Value.self) else {
        preconditionFailure(
          "Focused value type mismatch for \(String(reflecting: key)). Expected \(K.Value.self), found \(boxed.valueTypeDescription)."
        )
      }
      return typed
    }
    set {
      let identifier = ObjectIdentifier(key)
      if let newValue {
        storage[identifier] = TypedFocusedValueBox(base: newValue)
      } else {
        storage.removeValue(forKey: identifier)
      }
    }
  }

  package var isEmpty: Bool {
    storage.isEmpty
  }

  package func merging(
    _ other: Self
  ) -> Self {
    var merged = self
    merged.storage.merge(other.storage) { _, new in new }
    return merged
  }

  package mutating func merge(
    _ other: Self
  ) {
    self = merging(other)
  }

  public static func == (
    lhs: Self,
    rhs: Self
  ) -> Bool {
    guard lhs.storage.keys == rhs.storage.keys else {
      return false
    }

    for identifier in lhs.storage.keys {
      guard let lhsValue = lhs.storage[identifier],
        let rhsValue = rhs.storage[identifier],
        lhsValue.isEqual(to: rhsValue)
      else {
        return false
      }
    }

    return true
  }
}
