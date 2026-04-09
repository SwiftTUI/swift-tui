import TerminalUI

struct TodoTab: View {
  @State private var items: [TodoItem] = TodoItem.seeds
  @State private var filter: TodoFilter = .all

  private var visibleItems: [TodoItem] {
    items.filter(filter.matches)
  }

  private var remaining: Int {
    items.filter { !$0.done }.count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      Divider()
      list
      Spacer(minLength: 0)
      footer
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    HStack(spacing: 2) {
      Picker("Filter", selection: $filter) {
        ForEach(TodoFilter.allCases) { option in
          Text(option.label).tag(option)
        }
      }
      Spacer()
      Text("\(remaining) remaining")
        .foregroundStyle(.separator)
    }
  }

  private var list: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(visibleItems) { item in
        row(for: item)
      }
    }
  }

  private func row(for item: TodoItem) -> some View {
    HStack(spacing: 1) {
      Toggle(item.title, isOn: doneBinding(for: item))
      Spacer()
      Button("×", role: .destructive) {
        items.removeAll { $0.id == item.id }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 2) {
      // Placeholder — replaced with "New task" button in Task 5.
      Text(" ")
      Spacer()
      Button("Clear ✓") {
        items.removeAll { $0.done }
      }
    }
  }

  private func doneBinding(for item: TodoItem) -> Binding<Bool> {
    Binding<Bool>(
      get: {
        items.first(where: { $0.id == item.id })?.done ?? false
      },
      set: { newValue in
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
          return
        }
        items[index].done = newValue
      }
    )
  }
}
