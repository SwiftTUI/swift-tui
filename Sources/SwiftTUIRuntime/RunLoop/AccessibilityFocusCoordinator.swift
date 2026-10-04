import SwiftTUICore

/// Keeps semantic review separate from keyboard focus and arbitrates authored
/// requests against the current committed semantic scope.
@MainActor
package final class AccessibilityFocusCoordinator {
  private struct Target: Equatable {
    var identity: Identity
    var owner: ViewNodeID?
    init(_ node: AccessibilityNode) {
      identity = node.actionIdentity ?? node.identity
      owner = node.viewNodeID
    }
  }
  private var focused: Target?
  private var requestGeneration: UInt64 = 0
  private var consumedRequests: [FocusBindingKey: UInt64] = [:]
  private var previousBindings: [FocusBindingRegistrationSnapshot] = []

  package func accepts(_ node: AccessibilityNode, in snapshot: SemanticSnapshot) -> Bool {
    allowedNodes(in: snapshot).contains { Target($0) == Target(node) }
  }

  @discardableResult
  package func receive(_ node: AccessibilityNode, focused newValue: Bool) -> Bool {
    let target = Target(node)
    if !newValue && focused != target { return false }
    let next = newValue ? target : nil
    guard focused != next else { return false }
    focused = next
    return true
  }

  package func synchronize(snapshot: SemanticSnapshot, registry: LocalFocusBindingRegistry) -> Bool
  {
    let before = focused
    let allowed = allowedNodes(in: snapshot)
    if let focused, !allowed.contains(where: { Target($0) == focused }) { self.focused = nil }
    let bindings = registry.snapshot().filter { $0.domain == .accessibility }
    let liveKeys = Set(bindings.map(\.bindingKey))
    consumedRequests = consumedRequests.filter { liveKeys.contains($0.key) }
    var changed = false
    // Retiring a target clears its still-live binding owner. Generation checks
    // in the binding protect a newer authored request and replacement owners.
    for previous in previousBindings
    where !bindings.contains(where: {
      $0.bindingKey == previous.bindingKey && $0.identity == previous.identity
    }) {
      changed = previous.applyRuntimeFocus(false) || changed
    }
    previousBindings = bindings
    var appliedRequest = false
    for binding in bindings
    where binding.hasPendingRequest
      && consumedRequests[binding.bindingKey] != binding.requestGeneration
    {
      consumedRequests[binding.bindingKey] = binding.requestGeneration
      guard !appliedRequest else { continue }
      let group = bindings.filter { $0.bindingKey == binding.bindingKey }
      if let selected = group.first(where: \.isSelected) {
        guard
          let node = allowed.first(where: {
            ($0.actionIdentity ?? $0.identity) == selected.identity
          })
        else { continue }
        focused = Target(node)
      } else {
        focused = nil
      }
      precondition(
        requestGeneration < UInt64.max, "Accessibility focus request generation exhausted")
      requestGeneration += 1
      appliedRequest = true
    }
    changed =
      registry.sync(actualFocusedIdentity: focused?.identity, domain: .accessibility) || changed
    return changed || appliedRequest || before != focused
  }

  package func present(in snapshot: inout SemanticSnapshot) {
    for index in snapshot.accessibilityNodes.indices {
      snapshot.accessibilityNodes[index].isAccessibilityFocused =
        Target(snapshot.accessibilityNodes[index]) == focused
    }
    if requestGeneration > 0 {
      snapshot.accessibilityFocusRequest = .init(
        generation: requestGeneration,
        target: snapshot.accessibilityNodes.first(where: \.isAccessibilityFocused)?.actionTarget)
    }
  }

  private func allowedNodes(in snapshot: SemanticSnapshot) -> [AccessibilityNode] {
    let regions = snapshot.focusRegions + snapshot.accessibilityActionRegions
    let activeModal = regions.compactMap(\.modalFocusScopePath).max { $0.count < $1.count }
    return snapshot.accessibilityNodes.filter { node in
      !node.hidden && node.control?.actions.contains(.accessibilityFocus) == true
        && regions.contains { region in
          region.identity == (node.actionIdentity ?? node.identity)
            && region.ownerNodeID == node.viewNodeID
            && (activeModal == nil || region.modalFocusScopePath == activeModal)
        }
    }
  }
}
