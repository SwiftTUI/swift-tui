import Foundation

public struct DueDate: Codable, Sendable {
  public let string: String
  public let date: String
  public let datetime: String?
  public let timezone: String?
  public let lang: String?
  public let isRecurring: Bool?

  public init(
    string: String,
    date: String,
    datetime: String? = nil,
    timezone: String? = nil,
    lang: String? = nil,
    isRecurring: Bool? = nil,
  ) {
    self.string = string
    self.date = date
    self.datetime = datetime
    self.timezone = timezone
    self.lang = lang
    self.isRecurring = isRecurring
  }
}

public struct Duration: Codable, Sendable {
  public let amount: Int
  public let unit: String
}
