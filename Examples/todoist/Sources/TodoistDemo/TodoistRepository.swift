import Foundation
import GRDB
import StructuredQueries
import StructuredQueriesSQLite
import TodoistAPI

actor TodoistRepository {
  private let dbQueue: DatabaseQueue
  private let databaseURL: URL
  private let authToken: String?

  init(databaseURL: URL, authToken: String?) throws {
    self.databaseURL = databaseURL
    let trimmedToken = authToken?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.authToken = trimmedToken

    let directoryURL = databaseURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    dbQueue = try DatabaseQueue(path: databaseURL.path)

    try Self.migrator.migrate(dbQueue)
  }

  var isAuthenticated: Bool {
    authToken?.isEmpty == false
  }

  func loadSnapshot() throws -> TodoistSnapshot {
    try dbQueue.read { db in
      let projectRequest: SQLRequest<CachedProject> = request(
        for: CachedProject.activeProjectsQuery)
      let taskRequest: SQLRequest<CachedTask> = request(for: CachedTask.activeTasksQuery)
      let lastSyncRequest: SQLRequest<String> = request(
        for: CacheSetting.valueQuery(for: "last_sync_at"))

      let projects = try CachedProject.fetchAll(db, projectRequest)
      let tasks = try CachedTask.fetchAll(db, taskRequest)
      let projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
      let lastSyncAt = try String.fetchOne(db, lastSyncRequest)

      return TodoistSnapshot(
        projects: projects.map(\.summary),
        tasks: tasks.map { $0.summary(projectName: $0.projectID.flatMap { projectNames[$0] }) },
        lastSyncAt: lastSyncAt,
        databasePath: databaseURL.path,
        isAuthenticated: isAuthenticated
      )
    }
  }

  func sync() async throws -> TodoistSnapshot {
    let client = try makeClient()

    let remoteProjects = try await fetchAllProjects(using: client)
    let remoteTasks = try await fetchAllTasks(using: client)
    let syncTimestamp = Self.timestamp()

    try await dbQueue.write { db in
      try db.execute(sql: "DELETE FROM tasks")
      try db.execute(sql: "DELETE FROM projects")

      for project in remoteProjects {
        try CachedProject(remote: project).save(db)
      }
      for task in remoteTasks {
        try CachedTask(remote: task).save(db)
      }

      try CacheSetting(key: "last_sync_at", value: syncTimestamp).save(db)
    }

    return try loadSnapshot()
  }

  func addTask(content: String, projectID: String?) async throws -> TodoistSnapshot {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw TodoistRepositoryError.emptyTaskContent
    }
    let client = try makeClient()

    let task = try await client.tasks.create(
      .init(
        content: trimmed,
        projectId: projectID
      )
    )

    let syncTimestamp = Self.timestamp()

    try await dbQueue.write { db in
      try CachedTask(remote: task).save(db)
      try CacheSetting(
        key: "last_sync_at",
        value: syncTimestamp
      ).save(db)
    }

    return try loadSnapshot()
  }

  func closeTask(id: String) async throws -> TodoistSnapshot {
    let client = try makeClient()

    _ = try await client.tasks.close(id)

    let syncTimestamp = Self.timestamp()

    try await dbQueue.write { db in
      try db.execute(
        sql: "DELETE FROM tasks WHERE id = ?",
        arguments: [id]
      )
      try CacheSetting(
        key: "last_sync_at",
        value: syncTimestamp
      ).save(db)
    }

    return try loadSnapshot()
  }
}

extension TodoistRepository {
  private func makeClient() throws -> TodoistClient {
    guard let authToken, !authToken.isEmpty else {
      throw TodoistRepositoryError.missingAuthToken
    }
    return TodoistClient(authToken: authToken)
  }

  private static let migrator: DatabaseMigrator = {
    var migrator = DatabaseMigrator()

    migrator.registerMigration("todoist_demo_v1") { db in
      try db.create(table: "projects") { table in
        table.column("id", .text).primaryKey()
        table.column("name", .text).notNull()
        table.column("is_favorite", .boolean).notNull().defaults(to: false)
        table.column("is_inbox_project", .boolean).notNull().defaults(to: false)
        table.column("is_archived", .boolean).notNull().defaults(to: false)
        table.column("is_deleted", .boolean).notNull().defaults(to: false)
        table.column("child_order", .integer)
        table.column("color_name", .text)
        table.column("updated_at", .text)
      }

      try db.create(table: "tasks") { table in
        table.column("id", .text).primaryKey()
        table.column("project_id", .text)
        table.column("content", .text).notNull()
        table.column("details_text", .text)
        table.column("priority", .integer)
        table.column("checked", .boolean).notNull().defaults(to: false)
        table.column("is_deleted", .boolean).notNull().defaults(to: false)
        table.column("child_order", .integer)
        table.column("due_text", .text)
        table.column("updated_at", .text)
      }

      try db.create(table: "cache_settings") { table in
        table.column("key", .text).primaryKey()
        table.column("value", .text).notNull()
      }
    }

    return migrator
  }()

  private func fetchAllProjects(using client: TodoistClient) async throws -> [TodoistAPI.Project] {
    var results: [TodoistAPI.Project] = []
    var cursor: String?

    repeat {
      let page = try await client.projects.list(cursor: cursor, limit: 200)
      results.append(contentsOf: page.results)
      cursor = page.nextCursor
    } while cursor != nil

    return results
  }

  private func fetchAllTasks(using client: TodoistClient) async throws -> [TodoistAPI.Task] {
    var results: [TodoistAPI.Task] = []
    var cursor: String?

    repeat {
      let page = try await client.tasks.list(.init(cursor: cursor, limit: 200))
      results.append(contentsOf: page.results)
      cursor = page.nextCursor
    } while cursor != nil

    return results
  }

  private func request<RowDecoder>(
    for query: QueryFragment
  ) -> SQLRequest<RowDecoder> {
    let prepared = query.prepare { _ in "?" }
    return SQLRequest<RowDecoder>(
      sql: prepared.sql,
      arguments: StatementArguments(prepared.bindings.compactMap(Self.bindingValue))
    )
  }

  private static func bindingValue(
    _ binding: QueryBinding
  ) -> (any DatabaseValueConvertible)? {
    switch binding {
    case .blob(let blob):
      return Data(blob)
    case .bool(let bool):
      return bool
    case .double(let double):
      return double
    case .date(let date):
      return date
    case .int(let int):
      return int
    case .null:
      return nil
    case .text(let text):
      return text
    case .uint(let uint):
      return uint
    case .uuid(let uuid):
      return uuid
    case .invalid(let error):
      return String(describing: error.underlyingError)
    }
  }

  private static func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
  }
}
