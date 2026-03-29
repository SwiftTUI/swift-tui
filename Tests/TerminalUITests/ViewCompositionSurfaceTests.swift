import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct ViewCompositionSurfaceTests {
  @Test("resolver assigns stable indexed identities to grouped children")
  func resolverAssignsStableIndexedIdentities() {
    let root = Group {
      Text("Text")
      Divider()
    }
    let resolved = root.resolve(in: .init(identity: testIdentity("Root")))

    #expect(resolved.identity == testIdentity("Root"))
    #expect(resolved.children.count == 2)
    #expect(resolved.children[0].identity == testIdentity("Root", "Group[0]"))
    #expect(resolved.children[1].identity == testIdentity("Root", "Group[1]"))
    #expect(resolved.children[0].kind == .view("Text"))
    #expect(resolved.children[1].kind == .view("Divider"))
  }

  @Test("public metadata modifiers merge into resolved nodes without disturbing explicit identity")
  func publicMetadataModifiersMergeIntoResolvedNodes() {
    let resolved = Text("Button")
      .drawMetadata(.init(foregroundStyle: .semantic(.foreground)))
      .semanticMetadata(.init(participatesInPointerHitTesting: true))
      .id(testIdentity("Explicit", "Button"))
      .semanticMetadata(.init(isFocusable: true, presentationRole: .button))
      .drawMetadata(
        .init(
          borderShapeStyle: .semantic(.separator),
          borderStrokeStyle: .init(lineVariant: .rounded)
        )
      )
      .layoutMetadata(
        .init(
          layoutPriority: 2,
          spacing: .init(horizontal: 1, vertical: 2),
          alignmentKeys: ["center"]
        )
      )
      .resolve(in: .init(identity: testIdentity("Root")))

    #expect(resolved.identity == testIdentity("Explicit", "Button"))
    #expect(resolved.layoutMetadata.layoutPriority == 2)
    #expect(resolved.layoutMetadata.spacing == .init(horizontal: 1, vertical: 2))
    #expect(resolved.layoutMetadata.alignmentKeys == ["center"])
    #expect(resolved.drawMetadata.foregroundStyle == .semantic(.foreground))
    #expect(resolved.drawMetadata.borderShapeStyle == .semantic(.separator))
    #expect(resolved.drawMetadata.borderStrokeStyle == .init(lineVariant: .rounded))
    #expect(resolved.semanticMetadata.participatesInPointerHitTesting)
    #expect(resolved.semanticMetadata.isFocusable == true)
    #expect(resolved.semanticMetadata.presentationRole == .button)
  }
}
