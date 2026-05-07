import Foundation

struct Summary: Codable, Identifiable, Hashable {
    let id: UUID
    let contactId: UUID
    let summaryText: String
    let bulletPoints: [String]
    let lastMessageRowID: Int64
    let lastMessageDate: Date
    let messageWindowStart: Date?
    let generatedBy: String
    let modelVersion: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case contactId = "contact_id"
        case summaryText = "summary_text"
        case bulletPoints = "bullet_points"
        case lastMessageRowID = "last_message_rowid"
        case lastMessageDate = "last_message_date"
        case messageWindowStart = "message_window_start"
        case generatedBy = "generated_by"
        case modelVersion = "model_version"
        case createdAt = "created_at"
    }
}

/// Wire-shape for inserting a new summary row. The DB fills in id and created_at.
struct NewSummary: Encodable {
    let contact_id: UUID
    let summary_text: String
    let bullet_points: [String]
    let last_message_rowid: Int64
    let last_message_date: Date
    let message_window_start: Date?
    let generated_by: String
    let model_version: String
}
