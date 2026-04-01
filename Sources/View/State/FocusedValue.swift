public import Core

private enum FocusedValuesKey: EnvironmentKey {
  static let defaultValue = FocusedValues()
}

extension EnvironmentValues {
  package var focusedValues: FocusedValues {
    get { self[FocusedValuesKey.self] }
    set { self[FocusedValuesKey.self] = newValue }
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
    currentDynamicPropertyScope()?.focusedValues[keyPath: keyPath]
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
    currentDynamicPropertyScope()?.focusedValues[keyPath: keyPath]
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
    FocusedValueWritingModifier(
      content: self,
      keyPath: keyPath,
      value: value
    )
  }

  public func focusedValue<Value: Sendable>(
    _ keyPath: WritableKeyPath<FocusedValues, Value?>,
    _ value: Value?
  ) -> some View {
    FocusedValueWritingModifier(
      content: self,
      keyPath: keyPath,
      value: value
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

private struct FocusedValueWritingModifier<Content: View, Value: Sendable>: View,
  ResolvableView
{
  var content: Content
  var keyPath: WritableKeyPath<FocusedValues, Value?>
  var value: Value?

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
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
