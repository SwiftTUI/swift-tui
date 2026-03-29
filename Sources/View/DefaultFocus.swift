import Core

extension View {
  public func defaultFocus(
    _ binding: FocusState<Bool>.Binding,
    _ value: Bool = true,
    fileID: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column
  ) -> some View {
    BoolDefaultFocusModifier(
      content: self,
      binding: binding,
      value: value,
      sourceLocation: "\(fileID):\(line):\(column)"
    )
  }

  public func defaultFocus<Value: Hashable>(
    _ binding: FocusState<Value?>.Binding,
    _ value: Value,
    fileID: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column
  ) -> some View {
    OptionalDefaultFocusModifier(
      content: self,
      binding: binding,
      value: value,
      sourceLocation: "\(fileID):\(line):\(column)"
    )
  }
}

private struct BoolDefaultFocusModifier<Content: View>: View, ResolvableView {
  var content: Content
  var binding: FocusState<Bool>.Binding
  var value: Bool
  var sourceLocation: String

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    applyDefaultFocus(in: context)
    return content.resolveElements(in: context)
  }

  private func applyDefaultFocus(
    in context: ResolveContext
  ) {
    guard value else {
      return
    }
    guard context.environmentValues.parallelFocusedIdentity == nil else {
      return
    }
    guard consumeDefaultFocusSeed(in: context), !binding.wrappedValue else {
      return
    }
    binding.wrappedValue = true
  }

  private func consumeDefaultFocusSeed(
    in context: ResolveContext
  ) -> Bool {
    guard let stateStore = context.dynamicStateStore else {
      return true
    }

    let key = "\(context.identity.path)#DefaultFocus[\(sourceLocation)]"
    let hasSeeded: Bool = stateStore.value(for: key, seedValue: false)
    guard !hasSeeded else {
      return false
    }
    stateStore.set(true, for: key, invalidationIdentity: context.identity)
    return true
  }
}

private struct OptionalDefaultFocusModifier<Content: View, Value: Hashable>: View,
  ResolvableView
{
  var content: Content
  var binding: FocusState<Value?>.Binding
  var value: Value
  var sourceLocation: String

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    applyDefaultFocus(in: context)
    return content.resolveElements(in: context)
  }

  private func applyDefaultFocus(
    in context: ResolveContext
  ) {
    guard context.environmentValues.parallelFocusedIdentity == nil else {
      return
    }
    guard consumeDefaultFocusSeed(in: context), binding.wrappedValue == nil else {
      return
    }
    binding.wrappedValue = value
  }

  private func consumeDefaultFocusSeed(
    in context: ResolveContext
  ) -> Bool {
    guard let stateStore = context.dynamicStateStore else {
      return true
    }

    let key = "\(context.identity.path)#DefaultFocus[\(sourceLocation)]"
    let hasSeeded: Bool = stateStore.value(for: key, seedValue: false)
    guard !hasSeeded else {
      return false
    }
    stateStore.set(true, for: key, invalidationIdentity: context.identity)
    return true
  }
}
