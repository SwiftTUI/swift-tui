import SwiftUI
import SwiftUIHost
import SwiftUILayouts

private typealias NativeLayoutCatalog = SwiftUILayouts.LayoutCatalog
private typealias NativeLayoutEntry = SwiftUILayouts.LayoutEntry

@main
struct LayoutsApp: SwiftUI::App {
  var body: some SwiftUI::Scene {
    SwiftUI.WindowGroup {
      LayoutsRoot()
    }
  }
}

struct LayoutsRoot: SwiftUI::View {
  @SwiftUI::State private var selectedID = NativeLayoutCatalog.all.first?.id

  var body: some SwiftUI::View {
    SwiftUI.HStack(spacing: 0) {
      LayoutSidebar(selectedID: $selectedID)
        .frame(minWidth: 260, idealWidth: 320, maxWidth: 360)

      SwiftUI.Divider()

      if let selectedEntry {
        LayoutComparisonDetail(entry: selectedEntry)
      } else {
        SwiftUI.ContentUnavailableView("No Layout", systemImage: "rectangle.split.2x1")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private var selectedEntry: NativeLayoutEntry? {
    guard let selectedID else {
      return nil
    }

    return NativeLayoutCatalog.entry(id: selectedID)
  }
}

private struct LayoutSidebar: SwiftUI::View {
  @SwiftUI::Binding var selectedID: NativeLayoutEntry.ID?

  var body: some SwiftUI::View {
    SwiftUI.VStack(alignment: .leading, spacing: 0) {
      SwiftUI.VStack(alignment: .leading, spacing: 4) {
        SwiftUI.Text("Layouts")
          .font(.title2.weight(.semibold))
        SwiftUI.Text("\(NativeLayoutCatalog.all.count) examples")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding()

      SwiftUI.Divider()

      SwiftUI.ScrollView {
        SwiftUI.LazyVStack(alignment: .leading, spacing: 14) {
          SwiftUI.ForEach(NativeLayoutEntry.Category.allCases, id: \.rawValue) { category in
            let entries = NativeLayoutCatalog.all.filter { $0.category == category }
            if !entries.isEmpty {
              LayoutSidebarSection(
                category: category,
                entries: entries,
                selectedID: $selectedID
              )
            }
          }
        }
        .padding(12)
      }
    }
    .background(.background)
  }
}

private struct LayoutSidebarSection: SwiftUI::View {
  let category: NativeLayoutEntry.Category
  let entries: [NativeLayoutEntry]
  @SwiftUI::Binding var selectedID: NativeLayoutEntry.ID?

  var body: some SwiftUI::View {
    SwiftUI.VStack(alignment: .leading, spacing: 4) {
      SwiftUI.Text(category.rawValue)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 6)

      SwiftUI.VStack(alignment: .leading, spacing: 2) {
        SwiftUI.ForEach(entries) { entry in
          SwiftUI.Button {
            selectedID = entry.id
          } label: {
            LayoutSidebarRow(
              entry: entry,
              isSelected: selectedID == entry.id
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

private struct LayoutSidebarRow: SwiftUI::View {
  let entry: NativeLayoutEntry
  let isSelected: Bool

  var body: some SwiftUI::View {
    SwiftUI.VStack(alignment: .leading, spacing: 2) {
      SwiftUI.Text(entry.title)
        .font(.callout.weight(isSelected ? .semibold : .regular))
        .foregroundStyle(.primary)
        .lineLimit(1)
      SwiftUI.Text(entry.blurb)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background {
      SwiftUI.RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? SwiftUI.Color.accentColor.opacity(0.14) : SwiftUI.Color.clear)
    }
    .contentShape(SwiftUI.Rectangle())
  }
}

private struct LayoutComparisonDetail: SwiftUI::View {
  let entry: NativeLayoutEntry

  var body: some SwiftUI::View {
    SwiftUI.VStack(alignment: .leading, spacing: 0) {
      SwiftUI.VStack(alignment: .leading, spacing: 4) {
        SwiftUI.Text(entry.title)
          .font(.title2.weight(.semibold))
        SwiftUI.Text(entry.blurb)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding()

      SwiftUI.Divider()

      SwiftUI.HStack(spacing: 0) {
        LayoutComparisonPane(title: "SwiftUI") {
          entry.makeView()
            .frame(width: 500, height: 500, alignment: .topLeading)
        }

        SwiftUI.Divider()

        LayoutComparisonPane(title: "SwiftTUI") {
          EmbeddedTUILayoutSurface(entryID: entry.id)
            .frame(width: 500, height: 500)
        }
      }
    }
    .id(entry.id)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct LayoutComparisonPane<Content: SwiftUI::View>: SwiftUI::View {
  let title: String
  @SwiftUI::ViewBuilder var content: () -> Content

  var body: some SwiftUI::View {
    SwiftUI.VStack(alignment: .leading, spacing: 0) {
      SwiftUI.Text(title)
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)

      SwiftUI.Divider()

      SwiftUI.ScrollView([.horizontal, .vertical]) {
        content()
          .padding(16)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

@MainActor
private struct EmbeddedTUILayoutSurface: SwiftUI::View {
  let entryID: String

  @SwiftUI::State private var state: SwiftUIHostAppState<TUILayoutComparisonApp>?
  @SwiftUI::State private var launchError: String?

  var body: some SwiftUI::View {
    SwiftUI.Group {
      if let state {
        SwiftUIHostAppView(state: state)
      } else if let launchError {
        SwiftUI.ContentUnavailableView {
          SwiftUI.Label("SwiftTUI Launch Failed", systemImage: "exclamationmark.triangle")
        } description: {
          SwiftUI.Text(launchError)
        }
      } else {
        SwiftUI.ProgressView()
      }
    }
    .task(id: entryID) {
      rebuildState()
    }
    .onDisappear {
      state?.stop()
    }
  }

  private func rebuildState() {
    state?.stop()

    do {
      state = try SwiftUIHostAppState(
        app: TUILayoutComparisonApp(entryID: entryID),
        style: SwiftUIHostTerminalStyle(
          fontSize: 12,
          cursorBlink: false
        )
      )
      launchError = nil
    } catch {
      state = nil
      launchError = String(describing: error)
    }
  }
}
