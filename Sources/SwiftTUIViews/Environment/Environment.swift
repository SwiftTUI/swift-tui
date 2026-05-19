import Observation
public import SwiftTUICore
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

  /// Creates an empty environment container.
  public init() {
    storage = [:]
    snapshotValues = [:]
    _focusedIdentity = nil
    _pressedIdentity = nil
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
    lhs.snapshotValues == rhs.snapshotValues
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
  private let keyPath: KeyPath<EnvironmentValues, Value>

  /// Creates an environment-value reader for `keyPath`.
  public init(
    _ keyPath: KeyPath<EnvironmentValues, Value>
  ) {
    self.keyPath = keyPath
  }

  public var wrappedValue: Value {
    (EnvironmentValuesStorage.current ?? EnvironmentValues())[keyPath: keyPath]
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
        content(context.environmentValues[keyPath: keyPath])
      }
    }
    return view.resolveElements(in: context)
  }
}
