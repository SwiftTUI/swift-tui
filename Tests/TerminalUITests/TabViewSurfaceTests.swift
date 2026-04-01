import Testing

@testable import Core
@testable import TerminalUI
@testable import View

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    if case .text(let nodeText) = drawPayload, nodeText == text {
      return self
    }

    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }

    return nil
  }
}

@MainActor
@Suite
struct TabViewSurfaceTests {
  @Test("TabView resolves typed labels into semantics and strip chrome")
  func tabViewResolvesTypedLabels() throws {
    let artifacts = DefaultRenderer().render(
      TabView(selection: .constant("home")) {
        Text("Home content")
          .tabItem(TabItemLabel("Home", detail: "3"))
          .tag("home")

        Text("Settings content")
          .tabItem(TabItemLabel("Settings"))
          .tag("settings")
      }
      .id(testIdentity("Tabs")),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 32, height: 4)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let homeNode = try #require(artifacts.resolvedTree.descendant(withText: "Home content"))

    #expect(surface.contains("Home · 3"))
    #expect(surface.contains("Settings"))
    #expect(homeNode.semanticMetadata.tabItemLabel == TabItemLabel("Home", detail: "3"))
    #expect(homeNode.semanticMetadata.presentationRole == nil)
    #expect(artifacts.resolvedTree.semanticMetadata.presentationRole == .tabView)
  }
}
