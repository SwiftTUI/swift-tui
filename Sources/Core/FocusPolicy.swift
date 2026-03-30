package enum FocusParticipation: Equatable, Sendable {
  case automatic
  case included
  case excluded
}

package enum AutomaticFocusPolicy {
  private static let focusablePresentationRoles: Set<PresentationRole> = [
    .button,
    .disclosureGroup,
    .link,
    .list,
    .menu,
    .picker,
    .slider,
    .stepper,
    .table,
    .tabView,
    .textField,
    .toggle,
  ]

  static func includesTopLevelFocus(
    kind: NodeKind,
    metadata: SemanticMetadata
  ) -> Bool {
    if let presentationRole = metadata.presentationRole {
      return focusablePresentationRoles.contains(presentationRole)
    }

    guard case .view(let name) = kind else {
      return false
    }

    switch name {
    case "Button", "DisclosureGroup", "Link", "List", "Picker", "Slider", "Stepper",
      "Table", "TextField", "Toggle", "Menu":
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
