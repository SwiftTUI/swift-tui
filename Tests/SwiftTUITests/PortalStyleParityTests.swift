import SwiftTUIRuntime
import SwiftTUIViews
import Testing

@MainActor
struct PortalStyleParityTests {
  @Test(
    "Boolean and item declarations share the same automatic and dropdown rasters",
    arguments: [12, 60], [10, 24])
  func declarationParity(width: Int, height: Int) {
    let pairs: [(PortalParityFixture.Kind, PortalParityFixture.Kind)] = [
      (.alert, .alertItem), (.confirmation, .confirmationItem),
      (.sheet, .sheetItem), (.dropdown, .dropdownItem),
      (.cover, .coverItem), (.popover, .popoverItem),
    ]
    for (boolean, item) in pairs {
      let first = render(boolean, width: width, height: height)
      let second = render(item, width: width, height: height)
      let equal = first.rasterSurface == second.rasterSurface
      #expect(equal, "\(boolean): \(first.rasterSurface.lines) / \(second.rasterSurface.lines)")
    }
  }

  private func render(_ kind: PortalParityFixture.Kind, width: Int, height: Int) -> RenderSnapshot {
    DefaultRenderer().render(
      PortalParityFixture(kind: kind),
      context: .init(
        identity: Identity(components: ["PortalParity"]), applyEnvironmentValues: true),
      proposal: .init(width: width, height: height))
  }
}

private struct PortalParityFixture: View {
  enum Kind: CaseIterable {
    case alert, alertItem, confirmation, confirmationItem
    case sheet, sheetItem, dropdown, dropdownItem, cover, coverItem, popover, popoverItem
  }
  struct Item: Identifiable, Sendable { let id = 1 }
  let kind: Kind
  @ViewBuilder var body: some View {
    switch kind {
    case .alert:
      Text("Base").alert("Title", isPresented: .constant(true), actions: actions, message: message)
    case .alertItem:
      Text("Base").alert(
        "Title", item: .constant(Item()), actions: { _ in actions() }, message: { _ in message() })
    case .confirmation:
      Text("Base").confirmationDialog(
        "Title", isPresented: .constant(true), actions: actions, message: message)
    case .confirmationItem:
      Text("Base").confirmationDialog(
        "Title", item: .constant(Item()), actions: { _ in actions() }, message: { _ in message() })
    case .sheet:
      Text("Base").sheet("Title", isPresented: .constant(true), content: message)
    case .sheetItem:
      Text("Base").sheet("Title", item: .constant(Item()), content: { _ in message() })
    case .dropdown:
      Text("Base").sheet("Title", isPresented: .constant(true), content: message).sheetStyle(
        .dropdown)
    case .dropdownItem:
      Text("Base").sheet("Title", item: .constant(Item()), content: { _ in message() }).sheetStyle(
        .dropdown)
    case .cover:
      Text("Base").fullScreenCover(isPresented: .constant(true), content: message)
    case .coverItem:
      Text("Base").fullScreenCover(item: .constant(Item()), content: { _ in message() })
    case .popover:
      Text("Base").popover(isPresented: .constant(true), content: message)
    case .popoverItem:
      Text("Base").popover(item: .constant(Item()), content: { _ in message() })
    }
  }
  private func message() -> some View { Text("Message first line\nMessage second line") }
  @ViewBuilder private func actions() -> some View {
    Button("Accept") {}
    Button("Cancel", role: .cancel) {}
  }
}
