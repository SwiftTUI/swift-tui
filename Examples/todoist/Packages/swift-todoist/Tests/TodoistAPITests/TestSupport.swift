import Foundation
@testable import TodoistAPI

actor MockTransport: Transport {
    enum Action {
        case response(TodoistHTTPResponse)
        case failure(Error)
    }

    private var actions: [Action]
    private(set) var requests: [TodoistHTTPRequest] = []

    init(actions: [Action] = []) {
        self.actions = actions
    }

    func perform(_ request: TodoistHTTPRequest) async throws -> TodoistHTTPResponse {
        requests.append(request)
        guard !actions.isEmpty else {
            return TodoistHTTPResponse(statusCode: 500, statusText: "Missing Mock Action", headers: [:], data: Data())
        }

        let action = actions.removeFirst()
        switch action {
        case let .response(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    func enqueue(_ action: Action) {
        actions.append(action)
    }

    func allRequests() -> [TodoistHTTPRequest] {
        requests
    }

    func lastRequest() -> TodoistHTTPRequest? {
        requests.last
    }
}

func jsonResponse(_ object: Any, statusCode: Int = 200, headers: [String: String] = [:]) throws -> TodoistHTTPResponse {
    let data = try JSONSerialization.data(withJSONObject: object)
    return TodoistHTTPResponse(
        statusCode: statusCode,
        statusText: statusText(for: statusCode),
        headers: headers,
        data: data,
    )
}

func textResponse(_ text: String, statusCode: Int = 200, headers: [String: String] = [:]) -> TodoistHTTPResponse {
    TodoistHTTPResponse(
        statusCode: statusCode,
        statusText: statusText(for: statusCode),
        headers: headers,
        data: Data(text.utf8),
    )
}

func requestJSONBody(_ request: TodoistHTTPRequest) throws -> [String: Any] {
    guard let data = request.httpBody else {
        return [:]
    }
    let object = try JSONSerialization.jsonObject(with: data, options: [])
    return object as? [String: Any] ?? [:]
}

func queryItems(_ request: TodoistHTTPRequest) -> [String: String] {
    guard let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
          let items = components.queryItems
    else {
        return [:]
    }

    return items.reduce(into: [String: String]()) { result, item in
        result[item.name] = item.value
    }
}

func statusText(for statusCode: Int) -> String {
    switch statusCode {
    case 200:
        return "OK"
    case 201:
        return "Created"
    case 204:
        return "No Content"
    case 400:
        return "Bad Request"
    case 401:
        return "Unauthorized"
    case 403:
        return "Forbidden"
    case 404:
        return "Not Found"
    case 409:
        return "Conflict"
    case 429:
        return "Too Many Requests"
    case 500:
        return "Internal Server Error"
    default:
        return "HTTP \(statusCode)"
    }
}

let defaultDue = DueDate(
    string: "a date string",
    date: "2020-09-08T12:00:00Z",
    timezone: nil,
    lang: "en",
    isRecurring: false,
)

let defaultTask = Task(
    id: "1234",
    userId: "1234",
    projectId: "123",
    sectionId: "456",
    parentId: "5678",
    assignedByUid: "1234",
    responsibleUid: "1234",
    labels: ["personal", "work"],
    deadline: Deadline(date: "2020-09-08", lang: "en"),
    duration: Duration(amount: 10, unit: "minute"),
    checked: false,
    isDeleted: false,
    addedAt: "2020-09-08T12:00:00Z",
    completedAt: nil,
    updatedAt: "2020-09-08T12:00:00Z",
    due: defaultDue,
    priority: 1,
    childOrder: 3,
    content: "This is a task",
    description: "A description",
    dayOrder: 3,
    isCollapsed: false,
    isUncompletable: false,
    order: nil,
    recurring: nil,
    hasSubTasks: nil,
    url: URLHelpers.getTaskUrl(taskId: "1234", content: "This is a task"),
)

let defaultAbsoluteReminder = Reminder(
    id: "6XGgmFQrx44wfGHr",
    notifyUid: "5",
    itemId: "1234",
    projectId: nil,
    isDeleted: false,
    type: .absolute,
    due: defaultDue,
    minuteOffset: nil,
    isUrgent: true,
    name: nil,
    locLat: nil,
    locLong: nil,
    locTrigger: nil,
    radius: nil,
)

let defaultLocationReminder = Reminder(
    id: "6XGgmFQrx44wfGHr",
    notifyUid: "5",
    itemId: "1234",
    projectId: nil,
    isDeleted: false,
    type: .location,
    due: nil,
    minuteOffset: nil,
    isUrgent: nil,
    name: "Aliados",
    locLat: "41.148581",
    locLong: "-8.610945000000015",
    locTrigger: "on_enter",
    radius: 100,
)

let defaultComment = Comment(
    id: "comment-1",
    taskId: "task-1",
    projectId: nil,
    content: "Check this out",
    postedAt: "2024-01-01T00:00:00Z",
    fileAttachment: Attachment(
        resourceType: "file",
        fileName: "file.png",
        fileSize: 1024,
        fileType: "image/png",
        fileUrl: "https://files.todoist.com/user_upload/v2/123/file.png",
        fileDuration: nil,
        uploadState: "completed",
        image: nil,
        imageWidth: nil,
        imageHeight: nil,
        url: nil,
        title: nil,
    ),
    postedUid: "user-1",
    uidsToNotify: nil,
    reactions: nil,
    isDeleted: false,
)

func taskJSON(_ task: Task) -> [String: Any] {
    var json: [String: Any] = [
        "id": task.id,
        "labels": task.labels,
        "checked": task.checked,
        "is_deleted": task.isDeleted,
        "content": task.content,
        "is_collapsed": task.isCollapsed,
        "is_uncompletable": task.isUncompletable,
    ]

    if let userId = task.userId { json["user_id"] = userId }
    if let projectId = task.projectId { json["project_id"] = projectId }
    if let sectionId = task.sectionId { json["section_id"] = sectionId }
    if let parentId = task.parentId { json["parent_id"] = parentId }
    if let assignedByUid = task.assignedByUid { json["assigned_by_uid"] = assignedByUid }
    if let responsibleUid = task.responsibleUid { json["responsible_uid"] = responsibleUid }
    if let deadline = task.deadline {
        json["deadline"] = [
            "date": deadline.date,
            "lang": deadline.lang as Any,
        ].compactMapValues { $0 }
    }
    if let duration = task.duration {
        json["duration"] = [
            "amount": duration.amount,
            "unit": duration.unit,
        ]
    }
    if let addedAt = task.addedAt { json["added_at"] = addedAt }
    if let completedAt = task.completedAt { json["completed_at"] = completedAt }
    if let updatedAt = task.updatedAt { json["updated_at"] = updatedAt }
    if let due = task.due {
        json["due"] = [
            "string": due.string,
            "date": due.date,
            "timezone": due.timezone as Any,
            "lang": due.lang as Any,
            "is_recurring": due.isRecurring as Any,
        ].compactMapValues { $0 }
    }
    if let priority = task.priority { json["priority"] = priority }
    if let childOrder = task.childOrder { json["child_order"] = childOrder }
    if let description = task.description { json["description"] = description }
    if let dayOrder = task.dayOrder { json["day_order"] = dayOrder }
    if let order = task.order { json["order"] = order }
    if let recurring = task.recurring { json["recurring"] = recurring }
    if let hasSubTasks = task.hasSubTasks { json["has_sub_tasks"] = hasSubTasks }
    if let url = task.url { json["url"] = url }

    return json
}

func reminderJSON(_ reminder: Reminder) -> [String: Any] {
    var json: [String: Any] = [
        "id": reminder.id,
        "item_id": reminder.itemId,
        "is_deleted": reminder.isDeleted,
        "type": reminder.type.rawValue,
    ]

    if let notifyUid = reminder.notifyUid { json["notify_uid"] = notifyUid }
    if let projectId = reminder.projectId { json["project_id"] = projectId }
    if let due = reminder.due {
        json["due"] = [
            "string": due.string,
            "date": due.date,
            "timezone": due.timezone as Any,
            "lang": due.lang as Any,
            "is_recurring": due.isRecurring as Any,
        ].compactMapValues { $0 }
    }
    if let minuteOffset = reminder.minuteOffset { json["minute_offset"] = minuteOffset }
    if let isUrgent = reminder.isUrgent { json["is_urgent"] = isUrgent }
    if let name = reminder.name { json["name"] = name }
    if let locLat = reminder.locLat { json["loc_lat"] = locLat }
    if let locLong = reminder.locLong { json["loc_long"] = locLong }
    if let locTrigger = reminder.locTrigger { json["loc_trigger"] = locTrigger }
    if let radius = reminder.radius { json["radius"] = radius }

    return json
}

func attachmentJSON(_ attachment: Attachment) -> [String: Any] {
    var json: [String: Any] = [
        "resource_type": attachment.resourceType,
    ]

    if let fileName = attachment.fileName { json["file_name"] = fileName }
    if let fileSize = attachment.fileSize { json["file_size"] = fileSize }
    if let fileType = attachment.fileType { json["file_type"] = fileType }
    if let fileUrl = attachment.fileUrl { json["file_url"] = fileUrl }
    if let fileDuration = attachment.fileDuration { json["file_duration"] = fileDuration }
    if let uploadState = attachment.uploadState { json["upload_state"] = uploadState }
    if let image = attachment.image { json["image"] = image }
    if let imageWidth = attachment.imageWidth { json["image_width"] = imageWidth }
    if let imageHeight = attachment.imageHeight { json["image_height"] = imageHeight }
    if let url = attachment.url { json["url"] = url }
    if let title = attachment.title { json["title"] = title }

    return json
}
