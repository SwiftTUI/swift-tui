import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Style-seam root fix: a control style's `makeBody` output must resolve
/// through its own view node (`resolveView`), not as a value-only
/// `ResolvedNode`. A value-only style child forces
/// `ViewGraph.nodeForResolvedNode`'s identity fallback to mint a hollow,
/// never-evaluated placeholder for the style body; those placeholders
/// rebuilt stale snapshots from hollow committed values and stranded chrome
/// interiors (`ButtonBody/…/base`, `/overlay`, `/background`) when a host
/// generation departed — the F04 teardown-coherence leak residual (gallery
/// fuzzer case-139).
@MainActor
struct StyleBodyViewNodeTests {
  private struct GraphResolveResult {
    let graph: ViewGraph
    let resolved: ResolvedNode
  }

  private func resolveWithGraph(
    _ view: some View,
    root: String
  ) -> GraphResolveResult {
    let graph = ViewGraph()
    let rootIdentity = testIdentity(root)
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}
    graph.beginFrame()
    var context = ResolveContext(
      identity: rootIdentity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    let resolved = Resolver().resolve(view, in: context)
    return GraphResolveResult(graph: graph, resolved: resolved)
  }

  private func firstNode(
    ofKind name: String,
    in node: ResolvedNode
  ) -> ResolvedNode? {
    if node.kind == .view(name) {
      return node
    }
    for child in node.children {
      if let found = firstNode(ofKind: name, in: child) {
        return found
      }
    }
    return nil
  }

  private func expectStyleBodyHasOwnAppliedNode(
    _ result: GraphResolveResult,
    controlKind: String,
    bodyComponent: StaticString,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let control = try #require(
      firstNode(ofKind: controlKind, in: result.resolved),
      "no \(controlKind) node in the resolved tree",
      sourceLocation: sourceLocation
    )
    let styleChild = try #require(
      control.children.first,
      "\(controlKind) resolved without a style-body child",
      sourceLocation: sourceLocation
    )
    let styleChildNodeID = try #require(
      styleChild.viewNodeID,
      "\(controlKind)'s style body resolved value-only (no view node of its own)",
      sourceLocation: sourceLocation
    )
    let bodyNode = try #require(
      result.graph.nodeForIdentity(
        control.identity.child(.named(bodyComponent))
      ),
      "\(controlKind) has no stored node at its style-body identity",
      sourceLocation: sourceLocation
    )
    #expect(
      bodyNode.viewNodeID == styleChildNodeID,
      "\(controlKind)'s style child is stamped with a different node than its style-body identity",
      sourceLocation: sourceLocation
    )
    #expect(
      bodyNode.committed.viewNodeID != nil,
      "\(controlKind)'s style-body node was minted but never applied (hollow placeholder)",
      sourceLocation: sourceLocation
    )
  }

  @Test("Button's automatic style body resolves through its own view node")
  func buttonAutomaticStyleBodyHasOwnNode() throws {
    let result = resolveWithGraph(
      Button("Press") {},
      root: "ButtonStyleNodeRoot"
    )
    try expectStyleBodyHasOwnAppliedNode(
      result,
      controlKind: "Button",
      bodyComponent: "ButtonBody"
    )
  }

  @Test("Button's bordered style body resolves through its own view node")
  func buttonBorderedStyleBodyHasOwnNode() throws {
    let result = resolveWithGraph(
      Button("Press") {}.buttonStyle(.bordered),
      root: "BorderedButtonStyleNodeRoot"
    )
    try expectStyleBodyHasOwnAppliedNode(
      result,
      controlKind: "Button",
      bodyComponent: "ButtonBody"
    )
  }

  @Test("TextField's style body resolves through its own view node")
  func textFieldStyleBodyHasOwnNode() throws {
    var text = ""
    let result = resolveWithGraph(
      TextField(
        "Name",
        text: Binding(get: { text }, set: { text = $0 })
      ),
      root: "TextFieldStyleNodeRoot"
    )
    try expectStyleBodyHasOwnAppliedNode(
      result,
      controlKind: "TextField",
      bodyComponent: "TextFieldBody"
    )
  }

  @Test("SecureField's style body resolves through its own view node")
  func secureFieldStyleBodyHasOwnNode() throws {
    var secret = ""
    let result = resolveWithGraph(
      SecureField(
        "Secret",
        text: Binding(get: { secret }, set: { secret = $0 })
      ),
      root: "SecureFieldStyleNodeRoot"
    )
    try expectStyleBodyHasOwnAppliedNode(
      result,
      controlKind: "SecureField",
      bodyComponent: "SecureFieldBody"
    )
  }

  @Test("Picker's style body resolves through its own view node")
  func pickerStyleBodyHasOwnNode() throws {
    var selection = 0
    let result = resolveWithGraph(
      Picker(
        "Priority",
        selection: Binding(get: { selection }, set: { selection = $0 })
      ) {
        Text("low").tag(0)
        Text("high").tag(1)
      },
      root: "PickerStyleNodeRoot"
    )
    try expectStyleBodyHasOwnAppliedNode(
      result,
      controlKind: "Picker",
      bodyComponent: "PickerBody"
    )
  }

  @Test("TabView's style body resolves through its own view node")
  func tabViewStyleBodyHasOwnNode() throws {
    var selection = "first"
    let result = resolveWithGraph(
      TabView(
        selection: Binding(get: { selection }, set: { selection = $0 })
      ) {
        Tab("First", value: "first") {
          Text("First body")
        }
        Tab("Second", value: "second") {
          Text("Second body")
        }
      },
      root: "TabViewStyleNodeRoot"
    )
    try expectStyleBodyHasOwnAppliedNode(
      result,
      controlKind: "TabView",
      bodyComponent: "TabBody"
    )
  }
}
