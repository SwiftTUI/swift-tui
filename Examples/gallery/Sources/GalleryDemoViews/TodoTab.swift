import SwiftTUI

struct TodoTab: View {
  @State private var items: [TodoItem] = TodoItem.seeds
  @State private var filter: TodoFilter = .all
  @State private var isPresentingNew: Bool = false
  @State private var draftTitle: String = ""
  @State private var draftPriority: TodoPriority = .normal

  private var visibleItems: [TodoItem] {
    items.filter(filter.matches)
  }

  private var remaining: Int {
    items.filter { !$0.done }.count
  }

  private var canAddDraft: Bool {
    !draftTitle.trimmingCharacters(in: .whitespaces).isEmpty
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
    .sheet("New task", isPresented: $isPresentingNew) {
      newTaskSheetBody
    }
    .toolbarItem(
      .init(
        title: "New task",
        action: {
          draftTitle = ""
          draftPriority = .normal
          isPresentingNew = true
        }
      )
    )
    .toolbarItem(
      .init(
        title: "Clear done",
        isEnabled: items.contains(where: \.done),
        action: {
          items.removeAll { $0.done }
        }
      )
    )
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
      Button("+ New task") {
        draftTitle = ""
        draftPriority = .normal
        isPresentingNew = true
      }
      Spacer()
      Button("Clear ✓") {
        items.removeAll { $0.done }
      }
    }
  }

  private var newTaskSheetBody: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Title").foregroundStyle(.separator)
      TextField("What needs doing?", text: $draftTitle)
      Text("Priority").foregroundStyle(.separator)
      Picker("Priority", selection: $draftPriority) {
        ForEach(TodoPriority.allCases) { option in
          Text(option.label).tag(option)
        }
      }

      Spacer(minLength: 1)

      HStack(spacing: 2) {
        Spacer()
        Button("Cancel", role: .cancel) {
          isPresentingNew = false
        }
        Button("Add") {
          addDraft()
        }
        .disabled(!canAddDraft)
      }
    }
    .padding(1)
  }

  private func addDraft() {
    let trimmed = draftTitle.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    items.append(
      TodoItem(title: trimmed, priority: draftPriority)
    )
    draftTitle = ""
    draftPriority = .normal
    isPresentingNew = false
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
