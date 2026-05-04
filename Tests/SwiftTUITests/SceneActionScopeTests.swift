import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
@Suite
struct SceneActionScopeTests {
  @Test("WindowGroup's scene root marks focusScopeBoundary on its resolved node")
  func sceneRootMarksFocusScopeBoundary() {
    // WindowHostView is the internal wrapper that becomes the root
    // node of every scene session. Rendering it through
    // DefaultRenderer at rootIdentity mirrors what
    // SceneSession.run(...) does at session startup.
    let rootIdentity = testIdentity("App", "test-window")
    let artifacts = DefaultRenderer().render(
      WindowHostView(content: Text("body").focusable(true)),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 20, height: 4)
    )

    let rootNode = artifacts.resolvedTree
    #expect(rootNode.identity == rootIdentity)
    #expect(rootNode.semanticMetadata.focusScopeBoundary == true)
  }

  @Test("Scene-rooted focus regions include the scene identity at index 0 of scopePath")
  func sceneIsOnScopePath() throws {
    let rootIdentity = testIdentity("App", "test-window")
    let artifacts = DefaultRenderer().render(
      WindowHostView(content: Text("body").focusable(true)),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 20, height: 4)
    )

    let regions = artifacts.semanticSnapshot.focusRegions
    #expect(regions.count >= 1)
    let leaf = regions.first { region in
      region.identity != rootIdentity
    }
    let leafRegion = try #require(leaf)
    #expect(leafRegion.scopePath.first == rootIdentity)
  }
}
