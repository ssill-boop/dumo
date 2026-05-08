import Foundation

/// Per-handle local cache of the most recent summary, used as a fallback
/// when Supabase is unconfigured or unreachable. Keyed by phone/email.
final class LocalSummaryCache {
    struct Entry: Codable {
        var bulletPoints: [String]
        var summaryText: String
        var lastMessageRowID: Int64
        var lastMessageDate: Date
        var generatedAt: Date
        var generatedBy: String
        var modelVersion: String
    }

    private let defaults: UserDefaults
    private let prefix = "iMessageSummary.cache.summary."
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        self.encoder = e
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
    }

    func read(handle: String) -> Entry? {
        guard let data = defaults.data(forKey: key(for: handle)) else { return nil }
        return try? decoder.decode(Entry.self, from: data)
    }

    func write(handle: String, entry: Entry) {
        guard let data = try? encoder.encode(entry) else { return }
        defaults.set(data, forKey: key(for: handle))
    }

    func remove(handle: String) {
        defaults.removeObject(forKey: key(for: handle))
    }

    /// Wipe every cached summary. Used by the "Clear local cache" button in
    /// Settings to recover from stale entries.
    func clearAll() {
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    func allHandles() -> [String] {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    private func key(for handle: String) -> String {
        prefix + handle
    }
}
