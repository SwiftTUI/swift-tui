public import SwiftTUICore

private enum FocusedValuesKey: EnvironmentKey {
  static let defaultValue = FocusedValues()
}

/// Synthetic dependency token for `@FocusedValue`/`@FocusedBinding` reads.
///
/// Decoupled from the value-carrying ``FocusedValuesKey`` for the same reason
/// `FocusedIdentityKey` is decoupled from `_focusedIdentity`: this key is never
/// written into the environment and never read by framework plumbing, so the
/// reverse dependency index for it contains *only* genuine focused-value readers.
/// (Recording against `FocusedValuesKey` instead would attribute every node,
/// because `ResolveContext.init` reads `environmentValues.focusedValues` per node.)
private enum FocusedValuesDependencyKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  package var focusedValues: FocusedValues {
    get { self[FocusedValuesKey.self] }
    set { self[FocusedValuesKey.self] = newValue }
  }

  /// The environment dependency key a `@FocusedValue`/`@FocusedBinding` reader
  /// records so a pure focused-value change can invalidate exactly those readers
  /// (precise, reuse-safe one-frame-lag propagation) instead of the whole tree.
  /// The run loop resolves readers through this key in
  /// `RunLoop.processFocusSyncIteration`'s single-pass branch.
  package static var focusedValuesDependencyKeys: Set<ObjectIdentifier> {
    [ObjectIdentifier(FocusedValuesDependencyKey.self)]
  }

  /// Attributes a focused-value read to the evaluating reader node.
  ///
  /// `@FocusedValue`/`@FocusedBinding` read the cached `AuthoringContext.focusedValues`
  /// field rather than going through the `EnvironmentValues` subscript, so the read
  /// is otherwise invisible to reader attribution. Recording the synthetic
  /// ``FocusedValuesDependencyKey`` here — mirroring the `recordEnvironmentRead`
  /// the real subscript performs — lets a focused-value change find and invalidate
  /// precisely the readers. The dependency index persists across reuse, so a reader
  /// reused since its last resolve stays discoverable (never left stale).
  @MainActor
  package static func recordFocusedValuesDependencyRead() {
    ViewNodeContext.current?.recordEnvironmentRead(
      ObjectIdentifier(FocusedValuesDependencyKey.self))
  }
}

@propertyWrapper
@MainActor
/// Reads a value exported by the currently focused subtree.
public struct FocusedValue<Value: Sendable> {
  private let keyPath: KeyPath<FocusedValues, Value?>

  /// Creates a focused-value reader for `keyPath`.
  public init(
    _ keyPath: KeyPath<FocusedValues, Value?>
  ) {
    self.keyPath = keyPath
  }

  public var wrappedValue: Value? {
    EnvironmentValues.recordFocusedValuesDependencyRead()
    return currentAuthoringContext()?.focusedValues[keyPath: keyPath]
  }
}

@propertyWrapper
@MainActor
/// Reads and writes a binding exported by the currently focused subtree.
public struct FocusedBinding<Value: Sendable> {
  private let keyPath: KeyPath<FocusedValues, Binding<Value>?>

  /// Creates a focused-binding reader for `keyPath`.
  public init(
    _ keyPath: KeyPath<FocusedValues, Binding<Value>?>
  ) {
    self.keyPath = keyPath
  }

  private var currentBinding: Binding<Value>? {
    EnvironmentValues.recordFocusedValuesDependencyRead()
    return currentAuthoringContext()?.focusedValues[keyPath: keyPath]
  }

  public var wrappedValue: Value? {
    get { currentBinding?.wrappedValue }
    nonmutating set {
      guard let newValue, let binding = currentBinding else {
        return
      }
      binding.wrappedValue = newValue
    }
  }

  public var projectedValue: Binding<Value>? {
    currentBinding
  }
}

extension View {
  public func focusedValue<Value: Sendable>(
    _ keyPath: WritableKeyPath<FocusedValues, Value?>,
    _ value: Value
  ) -> some View {
    modifier(
      FocusedValueWritingModifier(
        keyPath: keyPath,
        value: value
      )
    )
  }

  public func focusedValue<Value: Sendable>(
    _ keyPath: WritableKeyPath<FocusedValues, Value?>,
    _ value: Value?
  ) -> some View {
    modifier(
      FocusedValueWritingModifier(
        keyPath: keyPath,
        value: value
      )
    )
  }

  public func focusedSceneValue<Value: Sendable>(
    _ keyPath: WritableKeyPath<FocusedValues, Value?>,
    _ value: Value
  ) -> some View {
    focusedValue(keyPath, value)
  }

  public func focusedSceneValue<Value: Sendable>(
    _ keyPath: WritableKeyPath<FocusedValues, Value?>,
    _ value: Value?
  ) -> some View {
    focusedValue(keyPath, value)
  }
}

/// A focused-value `Binding` converges the focus-sync loop by its current value.
///
/// `Binding` has no stable identity across renders — `$state` yields a fresh
/// value of `@MainActor` closures on every body evaluation — so the focus-sync
/// comparison cannot use identity. When the bound `Value` is `Equatable`, the
/// bound value is the reliable signal: a focused field that keeps publishing a
/// binding to unchanged state compares equal and the loop converges, while a
/// real edit compares unequal and triggers exactly one propagation pass.
extension Binding: MainActorFocusedValueEquatable where Value: Equatable {
  @MainActor
  package func isFocusedValueEqual(to other: Any) -> Bool {
    guard let other = other as? Binding<Value> else {
      return false
    }
    return wrappedValue == other.wrappedValue
  }
}

public struct FocusedValueWritingModifier<Value: Sendable>: PrimitiveViewModifier {
  var keyPath: WritableKeyPath<FocusedValues, Value?>
  var value: Value?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let node = content.resolve(in: context)

    if let value {
      var focusedValues = FocusedValues()
      focusedValues[keyPath: keyPath] = value
      context.localFocusedValuesRegistry?.register(
        identity: node.identity,
        descendantIdentities: Set(node.collectIdentities()),
        values: focusedValues
      )
    }

    return [node]
  }
}
