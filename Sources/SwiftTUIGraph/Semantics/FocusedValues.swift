/// Declares a typed focused value exported by the currently focused subtree.
public protocol FocusedValueKey {
  associatedtype Value: Sendable
}

/// A focused value that reports its own equality on the main actor.
///
/// Focused values are compared by the focus-sync convergence loop to decide
/// whether a rendered tree still needs another pass. Some focused-value types
/// (notably `Binding`, the payload of `@FocusedBinding`) are neither `Hashable`
/// nor cheaply comparable off the main actor, so they cannot participate in the
/// nonisolated `FocusedValues.==`. Conforming such a type here lets it define a
/// main-actor comparison (e.g. a `Binding` compared by its current value) so a
/// stable focused value converges the loop instead of comparing unequal on every
/// iteration (which previously looped until the rerender budget tripped).
package protocol MainActorFocusedValueEquatable {
  @MainActor func isFocusedValueEqual(to other: Any) -> Bool
}

private protocol FocusedValueBox: Sendable {
  var valueTypeDescription: String { get }

  func value<Value>(as type: Value.Type) -> Value?
  func isEqual(
    to other: any FocusedValueBox
  ) -> Bool
  @MainActor func isMainActorEqual(
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

    // Conservative fallback for non-Hashable focused values: we cannot prove the
    // two values are equal, so we must assume they changed and report inequality.
    // Returning true here would swallow real updates (a changed value would be
    // seen as unchanged), so we return false to force an update instead.
    return false
  }

  @MainActor
  func isMainActorEqual(
    to other: any FocusedValueBox
  ) -> Bool {
    guard let otherValue: Value = other.value(as: Value.self) else {
      return false
    }

    // Main-actor self-comparison (e.g. a `Binding` compared by current value).
    // This is what lets a stable focused binding terminate the focus-sync loop:
    // a `Binding` has no stable identity across renders (it is a fresh value of
    // `@MainActor` closures each body evaluation), so only its bound value is a
    // reliable convergence signal.
    if let comparable = base as? any MainActorFocusedValueEquatable {
      return comparable.isFocusedValueEqual(to: otherValue)
    }

    // Otherwise fall back to the nonisolated structural comparison.
    return isEqual(to: other)
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

  /// Main-actor semantic equality used by the focus-sync convergence loop.
  ///
  /// Unlike the nonisolated ``==``, this compares main-actor self-comparing
  /// values (`Binding`, via ``MainActorFocusedValueEquatable``) by their current
  /// value rather than reporting them as always-changed. A focused field that
  /// publishes a stable `Binding` therefore converges the loop in one extra
  /// pass instead of rerendering until the budget trips.
  @MainActor
  package func focusSyncEquals(_ other: FocusedValues) -> Bool {
    guard storage.keys == other.storage.keys else {
      return false
    }

    for identifier in storage.keys {
      guard let lhsValue = storage[identifier],
        let rhsValue = other.storage[identifier],
        lhsValue.isMainActorEqual(to: rhsValue)
      else {
        return false
      }
    }

    return true
  }
}
