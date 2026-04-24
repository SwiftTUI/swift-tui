import Layouts
import TerminalUI

/// Full-screen picker: a sectioned list of every ``LayoutEntry`` in
/// ``LayoutCatalog/all``, grouped by ``LayoutEntry/Category``.
/// Selecting an entry calls `onSelect` with its ID; the parent
/// ``LayoutsRoot`` flips into the detail host.
struct LayoutPicker: View {
  let onSelect: (LayoutEntry.ID) -> Void

  @State private var selection: LayoutEntry.ID?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      List(selection: $selection) {
        ForEach(LayoutEntry.Category.allCases, id: \.rawValue) { category in
          let entries = LayoutCatalog.all.filter { $0.category == category }
          if !entries.isEmpty {
            Section(category.rawValue) {
              ForEach(entries, id: \.id) { entry in
                row(entry)
              }
            }
          }
        }
      }
      .listStyle(.plain)
      Divider()
      footer
    }
    .onChange(of: selection) { _, newValue in
      if let id = newValue {
        onSelect(id)
        // Clear selection so returning to the picker doesn't re-open
        // the same entry on the next render.
        selection = nil
      }
    }
    .panel(id: "layouts.picker")
  }

  private func row(_ entry: LayoutEntry) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(entry.title).foregroundStyle(.foreground)
      Text(entry.blurb).foregroundStyle(.separator)
    }
    .tag(entry.id)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("TerminalUI — Layouts").foregroundStyle(.foreground)
      Text(
        "\(LayoutCatalog.all.count) layouts across \(LayoutEntry.Category.allCases.count) categories"
      )
      .foregroundStyle(.separator)
    }
    .padding(.horizontal, 1)
  }

  private var footer: some View {
    Text("↑↓ move  ·  ⏎ open  ·  ⌃C quit").foregroundStyle(.muted)
      .padding(.horizontal, 1)
  }
}
