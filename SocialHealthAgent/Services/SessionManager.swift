import Foundation
import SwiftUI

/// Manages the current user session and app navigation state
/// This is the central coordinator for tracking progress through the app
@MainActor
class SessionManager: ObservableObject {

    // MARK: - Published Properties

    /// Current screen being displayed
    @Published var currentScreen: AppScreen = .welcome

    /// The current user session data
    @Published var session: UserSession = UserSession()

    /// Conversation messages for display
    @Published var conversationMessages: [ConversationMessage] = []

    /// Whether the user declined the activity
    @Published var didDeclineActivity: Bool = false

    // MARK: - Services

    let speechService = SpeechService()
    let openAIService = OpenAIService()

    // MARK: - Computed Properties

    /// Formatted conversation duration as MM:SS
    var formattedDuration: String {
        let minutes = Int(session.conversationDuration) / 60
        let seconds = Int(session.conversationDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Whether the minimum conversation time has been reached
    var hasReachedMinimumDuration: Bool {
        session.conversationDuration >= Constants.minimumConversationDuration
    }

    /// Formatted price for display
    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: session.eventPrice as NSNumber) ?? "$\(session.eventPrice)"
    }

    // MARK: - Navigation Methods

    /// Start a new conversation session
    func startConversation() {
        session = UserSession()
        conversationMessages = []
        currentScreen = .voiceAgent
    }

    /// Move to the activity recommendation screen
    func showActivityRecommendation() {
        currentScreen = .activityRecommendation
    }

    /// Move to the thank you screen
    func showThankYou() {
        currentScreen = .thankYou
    }

    /// Reset the app to the beginning
    func startOver() {
        session = UserSession()
        conversationMessages = []
        didDeclineActivity = false
        currentScreen = .welcome
    }

    // MARK: - Session Data Methods

    /// Add a message to the conversation
    func addMessage(role: MessageRole, content: String) {
        let message = ConversationMessage(role: role, content: content)
        conversationMessages.append(message)
        session.transcriptSnippets.append("\(role.rawValue): \(content)")
        updateFullTranscript()
    }

    /// Update the conversation duration
    func updateDuration(_ duration: TimeInterval) {
        session.conversationDuration = duration
    }

    /// Record the user's response to the activity
    func recordActivityResponse(accepted: Bool, feedback: String? = nil) {
        session.userResponse = accepted
        didDeclineActivity = !accepted
        if let feedback = feedback {
            session.declineFeedback = feedback
        }
    }

    /// Set the generated activity
    func setGeneratedActivity(_ activity: GeneratedActivity) {
        session.generatedActivity = activity
    }

    // MARK: - Private Methods

    /// Build the full transcript from all messages
    private func updateFullTranscript() {
        session.fullTranscript = conversationMessages
            .map { "\($0.role == .user ? "User" : "Coach"): \($0.content)" }
            .joined(separator: "\n\n")
    }

    // MARK: - Analytics (for future use)

    /// Log session data for analysis
    func logSessionData() {
        print("=== Session Analytics ===")
        print("Session ID: \(session.sessionId)")
        print("Duration: \(formattedDuration)")
        print("Messages: \(conversationMessages.count)")
        print("Activity Generated: \(session.generatedActivity?.title ?? "None")")
        print("User Response: \(session.userResponse?.description ?? "None")")
        print("Price Shown: \(formattedPrice)")
        if let feedback = session.declineFeedback {
            print("Decline Feedback: \(feedback)")
        }
        print("========================")
    }
}
