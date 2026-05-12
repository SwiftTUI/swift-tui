import CoreGraphics
import SwiftTUIRuntime
import SwiftUI

struct AccessibilityNodeMapping: Equatable {
  enum Trait: Hashable {
    case button
    case header
    case image
    case link
  }

  enum ControlKind: Equatable {
    case action
    case adjustable
    case group
    case image
    case link
    case staticText
    case textInput
  }

  let id: String
  let identity: Identity
  let parentIdentity: Identity?
  let frame: CGRect
  let role: AccessibilityRole
  let roleDescription: String
  let label: String?
  let hint: String?
  let traits: Set<Trait>
  let controlKind: ControlKind
  let isFocused: Bool
  let liveRegion: AccessibilityPoliteness?

  var swiftUITraits: SwiftUI.AccessibilityTraits {
    var traits: SwiftUI.AccessibilityTraits = []
    if self.traits.contains(.button) {
      _ = traits.insert(.isButton)
    }
    if self.traits.contains(.header) {
      _ = traits.insert(.isHeader)
    }
    if self.traits.contains(.image) {
      _ = traits.insert(.isImage)
    }
    if self.traits.contains(.link) {
      _ = traits.insert(.isLink)
    }
    return traits
  }
}

enum AccessibilityNodeMapper {
  static func mappings(
    for snapshot: SemanticSnapshot?,
    focusedIdentity: Identity?,
    cellSize: CGSize
  ) -> [AccessibilityNodeMapping] {
    guard let snapshot else {
      return []
    }

    return snapshot.accessibilityNodes.compactMap { node in
      mapping(
        for: node,
        focusedIdentity: focusedIdentity,
        cellSize: cellSize
      )
    }
  }

  static func mapping(
    for node: AccessibilityNode,
    focusedIdentity: Identity?,
    cellSize: CGSize
  ) -> AccessibilityNodeMapping? {
    guard let frame = frame(for: node.rect, cellSize: cellSize) else {
      return nil
    }

    let roleMapping = roleMapping(for: node.role)
    return AccessibilityNodeMapping(
      id: node.identity.path,
      identity: node.identity,
      parentIdentity: node.parentIdentity,
      frame: frame,
      role: node.role,
      roleDescription: roleMapping.description,
      label: node.label,
      hint: node.hint,
      traits: roleMapping.traits,
      controlKind: roleMapping.controlKind,
      isFocused: node.identity == focusedIdentity,
      liveRegion: node.liveRegion
    )
  }

  static func frame(
    for rect: CellRect,
    cellSize: CGSize
  ) -> CGRect? {
    guard
      !rect.isEmpty,
      cellSize.width > 0,
      cellSize.height > 0
    else {
      return nil
    }

    return CGRect(
      x: CGFloat(rect.origin.x) * cellSize.width,
      y: CGFloat(rect.origin.y) * cellSize.height,
      width: CGFloat(rect.size.width) * cellSize.width,
      height: CGFloat(rect.size.height) * cellSize.height
    )
  }

  private static func roleMapping(
    for role: AccessibilityRole
  ) -> (
    description: String,
    traits: Set<AccessibilityNodeMapping.Trait>,
    controlKind: AccessibilityNodeMapping.ControlKind
  ) {
    switch role {
    case .button, .disclosureGroup, .menuItem, .tab:
      (role.description, [.button], .action)
    case .checkbox, .toggle:
      (role.description, [.button], .action)
    case .link:
      (role.description, [.link], .link)
    case .heading, .columnHeader, .rowHeader:
      (role.description, [.header], .staticText)
    case .image:
      (role.description, [.image], .image)
    case .textField, .secureField, .textEditor:
      (role.description, [], .textInput)
    case .slider, .stepper, .progressBar:
      (role.description, [], .adjustable)
    case .alert, .status, .timer:
      (role.description, [], .staticText)
    case .cell, .confirmationDialog, .custom, .group, .list, .menu, .picker, .region,
      .scrollView, .scrollViewWithIndicators, .section, .separator, .sheet, .table,
      .tableRow, .tabPanel, .tabView:
      (role.description, [], .group)
    }
  }
}
