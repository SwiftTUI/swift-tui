import SwiftTUICore

/// A key for custom values stored on a ``Transaction`` — the
/// `EnvironmentKey` shape applied to transactions.
///
/// Declare a key type, give it a default, and read or write
/// `transaction[MyKey.self]`:
///
/// ```swift
/// private struct SourceKey: TransactionKey {
///   static let defaultValue = "programmatic"
/// }
///
/// var transaction = Transaction()
/// transaction[SourceKey.self] = "gesture"
/// withTransaction(transaction) { model.offset = .zero }
/// ```
///
/// `Value` is narrowed to `Hashable & Sendable` where SwiftUI leaves the
/// associated type unconstrained — the same narrowing this surface applies
/// to environment values, because transaction values cross the off-main
/// frame tail and participate in reuse comparisons.
///
/// > Important: Key values participate in retained-reuse equivalence —
/// > resolve-time transforms read them, so a stale value under subtree
/// > reuse would be a correctness bug. A key value that changes every
/// > frame therefore silently destroys retained reuse below the writer,
/// > the same hazard class as an unequatable environment value. Prefer
/// > coarse, slow-moving values.
public protocol TransactionKey {
  /// The type of the value stored under this key.
  associatedtype Value: Hashable & Sendable

  /// The value read for this key when no value was written.
  static var defaultValue: Value { get }
}

extension Transaction {
  /// Reads or writes the custom value stored under `key`.
  ///
  /// Reading a key that was never written returns
  /// ``TransactionKey/defaultValue``.
  public subscript<Key: TransactionKey>(key: Key.Type) -> Key.Value {
    get {
      customValues[ObjectIdentifier(key)]?.unwrap(as: Key.Value.self)
        ?? Key.defaultValue
    }
    set {
      customValues[ObjectIdentifier(key)] = AnyHashableSendable(newValue)
    }
  }
}
