package enum FocusParticipation: Equatable, Sendable {
  case automatic
  case included
  case excluded
}

package enum AutomaticFocusPolicy {
  private static let focusableAccessibilityRoles: Set<AccessibilityRole> = [
    .button,
    .disclosureGroup,
    .link,
    .list,
    .menu,
    .picker,
    .secureField,
    .slider,
    .stepper,
    .table,
    .tabView,
    .textEditor,
    .textField,
    .toggle,
  ]

  // Focus participation is role-driven only (F99). The original
  // string-literal view-NAME fallback ("Button", "TextField", ...) was
  // measured dead across a fully green repo gate on 2026-07-09 — every
  // focusable control resolves with an `accessibilityRole` — and was
  // deleted rather than kept as a silent rename hazard. A control absent
  // from `focusableAccessibilityRoles` opts in through its role (or an
  // explicit `.focusable(true)`); `FocusParticipationPolicyTests` pins the
  // per-role classification with a source-parsed totality lock.
  static func includesTopLevelFocus(
    kind: NodeKind,
    metadata: SemanticMetadata
  ) -> Bool {
    guard let accessibilityRole = metadata.accessibilityRole else {
      return false
    }
    return focusableAccessibilityRoles.contains(accessibilityRole)
  }
}

extension SemanticMetadata {
  package func participatesInTopLevelFocus(
    kind: NodeKind
  ) -> Bool {
    switch focusParticipation {
    case .included:
      return true
    case .excluded:
      return false
    case .automatic:
      return AutomaticFocusPolicy.includesTopLevelFocus(
        kind: kind,
        metadata: self
      )
    }
  }
}

extension ResolvedNode {
  package var participatesInTopLevelFocus: Bool {
    semanticMetadata.participatesInTopLevelFocus(kind: kind)
  }
}
