import Observation
public import SwiftTUICore
import Synchronization

/// Declares a typed environment value.
public protocol EnvironmentKey {
  associatedtype Value: Sendable
  static var defaultValue: Value { get }
}

private final class EnvironmentValueBox: Sendable {
  /// Stored as a metatype so a write never formats a reflected name; the
  /// snapshot's `values` projection reflects it on demand.
  let keyType: Any.Type
  let reuseValue: TypedReuseValue

  init<Key: EnvironmentKey>(key: Key.Type, base: Key.Value) {
    keyType = key
    reuseValue = TypedReuseValue(base)
  }

  /// Rebuilds a box from the graph's type-erased snapshot currency.
  ///
  /// `EnvironmentSnapshotValue` stores exactly this box's payload — the key
  /// metatype and the typed reuse value — because `EnvironmentValues.applying`
  /// mints it from one. That symmetry is what lets the reader-scoped
  /// environment repair travel back across the module seam without a key
  /// generic, an existential open, or any reflection.
  init(keyType: Any.Type, reuseValue: TypedReuseValue) {
    self.keyType = keyType
    self.reuseValue = reuseValue
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
    // Lean reads fall back to the task-local: async scopes bind via
    // `asyncBinding` (always task-local — a plain slot would leak across
    // interleaved jobs at suspension points), and a slot-only read would
    // leave those bindings invisible under the lean profile. Sync binds
    // always restore on exit, so a non-nil slot is the innermost scope.
    stackLeanResolveProfile ? (leanCurrent ?? taskLocalCurrent) : taskLocalCurrent
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
    _focusedIdentity = nil
    _pressedIdentity = nil
    _isFocused = false
  }

  /// Reads a key without recording a dependency on the evaluating node.
  ///
  /// For framework-infrastructure reads only (the ambient text-attribute
  /// stamping in `Text`/`Link` resolve). Correctness does not need the
  /// attribution: a changed environment value already re-resolves the
  /// writer's whole subtree through snapshot inequality (`ViewNode.canReuse`).
  /// Recording these reads would instead stamp framework noise into every
  /// text-bearing node's dependency fingerprint.
  ///
  /// The reader-scoped reuse toleration — the first consumer of reader-precise
  /// environment attribution — stays sound over these unattributed reads
  /// because it tolerates only keys declared outside this framework plus the
  /// individually certified framework keys
  /// (`EnvironmentKeyReuseClassification`), and every key read here is
  /// framework-declared and uncertified. Any new untracked read of a key
  /// declared outside these modules — or of a certified key — would break
  /// that argument: use the tracked subscript.
  package subscript<K: EnvironmentKey>(untracked key: K.Type) -> K.Value {
    guard let boxed = storage[ObjectIdentifier(key)] else {
      return K.defaultValue
    }
    guard let typed: K.Value = boxed.value(as: K.Value.self) else {
      preconditionFailure(
        "Environment type mismatch for \(String(reflecting: key)). Expected \(K.Value.self), found \(boxed.valueTypeDescription)."
      )
    }
    return typed
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
      // Write attribution for the reader-scoped reuse toleration. This
      // subscript is the *complete* funnel for user-declared keys — an
      // extension cannot add stored properties, so every authored
      // `.environment` / `.transformEnvironment` write lands here — and the
      // toleration needs completeness in exactly this direction: recording a
      // write that is not an authored subtree write only causes extra
      // denials, while missing one would let a subtree be served under a key
      // its own interior writer controls. Uncertified framework-declared keys
      // are skipped: they never enter the toleration (see
      // `EnvironmentKeyReuseClassification`), so recording them would be pure
      // cost on the hottest write path in the resolver (`\.stackAxis`, written
      // by every stack, every frame). Certified framework keys record like
      // user keys — the toleration's interior-writer denial needs them
      // indexed.
      // Classify BEFORE the isolation hop: the classification needs the key
      // metatype, and metatypes are not `Sendable`, so capturing one in the
      // main-actor closure is a `sending` violation. Only the
      // `ObjectIdentifier` crosses — the same shape the getter above uses.
      if EnvironmentKeyReuseClassification.isReaderAttributedOnly(key) {
        MainActor.assumeIsolated {
          ViewNodeContext.current?.recordEnvironmentWrite(identifier)
        }
      }
      storage[identifier] = EnvironmentValueBox(key: key, base: newValue)
    }
  }

  /// Returns a copy with the reader-scoped environment drift folded in.
  ///
  /// This is the re-entry half of the toleration: an evaluator closure
  /// captured inside a subtree that was served over a changed-but-unread key
  /// still holds that key's prior value, and a body that *newly* reads the key
  /// on re-run must see the current one. The write goes in unattributed on
  /// purpose — it is a repair of an ancestor's authored write, not a write by
  /// the re-entering node, and recording it would index the re-entering node
  /// as a writer of a key it never authored.
  package func applyingEnvironmentDrift(
    _ drift: [ObjectIdentifier: EnvironmentSnapshotValue]
  ) -> Self {
    var copy = self
    for (identifier, value) in drift {
      copy.storage[identifier] = EnvironmentValueBox(
        keyType: value.environmentKeyType,
        reuseValue: value.reuseValue
      )
    }
    return copy
  }

  // Widened from `fileprivate` to `package` so `ResolveContext` (moved to
  // `ResolveContext.swift`) can fold environment edits back into a snapshot.
  package func applying(
    to snapshot: EnvironmentSnapshot,
    reuseStyle: Bool = false
  ) -> EnvironmentSnapshot {
    var mergedTypedValues = snapshot.typedValues
    for (identifier, box) in storage {
      mergedTypedValues[identifier] = EnvironmentSnapshotValue(
        keyType: box.keyType,
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
      untypedValues: snapshot.untypedValues,
      typedValues: mergedTypedValues,
      style: style
    )
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    // Change detection compares the boxed typed values. The reflected `values`
    // projection is derived on demand and is deliberately not equality currency.
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

extension Environment: DynamicProperty {}

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
