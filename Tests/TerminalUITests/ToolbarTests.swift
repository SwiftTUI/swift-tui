import Testing

@testable import Core
@testable import TerminalUI
@testable import View

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
}
