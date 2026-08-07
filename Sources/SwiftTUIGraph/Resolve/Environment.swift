/// Opt-in reuse equality for closure-backed framework values that can name a
/// stable semantic carrier more precisely than generic `Equatable` can.
///
/// Opaque values do not receive reflection-based equality: absent `Equatable`,
/// this protocol, or reference identity, the typed reuse currency treats them
/// as changed. Implementations therefore carry the burden of proving that
/// equality cannot preserve a stale closure or handle.
package protocol TypedReuseEqualityProviding: Sendable {
  func isEqualForReuse(to other: any Sendable) -> Bool
}

extension Array: TypedReuseEqualityProviding where Element: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self,
      count == other.count
    else {
      return false
    }
    for (left, right) in zip(self, other) {
      guard left.isEqualForReuse(to: right) else {
        return false
      }
    }
    return true
  }
}

package func typedValuesAreEqualForReuse<Value: Sendable>(
  _ lhs: Value,
  _ rhs: Value
) -> Bool {
  if let equatable = lhs as? any Equatable {
    return typedEquatableValuesAreEqual(equatable, rhs)
  }
  if let provider = lhs as? any TypedReuseEqualityProviding {
    return provider.isEqualForReuse(to: rhs)
  }
  if Value.self is AnyObject.Type {
    return (lhs as AnyObject) === (rhs as AnyObject)
  }

  // No typed proof exists. Treating two such values as equal could retain a
  // stale closure; conservative inequality may cost reuse but preserves
  // correctness.
  return false
}

private func typedEquatableValuesAreEqual<Value>(
  _ lhs: any Equatable,
  _ rhs: Value
) -> Bool {
  func compare<T: Equatable>(_ left: T) -> Bool {
    guard let right = rhs as? T else {
      return false
    }
    return left == right
  }
  return compare(lhs)
}

/// A type-erased, typed equality currency used by environment snapshots and
/// reduced preferences.
///
/// `debugValue` deliberately is not equality input. It preserves the old
/// reflected representation for tree descriptions and denial diagnostics while
/// equality opens the original type and uses its declared semantics. Both
/// reflected strings are computed on demand: reflection must never run on the
/// per-write environment/preference hot path, only when diagnostics ask.
package struct TypedReuseValue: Sendable {
  private let storage: TypedReuseValueStorage

  package init<Value: Sendable>(_ value: Value) {
    storage = TypedReuseValueStorage(value)
  }

  package var debugValue: String {
    storage.debugValue
  }

  package var valueTypeDescription: String {
    storage.valueTypeDescription
  }

  package func isEqual(to other: Self) -> Bool {
    if storage === other.storage {
      return true
    }
    return storage.isEqual(to: other.storage)
  }

  package func value<Value>(as type: Value.Type) -> Value? {
    storage.value(as: type)
  }
}

private final class TypedReuseValueStorage: Sendable {
  private let valueType: ObjectIdentifier
  private let declaredValueType: Any.Type
  private let valueOperation: @Sendable () -> any Sendable
  private let comparator: @Sendable (TypedReuseValueStorage) -> Bool

  init<Value: Sendable>(_ value: Value) {
    valueType = ObjectIdentifier(Value.self)
    declaredValueType = Value.self
    valueOperation = { value }
    comparator = { other in
      guard other.valueType == ObjectIdentifier(Value.self),
        let right = other.valueOperation() as? Value
      else {
        return false
      }
      return typedValuesAreEqualForReuse(value, right)
    }
  }

  var debugValue: String {
    String(reflecting: valueOperation())
  }

  var valueTypeDescription: String {
    String(reflecting: declaredValueType)
  }

  func isEqual(to other: TypedReuseValueStorage) -> Bool {
    comparator(other)
  }

  func value<Value>(as type: Value.Type) -> Value? {
    valueOperation() as? Value
  }
}

package struct EnvironmentSnapshotValue: Sendable {
  private let keyType: Any.Type
  package let reuseValue: TypedReuseValue

  package init(
    keyType: Any.Type,
    reuseValue: TypedReuseValue
  ) {
    self.keyType = keyType
    self.reuseValue = reuseValue
  }

  /// The `EnvironmentKey` metatype this value was written under — the
  /// classification and rebuild currency for reader-scoped environment reuse.
  package var environmentKeyType: Any.Type {
    keyType
  }

  /// Reflected on demand; the per-write environment path stores only the key
  /// metatype and never formats it.
  package var keyDebugName: String {
    String(reflecting: keyType)
  }

  package func isEqual(to other: Self) -> Bool {
    reuseValue.isEqual(to: other.reuseValue)
  }
}

private final class EnvironmentSnapshotStorage: Sendable {
  let debugSignature: String
  let typedValues: [ObjectIdentifier: EnvironmentSnapshotValue]
  /// Entries with no typed counterpart (public `init(values:)` and the public
  /// `values` setter). Typed writes never touch this dictionary, so building a
  /// snapshot does no per-write partitioning work.
  let untypedValues: [String: String]
  let style: StyleEnvironmentSnapshot

  init(
    debugSignature: String,
    untypedValues: [String: String],
    typedValues: [ObjectIdentifier: EnvironmentSnapshotValue],
    style: StyleEnvironmentSnapshot
  ) {
    self.debugSignature = debugSignature
    self.untypedValues = untypedValues
    self.typedValues = typedValues
    self.style = style
  }
}

/// An immutable snapshot of environment values captured during resolve.
public struct EnvironmentSnapshot: Sendable {
  private var storage: EnvironmentSnapshotStorage

  public var debugSignature: String {
    get { storage.debugSignature }
    set {
      storage = .init(
        debugSignature: newValue,
        untypedValues: storage.untypedValues,
        typedValues: storage.typedValues,
        style: storage.style
      )
    }
  }

  /// The public debug projection: untyped entries plus each typed entry under
  /// its reflected key name. Derived on demand — reading it reflects; writing
  /// a snapshot never does.
  public var values: [String: String] {
    get {
      var projection = storage.untypedValues
      for value in storage.typedValues.values {
        projection[value.keyDebugName] = value.reuseValue.debugValue
      }
      return projection
    }
    set {
      // `values` is the public debug projection. Preserve typed currency only
      // for entries whose projection still matches; directly overwriting a
      // typed key invalidates that box and falls back to actual String equality.
      let retainedTypedValues = storage.typedValues.filter { _, value in
        newValue[value.keyDebugName] == value.reuseValue.debugValue
      }
      let retainedDebugNames = Set(retainedTypedValues.values.map(\.keyDebugName))
      storage = .init(
        debugSignature: storage.debugSignature,
        untypedValues: newValue.filter { !retainedDebugNames.contains($0.key) },
        typedValues: retainedTypedValues,
        style: storage.style
      )
    }
  }

  public var style: StyleEnvironmentSnapshot {
    get { storage.style }
    set {
      storage = .init(
        debugSignature: storage.debugSignature,
        untypedValues: storage.untypedValues,
        typedValues: storage.typedValues,
        style: newValue
      )
    }
  }

  public init(
    debugSignature: String = "",
    values: [String: String] = [:],
    style: StyleEnvironmentSnapshot = .init()
  ) {
    storage = .init(
      debugSignature: debugSignature,
      untypedValues: values,
      typedValues: [:],
      style: style
    )
  }

  package init(
    debugSignature: String = "",
    untypedValues: [String: String] = [:],
    typedValues: [ObjectIdentifier: EnvironmentSnapshotValue],
    style: StyleEnvironmentSnapshot = .init()
  ) {
    storage = .init(
      debugSignature: debugSignature,
      untypedValues: untypedValues,
      typedValues: typedValues,
      style: style
    )
  }

  package var typedValues: [ObjectIdentifier: EnvironmentSnapshotValue] {
    storage.typedValues
  }

  package var untypedValues: [String: String] {
    storage.untypedValues
  }

  /// The typed-key-level difference between two snapshots, for the
  /// reader-scoped reuse toleration (`ViewGraph.memoizedReusableSnapshot`).
  ///
  /// `changedTypedKeys` names keys present on BOTH sides whose values compare
  /// unequal. Any other divergence — a key present on only one side, an
  /// untyped-value difference, a style difference, or a signature difference —
  /// sets `hasNonTypedDivergence`, which callers treat as an unconditional
  /// denial (those classes are not reader-attributed).
  package struct TypedDiff {
    package var changedTypedKeys: Set<ObjectIdentifier> = []
    package var hasNonTypedDivergence = false
  }

  package func typedDiff(from other: Self) -> TypedDiff {
    var diff = TypedDiff()
    if debugSignature != other.debugSignature
      || storage.untypedValues != other.storage.untypedValues
      || style != other.style
    {
      diff.hasNonTypedDivergence = true
      return diff
    }
    let keys = Set(storage.typedValues.keys).union(other.storage.typedValues.keys)
    for key in keys {
      guard let left = storage.typedValues[key],
        let right = other.storage.typedValues[key]
      else {
        diff.hasNonTypedDivergence = true
        return diff
      }
      if !left.isEqual(to: right) {
        diff.changedTypedKeys.insert(key)
      }
    }
    return diff
  }

  package func differingValueDebugNames(from other: Self) -> [String] {
    var names: [String] = []
    let typedKeys = Set(storage.typedValues.keys).union(other.storage.typedValues.keys)
    for identifier in typedKeys {
      guard let left = storage.typedValues[identifier],
        let right = other.storage.typedValues[identifier],
        left.isEqual(to: right)
      else {
        names.append(
          storage.typedValues[identifier]?.keyDebugName
            ?? other.storage.typedValues[identifier]?.keyDebugName
            ?? String(describing: identifier)
        )
        continue
      }
    }

    let untypedKeys = Set(storage.untypedValues.keys).union(other.storage.untypedValues.keys)
    for key in untypedKeys where storage.untypedValues[key] != other.storage.untypedValues[key] {
      names.append(key)
    }
    return names.sorted()
  }
}

extension EnvironmentSnapshot: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    if lhs.storage === rhs.storage {
      return true
    }

    guard lhs.debugSignature == rhs.debugSignature,
      lhs.storage.untypedValues == rhs.storage.untypedValues,
      lhs.style == rhs.style,
      lhs.storage.typedValues.count == rhs.storage.typedValues.count
    else {
      return false
    }

    for (identifier, left) in lhs.storage.typedValues {
      guard let right = rhs.storage.typedValues[identifier],
        left.isEqual(to: right)
      else {
        return false
      }
    }
    return true
  }
}
