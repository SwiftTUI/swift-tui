import Foundation

struct TodoItem: Identifiable, Hashable {
  let id: UUID
  var title: String
  var priority: TodoPriority
  var done: Bool

  init(
    id: UUID = UUID(),
    title: String,
    priority: TodoPriority = .normal,
    done: Bool = false
  ) {
    self.id = id
    self.title = title
    self.priority = priority
    self.done = done
  }
}

extension TodoItem {
  static let seeds: [TodoItem] = [
    TodoItem(title: "Write docs", priority: .high),
    TodoItem(title: "Ship release", priority: .high, done: true),
    TodoItem(title: "Water plants", priority: .normal),
    TodoItem(title: "Call mum", priority: .low),
  ]
}

enum TodoFilter: String, CaseIterable, Identifiable, Hashable {
  case all
  case active
  case done

  var id: String { rawValue }

  var label: String {
    switch self {
    case .all: "All"
    case .active: "Active"
    case .done: "Done"
    }
  }

  func matches(_ item: TodoItem) -> Bool {
    switch self {
    case .all: true
    case .active: !item.done
    case .done: item.done
    }
  }
}

enum TodoPriority: String, CaseIterable, Identifiable, Hashable {
  case low
  case normal
  case high

  var id: String { rawValue }

  var label: String {
    switch self {
    case .low: "Low"
    case .normal: "Normal"
    case .high: "High"
    }
  }
}
