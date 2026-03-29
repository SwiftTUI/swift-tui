import Foundation
import Observation

@MainActor
@Observable
final class TodoistAppModel {
  @ObservationIgnored private let repository: TodoistRepository
  @ObservationIgnored private var didStart = false

  var projects: [ProjectSummary] = []
  var tasks: [TaskSummary] = []
  var selectedProject: ProjectSelection = .all
  var selectedTaskID = ""
  var searchText = ""
  var newTaskText = ""
  var lastSyncAt: String?
  var databasePath: String
  var isAuthenticated: Bool
  var isBusy = false
  var statusMessage: String

  nonisolated init(repository: TodoistRepository, databasePath: String, isAuthenticated: Bool) {
    self.repository = repository
    self.databasePath = databasePath
    self.isAuthenticated = isAuthenticated
    statusMessage =
      if isAuthenticated {
        "Ready to sync Todoist."
      } else {
        "Running offline. Set TODOIST_API_TOKEN to enable live sync."
      }
  }

  static func live() throws -> TodoistAppModel {
    let databaseURL = try defaultDatabaseURL()
    let authToken = ProcessInfo.processInfo.environment["TODOIST_API_TOKEN"]
    let repository = try TodoistRepository(databaseURL: databaseURL, authToken: authToken)
    return TodoistAppModel(
      repository: repository,
      databasePath: databaseURL.path,
      isAuthenticated: !(authToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    )
  }

  var visibleTasks: [TaskSummary] {
    let filteredByProject = tasks.filter { task in
      guard let selectedProjectID = selectedProject.projectID else {
        return true
      }
      return task.projectID == selectedProjectID
    }

    let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSearch.isEmpty else {
      return filteredByProject
    }

    let needle = trimmedSearch.lowercased()
    return filteredByProject.filter { task in
      task.titleText.lowercased().contains(needle)
        || task.detailText.lowercased().contains(needle)
    }
  }

  var selectedTask: TaskSummary? {
    visibleTasks.first { $0.id == selectedTaskID }
  }

  var canAddTask: Bool {
    isAuthenticated && !isBusy
  }

  var canCloseTask: Bool {
    isAuthenticated && !isBusy && selectedTask != nil
  }

  var subtitleText: String {
    let syncText = lastSyncAt.map { "Last sync \($0)" } ?? "No sync yet"
    return syncText + " | DB " + databasePath
  }

  @MainActor
  func start() async {
    guard !didStart else {
      return
    }
    didStart = true
    await reloadCache(statusOverride: nil)

    if isAuthenticated {
      await refresh()
    }
  }

  func requestRefresh() {
    Task { @MainActor in
      await refresh()
    }
  }

  func requestAddTask() {
    Task { @MainActor in
      await addTask()
    }
  }

  func requestCloseSelectedTask() {
    Task { @MainActor in
      await closeSelectedTask()
    }
  }

  func title(for selection: ProjectSelection) -> String {
    switch selection {
    case .all:
      return "All Tasks"
    case .project(let id):
      return projects.first(where: { $0.id == id })?.name ?? "Project"
    }
  }

  func taskCount(for selection: ProjectSelection) -> Int {
    switch selection {
    case .all:
      return tasks.count
    case .project(let id):
      return tasks.filter { $0.projectID == id }.count
    }
  }
}

extension TodoistAppModel {
  @MainActor
  private func refresh() async {
    guard !isBusy else {
      return
    }

    isBusy = true
    statusMessage = "Syncing Todoist projects and active tasks..."
    defer { isBusy = false }

    do {
      apply(snapshot: try await repository.sync())
      statusMessage = "Sync complete. Loaded \(projects.count) projects and \(tasks.count) active tasks."
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  @MainActor
  private func addTask() async {
    guard !isBusy else {
      return
    }

    isBusy = true
    statusMessage = "Creating task..."
    defer { isBusy = false }

    do {
      apply(snapshot: try await repository.addTask(content: newTaskText, projectID: selectedProject.projectID))
      newTaskText = ""
      statusMessage = "Task added."
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  @MainActor
  private func closeSelectedTask() async {
    guard !isBusy, let task = selectedTask else {
      return
    }

    isBusy = true
    statusMessage = "Closing '\(task.titleText)'..."
    defer { isBusy = false }

    do {
      apply(snapshot: try await repository.closeTask(id: task.id))
      statusMessage = "Task closed."
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  @MainActor
  private func reloadCache(statusOverride: String?) async {
    do {
      apply(snapshot: try await repository.loadSnapshot())
      if let statusOverride {
        statusMessage = statusOverride
      } else if tasks.isEmpty {
        statusMessage =
          isAuthenticated
          ? "Cache loaded. Press Refresh to pull the latest Todoist data."
          : "Offline cache is empty. Set TODOIST_API_TOKEN and press Refresh."
      }
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  @MainActor
  private func apply(snapshot: TodoistSnapshot) {
    projects = snapshot.projects
    tasks = snapshot.tasks
    lastSyncAt = snapshot.lastSyncAt
    databasePath = snapshot.databasePath
    isAuthenticated = snapshot.isAuthenticated

    if !visibleTasks.contains(where: { $0.id == selectedTaskID }) {
      selectedTaskID = ""
    }
  }

  private static func defaultDatabaseURL() throws -> URL {
    let appSupport =
      try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )

    return appSupport
      .appendingPathComponent("swift-terminal-ui")
      .appendingPathComponent("todoist-demo")
      .appendingPathComponent("todoist.sqlite3")
  }
}
