/// A focus storage owner, independent of the controls currently binding it.
/// Requests are one-frame commands; an unclaimed value is not a clear command
/// and must not stay parked until a target happens to mount later.
package struct FocusBindingSourceRegistration: Sendable {
  package var identity: Identity
  package var ownerIdentity: Identity? = nil
  package var bindingKey: FocusBindingKey
  package var domain: FocusBindingDomain
  package var requestGeneration: UInt64
  package var hasPendingRequest: Bool
  package var requestsClear: Bool
  package var isCurrentRequest: @MainActor @Sendable () -> Bool
  package var clearRuntimeValue: @MainActor @Sendable () -> Bool

  package init(
    identity: Identity, bindingKey: FocusBindingKey, domain: FocusBindingDomain,
    requestGeneration: UInt64, hasPendingRequest: Bool, requestsClear: Bool,
    isCurrentRequest: @escaping @MainActor @Sendable () -> Bool,
    clearRuntimeValue: @escaping @MainActor @Sendable () -> Bool
  ) {
    self.identity = identity
    self.bindingKey = bindingKey
    self.domain = domain
    self.requestGeneration = requestGeneration
    self.hasPendingRequest = hasPendingRequest
    self.requestsClear = requestsClear
    self.isCurrentRequest = isCurrentRequest
    self.clearRuntimeValue = clearRuntimeValue
  }
}
