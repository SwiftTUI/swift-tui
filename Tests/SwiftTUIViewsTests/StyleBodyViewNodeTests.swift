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
  @Test("Menu style bodies have their own applied nodes", arguments: [0, 1, 2, 3])
  func menuStyleBodyHasOwnNode(_ index: Int) throws {
    let styles: [AnyMenuStyle] = [.automatic, .button, .borderlessButton, .inline]
    let result = resolveWithGraph(
      Menu("Commands") { Text("Item") }.menuStyle(styles[index]), root: "MenuStyleNodeRoot")
    let menu = try #require(firstNode(ofKind: "Menu", in: result.resolved))
    let body = try #require(result.graph.nodeForIdentity(menu.identity.child(.named("MenuBody"))))
    #expect(body.committed.viewNodeID == body.viewNodeID)
    #expect(!body.committed.children.isEmpty)
  }

  @Test("ControlGroup style bodies have their own applied nodes", arguments: [0, 1, 2, 3])
  func controlGroupStyleBodyHasOwnNode(_ index: Int) throws {
    let styles: [AnyControlGroupStyle] = [.automatic, .horizontal, .vertical, .compactMenu]
    let result = resolveWithGraph(
      ControlGroup("Commands") { Text("Item") }.controlGroupStyle(styles[index]),
      root: "ControlGroupStyleNodeRoot")
    try expectStyleBodyHasOwnAppliedNode(
      result,
      controlKind: "ControlGroup", bodyComponent: "ControlGroupBody")
  }

  @Test("Slider style bodies have their own applied nodes", arguments: [0, 1])
  func sliderStyleBodyHasOwnNode(_ index: Int) throws {
    let styles: [AnySliderStyle] = [.automatic, .linear]
    let result = resolveWithGraph(
      Slider("Level", value: .constant(5), in: 0...10).sliderStyle(styles[index]),
      root: "SliderStyleNodeRoot")
    try expectStyleBodyHasOwnAppliedNode(result, controlKind: "Slider", bodyComponent: "SliderBody")
  }

  @Test("Stepper style bodies have their own applied nodes", arguments: [0, 1])
  func stepperStyleBodyHasOwnNode(_ index: Int) throws {
    let styles: [AnyStepperStyle] = [.automatic, .compact]
    let result = resolveWithGraph(
      Stepper("Count", value: .constant(5), in: 0...10).stepperStyle(styles[index]),
      root: "StepperStyleNodeRoot")
    try expectStyleBodyHasOwnAppliedNode(
      result, controlKind: "Stepper", bodyComponent: "StepperBody")
  }

  @Test("Toggle style bodies have their own applied nodes", arguments: [0, 1, 2])
  func toggleStyleBodyHasOwnNode(_ index: Int) throws {
    let styles: [AnyToggleStyle] = [.automatic, .checkbox, .button]
    let result = resolveWithGraph(
      Toggle("Switch", isOn: .constant(false)).toggleStyle(styles[index]),
      root: "ToggleStyleNodeRoot")
    try expectStyleBodyHasOwnAppliedNode(result, controlKind: "Toggle", bodyComponent: "ToggleBody")
  }

  @Test("DisclosureGroup style bodies have their own applied nodes", arguments: [0, 1])
  func disclosureGroupStyleBodyHasOwnNode(_ index: Int) throws {
    let styles: [AnyDisclosureGroupStyle] = [.automatic, .compact]
    let result = resolveWithGraph(
      DisclosureGroup("Details", isExpanded: .constant(true)) { Text("Child") }
        .disclosureGroupStyle(styles[index]), root: "DisclosureGroupStyleNodeRoot")
    try expectStyleBodyHasOwnAppliedNode(
      result, controlKind: "DisclosureGroup", bodyComponent: "DisclosureBody")
  }

  @Test("TextEditor style bodies have their own applied nodes", arguments: [0, 1, 2])
  func textEditorStyleBodyHasOwnNode(_ index: Int) throws {
    let styles: [AnyTextEditorStyle] = [.automatic, .plain, .roundedBorder]
    let result = resolveWithGraph(
      TextEditor(text: .constant("Text")).textEditorStyle(styles[index]),
      root: "TextEditorStyleNodeRoot")
    try expectStyleBodyHasOwnAppliedNode(
      result, controlKind: "TextEditor", bodyComponent: "TextEditorBody")
  }

  @Test("ProgressView style bodies have their own applied nodes", arguments: [0, 1, 2])
  func progressViewStyleBodyHasOwnNode(_ index: Int) throws {
    let styles: [AnyProgressViewStyle] = [.automatic, .linear, .circular]
    let result = resolveWithGraph(
      ProgressView(value: 0.5).progressViewStyle(styles[index]), root: "ProgressViewStyleNodeRoot")
    try expectStyleBodyHasOwnAppliedNode(
      result, controlKind: "ProgressView", bodyComponent: "ProgressViewBody")
  }

  @Test("label style bodies have their own applied nodes", arguments: [0, 1, 2, 3])
  func labelStyleBodyHasOwnNode(_ index: Int) throws {
    let styles: [AnyLabelStyle] = [.automatic, .titleAndIcon, .titleOnly, .iconOnly]
    let result = resolveWithGraph(
      Label("Title") { Text("*") }.labelStyle(styles[index]), root: "LabelStyleNodeRoot")
    try expectStyleBodyHasOwnAppliedNode(result, controlKind: "Label", bodyComponent: "LabelBody")
  }

  @Test("labeled-content style bodies have their own applied nodes", arguments: [false, true])
  func labeledContentStyleBodyHasOwnNode(_ stacked: Bool) throws {
    let result = resolveWithGraph(
      LabeledContent("Name", value: "Ada").labeledContentStyle(stacked ? .stacked : .automatic),
      root: "LabeledContentStyleNodeRoot")
    try expectStyleBodyHasOwnAppliedNode(
      result, controlKind: "LabeledContent", bodyComponent: "LabeledContentBody")
  }

  @Test("group-box style bodies have their own applied nodes", arguments: [0, 1, 2])
  func groupBoxStyleBodyHasOwnNode(_ index: Int) throws {
    let styles: [AnyGroupBoxStyle] = [.automatic, .bordered, .plain]
    let result = resolveWithGraph(
      GroupBox("Group") { Text("Value") }.groupBoxStyle(styles[index]),
      root: "GroupBoxStyleNodeRoot")
    try expectStyleBodyHasOwnAppliedNode(
      result, controlKind: "GroupBox", bodyComponent: "GroupBoxBody")
  }

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
