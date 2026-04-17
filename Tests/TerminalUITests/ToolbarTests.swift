import Testing

@testable import Core
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
}
