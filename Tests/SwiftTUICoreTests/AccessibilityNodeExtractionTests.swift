import Testing

@_spi(Testing) @testable import SwiftTUICore

@Suite
struct AccessibilityNodeExtractionTests {
  @Test("Button role emits a node with label inferred from rendered text")
  func buttonRoleEmitsInferredTextLabel() throws {
    let buttonID = testIdentity("Button")
    let buttonRect = rect(x: 0, y: 0, width: 4, height: 1)
    let placed = placedNode(
      identity: buttonID,
      bounds: buttonRect,
      semanticMetadata: .init(accessibilityRole: .button),
      drawPayload: .text("Save")
    )

    let nodes = SemanticExtractor().extract(from: placed).accessibilityNodes

    #expect(
      nodes == [
        AccessibilityNode(
          identity: buttonID,
          rect: buttonRect,
          role: .button,
          label: "Save"
        )
      ]
    )
  }

  @Test("Explicit accessibility label wins over inferred text")
  func explicitLabelWinsOverInferredText() throws {
    let buttonID = testIdentity("Button")
    let placed = placedNode(
      identity: buttonID,
      semanticMetadata: .init(
        accessibilityRole: .button,
        accessibilityLabel: "Remove item"
      ),
      drawPayload: .text("Delete")
    )

    let node = try #require(SemanticExtractor().extract(from: placed).accessibilityNodes.first)

    #expect(node.label == "Remove item")
  }

  @Test("Accessibility hidden skips the node and descendants")
  func accessibilityHiddenSkipsSubtree() {
    let rootID = testIdentity("Root")
    let hiddenID = testIdentity("Hidden")
    let hiddenButtonID = testIdentity("Hidden", "Button")
    let visibleButtonID = testIdentity("Visible", "Button")
    let hiddenSubtree = placedNode(
      identity: hiddenID,
      semanticMetadata: .init(accessibilityHidden: true),
      children: [
        placedNode(
          identity: hiddenButtonID,
          semanticMetadata: .init(accessibilityRole: .button),
          drawPayload: .text("Secret")
        )
      ]
    )
    let visibleButton = placedNode(
      identity: visibleButtonID,
      semanticMetadata: .init(accessibilityRole: .button),
      drawPayload: .text("Visible")
    )
    let root = placedNode(
      identity: rootID,
      children: [hiddenSubtree, visibleButton]
    )

    let nodes = SemanticExtractor().extract(from: root).accessibilityNodes
    let identities = Set(nodes.map(\.identity))

    #expect(identities.contains(rootID))
    #expect(identities.contains(visibleButtonID))
    #expect(!identities.contains(hiddenID))
    #expect(!identities.contains(hiddenButtonID))
  }

  @Test("Structural group ancestors preserve parent identity")
  func structuralGroupAncestorPreservesParentIdentity() throws {
    let rootID = testIdentity("Root")
    let childID = testIdentity("Root", "Child")
    let root = placedNode(
      identity: rootID,
      children: [
        placedNode(
          identity: childID,
          semanticMetadata: .init(accessibilityRole: .button),
          drawPayload: .text("Run")
        )
      ]
    )

    let nodes = SemanticExtractor().extract(from: root).accessibilityNodes
    let rootNode = try #require(nodes.first { $0.identity == rootID })
    let childNode = try #require(nodes.first { $0.identity == childID })

    #expect(rootNode.role == .group)
    #expect(rootNode.parentIdentity == nil)
    #expect(childNode.parentIdentity == rootID)
  }

  @Test("Focus-chain nodes emit without authored labels")
  func focusChainNodesEmitWithoutAuthoredLabels() throws {
    let focusID = testIdentity("Focusable")
    let placed = placedNode(
      identity: focusID,
      semanticMetadata: .init(isFocusable: true)
    )

    let snapshot = SemanticExtractor().extract(from: placed)
    let node = try #require(snapshot.accessibilityNodes.first)

    #expect(snapshot.focusRegions.map(\.identity) == [focusID])
    #expect(node.identity == focusID)
    #expect(node.role == .group)
    #expect(node.label == nil)
  }

  @Test("Accessibility node order follows layout reading order")
  func nodeOrderFollowsLayoutReadingOrder() {
    let rootID = testIdentity("Root")
    let leftID = testIdentity("Root", "Left")
    let rightID = testIdentity("Root", "Right")
    let root = placedNode(
      identity: rootID,
      children: [
        placedNode(
          identity: leftID,
          semanticMetadata: .init(accessibilityRole: .button),
          drawPayload: .text("Left")
        ),
        placedNode(
          identity: rightID,
          semanticMetadata: .init(accessibilityRole: .link),
          drawPayload: .text("Right")
        ),
      ]
    )

    let identities = SemanticExtractor().extract(from: root).accessibilityNodes.map(\.identity)

    #expect(identities == [rootID, leftID, rightID])
  }

  @Test("Text input caret anchors hoist onto the owning accessibility node")
  func textInputCaretAnchorHoistsToOwnerNode() throws {
    let ownerID = testIdentity("TextField")
    let contentID = testIdentity("TextField", "Content")
    let root = placedNode(
      identity: testIdentity("Root"),
      children: [
        placedNode(
          identity: ownerID,
          semanticMetadata: .init(accessibilityRole: .textField),
          children: [
            placedNode(
              identity: contentID,
              bounds: rect(x: 4, y: 2, width: 8, height: 1),
              semanticMetadata: .init(
                textInputAccessibilityCursorAnchor: .init(
                  ownerIdentity: ownerID,
                  anchor: CellPoint(x: 3, y: 0)
                )
              ),
              drawPayload: .text("abc")
            )
          ]
        )
      ]
    )

    let nodes = SemanticExtractor().extract(from: root).accessibilityNodes
    let ownerNode = try #require(nodes.first { $0.identity == ownerID })

    #expect(ownerNode.cursorAnchor == CellPoint(x: 7, y: 2))
    #expect(!nodes.contains { $0.identity == contentID })
  }

  @Test("Explicit accessibility cursor anchors still apply to their own node")
  func explicitCursorAnchorStillAppliesToOwnNode() throws {
    let identity = testIdentity("Custom")
    let placed = placedNode(
      identity: identity,
      bounds: rect(x: 2, y: 3, width: 8, height: 1),
      semanticMetadata: .init(
        accessibilityRole: .button,
        accessibilityCursorAnchor: CellPoint(x: 5, y: 0)
      ),
      drawPayload: .text("Run")
    )

    let node = try #require(SemanticExtractor().extract(from: placed).accessibilityNodes.first)

    #expect(node.cursorAnchor == CellPoint(x: 7, y: 3))
  }
}

private func placedNode(
  identity: Identity,
  bounds: CellRect = rect(x: 0, y: 0, width: 10, height: 1),
  semanticMetadata: SemanticMetadata = .init(),
  children: [PlacedNode] = [],
  drawPayload: DrawPayload = .none
) -> PlacedNode {
  PlacedNode(
    identity: identity,
    kind: .view("Test"),
    bounds: bounds,
    children: children,
    semanticMetadata: semanticMetadata,
    drawPayload: drawPayload
  )
}

private func rect(
  x: Int,
  y: Int,
  width: Int,
  height: Int
) -> CellRect {
  CellRect(
    origin: CellPoint(x: x, y: y),
    size: CellSize(width: width, height: height)
  )
}
