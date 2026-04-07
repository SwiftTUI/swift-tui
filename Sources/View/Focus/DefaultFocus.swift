import Core

extension View {
  public func defaultFocus(
    _ binding: FocusState<Bool>.Binding,
    _ value: Bool = true
  ) -> some View {
    BoolDefaultFocusModifier(
      content: self,
      binding: binding,
      value: value
    )
  }

  public func defaultFocus<Value: Hashable>(
    _ binding: FocusState<Value?>.Binding,
    _ value: Value
  ) -> some View {
    OptionalDefaultFocusModifier(
      content: self,
      binding: binding,
      value: value
    )
  }
}

private struct BoolDefaultFocusModifier<Content: View>: View, ResolvableView {
  var content: Content
  var binding: FocusState<Bool>.Binding
  var value: Bool

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
    guard context.environmentValues.focusedIdentity == nil else {
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
    guard
      let authoringContext = currentAuthoringContext(),
      let ordinal = authoringContext.ordinalTracker.claimOrdinal(),
      let viewNode = authoringContext.viewNode
    else {
      return true
    }

    let hasSeeded: Bool = viewNode.stateSlot(
      ordinal: ordinal,
      seed: false
    )
    guard !hasSeeded else {
      return false
    }
    viewNode.setStateSlot(ordinal: ordinal, value: true)
    return true
  }
}

private struct OptionalDefaultFocusModifier<Content: View, Value: Hashable>: View,
  ResolvableView
{
  var content: Content
  var binding: FocusState<Value?>.Binding
  var value: Value

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    applyDefaultFocus(in: context)
    return content.resolveElements(in: context)
  }

  private func applyDefaultFocus(
    in context: ResolveContext
  ) {
    guard context.environmentValues.focusedIdentity == nil else {
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
    guard
      let authoringContext = currentAuthoringContext(),
      let ordinal = authoringContext.ordinalTracker.claimOrdinal(),
      let viewNode = authoringContext.viewNode
    else {
      return true
    }

    let hasSeeded: Bool = viewNode.stateSlot(
      ordinal: ordinal,
      seed: false
    )
    guard !hasSeeded else {
      return false
    }
    viewNode.setStateSlot(ordinal: ordinal, value: true)
    return true
  }
}
