import SwiftTUICore

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
