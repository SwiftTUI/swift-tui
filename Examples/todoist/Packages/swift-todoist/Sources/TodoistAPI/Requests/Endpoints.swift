// swift-tools-version: 6.0

import Foundation

public let todoistBaseURL = "https://api.todoist.com"
public let todoistAuthURL = "https://todoist.com"
public let todoistWebURL = "https://app.todoist.com/app"

public let todoistAPIVersion = "v1"
public let todoistAPIBasePath = "/api/\(todoistAPIVersion)/"

public func getSyncBaseURI(domainBase: String = todoistBaseURL) -> String {
    if let url = URL(string: todoistAPIBasePath, relativeTo: URL(string: domainBase)) {
        return url.absoluteString
    }
    return "\(domainBase.replacingOccurrences(of: "/", with: ""))/api/v1/"
}

public func getAuthBaseURI(domainBase: String = todoistAuthURL) -> String {
    if let url = URL(string: "/oauth/", relativeTo: URL(string: domainBase)) {
        return url.absoluteString
    }
    return "\(domainBase.replacingOccurrences(of: "/", with: ""))/oauth/"
}

public let ENDPOINT_REST_TASKS = "tasks"
public let ENDPOINT_REST_TASKS_FILTER = ENDPOINT_REST_TASKS + "/filter"
public let ENDPOINT_REST_TASKS_COMPLETED_BY_COMPLETION_DATE =
    ENDPOINT_REST_TASKS + "/completed/by_completion_date"
public let ENDPOINT_REST_TASKS_COMPLETED_BY_DUE_DATE =
    ENDPOINT_REST_TASKS + "/completed/by_due_date"
public let ENDPOINT_REST_TASKS_COMPLETED_SEARCH = "completed/search"
public let ENDPOINT_REST_TASKS_COMPLETED = ENDPOINT_REST_TASKS + "/completed"
public let ENDPOINT_SYNC_QUICK_ADD = ENDPOINT_REST_TASKS + "/quick"
public let ENDPOINT_REST_TASK_CLOSE = "close"
public let ENDPOINT_REST_TASK_REOPEN = "reopen"
public let ENDPOINT_REST_TASK_MOVE = "move"

public let ENDPOINT_REST_SECTIONS = "sections"
public let ENDPOINT_REST_SECTIONS_SEARCH = ENDPOINT_REST_SECTIONS + "/search"
public let ENDPOINT_REST_PROJECTS = "projects"
public let ENDPOINT_REST_PROJECTS_SEARCH = ENDPOINT_REST_PROJECTS + "/search"
public let ENDPOINT_REST_PROJECTS_ARCHIVED = ENDPOINT_REST_PROJECTS + "/archived"
public let ENDPOINT_REST_PROJECTS_ARCHIVED_COUNT = ENDPOINT_REST_PROJECTS + "/archived/count"
public let ENDPOINT_REST_PROJECTS_PERMISSIONS = ENDPOINT_REST_PROJECTS + "/permissions"
public let ENDPOINT_REST_PROJECTS_MOVE_TO_WORKSPACE = ENDPOINT_REST_PROJECTS + "/move_to_workspace"
public let ENDPOINT_REST_PROJECTS_MOVE_TO_PERSONAL = ENDPOINT_REST_PROJECTS + "/move_to_personal"
public let ENDPOINT_REST_PROJECT_FULL = "full"
public let ENDPOINT_REST_PROJECT_JOIN = "join"
public let PROJECT_ARCHIVE = "archive"
public let PROJECT_UNARCHIVE = "unarchive"

public let SECTION_ARCHIVE = "archive"
public let SECTION_UNARCHIVE = "unarchive"

public let ENDPOINT_REST_LABELS = "labels"
public let ENDPOINT_REST_LABELS_SEARCH = ENDPOINT_REST_LABELS + "/search"
public let ENDPOINT_REST_LABELS_SHARED = ENDPOINT_REST_LABELS + "/shared"
public let ENDPOINT_REST_LABELS_SHARED_RENAME = ENDPOINT_REST_LABELS_SHARED + "/rename"
public let ENDPOINT_REST_LABELS_SHARED_REMOVE = ENDPOINT_REST_LABELS_SHARED + "/remove"

public let ENDPOINT_REST_COMMENTS = "comments"
public let ENDPOINT_REST_REMINDERS = "reminders"
public let ENDPOINT_REST_LOCATION_REMINDERS = "location_reminders"

public let ENDPOINT_REST_USER = "user"
public let ENDPOINT_REST_PRODUCTIVITY = ENDPOINT_REST_TASKS + "/completed/stats"
public let ENDPOINT_REST_ACTIVITIES = "activities"

public let ENDPOINT_REST_UPLOADS = "uploads"
public let ENDPOINT_REST_BACKUPS = "backups"
public let ENDPOINT_REST_BACKUPS_DOWNLOAD = "backups/download"
public let ENDPOINT_REST_TEMPLATES_FILE = "templates/file"
public let ENDPOINT_REST_TEMPLATES_URL = "templates/url"
public let ENDPOINT_REST_TEMPLATES_CREATE_FROM_FILE = "templates/create_project_from_file"
public let ENDPOINT_REST_TEMPLATES_IMPORT_FROM_FILE = "templates/import_into_project_from_file"
public let ENDPOINT_REST_TEMPLATES_IMPORT_FROM_ID = "templates/import_into_project_from_template_id"
public let ENDPOINT_REST_EMAILS = "emails"
public let ENDPOINT_REST_ID_MAPPINGS = "id_mappings"
public let ENDPOINT_REST_MOVED_IDS = "moved_ids"

public let ENDPOINT_SYNC = "sync"

public let ENDPOINT_AUTHORIZATION = "authorize"
public let ENDPOINT_GET_TOKEN = "access_token"
public let ENDPOINT_REVOKE = "revoke"
public let ENDPOINT_REST_ACCESS_TOKENS_MIGRATE = "access_tokens/migrate_personal_token"

public let ENDPOINT_WORKSPACES = "workspaces"
public let ENDPOINT_WORKSPACE_MEMBERS = ENDPOINT_WORKSPACES + "/members"
public let ENDPOINT_WORKSPACE_INVITATIONS = ENDPOINT_WORKSPACES + "/invitations"
public let ENDPOINT_WORKSPACE_INVITATIONS_ALL = ENDPOINT_WORKSPACES + "/invitations/all"
public let ENDPOINT_WORKSPACE_INVITATIONS_DELETE = ENDPOINT_WORKSPACES + "/invitations/delete"
public let ENDPOINT_WORKSPACE_JOIN = ENDPOINT_WORKSPACES + "/join"
public let ENDPOINT_WORKSPACE_USERS = ENDPOINT_WORKSPACES + "/users"
public let ENDPOINT_WORKSPACE_LOGO = ENDPOINT_WORKSPACES + "/logo"
public let ENDPOINT_WORKSPACE_PLAN_DETAILS = ENDPOINT_WORKSPACES + "/plan_details"

public func getWorkspaceInvitationAcceptEndpoint(_ inviteCode: String) -> String {
    return "\(ENDPOINT_WORKSPACE_INVITATIONS)/\(inviteCode)/accept"
}

public func getWorkspaceInvitationRejectEndpoint(_ inviteCode: String) -> String {
    return "\(ENDPOINT_WORKSPACE_INVITATIONS)/\(inviteCode)/reject"
}

public func getWorkspaceInviteUsersEndpoint(_ workspaceId: Int) -> String {
    return "\(ENDPOINT_WORKSPACES)/\(workspaceId)/users/invite"
}

public func getWorkspaceUserEndpoint(_ workspaceId: Int, _ userId: Int) -> String {
    return "\(ENDPOINT_WORKSPACES)/\(workspaceId)/users/\(userId)"
}

public func getWorkspaceUserTasksEndpoint(_ workspaceId: Int, _ userId: Int) -> String {
    return "\(ENDPOINT_WORKSPACES)/\(workspaceId)/users/\(userId)/tasks"
}

public func getWorkspaceActiveProjectsEndpoint(_ workspaceId: Int) -> String {
    return "\(ENDPOINT_WORKSPACES)/\(workspaceId)/projects/active"
}

public func getWorkspaceArchivedProjectsEndpoint(_ workspaceId: Int) -> String {
    return "\(ENDPOINT_WORKSPACES)/\(workspaceId)/projects/archived"
}

public func getProjectInsightsActivityStatsEndpoint(_ projectId: String) -> String {
    return "projects/\(projectId)/insights/activity_stats"
}

public func getProjectInsightsHealthEndpoint(_ projectId: String) -> String {
    return "projects/\(projectId)/insights/health"
}

public func getProjectInsightsHealthContextEndpoint(_ projectId: String) -> String {
    return "projects/\(projectId)/insights/health/context"
}

public func getProjectInsightsProgressEndpoint(_ projectId: String) -> String {
    return "projects/\(projectId)/insights/progress"
}

public func getProjectInsightsHealthAnalyzeEndpoint(_ projectId: String) -> String {
    return "projects/\(projectId)/insights/health/analyze"
}

public func getWorkspaceInsightsEndpoint(_ workspaceId: String) -> String {
    return "workspaces/\(workspaceId)/insights"
}

