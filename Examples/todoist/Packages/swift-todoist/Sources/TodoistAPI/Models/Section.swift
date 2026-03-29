import Foundation

public struct Section: Codable, Sendable {
    public let id: String
    public let userId: String?
    public let projectId: String?
    public let addedAt: String?
    public let updatedAt: String?
    public let archivedAt: String?
    public let name: String
    public let sectionOrder: Int?
    public let isArchived: Bool
    public let isDeleted: Bool
    public let isCollapsed: Bool
    public let order: Int?
    public let url: String?

    public init(
        id: String,
        userId: String? = nil,
        projectId: String? = nil,
        addedAt: String? = nil,
        updatedAt: String? = nil,
        archivedAt: String? = nil,
        name: String,
        sectionOrder: Int? = nil,
        isArchived: Bool,
        isDeleted: Bool,
        isCollapsed: Bool,
        order: Int? = nil,
        url: String? = nil,
    ) {
        self.id = id
        self.userId = userId
        self.projectId = projectId
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.name = name
        self.sectionOrder = sectionOrder
        self.isArchived = isArchived
        self.isDeleted = isDeleted
        self.isCollapsed = isCollapsed
        self.order = order
        self.url = url
    }
}
