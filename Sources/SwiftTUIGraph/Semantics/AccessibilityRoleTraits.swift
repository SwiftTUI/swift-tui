/// Role traits compose independently of the widget's action capabilities.
package enum AccessibilityRoleTrait: Int, CaseIterable, Sendable {
  case button, link, image, header, staticText

  package init?(_ role: AccessibilityRole?) {
    switch role {
    case .button: self = .button
    case .link: self = .link
    case .image: self = .image
    case .heading: self = .header
    case .group: self = .staticText
    default: return nil
    }
  }

  package var role: AccessibilityRole {
    switch self {
    case .button: .button
    case .link: .link
    case .image: .image
    case .header: .heading(level: 1)
    case .staticText: .group
    }
  }
}

package struct AccessibilityRoleTraitState: Equatable, Sendable {
  package var baseRole: AccessibilityRole?
  package var traits: Set<AccessibilityRoleTrait> = []
  package init(baseRole: AccessibilityRole?) { self.baseRole = baseRole }

  package mutating func apply(_ trait: AccessibilityRoleTrait, removing: Bool) {
    if removing {
      traits.remove(trait)
      if AccessibilityRoleTrait(baseRole) == trait { baseRole = nil }
    } else {
      traits.insert(trait)
    }
  }

  package var role: AccessibilityRole? {
    guard let strongest = traits.max(by: { $0.rawValue < $1.rawValue }) else { return baseRole }
    if let base = AccessibilityRoleTrait(baseRole), base.rawValue >= strongest.rawValue {
      return baseRole  // Preserve an authored heading's level.
    }
    return strongest.role
  }
}
