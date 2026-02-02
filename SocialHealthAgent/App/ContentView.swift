import SwiftUI

/// Main navigation coordinator for the app
/// Controls which screen is displayed based on app state
struct ContentView: View {
    @StateObject private var sessionManager = SessionManager()

    var body: some View {
        NavigationStack {
            switch sessionManager.currentScreen {
            case .welcome:
                WelcomeView(sessionManager: sessionManager)
            case .voiceAgent:
                VoiceAgentView(sessionManager: sessionManager)
            case .activityRecommendation:
                ActivityCardView(sessionManager: sessionManager)
            case .thankYou:
                ThankYouView(sessionManager: sessionManager)
            }
        }
        .preferredColorScheme(.light)
    }
}

/// Represents the different screens in the app flow
enum AppScreen {
    case welcome
    case voiceAgent
    case activityRecommendation
    case thankYou
}

#Preview {
    ContentView()
}
