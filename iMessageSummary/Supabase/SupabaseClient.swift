import Foundation

/// Thin wrapper over PostgREST. Uses the anon key per the spec
/// (single-user trusted env with permissive RLS).
final class SupabaseClient {
    enum Error: Swift.Error, CustomStringConvertible {
        case requestFailed(status: Int, body: String)
        case decoding(Swift.Error)
        case emptyResponse

        var description: String {
            switch self {
            case .requestFailed(let status, let body):
                return "supabase request failed (\(status)): \(body)"
            case .decoding(let err):
                return "supabase decoding error: \(err)"
            case .emptyResponse:
                return "supabase returned no rows where one was expected"
            }
        }
    }

    let baseURL: URL
    let anonKey: String
    private let session: URLSession
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init?(url: URL?, anonKey: String?, session: URLSession = .shared) {
        guard let url, let anonKey, !anonKey.isEmpty else { return nil }
        self.baseURL = url
        self.anonKey = anonKey
        self.session = session
        self.encoder = SupabaseClient.makeEncoder()
        self.decoder = SupabaseClient.makeDecoder()
    }

    // MARK: - REST methods

    func get<T: Decodable>(_ table: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: endpoint(table), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.percentEncodedQueryItems = query.map(Self.encodeForPostgREST)
        }
        var request = URLRequest(url: components.url!)
        authorize(&request)
        request.httpMethod = "GET"
        return try await execute(request)
    }

    func insert<Body: Encodable, T: Decodable>(_ table: String, body: Body) async throws -> T {
        var request = URLRequest(url: endpoint(table))
        authorize(&request)
        request.httpMethod = "POST"
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(body)
        return try await execute(request)
    }

    func update<Body: Encodable, T: Decodable>(_ table: String, query: [URLQueryItem], body: Body) async throws -> T {
        var components = URLComponents(url: endpoint(table), resolvingAgainstBaseURL: false)!
        components.percentEncodedQueryItems = query.map(Self.encodeForPostgREST)
        var request = URLRequest(url: components.url!)
        authorize(&request)
        request.httpMethod = "PATCH"
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(body)
        return try await execute(request)
    }

    // MARK: - Internals

    private func endpoint(_ table: String) -> URL {
        baseURL.appendingPathComponent("rest/v1").appendingPathComponent(table)
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw Error.requestFailed(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        if data.isEmpty, T.self == EmptyResponse.self {
            // swiftlint:disable:next force_cast
            return EmptyResponse() as! T
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }

    /// PostgREST treats `+` in URL query strings as a literal space (form-
    /// encoded behavior), so phone numbers like `+15551234567` never match
    /// when encoded by URLComponents' default `urlQueryAllowed` set (which
    /// considers `+` safe). Pre-encode `+` (and anything else outside the
    /// urlQueryAllowed set) here.
    private static let postgrestQueryAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+")
        return set
    }()

    private static func encodeForPostgREST(_ item: URLQueryItem) -> URLQueryItem {
        let encoded = item.value.map { value in
            value.addingPercentEncoding(withAllowedCharacters: postgrestQueryAllowed) ?? value
        }
        return URLQueryItem(name: item.name, value: encoded)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        let formatter = SupabaseClient.iso8601WithFractional
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let withFractional = SupabaseClient.iso8601WithFractional
        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            // PostgREST returns "2025-04-12T14:32:00.123456+00:00" or similar.
            // ISO8601DateFormatter only accepts millisecond precision, so trim.
            let trimmed = SupabaseClient.normalizeFractionalSeconds(raw)
            if let d = withFractional.date(from: trimmed) { return d }
            if let d = withoutFractional.date(from: trimmed) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable date: \(raw)"
            )
        }
        return decoder
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// PostgREST may emit microsecond precision (".123456"); ISO8601DateFormatter
    /// only handles milliseconds. Truncate the fractional component to 3 digits.
    private static func normalizeFractionalSeconds(_ raw: String) -> String {
        guard let dot = raw.firstIndex(of: ".") else { return raw }
        var i = raw.index(after: dot)
        var digitCount = 0
        while i < raw.endIndex, raw[i].isNumber {
            digitCount += 1
            i = raw.index(after: i)
        }
        guard digitCount > 3 else { return raw }
        let keepUntil = raw.index(dot, offsetBy: 4) // dot + 3 digits
        let prefix = String(raw[..<keepUntil])
        let suffix = String(raw[i...])
        return prefix + suffix
    }
}

struct EmptyResponse: Decodable {}
