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

  enum CodingKeys: String, CodingKey {
    case id
    case userId
    case projectId
    case sectionId
    case parentId
    case assignedByUid
    case responsibleUid
    case labels
    case deadline
    case duration
    case checked
    case isDeleted
    case addedAt
    case completedAt
    case updatedAt
    case due
    case priority
    case childOrder
    case content
    case description
    case dayOrder
    case isCollapsed
    case isUncompletable
    case order
    case recurring
    case hasSubTasks
    case url
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(String.self, forKey: .id)
    userId = try container.decodeIfPresent(String.self, forKey: .userId)
    projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
    sectionId = try container.decodeIfPresent(String.self, forKey: .sectionId)
    parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
    assignedByUid = try container.decodeIfPresent(String.self, forKey: .assignedByUid)
    responsibleUid = try container.decodeIfPresent(String.self, forKey: .responsibleUid)
    labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
    deadline = try container.decodeIfPresent(Deadline.self, forKey: .deadline)
    duration = try container.decodeIfPresent(Duration.self, forKey: .duration)
    checked = try container.decode(Bool.self, forKey: .checked)
    isDeleted = try container.decode(Bool.self, forKey: .isDeleted)
    addedAt = try container.decodeIfPresent(String.self, forKey: .addedAt)
    completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
    updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    due = try container.decodeIfPresent(DueDate.self, forKey: .due)
    priority = try container.decodeIfPresent(Int.self, forKey: .priority)
    childOrder = try container.decodeIfPresent(Int.self, forKey: .childOrder)
    content = try container.decode(String.self, forKey: .content)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    dayOrder = try container.decodeIfPresent(Int.self, forKey: .dayOrder)
    isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
    isUncompletable =
      try container.decodeIfPresent(Bool.self, forKey: .isUncompletable) ?? false
    order = try container.decodeIfPresent(Int.self, forKey: .order)
    recurring = try container.decodeIfPresent(Bool.self, forKey: .recurring)
    hasSubTasks = try container.decodeIfPresent(Bool.self, forKey: .hasSubTasks)
    url = try container.decodeIfPresent(String.self, forKey: .url)
  }
}

public struct Deadline: Codable, Sendable {
  public let date: String
  public let lang: String?
}
