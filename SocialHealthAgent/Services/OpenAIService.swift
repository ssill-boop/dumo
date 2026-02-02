import Foundation

/// Handles all communication with OpenAI's API
/// Used for both the conversational agent and activity generation
class OpenAIService: ObservableObject {

    // MARK: - Published Properties

    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    /// Your OpenAI API key - replace with your actual key
    /// For production, this should be stored securely (Keychain)
    /// For prototype testing, you can hardcode it here
    private var apiKey: String {
        // Try to get from environment or use placeholder
        // IMPORTANT: Replace "YOUR_API_KEY_HERE" with your actual OpenAI API key
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "YOUR_API_KEY_HERE"
    }

    // MARK: - Conversation Methods

    /// Send a message to the conversational agent and get a response
    /// - Parameters:
    ///   - userMessage: The user's spoken message
    ///   - conversationHistory: Previous messages in the conversation
    /// - Returns: The AI's response text
    func sendConversationMessage(
        userMessage: String,
        conversationHistory: [ConversationMessage]
    ) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        // Build the messages array for the API
        var messages: [[String: String]] = [
            ["role": "system", "content": Constants.conversationalAgentPrompt]
        ]

        // Add conversation history
        for message in conversationHistory {
            messages.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        // Add the new user message
        messages.append(["role": "user", "content": userMessage])

        let requestBody: [String: Any] = [
            "model": Constants.openAIModel,
            "messages": messages,
            "max_tokens": 150,
            "temperature": 0.8
        ]

        let response = try await makeAPIRequest(body: requestBody)
        return response
    }

    /// Generate an activity recommendation based on the conversation transcript
    /// - Parameter transcript: The full conversation transcript
    /// - Returns: A GeneratedActivity struct with the recommendation
    func generateActivityRecommendation(transcript: String) async throws -> GeneratedActivity {
        isLoading = true
        defer { isLoading = false }

        let messages: [[String: String]] = [
            ["role": "system", "content": Constants.activityGeneratorPrompt],
            ["role": "user", "content": "Here is the conversation transcript:\n\n\(transcript)"]
        ]

        let requestBody: [String: Any] = [
            "model": Constants.openAIModel,
            "messages": messages,
            "max_tokens": 500,
            "temperature": 0.7
        ]

        let responseText = try await makeAPIRequest(body: requestBody)

        // Parse the JSON response into a GeneratedActivity
        guard let jsonData = responseText.data(using: .utf8) else {
            throw OpenAIError.invalidResponse("Could not convert response to data")
        }

        do {
            let activity = try JSONDecoder().decode(GeneratedActivity.self, from: jsonData)
            return activity
        } catch {
            // Try to extract JSON from the response if it contains extra text
            if let jsonStart = responseText.firstIndex(of: "{"),
               let jsonEnd = responseText.lastIndex(of: "}") {
                let jsonString = String(responseText[jsonStart...jsonEnd])
                if let cleanData = jsonString.data(using: .utf8) {
                    let activity = try JSONDecoder().decode(GeneratedActivity.self, from: cleanData)
                    return activity
                }
            }
            throw OpenAIError.parsingError("Could not parse activity: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    /// Make the actual API request to OpenAI
    private func makeAPIRequest(body: [String: Any]) async throws -> String {
        guard let url = URL(string: Constants.openAIEndpoint) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw OpenAIError.serializationError(error.localizedDescription)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse the OpenAI response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse("Could not parse API response")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Error Types

enum OpenAIError: LocalizedError {
    case invalidURL
    case invalidResponse(String)
    case serializationError(String)
    case parsingError(String)
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .serializationError(let message):
            return "Failed to serialize request: \(message)"
        case .parsingError(let message):
            return "Failed to parse response: \(message)"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        }
    }
}
