import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct DropDestinationTests {
  @Test("dropDestination registers a handler at the Panel's scope identity")
  func registersAtScopeIdentity() {
    let registry = DropDestinationRegistry()
    let panel =
      Panel(id: "inbox") { EmptyView() }
      .dropDestination { _ in true }

    var context = ResolveContext(identity: testIdentity("drop-root"))
    context.dropDestinationRegistry = registry
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    let panelNode = findPanelNode(in: resolved)
    #expect(panelNode != nil)
    #expect(panelNode.flatMap { registry.handler(at: $0.identity) } != nil)
  }

  @Test("dropDestination forwards ActionScope conformance so keyCommand still compiles")
  func conformanceIsForwarded() {
    // If this compiles, the assertion holds; kept as an explicit test
    // so a later refactor that breaks the forwarding is caught here.
    _ =
      Panel(id: "inbox") { EmptyView() }
      .dropDestination { _ in true }
      .keyCommand("Save", key: .character("s"), modifiers: .ctrl, action: {})
  }
}

@MainActor
private func findPanelNode(in root: ResolvedNode) -> ResolvedNode? {
  var stack: [ResolvedNode] = [root]
  while let node = stack.popLast() {
    if case .view("Panel") = node.kind { return node }
    stack.append(contentsOf: node.children)
  }
  return nil
}
