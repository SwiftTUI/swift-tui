import CoreGraphics
import SwiftTUI
import Testing

@testable import SwiftUIHost

@MainActor
@Test
func node_mapper_covers_every_accessibility_role() throws {
  for (index, role) in accessibilityRoleSamples.enumerated() {
    let node = AccessibilityNode(
      identity: identity("role-\(index)"),
      rect: .init(origin: .init(x: index + 1, y: 1), size: .init(width: 2, height: 1)),
      role: role,
      label: "Role \(index)"
    )

    let mapping = try #require(
      AccessibilityNodeMapper.mapping(
        for: node,
        focusedIdentity: nil,
        cellSize: .init(width: 10, height: 20)
      )
    )

    #expect(mapping.role == role)
    #expect(mapping.roleDescription == role.description)
    #expect(mapping.label == "Role \(index)")
  }
}

@MainActor
@Test
func node_mapper_assigns_expected_native_trait_groups() throws {
  let button = try mapping(for: .button)
  #expect(button.traits == [.button])
  #expect(button.controlKind == .action)

  let link = try mapping(for: .link)
  #expect(link.traits == [.link])
  #expect(link.controlKind == .link)

  let heading = try mapping(for: .heading(level: 2))
  #expect(heading.traits == [.header])
  #expect(heading.controlKind == .staticText)

  let image = try mapping(for: .image)
  #expect(image.traits == [.image])
  #expect(image.controlKind == .image)

  let textField = try mapping(for: .textField)
  #expect(textField.traits.isEmpty)
  #expect(textField.controlKind == .textInput)

  let progressBar = try mapping(for: .progressBar)
  #expect(progressBar.traits.isEmpty)
  #expect(progressBar.controlKind == .adjustable)

  let custom = try mapping(for: .custom("meter"))
  #expect(custom.traits.isEmpty)
  #expect(custom.controlKind == .group)
  #expect(custom.roleDescription == "custom(meter)")
}

@MainActor
@Test
func node_mapper_converts_cell_rects_to_native_frames() throws {
  let node = AccessibilityNode(
    identity: identity("frame"),
    rect: .init(origin: .init(x: 2, y: 3), size: .init(width: 4, height: 2)),
    role: .button
  )

  let mapping = try #require(
    AccessibilityNodeMapper.mapping(
      for: node,
      focusedIdentity: identity("frame"),
      cellSize: .init(width: 9, height: 17)
    )
  )

  #expect(mapping.frame == CGRect(x: 18, y: 51, width: 36, height: 34))
  #expect(mapping.isFocused)
}

@MainActor
@Test
func node_mapper_skips_invalid_accessibility_frames() {
  let emptyRectNode = AccessibilityNode(
    identity: identity("empty"),
    rect: .zero,
    role: .button
  )
  let invalidCellSizeNode = AccessibilityNode(
    identity: identity("invalid-cell"),
    rect: .init(origin: .zero, size: .init(width: 1, height: 1)),
    role: .button
  )

  #expect(
    AccessibilityNodeMapper.mapping(
      for: emptyRectNode,
      focusedIdentity: nil,
      cellSize: .init(width: 10, height: 20)
    ) == nil)
  #expect(
    AccessibilityNodeMapper.mapping(
      for: invalidCellSizeNode,
      focusedIdentity: nil,
      cellSize: .init(width: 0, height: 20)
    ) == nil)
}

private func mapping(
  for role: AccessibilityRole
) throws -> AccessibilityNodeMapping {
  try #require(
    AccessibilityNodeMapper.mapping(
      for: AccessibilityNode(
        identity: identity(role.description),
        rect: .init(origin: .zero, size: .init(width: 1, height: 1)),
        role: role
      ),
      focusedIdentity: nil,
      cellSize: .init(width: 8, height: 16)
    )
  )
}

private let accessibilityRoleSamples: [AccessibilityRole] = [
  .alert,
  .button,
  .cell,
  .checkbox,
  .columnHeader,
  .confirmationDialog,
  .custom("meter"),
  .disclosureGroup,
  .group,
  .heading(level: 2),
  .image,
  .link,
  .list,
  .menu,
  .menuItem,
  .picker,
  .progressBar,
  .region,
  .rowHeader,
  .scrollView,
  .scrollViewWithIndicators,
  .section,
  .secureField,
  .separator,
  .sheet,
  .slider,
  .status,
  .stepper,
  .tab,
  .tabPanel,
  .table,
  .tableRow,
  .tabView,
  .textEditor,
  .textField,
  .timer,
  .toggle,
]

private func identity(
  _ value: String
) -> Identity {
  Identity(components: [value])
}
