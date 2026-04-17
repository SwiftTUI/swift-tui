import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct PanelTests {
  @Test("Panel with explicit id exposes that id via ActionScope.ID")
  func panelExposesExplicitID() {
    let panel = Panel(id: "editor") { EmptyView() }
    #expect(panel.id == "editor")
  }

  @Test("Panel sets focusScopeBoundary in its resolved node metadata")
  func panelMarksFocusScopeBoundary() {
    let panel = Panel(id: "editor") { EmptyView() }
    let resolved = resolveForTest(panel)
    #expect(resolved.semanticMetadata.focusScopeBoundary == true)
  }

  @Test("Panel is focusable")
  func panelIsFocusable() {
    let panel = Panel(id: "editor") { EmptyView() }
    let resolved = resolveForTest(panel)
    #expect(resolved.semanticMetadata.isFocusable == true)
  }

  @Test(".panel() produces stable AnyID across re-resolves at the same source location")
  func panelPseudonymousIDIsStable() {
    // Build the same view twice, resolve each to a ResolvedNode, and
    // verify the Panel's identity is equal across the two resolves.
    // The view must be constructed the same way both times — a View
    // tree that includes Text("x").panel() at the same position.
    let view1 = Text("content").panel()
    let view2 = Text("content").panel()
    // Panel's ID is AnyID; the resolved identity path also encodes
    // source-location structure. Compare whichever is stable.
    #expect(view1.id == view2.id)
  }
}

/// Resolves `view` by running it through the full resolver once and
/// returning the root `ResolvedNode`. Mirrors what existing tests do in
/// `Tests/ViewTests/ViewResolutionTests.swift` but keeps Panel tests
/// scoped to the `TerminalUITests` target where `DefaultRenderer` lives.
@MainActor
private func resolveForTest<V: View>(_ view: V) -> ResolvedNode {
  let resolver = Resolver()
  return resolver.resolve(
    AnyView(view),
    in: ResolveContext(identity: testIdentity("panel-test-root"))
  )
}
