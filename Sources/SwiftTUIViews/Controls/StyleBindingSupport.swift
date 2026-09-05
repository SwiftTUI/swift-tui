import SwiftTUICore

/// A style can write the primitive's value without replacing its storage or
/// bypassing disabled state. Forward the binding's transaction and source token
/// as well as its closures, like the public Binding projection initializers.
@MainActor
func enabledStyleBinding<Value>(_ binding: Binding<Value>, isEnabled: Bool) -> Binding<Value> {
  var projection = Binding(
    get: { binding.wrappedValue },
    set: { if isEnabled { binding.wrappedValue = $0 } })
  projection.transaction = binding.transaction
  projection.bindingSourceID = binding.bindingSourceID
  return projection
}
