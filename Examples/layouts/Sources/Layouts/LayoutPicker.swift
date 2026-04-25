import TerminalUI

/// Full-screen picker: a sectioned list of every ``LayoutEntry`` in
/// ``LayoutCatalog/all``, grouped by ``LayoutEntry/Category``.
/// Selecting an entry calls `onSelect` with its ID; the parent
/// `LayoutsRoot` flips into the detail host.
///
/// Lives in the `Layouts` library (not `LayoutsApp`) so the
/// `LayoutsTests` target can `@testable import Layouts` and rasterise
/// the picker in `PickerShellTests`. Executable targets cannot be
/// reliably `@testable`-imported from a sibling test target; library
/// targets can.
public struct LayoutPicker: View {
  let onSelect: @MainActor @Sendable (LayoutEntry.ID) -> Void

  @State private var selection: LayoutEntry.ID?

  public init(onSelect: @escaping @MainActor @Sendable (LayoutEntry.ID) -> Void) {
    self.onSelect = onSelect
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        List(selection: $selection, onActivate: activate) {
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
      }
      .listStyle(.insetGrouped)
      Divider()
      footer
    }
    .panel(id: "layouts.picker")
  }

  private func activate(_ id: LayoutEntry.ID?) {
    if let id {
      onSelect(id)
    }
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
    Text("↑↓ move  ·  ⏎ open  ·  click open  ·  ⌃C quit").foregroundStyle(.muted)
      .padding(.horizontal, 1)
  }
}
