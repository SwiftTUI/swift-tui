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
  let current = binding.wrappedValue
  guard current.controlDoubleValue.isFinite else { return false }
  let next = steppedControlValue(
    from: current,
    delta: delta,
    step: step,
    bounds: bounds
  )
  guard next.controlDoubleValue.isFinite, next != current else {
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
    guard let authored = Value.accessibilityValue(number) else { return .invalidValue }
    guard bounds?.contains(authored) != false else { return .invalidValue }
    // Compare against the published value. An assistive no-op must not
    // normalize an out-of-range model behind the author's back.
    guard authored != clampedControlValue(binding.wrappedValue, to: bounds) else {
      return .unchanged
    }
    binding.wrappedValue = authored
    return .changed
  default: return .unsupported
  }
}
