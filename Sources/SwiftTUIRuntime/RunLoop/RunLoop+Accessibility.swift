import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
  /// Resolve against the committed semantic tree and its active focus scope.
  /// Authored identities alone are insufficient: a removed/recreated control
  /// must not receive an operation queued for its predecessor.
  @discardableResult
  package func handleAccessibilityAction(
    _ request: AccessibilityActionRequest
  ) -> AccessibilityActionResult {
    guard
      let node = publishedAccessibilitySnapshot.accessibilityNodes.first(where: {
        $0.actionTarget == request.target
      }), let control = node.control
    else {
      return .staleTarget
    }
    if request.action == .accessibilityFocus || request.action == .accessibilityBlur {
      guard control.actions.contains(request.action.kind) else { return .unsupported }
      guard accessibilityFocusCoordinator.accepts(node, in: publishedAccessibilitySnapshot) else {
        return .outOfScope
      }
      if accessibilityFocusCoordinator.receive(node, focused: request.action == .accessibilityFocus)
      {
        scheduler.requestInput()
      }
      return .accepted
    }
    guard node.isEnabled else { return .disabled }
    let combined: AccessibilityCombinedAction?
    if case .custom(let name) = request.action {
      combined = node.combinedActions[name]
    } else {
      combined = nil
    }
    guard let identity = combined?.identity ?? node.actionIdentity else { return .unsupported }
    let owner = combined?.owner ?? node.viewNodeID
    if let combined, !combined.enabled { return .disabled }
    if combined?.readOnly == true { return .unsupported }
    let actionRegions =
      focusTracker.focusRegions + publishedAccessibilitySnapshot.accessibilityActionRegions
    guard !node.hidden,
      actionRegions.contains(where: {
        $0.identity == identity && $0.ownerNodeID == owner
      })
    else { return .outOfScope }
    guard control.actions.contains(request.action.kind) else { return .unsupported }
    if case .custom(let name) = request.action,
      !control.customActions.contains(name)
    {
      return .unsupported
    }
    // Read-only controls remain focusable, but cannot be mutated by a host.
    guard node.properties?.readOnly != true || request.action == .focus else {
      return .unsupported
    }
    if case .setValue(let value) = request.action {
      switch (control.value, value, node.role) {
      case (.boolean, .boolean, _), (.text, .text, _), (nil, .text, .secureField):
        break
      case (.number, .number(let number), _):
        guard number.isFinite,
          control.minimum.map({ number >= $0 }) ?? true,
          control.maximum.map({ number <= $0 }) ?? true
        else { return .invalidValue }
      default: return .invalidValue
      }
    }
    if request.action == .focus {
      pendingKeyFocus = nil
      pendingFocusTraversal = nil
      pendingClickFocusRestore = nil
      if focusTracker.setFocus(to: identity) { scheduler.requestInput() }
      return .accepted
    }
    guard localActionRegistry.hasHandler(identity: identity) else { return .unsupported }
    let before = schedulerInvalidationRequestGeneration()
    switch localActionRegistry.dispatchAccessibility(
      identity: identity, action: combined?.action ?? request.action)
    {
    case .changed:
      scheduler.requestInput()
      recordFollowUpInvalidation(
        for: identity, schedulerInvalidationGenerationBeforeDispatch: before)
      return .accepted
    case .unchanged: return .accepted
    case .invalidValue: return .invalidValue
    case .unsupported: return .unsupported
    }
  }
}

/// A graph owner can survive while its root control disappears. Scope issued
/// action targets to continuous committed semantic presence, not just that
/// owner's lifetime. Candidate/focus-convergence frames never advance this map.
package struct AccessibilityTargetLifetimes {
  private struct Key: Hashable {
    var target: String
    var role: AccessibilityRole?
  }
  private var active: [Key: UInt64] = [:]
  private var next: UInt64 = 0

  package mutating func stamp(_ snapshot: inout SemanticSnapshot) {
    var present: [Key: UInt64] = [:]
    for index in snapshot.accessibilityNodes.indices {
      guard let raw = snapshot.accessibilityNodes[index].actionTarget else { continue }
      let key = Key(target: raw, role: snapshot.accessibilityNodes[index].role)
      let lifetime: UInt64
      if let existing = active[key] ?? present[key] {
        lifetime = existing
      } else {
        precondition(next < UInt64.max, "Accessibility action lifetime exhausted")
        next += 1
        lifetime = next
      }
      present[key] = lifetime
      snapshot.accessibilityNodes[index].actionTarget = "\(raw)#\(lifetime)"
    }
    active = present
  }
}
