import SwiftUI

/// Thank you screen shown after user responds to the activity
/// Different content based on whether they accepted or declined
struct ThankYouView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var feedbackText = ""
    @State private var showContent = false
    @FocusState private var isFeedbackFocused: Bool

    private var accepted: Bool {
        sessionManager.session.userResponse ?? false
    }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "F5F0EB"), Color(hex: "E8E0D5")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .onTapGesture {
                isFeedbackFocused = false
            }

            ScrollView {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: 60)

                    // Success icon
                    ZStack {
                        Circle()
                            .fill(accepted ? Color(hex: "7A9E7E").opacity(0.2) : Color(hex: "E0E0E0").opacity(0.5))
                            .frame(width: 120, height: 120)

                        Image(systemName: accepted ? "heart.fill" : "hand.wave.fill")
                            .font(.system(size: 50))
                            .foregroundColor(accepted ? Color(hex: "7A9E7E") : Color(hex: "888888"))
                    }
                    .scaleEffect(showContent ? 1 : 0.5)
                    .opacity(showContent ? 1 : 0)

                    // Message
                    VStack(spacing: 16) {
                        Text(accepted ? "Wonderful!" : "Thanks for trying!")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "3D3D3D"))

                        Text(accepted
                            ? "We're building this experience and will notify you when it's ready. Your interest helps us create meaningful connections."
                            : "We appreciate you taking the time to explore. Your feedback helps us create better experiences.")
                            .font(.system(size: 17, weight: .regular, design: .rounded))
                            .foregroundColor(Color(hex: "666666"))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 24)
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)

                    // Feedback section (only for declined)
                    if !accepted {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Mind sharing why? (optional)")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "666666"))

                            TextEditor(text: $feedbackText)
                                .font(.system(size: 16, design: .rounded))
                                .frame(minHeight: 100)
                                .padding(12)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(hex: "E0E0E0"), lineWidth: 1)
                                )
                                .focused($isFeedbackFocused)

                            if !feedbackText.isEmpty {
                                Button(action: {
                                    sessionManager.recordActivityResponse(accepted: false, feedback: feedbackText)
                                    isFeedbackFocused = false
                                }) {
                                    Text("Submit Feedback")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color(hex: "7A9E7E"))
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                        .background(Color.white.opacity(0.6))
                        .cornerRadius(20)
                        .padding(.horizontal, 20)
                        .opacity(showContent ? 1 : 0)
                    }

                    // Session summary card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your Session")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "666666"))

                        HStack(spacing: 24) {
                            SummaryItem(
                                icon: "clock.fill",
                                value: sessionManager.formattedDuration,
                                label: "Duration"
                            )

                            SummaryItem(
                                icon: "bubble.left.and.bubble.right.fill",
                                value: "\(sessionManager.conversationMessages.count)",
                                label: "Messages"
                            )

                            if let activity = sessionManager.session.generatedActivity {
                                SummaryItem(
                                    icon: "sparkles",
                                    value: "1",
                                    label: "Activity"
                                )
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.6))
                    .cornerRadius(16)
                    .padding(.horizontal, 20)
                    .opacity(showContent ? 1 : 0)

                    Spacer()
                        .frame(height: 40)

                    // Start over button
                    Button(action: {
                        sessionManager.logSessionData()
                        sessionManager.startOver()
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 16))
                            Text("Start Over")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "7A9E7E"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color(hex: "7A9E7E").opacity(0.15))
                        .cornerRadius(16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                    .opacity(showContent ? 1 : 0)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.2)) {
                showContent = true
            }
        }
    }
}

/// Summary item showing a stat from the session
struct SummaryItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "7A9E7E"))

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "3D3D3D"))

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "999999"))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ThankYouView(sessionManager: SessionManager())
}
