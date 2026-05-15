import Layouts
import SwiftTUIRuntime

struct TUILayoutComparisonApp: App {
  private let entryID: String

  nonisolated init() {
    entryID = LayoutCatalog.all.first?.id ?? ""
  }

  nonisolated init(entryID: String) {
    self.entryID = entryID
  }

  var body: some Scene {
    WindowGroup("SwiftTUI", id: "comparison") {
      if let entry = LayoutCatalog.entry(id: entryID) {
        TUILayoutComparisonRoot(entry: entry)
      } else {
        Text("Missing layout: \(entryID)")
          .padding(1)
      }
    }
    .exitOnKeys([])
  }
}

private struct TUILayoutComparisonRoot: View {
  let entry: LayoutEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      entry.makeView()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      Divider()
      Text("SwiftTUI / \(entry.category.rawValue) / \(entry.title)")
        .foregroundStyle(.muted)
        .padding(.horizontal, 1)
    }
    .panel(id: "layouts.embedded.\(entry.id)")
  }
}
