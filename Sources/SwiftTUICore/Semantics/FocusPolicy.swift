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

  static func includesTopLevelFocus(
    kind: NodeKind,
    metadata: SemanticMetadata
  ) -> Bool {
    if let accessibilityRole = metadata.accessibilityRole {
      return focusableAccessibilityRoles.contains(accessibilityRole)
    }

    guard case .view(let name) = kind else {
      return false
    }

    switch name {
    case "Button", "DisclosureGroup", "Link", "List", "Picker", "SecureField", "Slider",
      "Stepper", "Table", "TextEditor", "TextField", "Toggle", "Menu":
      return true
    default:
      return false
    }
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

extension PlacedNode {
  package var participatesInTopLevelFocus: Bool {
    semanticMetadata.participatesInTopLevelFocus(kind: kind)
  }
}
