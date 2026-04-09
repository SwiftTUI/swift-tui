import Foundation
import GRDB
import Testing

@testable import TodoistDemo

@Suite
struct TodoistCachePersistenceTests {
  @Test("Cached Todoist records persist using the SQLite schema column names")
  func cachedRecordsPersistUsingSchemaColumnNames() throws {
    let dbQueue = try DatabaseQueue(path: ":memory:")

    try dbQueue.write { db in
      try db.execute(
        sql: """
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_favorite BOOLEAN NOT NULL DEFAULT 0,
            is_inbox_project BOOLEAN NOT NULL DEFAULT 0,
            is_archived BOOLEAN NOT NULL DEFAULT 0,
            is_deleted BOOLEAN NOT NULL DEFAULT 0,
            child_order INTEGER,
            color_name TEXT,
            updated_at TEXT
          )
          """)

      try db.execute(
        sql: """
          CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            project_id TEXT,
            content TEXT NOT NULL,
            details_text TEXT,
            priority INTEGER,
            checked BOOLEAN NOT NULL DEFAULT 0,
            is_deleted BOOLEAN NOT NULL DEFAULT 0,
            child_order INTEGER,
            due_text TEXT,
            updated_at TEXT
          )
          """)

      try CachedProject(
        id: "project-1",
        name: "Inbox",
        isFavorite: true,
        isInboxProject: true,
        isArchived: false,
        isDeleted: false,
        childOrder: 3,
        colorName: "charcoal",
        updatedAt: "2026-03-30T00:00:00Z"
      ).save(db)

      try CachedTask(
        id: "task-1",
        projectID: "project-1",
        content: "Ship fix",
        detailsText: "Ensure GRDB uses snake_case columns",
        priority: 1,
        checked: false,
        isDeleted: false,
        childOrder: 2,
        dueText: "today",
        updatedAt: "2026-03-30T00:00:00Z"
      ).save(db)

      let projectIsFavorite = try Bool.fetchOne(
        db,
        sql: "SELECT is_favorite FROM projects WHERE id = ?",
        arguments: ["project-1"]
      )
      let taskProjectID = try String.fetchOne(
        db,
        sql: "SELECT project_id FROM tasks WHERE id = ?",
        arguments: ["task-1"]
      )
      let taskDetails = try String.fetchOne(
        db,
        sql: "SELECT details_text FROM tasks WHERE id = ?",
        arguments: ["task-1"]
      )

      #expect(projectIsFavorite == true)
      #expect(taskProjectID == "project-1")
      #expect(taskDetails == "Ensure GRDB uses snake_case columns")
    }
  }
}
