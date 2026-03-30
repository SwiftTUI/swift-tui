import Foundation
import Observation
import TodoistAPI

@Observable
final class TodoistAppModel: @unchecked Sendable {
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
  var lastErrorDetails: String?

  init(repository: TodoistRepository, databasePath: String, isAuthenticated: Bool) {
    self.repository = repository
    self.databasePath = databasePath
    self.isAuthenticated = isAuthenticated
    statusMessage =
      if isAuthenticated {
        "Ready to sync Todoist."
      } else {
        "Running offline. Set TODOIST_API_TOKEN to enable live sync."
      }
    lastErrorDetails = nil
  }

  static func live(authTokenOverride: String? = nil) throws -> TodoistAppModel {
    let paths = try TodoistDemoConfiguration.paths()
    let authToken =
      if let authTokenOverride {
        authTokenOverride
      } else {
        try TodoistDemoConfiguration.resolvedAuthToken()
      }
    let repository = try TodoistRepository(databaseURL: paths.databaseURL, authToken: authToken)
    return TodoistAppModel(
      repository: repository,
      databasePath: paths.databaseURL.path,
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
    Swift.Task { @MainActor in
      await refresh()
    }
  }

  func requestAddTask() {
    Swift.Task { @MainActor in
      await addTask()
    }
  }

  func requestCloseSelectedTask() {
    Swift.Task { @MainActor in
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
      clearLastError()
      statusMessage =
        "Sync complete. Loaded \(projects.count) projects and \(tasks.count) active tasks."
    } catch {
      recordError(error, summary: "Sync failed. See Last Error in the inspector.")
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
      apply(
        snapshot: try await repository.addTask(
          content: newTaskText, projectID: selectedProject.projectID))
      newTaskText = ""
      clearLastError()
      statusMessage = "Task added."
    } catch {
      recordError(error, summary: "Task creation failed. See Last Error in the inspector.")
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
      clearLastError()
      statusMessage = "Task closed."
    } catch {
      recordError(error, summary: "Closing the task failed. See Last Error in the inspector.")
    }
  }

  @MainActor
  private func reloadCache(statusOverride: String?) async {
    do {
      apply(snapshot: try await repository.loadSnapshot())
      clearLastError()
      if let statusOverride {
        statusMessage = statusOverride
      } else if tasks.isEmpty {
        statusMessage =
          isAuthenticated
          ? "Cache loaded. Press Refresh to pull the latest Todoist data."
          : "Offline cache is empty. Set TODOIST_API_TOKEN and press Refresh."
      }
    } catch {
      recordError(error, summary: "Loading the cache failed. See Last Error in the inspector.")
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

  private func clearLastError() {
    lastErrorDetails = nil
  }

  private func recordError(_ error: Error, summary: String) {
    statusMessage = summary
    lastErrorDetails = Self.errorDetails(for: error)
  }

  private static func errorDetails(for error: Error) -> String {
    if let requestError = error as? TodoistRequestError {
      var lines: [String] = []

      if let decodeLines = decodeErrorLines(for: requestError.message) {
        lines.append(contentsOf: decodeLines)
      } else {
        lines.append("Message: \(requestError.message)")
      }

      if let statusCode = requestError.httpStatusCode {
        lines.append("HTTP Status: \(statusCode)")
      }

      if let responseData = requestError.responseData,
        let body = String(data: responseData, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        !body.isEmpty,
        body != requestError.message
      {
        let preview = body.count > 600 ? String(body.prefix(600)) + "..." : body
        lines.append("Response Body: \(preview)")
      }

      return lines.joined(separator: "\n")
    }

    return "Type: \(String(reflecting: type(of: error)))\nMessage: \(error.localizedDescription)"
  }

  private static func decodeErrorLines(for message: String) -> [String]? {
    let prefix = "Response decoding failed: "
    let separator = " while decoding "

    guard message.hasPrefix(prefix), let separatorRange = message.range(of: separator) else {
      return nil
    }

    let detail = String(message[message.index(message.startIndex, offsetBy: prefix.count)..<separatorRange.lowerBound])
    let type = String(message[separatorRange.upperBound...])

    return [
      "Decode Error: \(detail)",
      "Expected Type: \(type)",
    ]
  }
}
