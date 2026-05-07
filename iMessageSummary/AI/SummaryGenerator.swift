import Foundation

final class SummaryGenerator {
    enum Error: Swift.Error, CustomStringConvertible {
        case requestFailed(status: Int, body: String)
        case noTextContent
        case malformedJSON(String)

        var description: String {
            switch self {
            case .requestFailed(let status, let body):
                return "anthropic request failed (\(status)): \(body)"
            case .noTextContent:
                return "anthropic response had no text block"
            case .malformedJSON(let raw):
                return "anthropic returned malformed JSON: \(raw)"
            }
        }
    }

    struct Output: Decodable {
        let bulletPoints: [String]
        let summaryText: String

        enum CodingKeys: String, CodingKey {
            case bulletPoints = "bullet_points"
            case summaryText = "summary_text"
        }
    }

    static let defaultModel = "claude-haiku-4-5-20251001"

    let apiKey: String
    let model: String
    private let session: URLSession

    init(apiKey: String, model: String = SummaryGenerator.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func generateInitial(displayName: String, handle: String, messages: [Message]) async throws -> Output {
        let prompt = Self.initialPrompt(displayName: displayName, handle: handle, messages: messages)
        return try await call(userPrompt: prompt)
    }

    func generateUpdate(displayName: String, handle: String, prior: Summary, newMessages: [Message]) async throws -> Output {
        let prompt = try Self.updatePrompt(
            displayName: displayName,
            handle: handle,
            prior: prior,
            newMessages: newMessages
        )
        return try await call(userPrompt: prompt)
    }

    // MARK: - HTTP

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let temperature: Double
        let messages: [Msg]
        struct Msg: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ResponseBody: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
    }

    private func call(userPrompt: String) async throws -> Output {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: model,
            max_tokens: 1000,
            temperature: 0,
            messages: [.init(role: "user", content: userPrompt)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw Error.requestFailed(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        let parsed = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let text = parsed.content.first(where: { $0.type == "text" })?.text, !text.isEmpty else {
            throw Error.noTextContent
        }
        let cleaned = Self.stripCodeFences(text)
        guard let payload = cleaned.data(using: .utf8) else {
            throw Error.malformedJSON(text)
        }
        do {
            return try JSONDecoder().decode(Output.self, from: payload)
        } catch {
            throw Error.malformedJSON(text)
        }
    }

    /// Defensive: occasionally Claude wraps JSON in ``` even when told not to.
    private static func stripCodeFences(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3))
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt construction

    private static let messageDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f
    }()

    static func initialPrompt(displayName: String, handle: String, messages: [Message]) -> String {
        let formatted = formatMessages(displayName: displayName, messages: messages)
        let start = messages.first.map { messageDateFormatter.string(from: $0.date) } ?? "?"
        let end = messages.last.map { messageDateFormatter.string(from: $0.date) } ?? "?"
        return """
        You are summarizing a personal iMessage conversation thread.
        Extract only information that is still likely to be relevant today.
        Focus on: upcoming plans, ongoing situations, recent life updates, open questions or threads, shared projects.
        Ignore: one-off logistics already resolved, old plans that have passed, small talk.

        Format your response as JSON with this shape:
        {
          "bullet_points": ["string", "string", ...],
          "summary_text": "string"
        }

        Return only valid JSON. No preamble, no markdown fences.

        Contact: \(displayName) (\(handle))
        Messages (\(messages.count) total, from \(start) to \(end)):

        \(formatted)
        """
    }

    static func updatePrompt(displayName: String, handle: String, prior: Summary, newMessages: [Message]) throws -> String {
        struct PriorWire: Encodable {
            let bullet_points: [String]
            let summary_text: String
        }
        let priorData = try JSONEncoder().encode(PriorWire(
            bullet_points: prior.bulletPoints,
            summary_text: prior.summaryText
        ))
        let priorJSON = String(data: priorData, encoding: .utf8) ?? "{}"
        let formatted = formatMessages(displayName: displayName, messages: newMessages)
        let start = newMessages.first.map { messageDateFormatter.string(from: $0.date) } ?? "?"
        let end = newMessages.last.map { messageDateFormatter.string(from: $0.date) } ?? "?"
        return """
        You are updating an existing summary of a personal iMessage conversation thread.
        You have the prior summary and a set of new messages since that summary was generated.
        Update the bullet points to reflect the current state of the conversation.
        Remove bullets that are now outdated or resolved. Add bullets for new relevant topics.
        Keep bullets that are still relevant unchanged.

        Format your response as JSON:
        {
          "bullet_points": ["string", ...],
          "summary_text": "string"
        }

        Return only valid JSON. No preamble, no markdown fences.

        Contact: \(displayName) (\(handle))

        Prior summary:
        \(priorJSON)

        New messages (\(newMessages.count) since last summary, \(start) to \(end)):
        \(formatted)
        """
    }

    private static func formatMessages(displayName: String, messages: [Message]) -> String {
        messages.compactMap { msg -> String? in
            // Strip iMessage's attachment placeholder (U+FFFC) so the model
            // sees clean text rather than mystery characters.
            let cleaned = msg.text
                .replacingOccurrences(of: "\u{FFFC}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            let when = messageDateFormatter.string(from: msg.date)
            let who = msg.isFromMe ? "Me" : displayName
            return "[\(when)] \(who): \(cleaned)"
        }.joined(separator: "\n")
    }
}
