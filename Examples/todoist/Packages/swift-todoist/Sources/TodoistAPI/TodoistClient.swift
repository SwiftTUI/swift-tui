import Foundation

public enum NullableField<Value: Sendable>: Sendable {
    case unchanged
    case null
    case value(Value)
}

public struct TodoistPage<Value: Codable & Sendable>: Codable, Sendable {
    public let results: [Value]
    public let nextCursor: String?

    public init(results: [Value], nextCursor: String? = nil) {
        self.results = results
        self.nextCursor = nextCursor
    }
}

public struct Backup: Codable, Sendable {
    public let version: String
    public let url: String
}

public struct ExportTemplateURLResponse: Codable, Sendable {
    public let fileName: String
    public let fileUrl: String
}

public struct TemplateImportResponse: Codable, Sendable {
    public let status: String
    public let templateType: String
    public let projects: [Project]
    public let sections: [Section]
    public let tasks: [Task]
    public let comments: [Comment]
}

public struct TaskQuery: Sendable {
    public let projectId: String?
    public let sectionId: String?
    public let parentId: String?
    public let label: String?
    public let ids: [String]?
    public let cursor: String?
    public let limit: Int?

    public init(
        projectId: String? = nil,
        sectionId: String? = nil,
        parentId: String? = nil,
        label: String? = nil,
        ids: [String]? = nil,
        cursor: String? = nil,
        limit: Int? = nil,
    ) {
        self.projectId = projectId
        self.sectionId = sectionId
        self.parentId = parentId
        self.label = label
        self.ids = ids
        self.cursor = cursor
        self.limit = limit
    }
}

public struct TaskCreateRequest: Sendable {
    public let content: String
    public let description: String?
    public let projectId: String?
    public let sectionId: String?
    public let parentId: String?
    public let order: Int?
    public let labels: [String]?
    public let priority: Int?
    public let assigneeId: String?
    public let dueString: String?
    public let dueLang: String?
    public let dueDate: String?
    public let dueDatetime: String?
    public let deadlineDate: String?
    public let deadlineLang: String?
    public let duration: Int?
    public let durationUnit: String?
    public let isUncompletable: Bool?

    public init(
        content: String,
        description: String? = nil,
        projectId: String? = nil,
        sectionId: String? = nil,
        parentId: String? = nil,
        order: Int? = nil,
        labels: [String]? = nil,
        priority: Int? = nil,
        assigneeId: String? = nil,
        dueString: String? = nil,
        dueLang: String? = nil,
        dueDate: String? = nil,
        dueDatetime: String? = nil,
        deadlineDate: String? = nil,
        deadlineLang: String? = nil,
        duration: Int? = nil,
        durationUnit: String? = nil,
        isUncompletable: Bool? = nil,
    ) {
        self.content = content
        self.description = description
        self.projectId = projectId
        self.sectionId = sectionId
        self.parentId = parentId
        self.order = order
        self.labels = labels
        self.priority = priority
        self.assigneeId = assigneeId
        self.dueString = dueString
        self.dueLang = dueLang
        self.dueDate = dueDate
        self.dueDatetime = dueDatetime
        self.deadlineDate = deadlineDate
        self.deadlineLang = deadlineLang
        self.duration = duration
        self.durationUnit = durationUnit
        self.isUncompletable = isUncompletable
    }
}

public struct QuickAddTaskRequest: Sendable {
    public let text: String
    public let note: String?
    public let reminder: String?
    public let autoReminder: Bool?
    public let meta: Bool?
    public let isUncompletable: Bool?

    public init(
        text: String,
        note: String? = nil,
        reminder: String? = nil,
        autoReminder: Bool? = nil,
        meta: Bool? = nil,
        isUncompletable: Bool? = nil,
    ) {
        self.text = text
        self.note = note
        self.reminder = reminder
        self.autoReminder = autoReminder
        self.meta = meta
        self.isUncompletable = isUncompletable
    }
}

public struct TaskUpdateRequest: Sendable {
    public let content: String?
    public let description: String?
    public let labels: [String]?
    public let priority: Int?
    public let order: Int?
    public let dueString: NullableField<String>
    public let dueLang: NullableField<String>
    public let dueDate: String?
    public let dueDatetime: String?
    public let assigneeId: NullableField<String>
    public let deadlineDate: NullableField<String>
    public let deadlineLang: NullableField<String>
    public let duration: Int?
    public let durationUnit: String?
    public let isUncompletable: Bool?

    public init(
        content: String? = nil,
        description: String? = nil,
        labels: [String]? = nil,
        priority: Int? = nil,
        order: Int? = nil,
        dueString: NullableField<String> = .unchanged,
        dueLang: NullableField<String> = .unchanged,
        dueDate: String? = nil,
        dueDatetime: String? = nil,
        assigneeId: NullableField<String> = .unchanged,
        deadlineDate: NullableField<String> = .unchanged,
        deadlineLang: NullableField<String> = .unchanged,
        duration: Int? = nil,
        durationUnit: String? = nil,
        isUncompletable: Bool? = nil,
    ) {
        self.content = content
        self.description = description
        self.labels = labels
        self.priority = priority
        self.order = order
        self.dueString = dueString
        self.dueLang = dueLang
        self.dueDate = dueDate
        self.dueDatetime = dueDatetime
        self.assigneeId = assigneeId
        self.deadlineDate = deadlineDate
        self.deadlineLang = deadlineLang
        self.duration = duration
        self.durationUnit = durationUnit
        self.isUncompletable = isUncompletable
    }
}

public enum TaskMoveDestination: Sendable {
    case project(String)
    case section(String)
    case parent(String)

    fileprivate var payload: [String: Any] {
        switch self {
        case let .project(id):
            return ["projectId": id]
        case let .section(id):
            return ["sectionId": id]
        case let .parent(id):
            return ["parentId": id]
        }
    }
}

public struct ProjectCreateRequest: Sendable {
    public let name: String
    public let parentId: String?
    public let color: String?
    public let isFavorite: Bool?
    public let viewStyle: String?
    public let workspaceId: String?

    public init(
        name: String,
        parentId: String? = nil,
        color: String? = nil,
        isFavorite: Bool? = nil,
        viewStyle: String? = nil,
        workspaceId: String? = nil,
    ) {
        self.name = name
        self.parentId = parentId
        self.color = color
        self.isFavorite = isFavorite
        self.viewStyle = viewStyle
        self.workspaceId = workspaceId
    }
}

public struct ProjectUpdateRequest: Sendable {
    public let name: String?
    public let color: String?
    public let isFavorite: Bool?
    public let viewStyle: String?

    public init(
        name: String? = nil,
        color: String? = nil,
        isFavorite: Bool? = nil,
        viewStyle: String? = nil,
    ) {
        self.name = name
        self.color = color
        self.isFavorite = isFavorite
        self.viewStyle = viewStyle
    }
}

public struct SectionCreateRequest: Sendable {
    public let name: String
    public let projectId: String
    public let order: Int?

    public init(name: String, projectId: String, order: Int? = nil) {
        self.name = name
        self.projectId = projectId
        self.order = order
    }
}

public struct SectionUpdateRequest: Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct LabelCreateRequest: Sendable {
    public let name: String
    public let order: Int?
    public let color: String?
    public let isFavorite: Bool?

    public init(
        name: String,
        order: Int? = nil,
        color: String? = nil,
        isFavorite: Bool? = nil,
    ) {
        self.name = name
        self.order = order
        self.color = color
        self.isFavorite = isFavorite
    }
}

public struct LabelUpdateRequest: Sendable {
    public let name: String?
    public let order: Int?
    public let color: String?
    public let isFavorite: Bool?

    public init(
        name: String? = nil,
        order: Int? = nil,
        color: String? = nil,
        isFavorite: Bool? = nil,
    ) {
        self.name = name
        self.order = order
        self.color = color
        self.isFavorite = isFavorite
    }
}

public struct CommentQuery: Sendable {
    public let taskId: String?
    public let projectId: String?
    public let cursor: String?
    public let limit: Int?

    public init(taskId: String? = nil, projectId: String? = nil, cursor: String? = nil, limit: Int? = nil) {
        self.taskId = taskId
        self.projectId = projectId
        self.cursor = cursor
        self.limit = limit
    }
}

public struct CommentAttachmentInput: Sendable {
    public let fileName: String?
    public let fileUrl: String
    public let fileType: String?
    public let resourceType: String?

    public init(fileName: String? = nil, fileUrl: String, fileType: String? = nil, resourceType: String? = nil) {
        self.fileName = fileName
        self.fileUrl = fileUrl
        self.fileType = fileType
        self.resourceType = resourceType
    }
}

public struct CommentCreateRequest: Sendable {
    public let content: String
    public let taskId: String?
    public let projectId: String?
    public let attachment: CommentAttachmentInput?
    public let uidsToNotify: [String]?

    public init(
        content: String,
        taskId: String? = nil,
        projectId: String? = nil,
        attachment: CommentAttachmentInput? = nil,
        uidsToNotify: [String]? = nil,
    ) {
        self.content = content
        self.taskId = taskId
        self.projectId = projectId
        self.attachment = attachment
        self.uidsToNotify = uidsToNotify
    }
}

public struct CommentUpdateRequest: Sendable {
    public let content: String

    public init(content: String) {
        self.content = content
    }
}

public struct ReminderQuery: Sendable {
    public let taskId: String?
    public let cursor: String?
    public let limit: Int?

    public init(taskId: String? = nil, cursor: String? = nil, limit: Int? = nil) {
        self.taskId = taskId
        self.cursor = cursor
        self.limit = limit
    }
}

public struct RelativeReminderCreateRequest: Sendable {
    public let taskId: String
    public let minuteOffset: Int
    public let notifyUid: String?
    public let service: String?
    public let isUrgent: Bool?

    public init(
        taskId: String,
        minuteOffset: Int,
        notifyUid: String? = nil,
        service: String? = nil,
        isUrgent: Bool? = nil,
    ) {
        self.taskId = taskId
        self.minuteOffset = minuteOffset
        self.notifyUid = notifyUid
        self.service = service
        self.isUrgent = isUrgent
    }
}

public struct AbsoluteReminderCreateRequest: Sendable {
    public let taskId: String
    public let due: DueDate
    public let notifyUid: String?
    public let service: String?
    public let isUrgent: Bool?

    public init(
        taskId: String,
        due: DueDate,
        notifyUid: String? = nil,
        service: String? = nil,
        isUrgent: Bool? = nil,
    ) {
        self.taskId = taskId
        self.due = due
        self.notifyUid = notifyUid
        self.service = service
        self.isUrgent = isUrgent
    }
}

public struct LocationReminderCreateRequest: Sendable {
    public let taskId: String
    public let notifyUid: String?
    public let name: String
    public let locLat: String
    public let locLong: String
    public let locTrigger: String
    public let radius: Int?

    public init(
        taskId: String,
        notifyUid: String? = nil,
        name: String,
        locLat: String,
        locLong: String,
        locTrigger: String,
        radius: Int? = nil,
    ) {
        self.taskId = taskId
        self.notifyUid = notifyUid
        self.name = name
        self.locLat = locLat
        self.locLong = locLong
        self.locTrigger = locTrigger
        self.radius = radius
    }
}

public struct RelativeReminderUpdateRequest: Sendable {
    public let minuteOffset: Int?
    public let notifyUid: String?
    public let service: String?
    public let isUrgent: Bool?

    public init(
        minuteOffset: Int? = nil,
        notifyUid: String? = nil,
        service: String? = nil,
        isUrgent: Bool? = nil,
    ) {
        self.minuteOffset = minuteOffset
        self.notifyUid = notifyUid
        self.service = service
        self.isUrgent = isUrgent
    }

    fileprivate var hasMutableFields: Bool {
        minuteOffset != nil || notifyUid != nil || service != nil || isUrgent != nil
    }
}

public struct AbsoluteReminderUpdateRequest: Sendable {
    public let due: DueDate?
    public let notifyUid: String?
    public let service: String?
    public let isUrgent: Bool?

    public init(
        due: DueDate? = nil,
        notifyUid: String? = nil,
        service: String? = nil,
        isUrgent: Bool? = nil,
    ) {
        self.due = due
        self.notifyUid = notifyUid
        self.service = service
        self.isUrgent = isUrgent
    }

    fileprivate var hasMutableFields: Bool {
        due != nil || notifyUid != nil || service != nil || isUrgent != nil
    }
}

public struct LocationReminderUpdateRequest: Sendable {
    public let notifyUid: String?
    public let name: String?
    public let locLat: String?
    public let locLong: String?
    public let locTrigger: String?
    public let radius: Int?

    public init(
        notifyUid: String? = nil,
        name: String? = nil,
        locLat: String? = nil,
        locLong: String? = nil,
        locTrigger: String? = nil,
        radius: Int? = nil,
    ) {
        self.notifyUid = notifyUid
        self.name = name
        self.locLat = locLat
        self.locLong = locLong
        self.locTrigger = locTrigger
        self.radius = radius
    }

    fileprivate var hasMutableFields: Bool {
        notifyUid != nil || name != nil || locLat != nil || locLong != nil || locTrigger != nil || radius != nil
    }
}

public struct UploadRequest {
    public let file: UploadFileSource
    public let fileName: String?
    public let projectId: String?

    public init(file: UploadFileSource, fileName: String? = nil, projectId: String? = nil) {
        self.file = file
        self.fileName = fileName
        self.projectId = projectId
    }
}

public struct WorkspaceCreateRequest: Sendable {
    public let name: String
    public let description: String?
    public let isLinkSharingEnabled: Bool?
    public let isGuestAllowed: Bool?
    public let domainName: String?
    public let domainDiscovery: Bool?
    public let restrictEmailDomains: Bool?

    public init(
        name: String,
        description: String? = nil,
        isLinkSharingEnabled: Bool? = nil,
        isGuestAllowed: Bool? = nil,
        domainName: String? = nil,
        domainDiscovery: Bool? = nil,
        restrictEmailDomains: Bool? = nil,
    ) {
        self.name = name
        self.description = description
        self.isLinkSharingEnabled = isLinkSharingEnabled
        self.isGuestAllowed = isGuestAllowed
        self.domainName = domainName
        self.domainDiscovery = domainDiscovery
        self.restrictEmailDomains = restrictEmailDomains
    }
}

public struct WorkspaceUpdateRequest: Sendable {
    public let name: String?
    public let description: NullableField<String>
    public let isLinkSharingEnabled: Bool?
    public let isGuestAllowed: Bool?
    public let domainName: NullableField<String>
    public let domainDiscovery: Bool?
    public let restrictEmailDomains: Bool?
    public let isCollapsed: Bool?

    public init(
        name: String? = nil,
        description: NullableField<String> = .unchanged,
        isLinkSharingEnabled: Bool? = nil,
        isGuestAllowed: Bool? = nil,
        domainName: NullableField<String> = .unchanged,
        domainDiscovery: Bool? = nil,
        restrictEmailDomains: Bool? = nil,
        isCollapsed: Bool? = nil,
    ) {
        self.name = name
        self.description = description
        self.isLinkSharingEnabled = isLinkSharingEnabled
        self.isGuestAllowed = isGuestAllowed
        self.domainName = domainName
        self.domainDiscovery = domainDiscovery
        self.restrictEmailDomains = restrictEmailDomains
        self.isCollapsed = isCollapsed
    }
}

private enum TodoistClientSupport {
    static func path(_ segments: String...) -> String {
        segments.joined(separator: "/")
    }

    static func responseMessage(from response: TodoistHTTPResponse) -> String {
        if let decoded = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
           let error = decoded["error"] as? String
        {
            return error
        }

        if let text = String(data: response.data, encoding: .utf8), !text.isEmpty {
            return text
        }

        return response.statusText
    }

    static func ensureSuccess(_ response: TodoistHTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw TodoistRequestError(
                responseMessage(from: response),
                httpStatusCode: response.statusCode,
                responseData: response.data,
            )
        }
    }

    static func string(for value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        return String(describing: value)
    }
}

public final class TodoistClient: Sendable {
    struct Configuration: Sendable {
        let authToken: String
        let transport: Transport
        let syncBaseURL: String
        let httpClient: TodoistHTTPClient

        init(authToken: String, baseURL: String, transport: Transport) {
            self.authToken = authToken
            self.transport = transport
            self.syncBaseURL = getSyncBaseURI(domainBase: baseURL)
            self.httpClient = TodoistHTTPClient(
                transport: transport,
                baseURL: getSyncBaseURI(domainBase: baseURL),
                authToken: authToken,
            )
        }

        func request<T: Decodable>(
            _ type: T.Type,
            method: HTTPMethod,
            path: String,
            payload: [String: Any]? = nil,
            requestId: String? = nil,
            includeRequestIdForSync: Bool = false,
        ) async throws -> T {
            let result: (TodoistHTTPResponse, T) = try await httpClient.request(
                method: method,
                path: path,
                payload: payload,
                requestId: requestId,
                includeRequestIdForSync: includeRequestIdForSync,
            )
            return result.1
        }

        func requestRaw(
            method: HTTPMethod,
            path: String,
            payload: [String: Any]? = nil,
            requestId: String? = nil,
            includeRequestIdForSync: Bool = false,
            customHeaders: [String: String] = [:],
        ) async throws -> TodoistHTTPResponse {
            let response = try await httpClient.requestVoid(
                method: method,
                path: path,
                payload: payload,
                requestId: requestId,
                includeRequestIdForSync: includeRequestIdForSync,
                customHeaders: customHeaders,
            )
            try TodoistClientSupport.ensureSuccess(response)
            return response
        }

        func requestBool(
            method: HTTPMethod,
            path: String,
            payload: [String: Any]? = nil,
            requestId: String? = nil,
            includeRequestIdForSync: Bool = false,
            customHeaders: [String: String] = [:],
        ) async throws -> Bool {
            _ = try await requestRaw(
                method: method,
                path: path,
                payload: payload,
                requestId: requestId,
                includeRequestIdForSync: includeRequestIdForSync,
                customHeaders: customHeaders,
            )
            return true
        }

        func decode<T: Decodable>(_ type: T.Type, from response: TodoistHTTPResponse) throws -> T {
            try JSONDecoder.default.decode(T.self, from: response.data)
        }

        func buildURL(for path: String) throws -> URL {
            let separator = syncBaseURL.hasSuffix("/") ? "" : "/"
            guard let url = URL(string: "\(syncBaseURL)\(separator)\(path)") else {
                throw TodoistArgumentError("Invalid URL for path \(path)")
            }
            return url
        }

        func authenticatedGET(url: URL) async throws -> TodoistHTTPResponse {
            var request = TodoistHTTPRequest(url: url)
            request.method = .get
            request.timeoutInterval = 30
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            return try await transport.perform(request)
        }

        func uploadMultipart<T: Decodable>(
            endpoint: String,
            file: UploadFileSource,
            fileName: String?,
            additionalFields: [String: Any] = [:],
            requestId: String? = nil,
        ) async throws -> T {
            let upload: (data: Data, fileName: String, mimeType: String?)
            do {
                upload = try uploadMultipartFile(fileSource: file, fileName: fileName, filePath: nil)
            } catch MultipartEncodingError.missingFileName {
                switch file {
                case .data:
                    throw TodoistFileValidationError.fileNameRequired(transport: "buffer")
                case .stream:
                    throw TodoistFileValidationError.fileNameRequired(transport: "stream")
                case .path:
                    throw MultipartEncodingError.missingFileName
                }
            }
            guard !upload.data.isEmpty else {
                throw TodoistFileValidationError.emptyFile
            }

            let boundary = "Boundary-\(UUID().uuidString)"
            var body = Data()

            for (key, value) in additionalFields {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(TodoistClientSupport.string(for: value))\r\n".data(using: .utf8)!)
            }

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(upload.fileName)\"\r\n"
                    .data(using: .utf8)!
            )
            body.append("Content-Type: \(upload.mimeType ?? "application/octet-stream")\r\n\r\n".data(using: .utf8)!)
            body.append(upload.data)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

            var request = TodoistHTTPRequest(url: try buildURL(for: endpoint))
            request.method = .post
            request.timeoutInterval = 30
            request.httpBody = body
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            if let requestId {
                request.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
            }

            let response = try await transport.perform(request)
            try TodoistClientSupport.ensureSuccess(response)
            return try decode(T.self, from: response)
        }
    }

    public struct TasksService: Sendable {
        fileprivate let configuration: Configuration

        public func get(_ id: String) async throws -> Task {
            try await configuration.request(
                Task.self,
                method: .get,
                path: TodoistClientSupport.path(ENDPOINT_REST_TASKS, id),
            )
        }

        public func list(_ query: TaskQuery = .init()) async throws -> TodoistPage<Task> {
            let response: TodoistPage<Task> = try await configuration.request(
                TodoistPage<Task>.self,
                method: .get,
                path: ENDPOINT_REST_TASKS,
                payload: [
                    "projectId": query.projectId as Any,
                    "sectionId": query.sectionId as Any,
                    "parentId": query.parentId as Any,
                    "label": query.label as Any,
                    "ids": query.ids as Any,
                    "cursor": query.cursor as Any,
                    "limit": query.limit as Any,
                ].compactMapValues { $0 },
            )
            return response
        }

        public func create(_ request: TaskCreateRequest, requestId: String? = nil) async throws -> Task {
            try request.validate()
            return try await configuration.request(
                Task.self,
                method: .post,
                path: ENDPOINT_REST_TASKS,
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func quickAdd(_ request: QuickAddTaskRequest) async throws -> Task {
            var payload: [String: Any] = [
                "text": UncompletableHelpers.processTaskContent(request.text, isUncompletable: request.isUncompletable),
            ]
            if let note = request.note { payload["note"] = note }
            if let reminder = request.reminder { payload["reminder"] = reminder }
            if let autoReminder = request.autoReminder { payload["autoReminder"] = autoReminder }
            if let meta = request.meta { payload["meta"] = meta }

            return try await configuration.request(
                Task.self,
                method: .post,
                path: ENDPOINT_SYNC_QUICK_ADD,
                payload: payload,
            )
        }

        public func update(_ id: String, _ request: TaskUpdateRequest, requestId: String? = nil) async throws -> Task {
            try request.validate()
            return try await configuration.request(
                Task.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_TASKS, id),
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func move(_ id: String, to destination: TaskMoveDestination, requestId: String? = nil) async throws -> Task {
            try await configuration.request(
                Task.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_TASKS, id, ENDPOINT_REST_TASK_MOVE),
                payload: destination.payload,
                requestId: requestId,
            )
        }

        public func move(_ ids: [String], to destination: TaskMoveDestination, requestId: String? = nil) async throws -> [Task] {
            guard ids.count <= MAX_COMMAND_COUNT else {
                throw TodoistRequestError("Maximum number of items is \(MAX_COMMAND_COUNT)", httpStatusCode: 400)
            }

            let commands = ids.map { id in
                SyncHelpers.createCommand(
                    .itemMove,
                    args: ["id": id].merging(destination.payload) { _, new in new },
                )
            }
            let syncResponse = try await SyncService(configuration: configuration).execute(
                SyncRequest(commands: commands, resourceTypes: ["items"], syncToken: nil),
                requestId: requestId,
            )

            guard let items = syncResponse.items, !items.isEmpty else {
                throw TodoistRequestError("Tasks not found", httpStatusCode: 404)
            }

            let filtered = items.filter { ids.contains($0.id) }
            guard !filtered.isEmpty else {
                throw TodoistRequestError("Tasks not found", httpStatusCode: 404)
            }
            return filtered
        }

        public func close(_ id: String, requestId: String? = nil) async throws -> Bool {
            try await configuration.requestBool(
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_TASKS, id, ENDPOINT_REST_TASK_CLOSE),
                requestId: requestId,
            )
        }

        public func reopen(_ id: String, requestId: String? = nil) async throws -> Bool {
            try await configuration.requestBool(
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_TASKS, id, ENDPOINT_REST_TASK_REOPEN),
                requestId: requestId,
            )
        }

        public func delete(_ id: String, requestId: String? = nil) async throws -> Bool {
            try await configuration.requestBool(
                method: .delete,
                path: TodoistClientSupport.path(ENDPOINT_REST_TASKS, id),
                requestId: requestId,
            )
        }
    }

    public struct ProjectsService: Sendable {
        fileprivate let configuration: Configuration

        public func get(_ id: String) async throws -> Project {
            try await configuration.request(Project.self, method: .get, path: TodoistClientSupport.path(ENDPOINT_REST_PROJECTS, id))
        }

        public func list(cursor: String? = nil, limit: Int? = nil) async throws -> TodoistPage<Project> {
            try await configuration.request(
                TodoistPage<Project>.self,
                method: .get,
                path: ENDPOINT_REST_PROJECTS,
                payload: ["cursor": cursor as Any, "limit": limit as Any].compactMapValues { $0 },
            )
        }

        public func create(_ request: ProjectCreateRequest, requestId: String? = nil) async throws -> Project {
            try await configuration.request(
                Project.self,
                method: .post,
                path: ENDPOINT_REST_PROJECTS,
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func update(_ id: String, _ request: ProjectUpdateRequest, requestId: String? = nil) async throws -> Project {
            try await configuration.request(
                Project.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_PROJECTS, id),
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func delete(_ id: String, requestId: String? = nil) async throws -> Bool {
            try await configuration.requestBool(
                method: .delete,
                path: TodoistClientSupport.path(ENDPOINT_REST_PROJECTS, id),
                requestId: requestId,
            )
        }

        public func archive(_ id: String, requestId: String? = nil) async throws -> Project {
            try await configuration.request(
                Project.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_PROJECTS, id, PROJECT_ARCHIVE),
                requestId: requestId,
            )
        }

        public func unarchive(_ id: String, requestId: String? = nil) async throws -> Project {
            try await configuration.request(
                Project.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_PROJECTS, id, PROJECT_UNARCHIVE),
                requestId: requestId,
            )
        }
    }

    public struct SectionsService: Sendable {
        fileprivate let configuration: Configuration

        public func get(_ id: String) async throws -> Section {
            try await configuration.request(Section.self, method: .get, path: TodoistClientSupport.path(ENDPOINT_REST_SECTIONS, id))
        }

        public func list(projectId: String? = nil, cursor: String? = nil, limit: Int? = nil) async throws -> TodoistPage<Section> {
            try await configuration.request(
                TodoistPage<Section>.self,
                method: .get,
                path: ENDPOINT_REST_SECTIONS,
                payload: ["projectId": projectId as Any, "cursor": cursor as Any, "limit": limit as Any].compactMapValues { $0 },
            )
        }

        public func create(_ request: SectionCreateRequest, requestId: String? = nil) async throws -> Section {
            try await configuration.request(
                Section.self,
                method: .post,
                path: ENDPOINT_REST_SECTIONS,
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func update(_ id: String, _ request: SectionUpdateRequest, requestId: String? = nil) async throws -> Section {
            try await configuration.request(
                Section.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_SECTIONS, id),
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func delete(_ id: String, requestId: String? = nil) async throws -> Bool {
            try await configuration.requestBool(
                method: .delete,
                path: TodoistClientSupport.path(ENDPOINT_REST_SECTIONS, id),
                requestId: requestId,
            )
        }

        public func archive(_ id: String, requestId: String? = nil) async throws -> Section {
            try await configuration.request(
                Section.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_SECTIONS, id, SECTION_ARCHIVE),
                requestId: requestId,
            )
        }

        public func unarchive(_ id: String, requestId: String? = nil) async throws -> Section {
            try await configuration.request(
                Section.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_SECTIONS, id, SECTION_UNARCHIVE),
                requestId: requestId,
            )
        }
    }

    public struct LabelsService: Sendable {
        fileprivate let configuration: Configuration

        public func get(_ id: String) async throws -> Label {
            try await configuration.request(Label.self, method: .get, path: TodoistClientSupport.path(ENDPOINT_REST_LABELS, id))
        }

        public func list(cursor: String? = nil, limit: Int? = nil) async throws -> TodoistPage<Label> {
            try await configuration.request(
                TodoistPage<Label>.self,
                method: .get,
                path: ENDPOINT_REST_LABELS,
                payload: ["cursor": cursor as Any, "limit": limit as Any].compactMapValues { $0 },
            )
        }

        public func create(_ request: LabelCreateRequest, requestId: String? = nil) async throws -> Label {
            try await configuration.request(
                Label.self,
                method: .post,
                path: ENDPOINT_REST_LABELS,
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func update(_ id: String, _ request: LabelUpdateRequest, requestId: String? = nil) async throws -> Label {
            try await configuration.request(
                Label.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_LABELS, id),
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func delete(_ id: String, requestId: String? = nil) async throws -> Bool {
            try await configuration.requestBool(
                method: .delete,
                path: TodoistClientSupport.path(ENDPOINT_REST_LABELS, id),
                requestId: requestId,
            )
        }
    }

    public struct CommentsService: Sendable {
        fileprivate let configuration: Configuration

        public func get(_ id: String) async throws -> Comment {
            try await configuration.request(Comment.self, method: .get, path: TodoistClientSupport.path(ENDPOINT_REST_COMMENTS, id))
        }

        public func list(_ query: CommentQuery) async throws -> TodoistPage<Comment> {
            guard (query.taskId != nil) != (query.projectId != nil) else {
                throw TodoistArgumentError("Exactly one of taskId or projectId must be provided.")
            }

            return try await configuration.request(
                TodoistPage<Comment>.self,
                method: .get,
                path: ENDPOINT_REST_COMMENTS,
                payload: [
                    "taskId": query.taskId as Any,
                    "projectId": query.projectId as Any,
                    "cursor": query.cursor as Any,
                    "limit": query.limit as Any,
                ].compactMapValues { $0 },
            )
        }

        public func create(_ request: CommentCreateRequest, requestId: String? = nil) async throws -> Comment {
            guard (request.taskId != nil) != (request.projectId != nil) else {
                throw TodoistArgumentError("Exactly one of taskId or projectId must be provided.")
            }

            return try await configuration.request(
                Comment.self,
                method: .post,
                path: ENDPOINT_REST_COMMENTS,
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func update(_ id: String, _ request: CommentUpdateRequest, requestId: String? = nil) async throws -> Comment {
            try await configuration.request(
                Comment.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_REST_COMMENTS, id),
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func delete(_ id: String, requestId: String? = nil) async throws -> Bool {
            try await configuration.requestBool(
                method: .delete,
                path: TodoistClientSupport.path(ENDPOINT_REST_COMMENTS, id),
                requestId: requestId,
            )
        }
    }

    public struct RemindersService: Sendable {
        fileprivate let configuration: Configuration

        public func list(_ query: ReminderQuery = .init()) async throws -> TodoistPage<Reminder> {
            try await configuration.request(
                TodoistPage<Reminder>.self,
                method: .get,
                path: ENDPOINT_REST_REMINDERS,
                payload: ["taskId": query.taskId as Any, "cursor": query.cursor as Any, "limit": query.limit as Any].compactMapValues { $0 },
            )
        }

        public func listLocation(_ query: ReminderQuery = .init()) async throws -> TodoistPage<Reminder> {
            try await configuration.request(
                TodoistPage<Reminder>.self,
                method: .get,
                path: ENDPOINT_REST_LOCATION_REMINDERS,
                payload: ["taskId": query.taskId as Any, "cursor": query.cursor as Any, "limit": query.limit as Any].compactMapValues { $0 },
            )
        }

        public func get(_ id: String) async throws -> Reminder {
            do {
                return try await configuration.request(
                    Reminder.self,
                    method: .get,
                    path: TodoistClientSupport.path(ENDPOINT_REST_REMINDERS, id),
                )
            } catch let error as TodoistRequestError where error.httpStatusCode == 404 {
                throw TodoistArgumentError(
                    "Reminder \(id) was not found on the time-based reminder endpoint. If this is a location reminder, use getLocationReminder instead."
                )
            }
        }

        public func getLocation(_ id: String) async throws -> Reminder {
            do {
                return try await configuration.request(
                    Reminder.self,
                    method: .get,
                    path: TodoistClientSupport.path(ENDPOINT_REST_LOCATION_REMINDERS, id),
                )
            } catch let error as TodoistRequestError where error.httpStatusCode == 404 {
                throw TodoistArgumentError(
                    "Location reminder \(id) was not found on the location reminder endpoint. If this is a time-based reminder, use getReminder instead."
                )
            }
        }

        public func create(_ request: RelativeReminderCreateRequest, requestId: String? = nil) async throws -> Reminder {
            try await configuration.request(
                Reminder.self,
                method: .post,
                path: ENDPOINT_REST_REMINDERS,
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func create(_ request: AbsoluteReminderCreateRequest, requestId: String? = nil) async throws -> Reminder {
            try await configuration.request(
                Reminder.self,
                method: .post,
                path: ENDPOINT_REST_REMINDERS,
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func createLocation(_ request: LocationReminderCreateRequest, requestId: String? = nil) async throws -> Reminder {
            try await configuration.request(
                Reminder.self,
                method: .post,
                path: ENDPOINT_REST_LOCATION_REMINDERS,
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func update(_ id: String, _ request: RelativeReminderUpdateRequest, requestId: String? = nil) async throws -> Reminder {
            guard request.hasMutableFields else {
                throw TodoistArgumentError("At least one reminder field must be provided to updateReminder")
            }

            do {
                return try await configuration.request(
                    Reminder.self,
                    method: .post,
                    path: TodoistClientSupport.path(ENDPOINT_REST_REMINDERS, id),
                    payload: request.payload(),
                    requestId: requestId,
                )
            } catch let error as TodoistRequestError where error.httpStatusCode == 404 {
                throw TodoistArgumentError(
                    "Reminder \(id) was not found on the time-based reminder endpoint. If this is a location reminder, use updateLocationReminder instead."
                )
            }
        }

        public func update(_ id: String, _ request: AbsoluteReminderUpdateRequest, requestId: String? = nil) async throws -> Reminder {
            guard request.hasMutableFields else {
                throw TodoistArgumentError("At least one reminder field must be provided to updateReminder")
            }

            do {
                return try await configuration.request(
                    Reminder.self,
                    method: .post,
                    path: TodoistClientSupport.path(ENDPOINT_REST_REMINDERS, id),
                    payload: request.payload(),
                    requestId: requestId,
                )
            } catch let error as TodoistRequestError where error.httpStatusCode == 404 {
                throw TodoistArgumentError(
                    "Reminder \(id) was not found on the time-based reminder endpoint. If this is a location reminder, use updateLocationReminder instead."
                )
            }
        }

        public func updateLocation(_ id: String, _ request: LocationReminderUpdateRequest, requestId: String? = nil) async throws -> Reminder {
            guard request.hasMutableFields else {
                throw TodoistArgumentError("At least one reminder field must be provided to updateLocationReminder")
            }

            do {
                return try await configuration.request(
                    Reminder.self,
                    method: .post,
                    path: TodoistClientSupport.path(ENDPOINT_REST_LOCATION_REMINDERS, id),
                    payload: request.payload(),
                    requestId: requestId,
                )
            } catch let error as TodoistRequestError where error.httpStatusCode == 404 {
                throw TodoistArgumentError(
                    "Location reminder \(id) was not found on the location reminder endpoint. If this is a time-based reminder, use updateReminder instead."
                )
            }
        }

        public func delete(_ id: String, requestId: String? = nil) async throws -> Bool {
            do {
                return try await configuration.requestBool(
                    method: .delete,
                    path: TodoistClientSupport.path(ENDPOINT_REST_REMINDERS, id),
                    requestId: requestId,
                )
            } catch let error as TodoistRequestError where error.httpStatusCode == 404 {
                throw TodoistArgumentError(
                    "Reminder \(id) was not found on the time-based reminder endpoint. If this is a location reminder, use deleteLocationReminder instead."
                )
            }
        }

        public func deleteLocation(_ id: String, requestId: String? = nil) async throws -> Bool {
            do {
                return try await configuration.requestBool(
                    method: .delete,
                    path: TodoistClientSupport.path(ENDPOINT_REST_LOCATION_REMINDERS, id),
                    requestId: requestId,
                )
            } catch let error as TodoistRequestError where error.httpStatusCode == 404 {
                throw TodoistArgumentError(
                    "Location reminder \(id) was not found on the location reminder endpoint. If this is a time-based reminder, use deleteReminder instead."
                )
            }
        }
    }

    public struct UploadsService: Sendable {
        fileprivate let configuration: Configuration

        public func upload(_ request: UploadRequest, requestId: String? = nil) async throws -> Attachment {
            try await configuration.uploadMultipart(
                endpoint: ENDPOINT_REST_UPLOADS,
                file: request.file,
                fileName: request.fileName,
                additionalFields: request.projectId.map { ["projectId": $0] } ?? [:],
                requestId: requestId,
            )
        }

        public func delete(fileURL: String, requestId: String? = nil) async throws -> Bool {
            try await configuration.requestBool(
                method: .delete,
                path: ENDPOINT_REST_UPLOADS,
                payload: ["fileUrl": fileURL],
                requestId: requestId,
            )
        }

        public func viewAttachment(url: String) async throws -> TodoistFileResponse {
            guard let parsedURL = URL(string: url) else {
                throw TodoistArgumentError("Invalid attachment URL")
            }

            guard parsedURL.host?.hasSuffix(".todoist.com") == true else {
                throw TodoistArgumentError("Attachment URLs must be on a todoist.com domain")
            }

            let response = try await configuration.authenticatedGET(url: parsedURL)
            guard (200..<300).contains(response.statusCode) else {
                throw TodoistArgumentError("Failed to fetch attachment: \(response.statusCode) \(response.statusText)")
            }

            return TodoistFileResponse(
                statusCode: response.statusCode,
                statusText: response.statusText,
                headers: response.headers,
                rawData: response.data,
            )
        }

        public func viewAttachment(comment: Comment) async throws -> TodoistFileResponse {
            guard let fileURL = comment.fileAttachment?.fileUrl else {
                throw TodoistArgumentError("Comment does not have a file attachment")
            }
            return try await viewAttachment(url: fileURL)
        }
    }

    public struct BackupsService: Sendable {
        fileprivate let configuration: Configuration

        public func list(mfaToken: String? = nil) async throws -> [Backup] {
            try await configuration.request(
                [Backup].self,
                method: .get,
                path: ENDPOINT_REST_BACKUPS,
                payload: ["mfaToken": mfaToken as Any].compactMapValues { $0 },
            )
        }

        public func download(file: String) async throws -> TodoistFileResponse {
            var components = URLComponents(url: try configuration.buildURL(for: ENDPOINT_REST_BACKUPS_DOWNLOAD), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "file", value: file)]
            guard let url = components?.url else {
                throw TodoistArgumentError("Invalid backup download URL")
            }

            let response = try await configuration.authenticatedGET(url: url)
            try TodoistClientSupport.ensureSuccess(response)
            return TodoistFileResponse(
                statusCode: response.statusCode,
                statusText: response.statusText,
                headers: response.headers,
                rawData: response.data,
            )
        }
    }

    public struct TemplatesService: Sendable {
        fileprivate let configuration: Configuration

        public func exportAsFile(projectId: String, useRelativeDates: Bool? = nil) async throws -> String {
            let response = try await configuration.requestRaw(
                method: .get,
                path: ENDPOINT_REST_TEMPLATES_FILE,
                payload: ["projectId": projectId, "useRelativeDates": useRelativeDates as Any].compactMapValues { $0 },
            )
            guard let string = String(data: response.data, encoding: .utf8) else {
                throw TodoistRequestError("Unable to decode template file")
            }
            return string
        }

        public func exportAsURL(projectId: String, useRelativeDates: Bool? = nil) async throws -> ExportTemplateURLResponse {
            try await configuration.request(
                ExportTemplateURLResponse.self,
                method: .get,
                path: ENDPOINT_REST_TEMPLATES_URL,
                payload: ["projectId": projectId, "useRelativeDates": useRelativeDates as Any].compactMapValues { $0 },
            )
        }

        public func createProject(
            name: String,
            file: UploadFileSource,
            fileName: String? = nil,
            workspaceId: String? = nil,
            requestId: String? = nil,
        ) async throws -> TemplateImportResponse {
            try await configuration.uploadMultipart(
                endpoint: ENDPOINT_REST_TEMPLATES_CREATE_FROM_FILE,
                file: file,
                fileName: fileName,
                additionalFields: [
                    "name": name,
                    "workspaceId": workspaceId as Any,
                ].compactMapValues { $0 },
                requestId: requestId,
            )
        }

        public func importIntoProject(
            projectId: String,
            file: UploadFileSource,
            fileName: String? = nil,
            requestId: String? = nil,
        ) async throws -> TemplateImportResponse {
            try await configuration.uploadMultipart(
                endpoint: ENDPOINT_REST_TEMPLATES_IMPORT_FROM_FILE,
                file: file,
                fileName: fileName,
                additionalFields: ["projectId": projectId],
                requestId: requestId,
            )
        }

        public func importFromTemplateID(
            projectId: String,
            templateId: String,
            locale: String? = nil,
            requestId: String? = nil,
        ) async throws -> TemplateImportResponse {
            try await configuration.request(
                TemplateImportResponse.self,
                method: .post,
                path: ENDPOINT_REST_TEMPLATES_IMPORT_FROM_ID,
                payload: [
                    "projectId": projectId,
                    "templateId": templateId,
                    "locale": locale as Any,
                ].compactMapValues { $0 },
                requestId: requestId,
            )
        }
    }

    public struct WorkspacesService: Sendable {
        fileprivate let configuration: Configuration

        public func list(requestId: String? = nil) async throws -> [Workspace] {
            try await configuration.request([Workspace].self, method: .get, path: ENDPOINT_WORKSPACES, requestId: requestId)
        }

        public func get(_ id: String, requestId: String? = nil) async throws -> Workspace {
            try await configuration.request(Workspace.self, method: .get, path: TodoistClientSupport.path(ENDPOINT_WORKSPACES, id), requestId: requestId)
        }

        public func create(_ request: WorkspaceCreateRequest, requestId: String? = nil) async throws -> Workspace {
            try await configuration.request(
                Workspace.self,
                method: .post,
                path: ENDPOINT_WORKSPACES,
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func update(_ id: String, _ request: WorkspaceUpdateRequest, requestId: String? = nil) async throws -> Workspace {
            try await configuration.request(
                Workspace.self,
                method: .post,
                path: TodoistClientSupport.path(ENDPOINT_WORKSPACES, id),
                payload: request.payload(),
                requestId: requestId,
            )
        }

        public func delete(_ id: String, requestId: String? = nil) async throws -> Bool {
            try await configuration.requestBool(
                method: .delete,
                path: TodoistClientSupport.path(ENDPOINT_WORKSPACES, id),
                requestId: requestId,
            )
        }
    }

    public struct SyncService: Sendable {
        fileprivate let configuration: Configuration

        public func execute(_ request: SyncRequest, requestId: String? = nil) async throws -> SyncResponse {
            if let commands = request.commands, commands.count > MAX_COMMAND_COUNT {
                throw TodoistRequestError("Maximum number of items is \(MAX_COMMAND_COUNT)", httpStatusCode: 400)
            }

            let processedCommands = request.commands.map(SyncHelpers.preprocessSyncCommands)
            let payload: [String: Any] = [
                "commands": processedCommands?.map { command in
                    var result: [String: Any] = [
                        "type": command.type.rawValue,
                        "uuid": command.uuid,
                        "args": command.args.reduce(into: [String: Any]()) { partialResult, item in
                            partialResult[item.key] = item.value.value
                        },
                    ]
                    if let tempId = command.tempId {
                        result["tempId"] = tempId
                    }
                    return result
                } as Any,
                "resourceTypes": request.resourceTypes as Any,
                "syncToken": request.syncToken as Any,
            ].compactMapValues { $0 }

            let response = try await configuration.request(
                SyncResponse.self,
                method: .post,
                path: ENDPOINT_SYNC,
                payload: payload,
                requestId: requestId,
                includeRequestIdForSync: processedCommands?.isEmpty == false,
            )

            if let syncStatus = response.syncStatus {
                for value in syncStatus.values {
                    switch value {
                    case .ok:
                        continue
                    case let .error(error):
                        throw TodoistRequestError(error.error, httpStatusCode: error.httpCode)
                    }
                }
            }

            return response
        }
    }

    private let configuration: Configuration

    public let tasks: TasksService
    public let projects: ProjectsService
    public let sections: SectionsService
    public let labels: LabelsService
    public let comments: CommentsService
    public let reminders: RemindersService
    public let uploads: UploadsService
    public let backups: BackupsService
    public let templates: TemplatesService
    public let workspaces: WorkspacesService
    public let syncAPI: SyncService

    public init(
        authToken: String,
        baseURL: String = todoistBaseURL,
        transport: Transport = DefaultTodoistTransport(),
    ) {
        let configuration = Configuration(authToken: authToken, baseURL: baseURL, transport: transport)
        self.configuration = configuration
        tasks = TasksService(configuration: configuration)
        projects = ProjectsService(configuration: configuration)
        sections = SectionsService(configuration: configuration)
        labels = LabelsService(configuration: configuration)
        comments = CommentsService(configuration: configuration)
        reminders = RemindersService(configuration: configuration)
        uploads = UploadsService(configuration: configuration)
        backups = BackupsService(configuration: configuration)
        templates = TemplatesService(configuration: configuration)
        workspaces = WorkspacesService(configuration: configuration)
        syncAPI = SyncService(configuration: configuration)
    }

    public func sync(_ request: SyncRequest, requestId: String? = nil) async throws -> SyncResponse {
        try await syncAPI.execute(request, requestId: requestId)
    }
}

public extension TaskCreateRequest {
    func validate() throws {
        if dueDate != nil, dueDatetime != nil {
            throw TodoistArgumentError("Only one of dueDate or dueDatetime can be provided.")
        }
        if (duration == nil) != (durationUnit == nil) {
            throw TodoistArgumentError("duration and durationUnit must be provided together.")
        }
    }

    func payload() -> [String: Any] {
        var payload: [String: Any] = [
            "content": UncompletableHelpers.processTaskContent(content, isUncompletable: isUncompletable),
        ]
        if let description { payload["description"] = description }
        if let projectId { payload["projectId"] = projectId }
        if let sectionId { payload["sectionId"] = sectionId }
        if let parentId { payload["parentId"] = parentId }
        if let order { payload["order"] = order }
        if let labels { payload["labels"] = labels }
        if let priority { payload["priority"] = priority }
        if let assigneeId { payload["assigneeId"] = assigneeId }
        if let dueString { payload["dueString"] = dueString }
        if let dueLang { payload["dueLang"] = dueLang }
        if let dueDate { payload["dueDate"] = dueDate }
        if let dueDatetime { payload["dueDatetime"] = dueDatetime }
        if let deadlineDate { payload["deadlineDate"] = deadlineDate }
        if let deadlineLang { payload["deadlineLang"] = deadlineLang }
        if let duration { payload["duration"] = duration }
        if let durationUnit { payload["durationUnit"] = durationUnit }
        if let isUncompletable { payload["isUncompletable"] = isUncompletable }
        return payload
    }
}

public extension TaskUpdateRequest {
    func validate() throws {
        if dueDate != nil, dueDatetime != nil {
            throw TodoistArgumentError("Only one of dueDate or dueDatetime can be provided.")
        }
        if (duration == nil) != (durationUnit == nil) {
            throw TodoistArgumentError("duration and durationUnit must be provided together.")
        }
    }

    func payload() -> [String: Any] {
        var payload: [String: Any] = [:]

        if let content {
            payload["content"] = UncompletableHelpers.processTaskContent(content, isUncompletable: isUncompletable)
        }
        if let description { payload["description"] = description }
        if let labels { payload["labels"] = labels }
        if let priority { payload["priority"] = priority }
        if let order { payload["childOrder"] = order }
        if let dueDate { payload["dueDate"] = dueDate }
        if let dueDatetime { payload["dueDatetime"] = dueDatetime }
        if let duration { payload["duration"] = duration }
        if let durationUnit { payload["durationUnit"] = durationUnit }
        if let isUncompletable { payload["isUncompletable"] = isUncompletable }

        switch dueString {
        case .unchanged:
            break
        case .null:
            payload["dueString"] = "no date"
        case let .value(value):
            payload["dueString"] = value
        }

        switch dueLang {
        case .unchanged:
            break
        case .null:
            payload["dueLang"] = NSNull()
        case let .value(value):
            payload["dueLang"] = value
        }

        switch assigneeId {
        case .unchanged:
            break
        case .null:
            payload["assigneeId"] = NSNull()
        case let .value(value):
            payload["assigneeId"] = value
        }

        switch deadlineDate {
        case .unchanged:
            break
        case .null:
            payload["deadlineDate"] = NSNull()
        case let .value(value):
            payload["deadlineDate"] = value
        }

        switch deadlineLang {
        case .unchanged:
            break
        case .null:
            payload["deadlineLang"] = NSNull()
        case let .value(value):
            payload["deadlineLang"] = value
        }

        return payload
    }
}

public extension ProjectCreateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = ["name": name]
        if let parentId { payload["parentId"] = parentId }
        if let color { payload["color"] = color }
        if let isFavorite { payload["isFavorite"] = isFavorite }
        if let viewStyle { payload["viewStyle"] = viewStyle }
        if let workspaceId { payload["workspaceId"] = workspaceId }
        return payload
    }
}

public extension ProjectUpdateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if let color { payload["color"] = color }
        if let isFavorite { payload["isFavorite"] = isFavorite }
        if let viewStyle { payload["viewStyle"] = viewStyle }
        return payload
    }
}

public extension SectionCreateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = ["name": name, "projectId": projectId]
        if let order { payload["order"] = order }
        return payload
    }
}

public extension SectionUpdateRequest {
    func payload() -> [String: Any] {
        ["name": name]
    }
}

public extension LabelCreateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = ["name": name]
        if let order { payload["order"] = order }
        if let color { payload["color"] = color }
        if let isFavorite { payload["isFavorite"] = isFavorite }
        return payload
    }
}

public extension LabelUpdateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if let order { payload["order"] = order }
        if let color { payload["color"] = color }
        if let isFavorite { payload["isFavorite"] = isFavorite }
        return payload
    }
}

public extension CommentCreateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = ["content": content]
        if let taskId { payload["taskId"] = taskId }
        if let projectId { payload["projectId"] = projectId }
        if let uidsToNotify { payload["uidsToNotify"] = uidsToNotify.joined(separator: ",") }
        if let attachment {
            payload["attachment"] = [
                "fileName": attachment.fileName as Any,
                "fileUrl": attachment.fileUrl,
                "fileType": attachment.fileType as Any,
                "resourceType": attachment.resourceType as Any,
            ].compactMapValues { $0 }
        }
        return payload
    }
}

public extension CommentUpdateRequest {
    func payload() -> [String: Any] {
        ["content": content]
    }
}

public extension RelativeReminderCreateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = [
            "taskId": taskId,
            "minuteOffset": minuteOffset,
        ]
        if let notifyUid { payload["notifyUid"] = notifyUid }
        if let service { payload["service"] = service }
        if let isUrgent { payload["isUrgent"] = isUrgent }
        return payload
    }
}

public extension AbsoluteReminderCreateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = [
            "taskId": taskId,
            "reminderType": ReminderType.absolute.rawValue,
            "due": try! JSONUtils.toJSONObject(due),
        ]
        if let notifyUid { payload["notifyUid"] = notifyUid }
        if let service { payload["service"] = service }
        if let isUrgent { payload["isUrgent"] = isUrgent }
        return payload
    }
}

public extension LocationReminderCreateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = [
            "taskId": taskId,
            "reminderType": ReminderType.location.rawValue,
            "name": name,
            "locLat": locLat,
            "locLong": locLong,
            "locTrigger": locTrigger,
        ]
        if let notifyUid { payload["notifyUid"] = notifyUid }
        if let radius { payload["radius"] = radius }
        return payload
    }
}

public extension RelativeReminderUpdateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = ["reminderType": ReminderType.relative.rawValue]
        if let minuteOffset { payload["minuteOffset"] = minuteOffset }
        if let notifyUid { payload["notifyUid"] = notifyUid }
        if let service { payload["service"] = service }
        if let isUrgent { payload["isUrgent"] = isUrgent }
        return payload
    }
}

public extension AbsoluteReminderUpdateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = ["reminderType": ReminderType.absolute.rawValue]
        if let due { payload["due"] = try! JSONUtils.toJSONObject(due) }
        if let notifyUid { payload["notifyUid"] = notifyUid }
        if let service { payload["service"] = service }
        if let isUrgent { payload["isUrgent"] = isUrgent }
        return payload
    }
}

public extension LocationReminderUpdateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let notifyUid { payload["notifyUid"] = notifyUid }
        if let name { payload["name"] = name }
        if let locLat { payload["locLat"] = locLat }
        if let locLong { payload["locLong"] = locLong }
        if let locTrigger { payload["locTrigger"] = locTrigger }
        if let radius { payload["radius"] = radius }
        return payload
    }
}

public extension WorkspaceCreateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = ["name": name]
        if let description { payload["description"] = description }
        if let isLinkSharingEnabled { payload["isLinkSharingEnabled"] = isLinkSharingEnabled }
        if let isGuestAllowed { payload["isGuestAllowed"] = isGuestAllowed }
        if let domainName { payload["domainName"] = domainName }
        if let domainDiscovery { payload["domainDiscovery"] = domainDiscovery }
        if let restrictEmailDomains { payload["restrictEmailDomains"] = restrictEmailDomains }
        return payload
    }
}

public extension WorkspaceUpdateRequest {
    func payload() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if let isLinkSharingEnabled { payload["isLinkSharingEnabled"] = isLinkSharingEnabled }
        if let isGuestAllowed { payload["isGuestAllowed"] = isGuestAllowed }
        if let domainDiscovery { payload["domainDiscovery"] = domainDiscovery }
        if let restrictEmailDomains { payload["restrictEmailDomains"] = restrictEmailDomains }
        if let isCollapsed { payload["isCollapsed"] = isCollapsed }

        switch description {
        case .unchanged:
            break
        case .null:
            payload["description"] = NSNull()
        case let .value(value):
            payload["description"] = value
        }

        switch domainName {
        case .unchanged:
            break
        case .null:
            payload["domainName"] = NSNull()
        case let .value(value):
            payload["domainName"] = value
        }

        return payload
    }
}

public extension TodoistClient {
    @available(*, deprecated, message: "Use tasks.get(_:)")
    func getTask(_ id: String) async throws -> Task {
        try await tasks.get(id)
    }

    @available(*, deprecated, message: "Use tasks.list(_:)")
    func getTasks(_ query: TaskQuery = .init()) async throws -> TodoistPage<Task> {
        try await tasks.list(query)
    }

    @available(*, deprecated, message: "Use tasks.create(_:requestId:)")
    func addTask(_ request: TaskCreateRequest, requestId: String? = nil) async throws -> Task {
        try await tasks.create(request, requestId: requestId)
    }

    @available(*, deprecated, message: "Use tasks.quickAdd(_:)")
    func quickAddTask(_ request: QuickAddTaskRequest) async throws -> Task {
        try await tasks.quickAdd(request)
    }

    @available(*, deprecated, message: "Use tasks.update(_:_:requestId:)")
    func updateTask(_ id: String, _ request: TaskUpdateRequest, requestId: String? = nil) async throws -> Task {
        try await tasks.update(id, request, requestId: requestId)
    }

    @available(*, deprecated, message: "Use tasks.move(_:to:requestId:)")
    func moveTask(_ id: String, to destination: TaskMoveDestination, requestId: String? = nil) async throws -> Task {
        try await tasks.move(id, to: destination, requestId: requestId)
    }

    @available(*, deprecated, message: "Use tasks.move(_:to:requestId:)")
    func moveTasks(_ ids: [String], to destination: TaskMoveDestination, requestId: String? = nil) async throws -> [Task] {
        try await tasks.move(ids, to: destination, requestId: requestId)
    }

    @available(*, deprecated, message: "Use tasks.close(_:requestId:)")
    func closeTask(_ id: String, requestId: String? = nil) async throws -> Bool {
        try await tasks.close(id, requestId: requestId)
    }

    @available(*, deprecated, message: "Use tasks.reopen(_:requestId:)")
    func reopenTask(_ id: String, requestId: String? = nil) async throws -> Bool {
        try await tasks.reopen(id, requestId: requestId)
    }

    @available(*, deprecated, message: "Use tasks.delete(_:requestId:)")
    func deleteTask(_ id: String, requestId: String? = nil) async throws -> Bool {
        try await tasks.delete(id, requestId: requestId)
    }

    @available(*, deprecated, message: "Use projects.get(_:)")
    func getProject(_ id: String) async throws -> Project {
        try await projects.get(id)
    }

    @available(*, deprecated, message: "Use projects.list(cursor:limit:)")
    func getProjects(cursor: String? = nil, limit: Int? = nil) async throws -> TodoistPage<Project> {
        try await projects.list(cursor: cursor, limit: limit)
    }

    @available(*, deprecated, message: "Use projects.create(_:requestId:)")
    func addProject(_ request: ProjectCreateRequest, requestId: String? = nil) async throws -> Project {
        try await projects.create(request, requestId: requestId)
    }

    @available(*, deprecated, message: "Use sections.get(_:)")
    func getSection(_ id: String) async throws -> Section {
        try await sections.get(id)
    }

    @available(*, deprecated, message: "Use labels.get(_:)")
    func getLabel(_ id: String) async throws -> Label {
        try await labels.get(id)
    }

    @available(*, deprecated, message: "Use comments.get(_:)")
    func getComment(_ id: String) async throws -> Comment {
        try await comments.get(id)
    }

    @available(*, deprecated, message: "Use reminders.get(_:)")
    func getReminder(_ id: String) async throws -> Reminder {
        try await reminders.get(id)
    }

    @available(*, deprecated, message: "Use reminders.getLocation(_:)")
    func getLocationReminder(_ id: String) async throws -> Reminder {
        try await reminders.getLocation(id)
    }

    @available(*, deprecated, message: "Use reminders.create(_:requestId:)")
    func addReminder(_ request: RelativeReminderCreateRequest, requestId: String? = nil) async throws -> Reminder {
        try await reminders.create(request, requestId: requestId)
    }

    @available(*, deprecated, message: "Use reminders.create(_:requestId:)")
    func addReminder(_ request: AbsoluteReminderCreateRequest, requestId: String? = nil) async throws -> Reminder {
        try await reminders.create(request, requestId: requestId)
    }

    @available(*, deprecated, message: "Use reminders.createLocation(_:requestId:)")
    func addLocationReminder(_ request: LocationReminderCreateRequest, requestId: String? = nil) async throws -> Reminder {
        try await reminders.createLocation(request, requestId: requestId)
    }

    @available(*, deprecated, message: "Use reminders.update(_:_:requestId:)")
    func updateReminder(_ id: String, _ request: RelativeReminderUpdateRequest, requestId: String? = nil) async throws -> Reminder {
        try await reminders.update(id, request, requestId: requestId)
    }

    @available(*, deprecated, message: "Use reminders.update(_:_:requestId:)")
    func updateReminder(_ id: String, _ request: AbsoluteReminderUpdateRequest, requestId: String? = nil) async throws -> Reminder {
        try await reminders.update(id, request, requestId: requestId)
    }

    @available(*, deprecated, message: "Use reminders.updateLocation(_:_:requestId:)")
    func updateLocationReminder(_ id: String, _ request: LocationReminderUpdateRequest, requestId: String? = nil) async throws -> Reminder {
        try await reminders.updateLocation(id, request, requestId: requestId)
    }

    @available(*, deprecated, message: "Use reminders.delete(_:requestId:)")
    func deleteReminder(_ id: String, requestId: String? = nil) async throws -> Bool {
        try await reminders.delete(id, requestId: requestId)
    }

    @available(*, deprecated, message: "Use reminders.deleteLocation(_:requestId:)")
    func deleteLocationReminder(_ id: String, requestId: String? = nil) async throws -> Bool {
        try await reminders.deleteLocation(id, requestId: requestId)
    }

    @available(*, deprecated, message: "Use uploads.upload(_:requestId:)")
    func uploadFile(_ request: UploadRequest, requestId: String? = nil) async throws -> Attachment {
        try await uploads.upload(request, requestId: requestId)
    }

    @available(*, deprecated, message: "Use uploads.delete(fileURL:requestId:)")
    func deleteUpload(fileURL: String, requestId: String? = nil) async throws -> Bool {
        try await uploads.delete(fileURL: fileURL, requestId: requestId)
    }

    @available(*, deprecated, message: "Use uploads.viewAttachment(url:)")
    func viewAttachment(_ url: String) async throws -> TodoistFileResponse {
        try await uploads.viewAttachment(url: url)
    }

    @available(*, deprecated, message: "Use uploads.viewAttachment(comment:)")
    func viewAttachment(_ comment: Comment) async throws -> TodoistFileResponse {
        try await uploads.viewAttachment(comment: comment)
    }
}
