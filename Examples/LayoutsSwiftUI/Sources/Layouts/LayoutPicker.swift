import SwiftUI

/// Full-screen picker: a sectioned list of every ``LayoutEntry`` in
/// ``LayoutCatalog/all``, grouped by ``LayoutEntry/Category``.
/// Selecting an entry calls `onSelect` with its ID; the parent
/// `LayoutsRoot` flips into the detail host.
///
/// SwiftUI port: the original used SwiftTUI's
/// `List(selection:onActivate:)`, which combines selection binding
/// and an activation callback. SwiftUI's `List(selection:)` only
/// binds selection; activation comes through tap or `.onChange`.
/// This port forwards changes via `.onChange(of: selection)`.
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
      .onChange(of: selection) { _, newValue in
        if let newValue { onSelect(newValue) }
      }
      Divider()
      footer
    }
  }

  private func row(_ entry: LayoutEntry) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(entry.title).foregroundStyle(.primary)
      Text(entry.blurb).foregroundStyle(.tertiary)
    }
    .tag(entry.id)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("SwiftUI — Layouts").foregroundStyle(.primary)
      Text(
        "\(LayoutCatalog.all.count) layouts across \(LayoutEntry.Category.allCases.count) categories"
      )
      .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, cell(1))
  }

  private var footer: some View {
    Text("↑↓ move  ·  ⏎ open  ·  click open  ·  ⌃C quit").foregroundStyle(.secondary)
      .padding(.horizontal, cell(1))
  }
}
