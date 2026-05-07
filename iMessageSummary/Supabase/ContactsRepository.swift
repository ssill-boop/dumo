import Foundation

final class ContactsRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Look up by phone_or_email; create if missing. Patch the display_name
    /// if we now have a non-empty value and it differs from the stored one.
    func findOrCreate(phoneOrEmail: String, displayName: String?) async throws -> Contact {
        let existing: [Contact] = try await client.get(
            "imessage_contacts",
            query: [
                URLQueryItem(name: "phone_or_email", value: "eq.\(phoneOrEmail)"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        if let found = existing.first {
            if let new = displayName?.nilIfEmpty, found.displayName != new {
                struct Patch: Encodable { let display_name: String }
                let updated: [Contact] = try await client.update(
                    "imessage_contacts",
                    query: [URLQueryItem(name: "id", value: "eq.\(found.id.uuidString)")],
                    body: Patch(display_name: new)
                )
                return updated.first ?? found
            }
            return found
        }
        struct New: Encodable {
            let phone_or_email: String
            let display_name: String?
        }
        let inserted: [Contact] = try await client.insert(
            "imessage_contacts",
            body: New(phone_or_email: phoneOrEmail, display_name: displayName?.nilIfEmpty)
        )
        guard let contact = inserted.first else { throw SupabaseClient.Error.emptyResponse }
        return contact
    }

    func fetchAll() async throws -> [Contact] {
        try await client.get(
            "imessage_contacts",
            query: [URLQueryItem(name: "order", value: "display_name.asc.nullslast")]
        )
    }

    func setBlacklisted(contactID: UUID, isBlacklisted: Bool) async throws -> Contact {
        struct Patch: Encodable { let is_blacklisted: Bool }
        let updated: [Contact] = try await client.update(
            "imessage_contacts",
            query: [URLQueryItem(name: "id", value: "eq.\(contactID.uuidString)")],
            body: Patch(is_blacklisted: isBlacklisted)
        )
        guard let contact = updated.first else { throw SupabaseClient.Error.emptyResponse }
        return contact
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
