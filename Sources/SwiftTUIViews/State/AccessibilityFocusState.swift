public import SwiftTUICore

/// An assistive focus binding independent of the application's keyboard focus.
/// Browser presenters report native semantic focus, not an unobservable screen
/// reader's virtual review cursor. Programmatic requests target the committed,
/// visible semantic element and never change terminal keyboard focus.
@propertyWrapper
@MainActor
public struct AccessibilityFocusState<Value: Hashable>: DynamicProperty {
  private var storage: FocusState<Value>

  public init(line: UInt = #line, column: UInt = #column) where Value == Bool {
    storage = FocusState(line: line, column: column)
  }

  public init<Wrapped: Hashable>(line: UInt = #line, column: UInt = #column)
  where Value == Wrapped? {
    storage = FocusState(line: line, column: column)
  }

  public var wrappedValue: Value {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var projectedValue: Binding { Binding(base: storage.projectedValue) }

  /// The underlying focus storage participates in the nested dynamic-property
  /// pass, including qualified state slots and hot-reload declarations.
  public func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    .unchanged
  }

  public struct Binding {
    fileprivate let base: FocusState<Value>.Binding
    @MainActor
    public var wrappedValue: Value {
      get { base.wrappedValue }
      nonmutating set { base.wrappedValue = newValue }
    }
    public var projectedValue: Self { self }
  }
}

extension AccessibilityFocusState: DynamicPropertyLeaseIndependent {}
extension AccessibilityFocusState: DynamicPropertyMemoStorageOnly {}

extension View {
  /// Binds assistive semantic focus without making static content a keyboard stop.
  public func accessibilityFocused(_ binding: AccessibilityFocusState<Bool>.Binding) -> some View {
    modifier(
      AccessibilityFocusBindingModifier(binding: binding, selectedValue: true, clearValue: false))
  }

  public func accessibilityFocused<Value: Hashable>(
    _ binding: AccessibilityFocusState<Value?>.Binding, equals value: Value
  ) -> some View {
    modifier(
      AccessibilityFocusBindingModifier(binding: binding, selectedValue: value, clearValue: nil))
  }
}

private struct AccessibilityFocusBindingModifier<Value: Hashable>: IterativePrimitiveViewModifier {
  let binding: AccessibilityFocusState<Value>.Binding
  let selectedValue: Value
  let clearValue: Value

  func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>, in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    content.resolveWork(in: context).map { completed in
      var node = completed
      let base = binding.base
      let generation = base.requestGeneration
      let identity = node.identity
      context.localFocusBindingRegistry?.register(
        identity: identity, bindingKey: base.bindingKey, bindingID: base.bindingID,
        hasPendingRequest: base.hasPendingRequest,
        isSelected: base.registrationValue == selectedValue,
        domain: .accessibility, requestGeneration: generation,
        applyRuntimeFocus: { focused in
          if !focused && base.registrationValue != selectedValue { return false }
          return base.applyRuntimeValue(
            focused ? selectedValue : clearValue,
            observedRequestGeneration: generation, registrationIdentity: identity)
        })
      installAccessibilityFocusActions(on: &node)
      return [node]
    }
  }
}

package func installAccessibilityFocusActions(on node: inout ResolvedNode) {
  let previous = node.semanticMetadata.accessibilityControl
  var actions = previous?.actions ?? []
  for kind in [AccessibilityActionKind.accessibilityFocus, .accessibilityBlur]
  where !actions.contains(kind) { actions.append(kind) }
  node.semanticMetadata.accessibilityControl = .init(
    actions: actions, value: previous?.value, minimum: previous?.minimum,
    maximum: previous?.maximum, step: previous?.step, selection: previous?.selection,
    customActions: previous?.customActions ?? [], opensLink: previous?.opensLink ?? false)
}
