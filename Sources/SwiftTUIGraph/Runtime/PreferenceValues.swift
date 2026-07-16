/// Declares a named value produced by a view subtree.
public protocol PreferenceKey {
  associatedtype Value: Sendable

  /// The default value of the preference.
  static var defaultValue: Value { get }

  /// Combines one preference value with the next value in view-tree order.
  static func reduce(
    value: inout Value,
    nextValue: () -> Value
  )
}

private protocol PreferenceValueBox: Sendable {
  var keyDebugName: String { get }
  var snapshotValue: String { get }
  var valueTypeDescription: String { get }
  var reuseValue: TypedReuseValue { get }

  func value<Value>(as type: Value.Type) -> Value?
  func isEqual(to other: any PreferenceValueBox) -> Bool
  func reduced(
    with next: any PreferenceValueBox
  ) -> (any PreferenceValueBox)?
}

private struct TypedPreferenceValueBox<Key: PreferenceKey>: PreferenceValueBox {
  let base: Key.Value
  let reuseValue: TypedReuseValue

  init(base: Key.Value) {
    self.base = base
    reuseValue = TypedReuseValue(base)
  }

  var keyDebugName: String {
    String(reflecting: Key.self)
  }

  var snapshotValue: String {
    reuseValue.debugValue
  }

  var valueTypeDescription: String {
    reuseValue.valueTypeDescription
  }

  func value<Value>(as type: Value.Type) -> Value? {
    base as? Value
  }

  func isEqual(to other: any PreferenceValueBox) -> Bool {
    reuseValue.isEqual(to: other.reuseValue)
  }

  func reduced(
    with next: any PreferenceValueBox
  ) -> (any PreferenceValueBox)? {
    guard let nextValue: Key.Value = next.value(as: Key.Value.self) else {
      return nil
    }

    var reducedValue = base
    Key.reduce(
      value: &reducedValue,
      nextValue: { nextValue }
    )
    return TypedPreferenceValueBox(base: reducedValue)
  }
}

/// A typed container of reduced preference values for a resolved subtree.
package struct PreferenceValues: Equatable, Sendable {
  private var storage: [ObjectIdentifier: any PreferenceValueBox]
  /// Reflected values retained for diagnostics only. Reuse equality is driven
  /// by the typed boxes in `storage`.
  private var debugValues: [String: String]

  package init() {
    storage = [:]
    debugValues = [:]
  }

  package subscript<K: PreferenceKey>(key: K.Type) -> K.Value {
    get {
      let identifier = ObjectIdentifier(key)
      guard let boxed = storage[identifier] else {
        return K.defaultValue
      }
      guard let typed: K.Value = boxed.value(as: K.Value.self) else {
        preconditionFailure(
          "Preference value type mismatch for \(String(reflecting: key)). Expected \(K.Value.self), found \(boxed.valueTypeDescription)."
        )
      }
      return typed
    }
    set {
      let identifier = ObjectIdentifier(key)
      let box = TypedPreferenceValueBox<K>(base: newValue)
      storage[identifier] = box
      debugValues[box.keyDebugName] = box.snapshotValue
    }
  }

  package var isEmpty: Bool {
    storage.isEmpty
  }

  package func contains<K: PreferenceKey>(
    _ key: K.Type
  ) -> Bool {
    storage[ObjectIdentifier(key)] != nil
  }

  package mutating func merge<K: PreferenceKey>(
    _ key: K.Type,
    value: K.Value
  ) {
    let identifier = ObjectIdentifier(key)
    if let boxed = storage[identifier] {
      guard let currentValue: K.Value = boxed.value(as: K.Value.self) else {
        preconditionFailure(
          "Preference value type mismatch for \(String(reflecting: key)). Expected \(K.Value.self), found \(boxed.valueTypeDescription)."
        )
      }
      var reducedValue = currentValue
      K.reduce(
        value: &reducedValue,
        nextValue: { value }
      )
      self[key] = reducedValue
      return
    }

    self[key] = value
  }

  package mutating func transform<K: PreferenceKey>(
    _ key: K.Type,
    _ transform: (inout K.Value) -> Void
  ) {
    var value = self[key]
    transform(&value)
    self[key] = value
  }

  package mutating func merge(
    _ other: Self
  ) {
    for (identifier, nextBox) in other.storage {
      if let currentBox = storage[identifier] {
        guard let reducedBox = currentBox.reduced(with: nextBox) else {
          preconditionFailure(
            "Preference reduction type mismatch for \(nextBox.keyDebugName)."
          )
        }
        storage[identifier] = reducedBox
        debugValues[reducedBox.keyDebugName] = reducedBox.snapshotValue
      } else {
        storage[identifier] = nextBox
        debugValues[nextBox.keyDebugName] = nextBox.snapshotValue
      }
    }
  }
}

extension PreferenceValues {
  package static func == (
    lhs: Self,
    rhs: Self
  ) -> Bool {
    guard lhs.storage.count == rhs.storage.count else {
      return false
    }
    for (identifier, left) in lhs.storage {
      guard let right = rhs.storage[identifier],
        left.isEqual(to: right)
      else {
        return false
      }
    }
    return true
  }
}
