public struct Workspace: Codable, Sendable {
    public let id: String
    public let name: String
    public let plan: String
    public let role: String
    public let inviteCode: String?
    public let isLinkSharingEnabled: Bool
    public let isGuestAllowed: Bool
    public let createdAt: String?
    public let creatorId: String?
    public let logoBig: String?
    public let logoMedium: String?
    public let logoSmall: String?
    public let logoS640: String?
}
