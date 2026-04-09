import Foundation

public struct Project: Codable, Sendable {
  public let id: String
  public let canAssignTasks: Bool?
  public let childOrder: Int?
  public let color: String?
  public let createdAt: String?
  public let isArchived: Bool
  public let isDeleted: Bool
  public let isFavorite: Bool
  public let isFrozen: Bool
  public let name: String
  public let updatedAt: String?
  public let viewStyle: String?
  public let defaultOrder: Int?
  public let description: String?
  public let isCollapsed: Bool?
  public let isShared: Bool?
  public let parentId: String?
  public let inboxProject: Bool?
  public let access: ProjectAccess?
  public let collaboratorRoleDefault: String?
  public let folderId: String?
  public let isInviteOnly: Bool?
  public let isLinkSharingEnabled: Bool?
  public let role: String?
  public let status: String?
  public let workspaceId: String?
  public let url: String?

  public init(
    id: String,
    canAssignTasks: Bool? = nil,
    childOrder: Int? = nil,
    color: String? = nil,
    createdAt: String? = nil,
    isArchived: Bool,
    isDeleted: Bool,
    isFavorite: Bool,
    isFrozen: Bool,
    name: String,
    updatedAt: String? = nil,
    viewStyle: String? = nil,
    defaultOrder: Int? = nil,
    description: String? = nil,
    isCollapsed: Bool? = nil,
    isShared: Bool? = nil,
    parentId: String? = nil,
    inboxProject: Bool? = nil,
    access: ProjectAccess? = nil,
    collaboratorRoleDefault: String? = nil,
    folderId: String? = nil,
    isInviteOnly: Bool? = nil,
    isLinkSharingEnabled: Bool? = nil,
    role: String? = nil,
    status: String? = nil,
    workspaceId: String? = nil,
    url: String? = nil,
  ) {
    self.id = id
    self.canAssignTasks = canAssignTasks
    self.childOrder = childOrder
    self.color = color
    self.createdAt = createdAt
    self.isArchived = isArchived
    self.isDeleted = isDeleted
    self.isFavorite = isFavorite
    self.isFrozen = isFrozen
    self.name = name
    self.updatedAt = updatedAt
    self.viewStyle = viewStyle
    self.defaultOrder = defaultOrder
    self.description = description
    self.isCollapsed = isCollapsed
    self.isShared = isShared
    self.parentId = parentId
    self.inboxProject = inboxProject
    self.access = access
    self.collaboratorRoleDefault = collaboratorRoleDefault
    self.folderId = folderId
    self.isInviteOnly = isInviteOnly
    self.isLinkSharingEnabled = isLinkSharingEnabled
    self.role = role
    self.status = status
    self.workspaceId = workspaceId
    self.url = url
  }
}

public struct ProjectAccess: Codable, Sendable {
  public let visibility: String
}
