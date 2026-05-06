import CoreGraphics
import SwiftTUI
import Testing

@testable import SwiftUIHost

@MainActor
@Test
func overlay_mapping_updates_frames_when_cell_size_changes() throws {
  let snapshot = SemanticSnapshot(
    accessibilityNodes: [
      node("action", rect: .init(origin: .init(x: 1, y: 2), size: .init(width: 3, height: 1)))
    ]
  )

  let compact = HostedAccessibilityOverlay(
    semanticSnapshot: snapshot,
    focusedIdentity: nil,
    cellSize: .init(width: 8, height: 16)
  )
  let expanded = HostedAccessibilityOverlay(
    semanticSnapshot: snapshot,
    focusedIdentity: nil,
    cellSize: .init(width: 10, height: 20)
  )

  #expect(try #require(compact.mappings.first).frame == CGRect(x: 8, y: 32, width: 24, height: 16))
  #expect(
    try #require(expanded.mappings.first).frame == CGRect(x: 10, y: 40, width: 30, height: 20))
}

@MainActor
@Test
func overlay_mapping_reflects_node_removal() {
  let first = HostedAccessibilityOverlay(
    semanticSnapshot: SemanticSnapshot(
      accessibilityNodes: [
        node("one"),
        node("two"),
      ]
    ),
    focusedIdentity: nil,
    cellSize: .init(width: 8, height: 16)
  )
  let second = HostedAccessibilityOverlay(
    semanticSnapshot: SemanticSnapshot(
      accessibilityNodes: [
        node("two")
      ]
    ),
    focusedIdentity: nil,
    cellSize: .init(width: 8, height: 16)
  )

  #expect(first.mappings.map(\.id) == ["one", "two"])
  #expect(second.mappings.map(\.id) == ["two"])
}

@MainActor
@Test
func overlay_mapping_preserves_group_nesting_metadata_and_order() throws {
  let root = identity("group")
  let child = identity("group", "child")
  let overlay = HostedAccessibilityOverlay(
    semanticSnapshot: SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: root,
          rect: .init(origin: .zero, size: .init(width: 4, height: 2)),
          role: .group,
          label: "Group"
        ),
        AccessibilityNode(
          identity: child,
          parentIdentity: root,
          rect: .init(origin: .init(x: 1, y: 1), size: .init(width: 2, height: 1)),
          role: .button,
          label: "Child"
        ),
      ]
    ),
    focusedIdentity: child,
    cellSize: .init(width: 8, height: 16)
  )

  #expect(overlay.mappings.map(\.identity) == [root, child])
  let childMapping = try #require(overlay.mappings.last)
  #expect(childMapping.parentIdentity == root)
  #expect(childMapping.isFocused)
}

@MainActor
@Test
func overlay_mapping_moves_and_clears_focused_semantic_target() {
  let first = identity("first")
  let second = identity("second")
  let snapshot = SemanticSnapshot(
    accessibilityNodes: [
      AccessibilityNode(
        identity: first,
        rect: .init(origin: .zero, size: .init(width: 1, height: 1)),
        role: .button,
        label: "First"
      ),
      AccessibilityNode(
        identity: second,
        rect: .init(origin: .init(x: 2, y: 0), size: .init(width: 1, height: 1)),
        role: .button,
        label: "Second"
      ),
    ]
  )

  let firstFocused = HostedAccessibilityOverlay(
    semanticSnapshot: snapshot,
    focusedIdentity: first,
    cellSize: .init(width: 8, height: 16)
  )
  let secondFocused = HostedAccessibilityOverlay(
    semanticSnapshot: snapshot,
    focusedIdentity: second,
    cellSize: .init(width: 8, height: 16)
  )
  let removedFocused = HostedAccessibilityOverlay(
    semanticSnapshot: SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: second,
          rect: .init(origin: .zero, size: .init(width: 1, height: 1)),
          role: .button,
          label: "Second"
        )
      ]
    ),
    focusedIdentity: first,
    cellSize: .init(width: 8, height: 16)
  )

  #expect(firstFocused.mappings.map(\.isFocused) == [true, false])
  #expect(secondFocused.mappings.map(\.isFocused) == [false, true])
  #expect(removedFocused.mappings.allSatisfy { !$0.isFocused })
}

@MainActor
@Test
func overlay_mapping_handles_empty_and_zero_rect_trees() {
  let empty = HostedAccessibilityOverlay(
    semanticSnapshot: nil,
    focusedIdentity: nil,
    cellSize: .init(width: 8, height: 16)
  )
  let zeroRect = HostedAccessibilityOverlay(
    semanticSnapshot: SemanticSnapshot(
      accessibilityNodes: [
        node("hidden", rect: .zero)
      ]
    ),
    focusedIdentity: nil,
    cellSize: .init(width: 8, height: 16)
  )

  #expect(empty.mappings.isEmpty)
  #expect(zeroRect.mappings.isEmpty)
}

private func node(
  _ id: String,
  rect: CellRect = .init(origin: .zero, size: .init(width: 1, height: 1))
) -> AccessibilityNode {
  AccessibilityNode(
    identity: identity(id),
    rect: rect,
    role: .button,
    label: id
  )
}

private func identity(
  _ components: String...
) -> Identity {
  Identity(components: components)
}
