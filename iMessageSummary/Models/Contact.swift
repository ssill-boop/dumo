import Foundation

struct Contact: Codable, Identifiable, Hashable {
    let id: UUID
    let phoneOrEmail: String
    let displayName: String?
    let isBlacklisted: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case phoneOrEmail = "phone_or_email"
        case displayName = "display_name"
        case isBlacklisted = "is_blacklisted"
        case createdAt = "created_at"
    }

    var bestDisplayName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return phoneOrEmail
    }
}
