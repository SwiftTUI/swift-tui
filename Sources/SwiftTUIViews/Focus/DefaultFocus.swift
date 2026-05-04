package import SwiftTUICore

extension View {
  public func defaultFocus(
    _ binding: FocusState<Bool>.Binding,
    _ value: Bool = true
  ) -> some View {
    modifier(
      BoolDefaultFocusModifier(
        binding: binding,
        value: value
      )
    )
  }

  public func defaultFocus<Value: Hashable>(
    _ binding: FocusState<Value?>.Binding,
    _ value: Value
  ) -> some View {
    modifier(
      OptionalDefaultFocusModifier(
        binding: binding,
        value: value
      )
    )
  }
}

public struct BoolDefaultFocusModifier: PrimitiveViewModifier {
  var binding: FocusState<Bool>.Binding
  var value: Bool

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
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
      let modifierOrdinal = authoringContext.ordinalTracker.claimOrdinal(),
      let viewNode = authoringContext.viewNode
    else {
      return true
    }
    let ordinal = StateSlotOrdinals.defaultFocus(modifierOrdinal)

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

public struct OptionalDefaultFocusModifier<Value: Hashable>: PrimitiveViewModifier {
  var binding: FocusState<Value?>.Binding
  var value: Value

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
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
      let modifierOrdinal = authoringContext.ordinalTracker.claimOrdinal(),
      let viewNode = authoringContext.viewNode
    else {
      return true
    }
    let ordinal = StateSlotOrdinals.defaultFocus(modifierOrdinal)

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
