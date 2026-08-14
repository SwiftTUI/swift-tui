// Built-ins derive their invalidation from graph dependencies and never retain
// `DynamicPropertyContext.invalidationLease`. Marking that package-owned fact
// keeps their hot update path allocation- and registration-free; custom
// properties still receive a fully scoped lease by default.
extension Binding: DynamicPropertyLeaseIndependent {}
extension Bindable: DynamicPropertyLeaseIndependent {}
extension Environment: DynamicPropertyLeaseIndependent {}
extension FocusState: DynamicPropertyLeaseIndependent {}
extension FocusedBinding: DynamicPropertyLeaseIndependent {}
extension FocusedValue: DynamicPropertyLeaseIndependent {}
extension GestureState: DynamicPropertyLeaseIndependent {}
extension Namespace: DynamicPropertyLeaseIndependent {}
extension State: DynamicPropertyLeaseIndependent {}

// These wrappers' authored values are graph-slot seeds/handles only. Their
// visible values participate in the dependency gate, so memo comparison may
// omit the synthesized `_` storage. Other built-ins carry authored closures,
// model references, or key paths and must remain in value comparison.
extension FocusState: DynamicPropertyMemoStorageOnly {}
extension GestureState: DynamicPropertyMemoStorageOnly {}
extension Namespace: DynamicPropertyMemoStorageOnly {}
extension State: DynamicPropertyMemoStorageOnly {}
