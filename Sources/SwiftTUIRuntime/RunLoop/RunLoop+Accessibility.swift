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
      let node = latestSemanticSnapshot.accessibilityNodes.first(where: {
        $0.actionTarget == request.target
      }), let identity = node.actionIdentity, let control = node.control
    else {
      return .staleTarget
    }
    guard node.isEnabled else { return .disabled }
    guard !node.hidden,
      focusTracker.focusRegions.contains(where: {
        $0.identity == identity && $0.ownerNodeID == node.viewNodeID
      })
    else { return .outOfScope }
    guard control.actions.contains(request.action.kind) else { return .unsupported }
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
    switch localActionRegistry.dispatchAccessibility(identity: identity, action: request.action) {
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
