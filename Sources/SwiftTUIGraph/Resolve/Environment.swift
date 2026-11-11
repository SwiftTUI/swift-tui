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
///
/// The value is boxed by its static type once, when it is written. A snapshot
/// comparison reads every typed value of both snapshots, and one write is
/// compared by the reuse door, the measurement cache and the placement cache,
/// so the comparison is the hot side: it must not look a conformance up or
/// cast the value. See ``makeTypedReuseValueStorage(_:)``.
package struct TypedReuseValue: Sendable {
  private let storage: any TypedReuseValueStorage

  package init<Value: Sendable>(_ value: Value) {
    storage = makeTypedReuseValueStorage(value)
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

private protocol TypedReuseValueStorage: AnyObject, Sendable {
  var debugValue: String { get }
  var valueTypeDescription: String { get }

  /// Whether `other` boxes the same static type and an equal value.
  func isEqual(to other: any TypedReuseValueStorage) -> Bool
  func value<Value>(as type: Value.Type) -> Value?
}

/// Boxes `value` with the comparison its static type proves.
///
/// ``typedValuesAreEqualForReuse(_:_:)`` decides how to compare two values by
/// casting one of them to `any Equatable`, then to
/// `any TypedReuseEqualityProviding`. For a struct or an enum those casts
/// answer a question about the static type, so the answer is the same for
/// every value of the type and can be taken once, here. Such a value gets a
/// box that compares through the conformance directly.
///
/// A class instance and an existential keep the dynamic comparison: their
/// dynamic type can conform where the static type does not, and the function
/// above defines equality by the dynamic type.
private func makeTypedReuseValueStorage<Value: Sendable>(
  _ value: Value
) -> any TypedReuseValueStorage {
  if !(Value.self is AnyObject.Type) {
    let boxer = ReuseValueBoxer<Value>()
    if let equatable = boxer as? any EquatableReuseValueBoxing<Value> {
      return equatable.equatableStorage(value)
    }
    if let provider = boxer as? any ProvidedReuseValueBoxing<Value> {
      return provider.providedStorage(value)
    }
  }
  return DynamicReuseValueBox(value)
}

/// Opens `Subject: Equatable` from a type that is only known to be `Sendable`.
///
/// ``ReuseValueBoxer`` conforms exactly when its subject is `Equatable`, so a
/// successful cast to this protocol hands back a function that is compiled
/// against the conformance.
private protocol EquatableReuseValueBoxing<Subject> {
  associatedtype Subject: Sendable
  func equatableStorage(_ value: Subject) -> any TypedReuseValueStorage
}

/// Opens `Subject: TypedReuseEqualityProviding`; see
/// ``EquatableReuseValueBoxing``.
private protocol ProvidedReuseValueBoxing<Subject> {
  associatedtype Subject: Sendable
  func providedStorage(_ value: Subject) -> any TypedReuseValueStorage
}

private struct ReuseValueBoxer<Subject: Sendable> {}

extension ReuseValueBoxer: EquatableReuseValueBoxing where Subject: Equatable {
  func equatableStorage(_ value: Subject) -> any TypedReuseValueStorage {
    EquatableReuseValueBox(value)
  }
}

extension ReuseValueBoxer: ProvidedReuseValueBoxing
where Subject: TypedReuseEqualityProviding {
  func providedStorage(_ value: Subject) -> any TypedReuseValueStorage {
    ProvidedReuseValueBox(value)
  }
}

/// A value-type value compared with its own `==`.
private final class EquatableReuseValueBox<Value: Sendable & Equatable>:
  TypedReuseValueStorage
{
  private let value: Value

  init(_ value: Value) {
    self.value = value
  }

  var debugValue: String {
    String(reflecting: value)
  }

  var valueTypeDescription: String {
    String(reflecting: Value.self)
  }

  func isEqual(to other: any TypedReuseValueStorage) -> Bool {
    guard let other = other as? EquatableReuseValueBox<Value> else {
      return false
    }
    return value == other.value
  }

  func value<Requested>(as type: Requested.Type) -> Requested? {
    value as? Requested
  }
}

/// A value-type value that is not `Equatable` and names its own reuse
/// equality.
private final class ProvidedReuseValueBox<Value: TypedReuseEqualityProviding>:
  TypedReuseValueStorage
{
  private let value: Value

  init(_ value: Value) {
    self.value = value
  }

  var debugValue: String {
    String(reflecting: value)
  }

  var valueTypeDescription: String {
    String(reflecting: Value.self)
  }

  func isEqual(to other: any TypedReuseValueStorage) -> Bool {
    guard let other = other as? ProvidedReuseValueBox<Value> else {
      return false
    }
    return value.isEqualForReuse(to: other.value)
  }

  func value<Requested>(as type: Requested.Type) -> Requested? {
    value as? Requested
  }
}

/// A value whose comparison depends on its dynamic type, or that has no typed
/// proof at all.
private final class DynamicReuseValueBox<Value: Sendable>: TypedReuseValueStorage {
  private let value: Value

  init(_ value: Value) {
    self.value = value
  }

  var debugValue: String {
    String(reflecting: value)
  }

  var valueTypeDescription: String {
    String(reflecting: Value.self)
  }

  func isEqual(to other: any TypedReuseValueStorage) -> Bool {
    guard let other = other as? DynamicReuseValueBox<Value> else {
      return false
    }
    return typedValuesAreEqualForReuse(value, other.value)
  }

  func value<Requested>(as type: Requested.Type) -> Requested? {
    value as? Requested
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
  /// its reflected key name. Derived on demand: reading it reflects; writing
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

extension EnvironmentSnapshot {
  /// Remembers which pairs of distinct snapshots one tree walk has already
  /// proved equal.
  ///
  /// Two resolves of an unchanged view build separate snapshot objects that
  /// compare equal, and every node below an environment write shares its
  /// parent's snapshot. A walk that compares two such trees node by node would
  /// repeat the same deep comparison — every typed value of both snapshots —
  /// once per node. The memo keeps the last few proved pairs, so that
  /// comparison runs once per pair of snapshots. A pair is identified by the
  /// two storage objects, which both trees keep alive for the walk.
  package struct EqualityMemo {
    private struct Pair {
      let lhs: ObjectIdentifier
      let rhs: ObjectIdentifier
    }

    private var provedEqual: [Pair] = []
    private var nextReplacement = 0
    private static var capacity: Int { 4 }

    package init() {}

    /// `lhs == rhs`, compared deeply at most once per pair of snapshots.
    @inline(__always)
    package mutating func areEqual<Mode: ComparisonWorkMode>(
      _ lhs: EnvironmentSnapshot,
      _ rhs: EnvironmentSnapshot,
      mode: Mode.Type,
      work: inout ComparisonWork
    ) -> Bool {
      if lhs.storage === rhs.storage {
        if Mode.isEnabled {
          work.environmentSnapshots += 1
          work.environmentSharedStorage += 1
        }
        return true
      }
      let pair = Pair(lhs: ObjectIdentifier(lhs.storage), rhs: ObjectIdentifier(rhs.storage))
      for proved in provedEqual where proved.lhs == pair.lhs && proved.rhs == pair.rhs {
        return true
      }
      guard lhs.isEqual(to: rhs, mode: mode, work: &work) else {
        return false
      }
      if provedEqual.count < Self.capacity {
        provedEqual.append(pair)
      } else {
        provedEqual[nextReplacement] = pair
        nextReplacement = (nextReplacement + 1) % Self.capacity
      }
      return true
    }
  }
}

extension EnvironmentSnapshot: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    var work = ComparisonWork()
    return lhs.isEqual(to: rhs, mode: SkipComparisonWork.self, work: &work)
  }

  @inline(__always)
  package func isEqual<Mode: ComparisonWorkMode>(
    to rhs: Self,
    mode: Mode.Type,
    work: inout ComparisonWork
  ) -> Bool {
    let lhs = self
    if Mode.isEnabled { work.environmentSnapshots += 1 }
    if lhs.storage === rhs.storage {
      if Mode.isEnabled { work.environmentSharedStorage += 1 }
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
      guard let right = rhs.storage.typedValues[identifier] else {
        return false
      }
      if Mode.isEnabled { work.environmentValues += 1 }
      guard left.isEqual(to: right) else {
        return false
      }
    }
    return true
  }
}
