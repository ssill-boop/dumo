import Foundation

final class SummariesRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func latestSummary(contactID: UUID) async throws -> Summary? {
        let results: [Summary] = try await client.get(
            "imessage_summaries",
            query: [
                URLQueryItem(name: "contact_id", value: "eq.\(contactID.uuidString)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return results.first
    }

    func insert(_ summary: NewSummary) async throws -> Summary {
        let inserted: [Summary] = try await client.insert("imessage_summaries", body: summary)
        guard let value = inserted.first else { throw SupabaseClient.Error.emptyResponse }
        return value
    }

    /// Returns contacts that have at least one summary row, deduped.
    /// PostgREST embeds + a non-empty inner filter would also work; this is
    /// simpler and good enough at v1 scale.
    func contactsWithSummaries(via contactsRepo: ContactsRepository) async throws -> [Contact] {
        struct Row: Decodable { let contact_id: UUID }
        let rows: [Row] = try await client.get(
            "imessage_summaries",
            query: [URLQueryItem(name: "select", value: "contact_id")]
        )
        let ids = Set(rows.map(\.contact_id))
        guard !ids.isEmpty else { return [] }
        let all = try await contactsRepo.fetchAll()
        return all.filter { ids.contains($0.id) }
    }
}
