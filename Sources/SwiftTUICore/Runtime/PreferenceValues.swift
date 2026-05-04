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

  func value<Value>(as type: Value.Type) -> Value?
  func reduced(
    with next: any PreferenceValueBox
  ) -> (any PreferenceValueBox)?
}

private struct TypedPreferenceValueBox<Key: PreferenceKey>: PreferenceValueBox {
  let base: Key.Value

  var keyDebugName: String {
    String(reflecting: Key.self)
  }

  var snapshotValue: String {
    String(reflecting: base)
  }

  var valueTypeDescription: String {
    String(reflecting: Key.Value.self)
  }

  func value<Value>(as type: Value.Type) -> Value? {
    base as? Value
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
  private var snapshotValues: [String: String]

  package init() {
    storage = [:]
    snapshotValues = [:]
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
      snapshotValues[box.keyDebugName] = box.snapshotValue
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
        snapshotValues[reducedBox.keyDebugName] = reducedBox.snapshotValue
      } else {
        storage[identifier] = nextBox
        snapshotValues[nextBox.keyDebugName] = nextBox.snapshotValue
      }
    }
  }
}

extension PreferenceValues {
  package static func == (
    lhs: Self,
    rhs: Self
  ) -> Bool {
    lhs.snapshotValues == rhs.snapshotValues
  }
}
