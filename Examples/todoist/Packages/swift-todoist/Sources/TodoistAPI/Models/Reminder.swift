import Foundation

public struct Reminder: Codable, Sendable {
  public let id: String
  public let notifyUid: String?
  public let itemId: String
  public let projectId: String?
  public let isDeleted: Bool
  public let type: ReminderType
  public let due: DueDate?
  public let minuteOffset: Int?
  public let isUrgent: Bool?
  public let name: String?
  public let locLat: String?
  public let locLong: String?
  public let locTrigger: String?
  public let radius: Int?

  public init(
    id: String,
    notifyUid: String? = nil,
    itemId: String,
    projectId: String? = nil,
    isDeleted: Bool,
    type: ReminderType,
    due: DueDate? = nil,
    minuteOffset: Int? = nil,
    isUrgent: Bool? = nil,
    name: String? = nil,
    locLat: String? = nil,
    locLong: String? = nil,
    locTrigger: String? = nil,
    radius: Int? = nil,
  ) {
    self.id = id
    self.notifyUid = notifyUid
    self.itemId = itemId
    self.projectId = projectId
    self.isDeleted = isDeleted
    self.type = type
    self.due = due
    self.minuteOffset = minuteOffset
    self.isUrgent = isUrgent
    self.name = name
    self.locLat = locLat
    self.locLong = locLong
    self.locTrigger = locTrigger
    self.radius = radius
  }
}

public enum ReminderType: String, Codable, Sendable {
  case absolute
  case relative
  case location
}
