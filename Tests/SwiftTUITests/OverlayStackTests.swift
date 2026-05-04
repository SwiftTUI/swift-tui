import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct OverlayStackTests {
  @Test("overlay stack orders entries and gates modal base interaction")
  func overlayStackOrdersEntriesAndGatesModalBase() throws {
    var baseSemantics = SemanticMetadata(focusScopeBoundary: true)
    baseSemantics.isFocusable = true
    let baseIdentity = testIdentity("Scene")
    let rootIdentity = testIdentity("PortalRoot")
    let baseNode = ResolvedNode(
      identity: baseIdentity,
      kind: .view("Base"),
      semanticMetadata: baseSemantics
    )

    let stack = composeOverlayStackTree(
      baseNode: baseNode,
      entries: [
        overlayEntry(id: "later-low", zIndex: 1, activationOrdinal: 20),
        overlayEntry(id: "top", zIndex: 2, activationOrdinal: 1),
        overlayEntry(id: "earlier-low", zIndex: 1, activationOrdinal: 10),
      ],
      in: .init(identity: rootIdentity)
    )

    let base = try #require(stack.children.first)
    let overlays = try #require(stack.children.last)

    #expect(stack.kind == .view("OverlayStack"))
    #expect(stack.semanticMetadata.focusScopeBoundary)
    #expect(stack.semanticMetadata.focusScopeIdentity == baseIdentity)
    #expect(base.identity == baseIdentity)
    #expect(base.semanticMetadata.interactionAvailability == .disabled(reason: .modalOverlay))
    #expect(
      overlays.children.map(\.identity.path) == [
        "\(rootIdentity.path)/PortalHost/overlays/entry:earlier-low",
        "\(rootIdentity.path)/PortalHost/overlays/entry:later-low",
        "\(rootIdentity.path)/PortalHost/overlays/entry:top",
      ])
  }

  private func overlayEntry(
    id: String,
    zIndex: Int,
    activationOrdinal: Int
  ) -> OverlayStackEntry {
    OverlayStackEntry(
      id: id,
      ordering: .init(
        zIndex: zIndex,
        activationOrdinal: activationOrdinal,
        stableTieBreaker: id
      ),
      kindName: "TestOverlay",
      modalPolicy: id == "top" ? .disablesBaseInteraction : .nonModal,
      acceptsEscape: true,
      dismiss: {},
      payload: PortalContentPayload {
        Text(id)
      }
    )
  }
}
