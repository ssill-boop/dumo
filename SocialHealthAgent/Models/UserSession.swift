import Foundation

/// Tracks all data for a single user session
/// Lives only while app is open - no persistent storage
struct UserSession: Codable {
    /// Unique identifier for this session
    let sessionId: UUID

    /// When the session started
    let startTime: Date

    /// How long the voice conversation lasted
    var conversationDuration: TimeInterval

    /// Key snippets from the conversation for debugging/analysis
    var transcriptSnippets: [String]

    /// The full conversation transcript
    var fullTranscript: String

    /// The AI-generated activity recommendation (nil until generated)
    var generatedActivity: GeneratedActivity?

    /// User's response to the activity: true = Yes, false = No, nil = not answered yet
    var userResponse: Bool?

    /// The price shown for the event
    var eventPrice: Decimal

    /// Optional feedback if user declined the activity
    var declineFeedback: String?

    /// Creates a new session with default values
    init() {
        self.sessionId = UUID()
        self.startTime = Date()
        self.conversationDuration = 0
        self.transcriptSnippets = []
        self.fullTranscript = ""
        self.generatedActivity = nil
        self.userResponse = nil
        self.eventPrice = Constants.defaultEventPrice
        self.declineFeedback = nil
    }
}

/// Represents a single message in the conversation
struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
}
