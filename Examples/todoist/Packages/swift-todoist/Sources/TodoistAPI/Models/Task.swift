import Foundation

public struct Task: Codable, Sendable {
    public let id: String
    public let userId: String?
    public let projectId: String?
    public let sectionId: String?
    public let parentId: String?
    public let assignedByUid: String?
    public let responsibleUid: String?
    public let labels: [String]
    public let deadline: Deadline?
    public let duration: Duration?
    public let checked: Bool
    public let isDeleted: Bool
    public let addedAt: String?
    public let completedAt: String?
    public let updatedAt: String?
    public let due: DueDate?
    public let priority: Int?
    public let childOrder: Int?
    public let content: String
    public let description: String?
    public let dayOrder: Int?
    public let isCollapsed: Bool
    public let isUncompletable: Bool
    public let order: Int?
    public let recurring: Bool?
    public let hasSubTasks: Bool?
    public let url: String?

    public init(
        id: String,
        userId: String? = nil,
        projectId: String? = nil,
        sectionId: String? = nil,
        parentId: String? = nil,
        assignedByUid: String? = nil,
        responsibleUid: String? = nil,
        labels: [String] = [],
        deadline: Deadline? = nil,
        duration: Duration? = nil,
        checked: Bool = false,
        isDeleted: Bool = false,
        addedAt: String? = nil,
        completedAt: String? = nil,
        updatedAt: String? = nil,
        due: DueDate? = nil,
        priority: Int? = nil,
        childOrder: Int? = nil,
        content: String,
        description: String? = nil,
        dayOrder: Int? = nil,
        isCollapsed: Bool = false,
        isUncompletable: Bool = false,
        order: Int? = nil,
        recurring: Bool? = nil,
        hasSubTasks: Bool? = nil,
        url: String? = nil,
    ) {
        self.id = id
        self.userId = userId
        self.projectId = projectId
        self.sectionId = sectionId
        self.parentId = parentId
        self.assignedByUid = assignedByUid
        self.responsibleUid = responsibleUid
        self.labels = labels
        self.deadline = deadline
        self.duration = duration
        self.checked = checked
        self.isDeleted = isDeleted
        self.addedAt = addedAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.due = due
        self.priority = priority
        self.childOrder = childOrder
        self.content = content
        self.description = description
        self.dayOrder = dayOrder
        self.isCollapsed = isCollapsed
        self.isUncompletable = isUncompletable
        self.order = order
        self.recurring = recurring
        self.hasSubTasks = hasSubTasks
        self.url = url
    }
}

public struct Deadline: Codable, Sendable {
    public let date: String
    public let lang: String?
}
