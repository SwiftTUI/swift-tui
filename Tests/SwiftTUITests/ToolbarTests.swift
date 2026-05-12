import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ToolbarTests {
  @Test("DefaultTopToolbarStyle and DefaultBottomToolbarStyle conform to ToolbarStyle")
  func defaultStylesExist() {
    let top: any ToolbarStyle = DefaultTopToolbarStyle()
    let bottom: any ToolbarStyle = DefaultBottomToolbarStyle()
    #expect(top.placement == .top)
    #expect(bottom.placement == .bottom)
  }

  @Test("toolbarItem contributions accumulate up the tree via preference key")
  func toolbarItemsAccumulate() {
    let view = VStack {
      Text("A").toolbarItem(
        .init(
          title: "Item A",
          icon: nil,
          position: .top,
          isEnabled: true,
          action: {}
        )
      )
      Text("B").toolbarItem(
        .init(
          title: "Item B",
          icon: nil,
          position: .top,
          isEnabled: true,
          action: {}
        )
      )
    }
    let context = ResolveContext(identity: testIdentity("toolbar-root"))
    let resolved = Resolver().resolve(AnyView(view), in: context)
    let items = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    #expect(items.count == 2)
    #expect(items.map(\.title).contains("Item A"))
    #expect(items.map(\.title).contains("Item B"))
  }

  @Test("Builder toolbarItem variant registers its label text as the title")
  func builderVariantRegisters() {
    let view = Text("X").toolbarItem(action: {}) {
      Text("Copy")
    } icon: {
      EmptyView()
    }
    let context = ResolveContext(identity: testIdentity("toolbar-root"))
    let resolved = Resolver().resolve(AnyView(view), in: context)
    let items = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    #expect(items.first?.title == "Copy")
  }

  @Test("Panel with toolbar absorbs toolbar items from its subtree")
  func toolbarAbsorbsItems() {
    let panel =
      Panel(id: "outer") {
        Text("content").toolbarItem(
          .init(
            title: "Save",
            icon: nil,
            position: .top,
            isEnabled: true,
            action: {}
          )
        )
      }
      .toolbar(style: DefaultTopToolbarStyle())

    let context = ResolveContext(identity: testIdentity("toolbar-root"))
    let resolved = Resolver().resolve(AnyView(panel), in: context)
    // After the toolbar modifier consumes the preference, the outer
    // preferenceValues should NOT still contain the toolbar item.
    let leakedItems = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    #expect(leakedItems.isEmpty)
  }

  @Test(
    "Toolbar items bubble past a non-toolbar scope and land at the next ancestor with a toolbar")
  func toolbarItemsBubblePastScopeWithoutToolbar() {
    let view =
      Panel(id: "outer") {
        Panel(id: "inner") {
          Text("content").toolbarItem(
            .init(
              title: "Save",
              icon: nil,
              position: .top,
              isEnabled: true,
              action: {}
            )
          )
        }
      }
      .toolbar(style: DefaultTopToolbarStyle())

    let context = ResolveContext(identity: testIdentity("toolbar-root"))
    let resolved = Resolver().resolve(AnyView(view), in: context)
    let leakedItems = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    // Absorbed at outer Panel because inner Panel has no toolbar.
    #expect(leakedItems.isEmpty)
  }

  @Test("Panel with top toolbar renders item titles in a horizontal strip above the content")
  func toolbarRendersAboveContent() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Save",
              icon: nil,
              position: .top,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultTopToolbarStyle())
      .frame(width: 20, height: 5)

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("toolbar-render-root"))
    )
    let lines = artifacts.rasterSurface.lines
    let saveRow = lines.firstIndex { $0.contains("Save") }
    let bodyRow = lines.firstIndex { $0.contains("body") }
    #expect(saveRow != nil)
    #expect(bodyRow != nil)
    if let saveRow, let bodyRow {
      // Top-placement: toolbar strip must appear above the content.
      #expect(saveRow < bodyRow)
    }
  }

  @Test("Top toolbar reclaims the container's top safe area")
  func topToolbarUsesTopSafeArea() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Save",
              icon: nil,
              position: .top,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultTopToolbarStyle())
      .frame(width: 20, height: 5)

    let artifacts = render(
      panel,
      terminalSize: .init(width: 20, height: 6),
      safeAreaInsets: .init(top: 1, leading: 0, bottom: 0, trailing: 0)
    )
    let lines = artifacts.rasterSurface.lines
    let saveRow = lines.firstIndex { $0.contains("Save") }
    let bodyRow = lines.firstIndex { $0.contains("body") }

    #expect(saveRow != nil)
    #expect(bodyRow != nil)
    if let saveRow, let bodyRow {
      #expect(saveRow == 0)
      #expect(saveRow < bodyRow)
    }
  }

  @Test(
    "Toolbar-strip buttons inherit the Panel's scope path so commands registered at the Panel are visible from toolbar focus"
  )
  func toolbarStripInheritsPanelScope() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Save",
              icon: nil,
              position: .top,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultTopToolbarStyle())

    let context = ResolveContext(identity: testIdentity("toolbar-scope-root"))
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    // Find the Panel node and confirm the toolbar strip sits inside
    // it (not as a sibling). A toolbar whose strip is a sibling of
    // the Panel would leave toolbar-button focus outside the scope
    // boundary — palette/key commands registered at the Panel would
    // then be invisible to toolbar focus.
    guard let panelNode = findNode(in: resolved, where: { isKind($0.kind, named: "Panel") })
    else {
      Issue.record("Panel node not found in resolved tree")
      return
    }
    let hasButtonInsidePanel =
      findNode(
        in: panelNode,
        where: { isKind($0.kind, named: "Button") }
      ) != nil
    #expect(
      hasButtonInsidePanel,
      "expected a Button (toolbar-item button) somewhere inside the Panel subtree"
    )
  }

  @Test("Panel with bottom toolbar renders item titles below the content")
  func toolbarRendersBelowContent() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Close",
              icon: nil,
              position: .bottom,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultBottomToolbarStyle())
      .frame(width: 20, height: 5)

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("toolbar-render-bottom-root"))
    )
    let lines = artifacts.rasterSurface.lines
    let bodyRow = lines.firstIndex { $0.contains("body") }
    let closeRow = lines.firstIndex { $0.contains("Close") }
    #expect(bodyRow != nil)
    #expect(closeRow != nil)
    if let bodyRow, let closeRow {
      // Bottom-placement: toolbar strip must appear below the content.
      #expect(bodyRow < closeRow)
    }
  }

  @Test("Toolbar strip lays out multiple items as distinct siblings")
  func toolbarRendersMultipleItemsWithoutOverlap() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Reset counter",
              icon: nil,
              position: .bottom,
              isEnabled: true,
              action: {}
            )
          )
          .toolbarItem(
            .init(
              title: "⌃K Palette",
              icon: nil,
              position: .bottom,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultBottomToolbarStyle())
      .frame(width: 40, height: 6)

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("toolbar-multi-item-root"))
    )
    let lineContainingBoth = artifacts.rasterSurface.lines.first {
      $0.contains("Reset counter") && $0.contains("⌃K Palette")
    }

    #expect(lineContainingBoth != nil)
  }

  @Test("Bottom toolbar reclaims the container's bottom safe area")
  func bottomToolbarUsesBottomSafeArea() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Close",
              icon: nil,
              position: .bottom,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultBottomToolbarStyle())
      .frame(width: 20, height: 5)

    let artifacts = render(
      panel,
      terminalSize: .init(width: 20, height: 6),
      safeAreaInsets: .init(top: 0, leading: 0, bottom: 1, trailing: 0)
    )
    let lines = artifacts.rasterSurface.lines
    let bodyRow = lines.firstIndex { $0.contains("body") }
    let closeRow = lines.firstIndex { $0.contains("Close") }

    #expect(closeRow != nil)
    #expect(bodyRow != nil)
    if let bodyRow, let closeRow {
      #expect(closeRow == lines.index(before: lines.endIndex))
      #expect(bodyRow < closeRow)
    }
  }
}

@MainActor
private func findNode(
  in root: ResolvedNode,
  where predicate: (ResolvedNode) -> Bool
) -> ResolvedNode? {
  var stack: [ResolvedNode] = [root]
  while let node = stack.popLast() {
    if predicate(node) { return node }
    stack.append(contentsOf: node.children)
  }
  return nil
}

@MainActor
private func isKind(_ kind: NodeKind, named name: String) -> Bool {
  if case .view(let n) = kind, n == name { return true }
  return false
}

@MainActor
private func render<V: View>(
  _ view: V,
  terminalSize: CellSize,
  safeAreaInsets: EdgeInsets
) -> FrameArtifacts {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalSize = terminalSize
  environmentValues.safeAreaInsets = safeAreaInsets
  return DefaultRenderer().render(
    view,
    context: .init(
      identity: testIdentity("toolbar-safe-area-root"),
      environmentValues: environmentValues
    ),
    proposal: .init(
      width: terminalSize.width,
      height: terminalSize.height
    )
  )
}
