import SwiftTUICore

/// Slider and Stepper share keyboard and wheel vocabulary while each supplies
/// its own live bound-value adjustment policy.
@MainActor
func registerValueAdjustmentInput(
  intake: HandlerDescriptorIntake, identity: Identity,
  adjust: @escaping @MainActor @Sendable (Int) -> Bool
) {
  intake.registerKeyPressHandler(identity: identity) { press in
    guard press.modifiers.isEmpty else { return false }
    switch press.key {
    case .arrowLeft: return adjust(-1)
    case .arrowRight: return adjust(1)
    default: return false
    }
  }
  intake.registerPointerHandler(routeID: runtimePrimaryRouteID(for: identity)) { event in
    valueAdjustmentWheelOutcome(event, adjust: adjust)
  }
}

@MainActor
func valueAdjustmentWheelOutcome(
  _ event: LocalPointerEvent, adjust: @MainActor (Int) -> Bool
) -> PointerDispatchOutcome {
  guard case .scrolled(let deltaX, let deltaY) = event.kind,
    let delta = pointerValueDelta(deltaX: deltaX, deltaY: deltaY)
  else { return .ignored }
  return adjust(delta) ? .claimed : .ignored
}

@MainActor
func updateBoundControlValue<Value: AdjustableControlValue>(
  _ binding: Binding<Value>,
  delta: Int,
  step: Value,
  bounds: ClosedRange<Value>?
) -> Bool {
  let next = steppedControlValue(
    from: binding.wrappedValue,
    delta: delta,
    step: step,
    bounds: bounds
  )
  guard next != binding.wrappedValue else {
    return false
  }
  binding.wrappedValue = next
  return true
}

/// Assistive steps go through the same live adjustment policy as the
/// keyboard and wheel, so each control keeps one rule for every input vector.
@MainActor
func accessibilityNumericAction<Value: AdjustableControlValue>(
  _ action: AccessibilityAction, binding: Binding<Value>, bounds: ClosedRange<Value>?,
  adjust: @MainActor (Int) -> Bool
) -> AccessibilityActionOutcome {
  switch action {
  case .activate, .increment:
    return adjust(1) ? .changed : .unchanged
  case .decrement:
    return adjust(-1) ? .changed : .unchanged
  case .setValue(.number(let number)):
    guard let next = Value.accessibilityValue(number) else { return .invalidValue }
    guard next != binding.wrappedValue else { return .unchanged }
    binding.wrappedValue = clampedControlValue(next, to: bounds)
    return .changed
  default: return .unsupported
  }
}
