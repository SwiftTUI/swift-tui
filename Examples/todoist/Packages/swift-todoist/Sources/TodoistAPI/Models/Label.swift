public struct Label: Codable, Sendable {
  public let id: String
  public let order: Int?
  public let name: String
  public let color: String?
  public let isFavorite: Bool
}
