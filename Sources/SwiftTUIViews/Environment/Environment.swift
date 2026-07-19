import Observation
package import SwiftTUICore
import Synchronization

/// Declares a typed environment value.
public protocol EnvironmentKey {
  associatedtype Value: Sendable
  static var defaultValue: Value { get }
}

private final class EnvironmentValueBox: Sendable {
  let keyDebugName: String
  let reuseValue: TypedReuseValue

  init<Key: EnvironmentKey>(key: Key.Type, base: Key.Value) {
    keyDebugName = String(reflecting: key)
    reuseValue = TypedReuseValue(base)
  }

  var snapshotValue: String {
    reuseValue.debugValue
  }

  var valueTypeDescription: String {
    reuseValue.valueTypeDescription
  }

  func value<Value>(as type: Value.Type) -> Value? {
    reuseValue.value(as: type)
  }

  /// Change-detection equality between two boxed environment values.
  ///
  /// Compares the underlying typed values via `==`, explicit framework-owned
  /// reuse equality, or reference identity. An opaque value with no typed proof
  /// compares unequal; reflected ``snapshotValue`` text is diagnostics only.
  func isEqual(to other: EnvironmentValueBox) -> Bool {
    reuseValue.isEqual(to: other.reuseValue)
  }
}

// Semantic environment actions (`OpenLinkAction`, `ResetFocusAction`,
// `ClipboardWriteAction`, `ClipboardReadAction`) and their keys live in
// `EnvironmentActions.swift`.

private enum StackAxisKey: EnvironmentKey {
  static let defaultValue: SwiftTUICore.Axis? = nil
}

package enum EnvironmentValuesStorage {
  @TaskLocal private static var taskLocalCurrent: EnvironmentValues?
  /// Stack-lean ambient slot; see ``stackLeanResolveProfile``.
  @MainActor private static var leanCurrent: EnvironmentValues?

  @MainActor
  package static var current: EnvironmentValues? {
    stackLeanResolveProfile ? leanCurrent : taskLocalCurrent
  }

  /// Synchronous binding funnel — the only sanctioned way to install the
  /// ambient environment for a synchronous scope. Async scopes must keep
  /// using the task-local projection.
  @MainActor
  package static func binding<Result>(
    _ values: EnvironmentValues?,
    _ apply: () -> Result
  ) -> Result {
    if stackLeanResolveProfile {
      let saved = leanCurrent
      leanCurrent = values
      defer { leanCurrent = saved }
      return apply()
    }
    return $taskLocalCurrent.withValue(values) {
      apply()
    }
  }

  /// Async binding — always task-local (the scope can suspend).
  @MainActor
  package static func asyncBinding<Result>(
    _ values: EnvironmentValues?,
    _ apply: () async -> Result
  ) async -> Result {
    await $taskLocalCurrent.withValue(values) {
      await apply()
    }
  }
}

/// The inherited environment available while resolving a view subtree.
public struct EnvironmentValues: Equatable, Sendable {
  private var storage: [ObjectIdentifier: EnvironmentValueBox]
  /// Reflected values retained for snapshot diagnostics only. Change
  /// detection is driven by the typed boxes in `storage`.
  private var debugValues: [String: String]
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
    debugValues = [:]
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
      let box = EnvironmentValueBox(key: key, base: newValue)
      storage[identifier] = box
      debugValues[box.keyDebugName] = box.snapshotValue
    }
  }

  // Widened from `fileprivate` to `package` so `ResolveContext` (moved to
  // `ResolveContext.swift`) can fold environment edits back into a snapshot.
  package func applying(
    to snapshot: EnvironmentSnapshot,
    reuseStyle: Bool = false
  ) -> EnvironmentSnapshot {
    var mergedValues = snapshot.values
    if !debugValues.isEmpty {
      mergedValues.merge(debugValues) { _, new in new }
    }
    var mergedTypedValues = snapshot.typedValues
    for (identifier, box) in storage {
      mergedTypedValues[identifier] = EnvironmentSnapshotValue(
        keyDebugName: box.keyDebugName,
        reuseValue: box.reuseValue
      )
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
      typedValues: mergedTypedValues,
      style: style
    )
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    // Change detection compares the boxed typed values. `debugValues` is a
    // debug projection only; it is deliberately not equality currency.
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
