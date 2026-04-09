import Foundation

public struct Comment: Codable, Sendable {
  public let id: String
  public let taskId: String?
  public let projectId: String?
  public let content: String
  public let postedAt: String?
  public let fileAttachment: Attachment?
  public let postedUid: String?
  public let uidsToNotify: [String]?
  public let reactions: [String: [String]]?
  public let isDeleted: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case taskId
    case itemId
    case projectId
    case content
    case postedAt
    case fileAttachment
    case postedUid
    case uidsToNotify
    case reactions
    case isDeleted
  }

  public init(
    id: String,
    taskId: String? = nil,
    projectId: String? = nil,
    content: String,
    postedAt: String? = nil,
    fileAttachment: Attachment? = nil,
    postedUid: String? = nil,
    uidsToNotify: [String]? = nil,
    reactions: [String: [String]]? = nil,
    isDeleted: Bool,
  ) {
    self.id = id
    self.taskId = taskId
    self.projectId = projectId
    self.content = content
    self.postedAt = postedAt
    self.fileAttachment = fileAttachment
    self.postedUid = postedUid
    self.uidsToNotify = uidsToNotify
    self.reactions = reactions
    self.isDeleted = isDeleted
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    taskId =
      try
      (container.decodeIfPresent(String.self, forKey: .taskId)
      ?? container.decodeIfPresent(String.self, forKey: .itemId))
    projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
    content = try container.decode(String.self, forKey: .content)
    postedAt = try container.decodeIfPresent(String.self, forKey: .postedAt)
    fileAttachment = try container.decodeIfPresent(Attachment.self, forKey: .fileAttachment)
    postedUid = try container.decodeIfPresent(String.self, forKey: .postedUid)
    uidsToNotify = try container.decodeIfPresent([String].self, forKey: .uidsToNotify)
    reactions = try container.decodeIfPresent([String: [String]].self, forKey: .reactions)
    isDeleted = try container.decode(Bool.self, forKey: .isDeleted)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(taskId, forKey: .taskId)
    try container.encode(projectId, forKey: .projectId)
    try container.encode(content, forKey: .content)
    try container.encode(postedAt, forKey: .postedAt)
    try container.encode(fileAttachment, forKey: .fileAttachment)
    try container.encode(postedUid, forKey: .postedUid)
    try container.encode(uidsToNotify, forKey: .uidsToNotify)
    try container.encode(reactions, forKey: .reactions)
    try container.encode(isDeleted, forKey: .isDeleted)
  }
}
