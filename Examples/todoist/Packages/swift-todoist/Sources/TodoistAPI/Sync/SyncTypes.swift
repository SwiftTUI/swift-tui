import Foundation

public let MAX_COMMAND_COUNT = 100

public enum SyncCommandType: String, Codable, Sendable {
  case itemAdd = "item_add"
  case itemUpdate = "item_update"
  case itemComplete = "item_complete"
  case itemCompleteUndo = "item_complete_undo"
  case itemMove = "item_move"
  case itemReorder = "item_reorder"
  case itemUncomplete = "item_uncomplete"
  case itemUpdateDateComplete = "item_update_date_complete"
  case itemDelete = "item_delete"
  case itemUpdateDayOrders = "item_update_day_orders"
  case projectAdd = "project_add"
  case projectUpdate = "project_update"
  case projectMove = "project_move"
  case projectReorder = "project_reorder"
  case shareProject = "share_project"
  case projectLeave = "project_leave"
  case projectArchive = "project_archive"
  case projectUnarchive = "project_unarchive"
  case projectDelete = "project_delete"
  case projectMoveToWorkspace = "project_move_to_workspace"
  case projectMoveToPersonal = "project_move_to_personal"
  case sectionAdd = "section_add"
  case sectionUpdate = "section_update"
  case sectionMove = "section_move"
  case sectionReorder = "section_reorder"
  case sectionArchive = "section_archive"
  case sectionUnarchive = "section_unarchive"
  case sectionDelete = "section_delete"
  case labelAdd = "label_add"
  case labelRename = "label_rename"
  case labelUpdate = "label_update"
  case labelUpdateOrders = "label_update_orders"
  case labelDelete = "label_delete"
  case labelDeleteOccurrences = "label_delete_occurrences"
  case filterAdd = "filter_add"
  case filterUpdate = "filter_update"
  case filterUpdateOrders = "filter_update_orders"
  case filterDelete = "filter_delete"
  case noteAdd = "note_add"
  case noteUpdate = "note_update"
  case noteDelete = "note_delete"
  case noteReactionAdd = "note_reaction_add"
  case noteReactionRemove = "note_reaction_remove"
  case reminderAdd = "reminder_add"
  case reminderUpdate = "reminder_update"
  case reminderDelete = "reminder_delete"
  case workspaceAdd = "workspace_add"
  case workspaceUpdate = "workspace_update"
  case workspaceDelete = "workspace_delete"
  case workspaceUpdateUser = "workspace_update_user"
  case workspaceDeleteUser = "workspace_delete_user"
  case workspaceLeave = "workspace_leave"
  case workspaceInvite = "workspace_invite"
  case workspaceSetDefaultProjectOrdering = "workspace_set_default_project_ordering"
  case workspaceUpdateUserProjectSortPreference = "workspace_update_user_project_sort_preference"
  case folderAdd = "folder_add"
  case folderUpdate = "folder_update"
  case folderDelete = "folder_delete"
  case workspaceFilterAdd = "workspace_filter_add"
  case workspaceFilterUpdate = "workspace_filter_update"
  case workspaceFilterUpdateOrders = "workspace_filter_update_orders"
  case workspaceFilterDelete = "workspace_filter_delete"
  case workspaceGoalAdd = "workspace_goal_add"
  case workspaceGoalUpdate = "workspace_goal_update"
  case workspaceGoalDelete = "workspace_goal_delete"
  case workspaceGoalProjectAdd = "workspace_goal_project_add"
  case workspaceGoalProjectRemove = "workspace_goal_project_remove"
  case liveNotificationsMarkUnread = "live_notifications_mark_unread"
  case liveNotificationsMarkRead = "live_notifications_mark_read"
  case liveNotificationsMarkReadAll = "live_notifications_mark_read_all"
  case liveNotificationsSetLastRead = "live_notifications_set_last_read"
  case acceptInvitation = "accept_invitation"
  case rejectInvitation = "reject_invitation"
  case bizAcceptInvitation = "biz_accept_invitation"
  case bizRejectInvitation = "biz_reject_invitation"
  case viewOptionsSet = "view_options_set"
  case viewOptionsDelete = "view_options_delete"
  case projectViewOptionsDefaultsSet = "project_view_options_defaults_set"
  case calendarUpdate = "calendar_update"
  case calendarAccountUpdate = "calendar_account_update"
  case calendarAccountRestoreTaskCalendar = "calendar_account_restore_task_calendar"
  case userUpdate = "user_update"
  case userSettingsUpdate = "user_settings_update"
  case updateGoals = "update_goals"
  case deleteCollaborator = "delete_collaborator"
  case idMapping = "id_mapping"
  case suggestionDelete = "suggestion_delete"
}

public struct SyncCommand: Codable {
  public let type: SyncCommandType
  public let uuid: String
  public let args: [String: AnyCodable]
  public let tempId: String?

  public init(
    type: SyncCommandType,
    uuid: String = UUID().uuidString,
    args: [String: AnyCodable],
    tempId: String? = nil,
  ) {
    self.type = type
    self.uuid = uuid
    self.args = args
    self.tempId = tempId
  }
}

public struct SyncRequest: Codable {
  public let commands: [SyncCommand]?
  public let resourceTypes: [String]?
  public let syncToken: String?

  public init(
    commands: [SyncCommand]? = nil, resourceTypes: [String]? = nil, syncToken: String? = nil
  ) {
    self.commands = commands
    self.resourceTypes = resourceTypes
    self.syncToken = syncToken
  }
}

public struct SyncResponse: Codable {
  public struct SyncError: Codable {
    public let error: String
    public let errorExtra: [String: AnyCodable]?
    public let errorCode: Int?
    public let errorTag: String?
    public let httpCode: Int
  }

  public let syncToken: String?
  public let fullSync: Bool?
  public let syncStatus: [String: SyncStatusValue]?
  public let tempIdMapping: [String: String]?
  public let items: [Task]?
  public let projects: [Project]?
  public let sections: [Section]?
  public let labels: [Label]?
  public let reminders: [Reminder]?

  public init(
    syncToken: String? = nil,
    fullSync: Bool? = nil,
    syncStatus: [String: SyncStatusValue]? = nil,
    tempIdMapping: [String: String]? = nil,
    items: [Task]? = nil,
    projects: [Project]? = nil,
    sections: [Section]? = nil,
    labels: [Label]? = nil,
    reminders: [Reminder]? = nil,
  ) {
    self.syncToken = syncToken
    self.fullSync = fullSync
    self.syncStatus = syncStatus
    self.tempIdMapping = tempIdMapping
    self.items = items
    self.projects = projects
    self.sections = sections
    self.labels = labels
    self.reminders = reminders
  }
}

public enum SyncStatusValue: Codable {
  case ok
  case error(SyncResponse.SyncError)

  public init(from decoder: Decoder) throws {
    if let container = try? decoder.singleValueContainer(),
      let stringValue = try? container.decode(String.self),
      stringValue == "ok"
    {
      self = .ok
      return
    }

    let error = try SyncResponse.SyncError(from: decoder)
    self = .error(error)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .ok:
      try container.encode("ok")
    case .error(let error):
      try container.encode(error)
    }
  }
}

public let DATE_FORMATS = ["DD/MM/YYYY", "MM/DD/YYYY"] as [String]
public let TIME_FORMATS = ["24h", "12h"] as [String]
public let DAYS_OF_WEEK =
  ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] as [String]

public let DATE_FORMAT_TO_API: [String: Int] = [
  "DD/MM/YYYY": 0,
  "MM/DD/YYYY": 1,
]
public let TIME_FORMAT_TO_API: [String: Int] = [
  "24h": 0,
  "12h": 1,
]
public let DAY_OF_WEEK_TO_API: [String: Int] = [
  "Monday": 1,
  "Tuesday": 2,
  "Wednesday": 3,
  "Thursday": 4,
  "Friday": 5,
  "Saturday": 6,
  "Sunday": 7,
]

public let REMINDER_TYPE_ABSOLUTE = "absolute"
public let REMINDER_TYPE_RELATIVE = "relative"
public let REMINDER_TYPE_LOCATION = "location"
