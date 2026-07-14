import Observation
package import SwiftTUICore
import Synchronization

/// Declares a typed environment value.
public protocol EnvironmentKey {
  associatedtype Value: Sendable
  static var defaultValue: Value { get }
}

private protocol EnvironmentValueBox: Sendable {
  var snapshotValue: String { get }
  var valueTypeDescription: String { get }

  func value<Value>(as type: Value.Type) -> Value?

  /// Change-detection equality between two boxed environment values.
  ///
  /// Compares the underlying typed values via `==` when `Value` is `Equatable`,
  /// and otherwise falls back to the reflected ``snapshotValue`` string — the
  /// historical comparison for every value — so non-`Equatable` keys keep their
  /// prior conservative behavior.
  func isEqual(to other: any EnvironmentValueBox) -> Bool
}

private struct TypedEnvironmentValueBox<Value: Sendable>: EnvironmentValueBox {
  let base: Value

  var snapshotValue: String {
    String(reflecting: base)
  }

  var valueTypeDescription: String {
    String(reflecting: Value.self)
  }

  func value<T>(as type: T.Type) -> T? {
    base as? T
  }

  func isEqual(to other: any EnvironmentValueBox) -> Bool {
    // A box only ever shares a storage key with a box of the same `Value` type
    // (the environment key fixes the value type), so extraction succeeds for
    // matching keys. A type mismatch is treated as changed.
    guard let otherBase = other.value(as: Value.self) else {
      return false
    }
    if let equatable = base as? any Equatable {
      return Self.areEqual(equatable, otherBase)
    }
    // Non-`Equatable`: preserve the historical reflected-string comparison.
    return snapshotValue == other.snapshotValue
  }

  /// Opens the `any Equatable` existential to bind its concrete type so `==`
  /// is type-safe. Mirrors `MemoValueComparator.openEquatable`.
  private static func areEqual(_ lhs: any Equatable, _ rhs: Value) -> Bool {
    func compare<T: Equatable>(_ l: T) -> Bool {
      guard let r = rhs as? T else { return false }
      return l == r
    }
    return compare(lhs)
  }
}

// Semantic environment actions (`OpenLinkAction`, `ResetFocusAction`,
// `ClipboardWriteAction`, `ClipboardReadAction`) and their keys live in
// `EnvironmentActions.swift`.

private enum StackAxisKey: EnvironmentKey {
  static let defaultValue: SwiftTUICore.Axis? = nil
}

package enum EnvironmentValuesStorage {
  @TaskLocal static var current: EnvironmentValues?
}

/// The inherited environment available while resolving a view subtree.
public struct EnvironmentValues: Equatable, Sendable {
  private var storage: [ObjectIdentifier: any EnvironmentValueBox]
  private var snapshotValues: [String: String]
  package var _focusedIdentity: Identity?
  package var _pressedIdentity: Identity?
  /// Side-field like `_focusedIdentity`: the per-node focus-cone bake
  /// (`ResolveContext.contextualEnvironmentValues`) must not enter the
  /// reuse-compared snapshot, or every focus move env-mismatches the whole
  /// divergent ancestor cone and recomputes disjoint subtrees. Readers are
  /// invalidated through the `FocusedIdentityKey` runtime focus dependency
  /// instead (`runtimeFocusStateDependencyKey(for:)`).
  package var _isFocused: Bool

  /// Creates an empty environment container.
  public init() {
    storage = [:]
    snapshotValues = [:]
    _focusedIdentity = nil
    _pressedIdentity = nil
    _isFocused = false
  }

  public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
    get {
      let identifier = ObjectIdentifier(key)
      MainActor.assumeIsolated {
        ViewNodeContext.current?.recordEnvironmentRead(identifier)
      }
      guard let boxed = storage[identifier] else {
        let defaultValue = K.defaultValue
        recordObservableEnvironmentRead(defaultValue)
        return defaultValue
      }
      guard let typed: K.Value = boxed.value(as: K.Value.self) else {
        preconditionFailure(
          "Environment type mismatch for \(String(reflecting: key)). Expected \(K.Value.self), found \(boxed.valueTypeDescription)."
        )
      }
      recordObservableEnvironmentRead(typed)
      return typed
    }
    set {
      let identifier = ObjectIdentifier(key)
      let box = TypedEnvironmentValueBox(base: newValue)
      storage[identifier] = box
      snapshotValues[String(reflecting: key)] = box.snapshotValue
    }
  }

  // Widened from `fileprivate` to `package` so `ResolveContext` (moved to
  // `ResolveContext.swift`) can fold environment edits back into a snapshot.
  package func applying(
    to snapshot: EnvironmentSnapshot,
    reuseStyle: Bool = false
  ) -> EnvironmentSnapshot {
    var mergedValues = snapshot.values
    if !snapshotValues.isEmpty {
      mergedValues.merge(snapshotValues) { _, new in new }
    }
    let style: StyleEnvironmentSnapshot
    if reuseStyle {
      // Non-style keypath changed: reuse heavy fields, update lightweight ones.
      style = StyleEnvironmentSnapshot(
        heavyFields: snapshot.style.heavyFields,
        foregroundStyle: foregroundStyle,
        tintStyle: tintStyle,
        isEnabled: isEnabled,
        cellPixelMetrics: cellPixelMetrics
      )
    } else {
      style = StyleEnvironmentSnapshot(
        appearance: terminalAppearance,
        theme: theme,
        foregroundStyle: foregroundStyle,
        tintStyle: tintStyle,
        isEnabled: isEnabled,
        cellPixelMetrics: cellPixelMetrics
      )
    }
    return EnvironmentSnapshot(
      debugSignature: snapshot.debugSignature,
      values: mergedValues,
      style: style
    )
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    // Change detection compares the boxed typed values. `storage` keys are in
    // exact 1:1 correspondence with the reflected `snapshotValues` keys (both
    // are written together on every set and never removed), so requiring the
    // same key set here matches the historical `snapshotValues == snapshotValues`
    // key comparison. Per-key, `isEqual(to:)` uses typed `==` for `Equatable`
    // values and the reflected-string fallback otherwise.
    guard lhs.storage.count == rhs.storage.count else {
      return false
    }
    for (identifier, lhsBox) in lhs.storage {
      guard let rhsBox = rhs.storage[identifier],
        lhsBox.isEqual(to: rhsBox)
      else {
        return false
      }
    }
    return true
  }

  private func recordObservableEnvironmentRead<Value>(
    _ value: Value
  ) {
    guard let observable = value as? any Observable & AnyObject else {
      return
    }
    let observableID = ObjectIdentifier(observable)
    MainActor.assumeIsolated {
      ViewNodeContext.current?.recordObservableRead(observableID)
    }
  }
}

@propertyWrapper
@MainActor
/// Reads an inherited environment value from the current view context.
public struct Environment<Value: Sendable> {
  /// Non-nil for key-path readers; the type-keyed observable-object form
  /// (``init(_:)-swift.type``) reads through ``read`` instead, because a key
  /// path cannot reference the generic type-keyed subscript (metatype
  /// indices are not `Hashable`).
  private let keyPath: KeyPath<EnvironmentValues, Value>?
  private let read: (EnvironmentValues) -> Value

  /// Creates an environment-value reader for `keyPath`.
  public init(
    _ keyPath: KeyPath<EnvironmentValues, Value>
  ) {
    self.keyPath = keyPath
    read = { $0[keyPath: keyPath] }
  }

  /// The type-keyed reader seam for the observable-object form; see
  /// `ObservableObjectEnvironment.swift`.
  package init(read: @escaping (EnvironmentValues) -> Value) {
    keyPath = nil
    self.read = read
  }

  public var wrappedValue: Value {
    if let keyPath {
      EnvironmentValues.recordRuntimeFocusStateDependencyRead(for: keyPath)
    }
    guard let current = EnvironmentValuesStorage.current else {
      // The silent-default class (F136): inside an authoring/dispatch scope
      // the registration-time environment should have been established
      // around this read (`HandlerDescriptorIntake` stamps it over every
      // wrapped dispatch) — falling back to defaults there is the
      // observable signature of a capture seam that dodged the intake.
      // Reads with no authoring scope at all are the documented default
      // behavior and stay uncounted.
      if currentAuthoringContext() != nil {
        SoundnessProbeConfiguration.recordAmbientEnvironmentFallbackRead(
          "@Environment(\(keyPath.map(String.init(describing:)) ?? "\(Value.self)")) read default values inside an authoring scope"
        )
      }
      return read(EnvironmentValues())
    }
    return read(current)
  }
}

extension EnvironmentValues {
  package var stackAxis: SwiftTUICore.Axis? {
    get { self[StackAxisKey.self] }
    set { self[StackAxisKey.self] = newValue }
  }
}

// `ResolveContext` — the per-pass resolve configuration — lives in
// `ResolveContext.swift`.

/// Reads an environment value and maps it into authored content.
public struct EnvironmentReader<Value, Content: View>: PrimitiveView, ResolvableView {
  private let keyPath: KeyPath<EnvironmentValues, Value>
  private let content: (Value) -> Content
  private let authoringContext: AuthoringContext?

  public init(
    _ keyPath: KeyPath<EnvironmentValues, Value>,
    @ViewBuilder content: @escaping (Value) -> Content
  ) {
    self.keyPath = keyPath
    self.content = content
    authoringContext = currentAuthoringContext()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let view = withAuthoringContext(authoringContext) {
      context.trackingObservableAccess {
        EnvironmentValues.recordRuntimeFocusStateDependencyRead(for: keyPath)
        return content(context.environmentValues[keyPath: keyPath])
      }
    }
    return view.resolveElements(in: context)
  }
}

extension EnvironmentValues {
  package static func recordRuntimeFocusStateDependencyRead<Value>(
    for keyPath: KeyPath<EnvironmentValues, Value>
  ) {
    guard let key = runtimeFocusStateDependencyKey(for: keyPath) else {
      return
    }
    MainActor.assumeIsolated {
      ViewNodeContext.current?.recordEnvironmentRead(key)
    }
  }
}
