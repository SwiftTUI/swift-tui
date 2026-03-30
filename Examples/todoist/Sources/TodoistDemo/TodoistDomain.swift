import Foundation
import GRDB
import StructuredQueries
import StructuredQueriesSQLite
import TodoistAPI

enum ProjectSelection: Hashable, Sendable {
  case all
  case project(String)

  var projectID: String? {
    switch self {
    case .all:
      return nil
    case .project(let id):
      return id
    }
  }
}

struct TodoistSnapshot: Sendable {
  var projects: [ProjectSummary]
  var tasks: [TaskSummary]
  var lastSyncAt: String?
  var databasePath: String
  var isAuthenticated: Bool
}

struct ProjectSummary: Identifiable, Hashable, Sendable {
  var id: String
  var name: String
  var isFavorite: Bool
  var isInboxProject: Bool
  var colorName: String?

  var detailText: String {
    let flags = [
      isInboxProject ? "Inbox" : nil,
      isFavorite ? "Favorite" : nil,
      colorName,
    ].compactMap { $0 }
    return flags.isEmpty ? "Todoist project" : flags.joined(separator: " | ")
  }
}

struct TaskSummary: Identifiable, Hashable, Sendable {
  var id: String
  var projectID: String?
  var projectName: String?
  var content: String
  var details: String?
  var priority: Int?
  var dueText: String?

  var titleText: String {
    content.isEmpty ? "(untitled task)" : content
  }

  var detailText: String {
    let fields: [String] = [
      priority.map { "P\($0)" },
      dueText,
      projectName,
    ].compactMap { value in
      guard let value, !value.isEmpty else { return nil }
      return value
    }

    if let details, !details.isEmpty {
      if fields.isEmpty {
        return details
      }
      return fields.joined(separator: " | ") + " | " + details
    }

    return fields.isEmpty ? "Active task" : fields.joined(separator: " | ")
  }
}

enum TodoistRepositoryError: LocalizedError, Sendable {
  case missingAuthToken
  case emptyTaskContent

  var errorDescription: String? {
    switch self {
    case .missingAuthToken:
      return "Set TODOIST_API_TOKEN to enable live Todoist sync."
    case .emptyTaskContent:
      return "Enter a task title before adding a task."
    }
  }
}

@Table("projects")
struct CachedProject: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable,
  Sendable
{
  static let databaseTableName = "projects"

  let id: String
  var name: String
  @Column("is_favorite") var isFavorite: Bool
  @Column("is_inbox_project") var isInboxProject: Bool
  @Column("is_archived") var isArchived: Bool
  @Column("is_deleted") var isDeleted: Bool
  @Column("child_order") var childOrder: Int?
  @Column("color_name") var colorName: String?
  @Column("updated_at") var updatedAt: String?

  init(
    id: String,
    name: String,
    isFavorite: Bool,
    isInboxProject: Bool,
    isArchived: Bool,
    isDeleted: Bool,
    childOrder: Int? = nil,
    colorName: String? = nil,
    updatedAt: String? = nil
  ) {
    self.id = id
    self.name = name
    self.isFavorite = isFavorite
    self.isInboxProject = isInboxProject
    self.isArchived = isArchived
    self.isDeleted = isDeleted
    self.childOrder = childOrder
    self.colorName = colorName
    self.updatedAt = updatedAt
  }

  init(remote project: TodoistAPI.Project) {
    self.init(
      id: project.id,
      name: project.name,
      isFavorite: project.isFavorite,
      isInboxProject: project.inboxProject ?? false,
      isArchived: project.isArchived,
      isDeleted: project.isDeleted,
      childOrder: project.childOrder,
      colorName: project.color,
      updatedAt: project.updatedAt
    )
  }
}

extension CachedProject {
  static var activeProjectsQuery: QueryFragment {
    Self
      .where {
        !$0.isArchived && !$0.isDeleted
      }
      .order {
        (
          $0.isFavorite.desc(),
          $0.isInboxProject.desc(),
          $0.childOrder.asc(nulls: .last),
          $0.name.collate(.nocase).asc()
        )
      }
      .selectStar()
      .query
  }

  var summary: ProjectSummary {
    ProjectSummary(
      id: id,
      name: name,
      isFavorite: isFavorite,
      isInboxProject: isInboxProject,
      colorName: colorName
    )
  }
}

@Table("tasks")
struct CachedTask: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable
{
  static let databaseTableName = "tasks"

  let id: String
  @Column("project_id") var projectID: String?
  var content: String
  @Column("details_text") var detailsText: String?
  var priority: Int?
  var checked: Bool
  @Column("is_deleted") var isDeleted: Bool
  @Column("child_order") var childOrder: Int?
  @Column("due_text") var dueText: String?
  @Column("updated_at") var updatedAt: String?

  init(
    id: String,
    projectID: String?,
    content: String,
    detailsText: String?,
    priority: Int?,
    checked: Bool,
    isDeleted: Bool,
    childOrder: Int? = nil,
    dueText: String? = nil,
    updatedAt: String? = nil
  ) {
    self.id = id
    self.projectID = projectID
    self.content = content
    self.detailsText = detailsText
    self.priority = priority
    self.checked = checked
    self.isDeleted = isDeleted
    self.childOrder = childOrder
    self.dueText = dueText
    self.updatedAt = updatedAt
  }

  init(remote task: TodoistAPI.Task) {
    self.init(
      id: task.id,
      projectID: task.projectId,
      content: task.content,
      detailsText: task.description,
      priority: task.priority,
      checked: task.checked,
      isDeleted: task.isDeleted,
      childOrder: task.childOrder,
      dueText: task.due?.datetime ?? task.due?.date ?? task.due?.string,
      updatedAt: task.updatedAt
    )
  }

  func summary(projectName: String?) -> TaskSummary {
    TaskSummary(
      id: id,
      projectID: projectID,
      projectName: projectName,
      content: content,
      details: detailsText,
      priority: priority,
      dueText: dueText
    )
  }
}

extension CachedTask {
  static var activeTasksQuery: QueryFragment {
    Self
      .where {
        !$0.checked && !$0.isDeleted
      }
      .order {
        (
          $0.priority.desc(nulls: .last),
          $0.childOrder.asc(nulls: .last),
          $0.content.collate(.nocase).asc()
        )
      }
      .selectStar()
      .query
  }
}

@Table("cache_settings")
struct CacheSetting: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable,
  Sendable
{
  static let databaseTableName = "cache_settings"

  let key: String
  var value: String

  var id: String { key }
}

extension CacheSetting {
  static func valueQuery(for key: String) -> QueryFragment {
    Self
      .where { $0.key.eq(key) }
      .select(\.value)
      .limit(1)
      .query
  }
}
