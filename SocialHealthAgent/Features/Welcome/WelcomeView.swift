import SwiftUI

/// The welcome screen - first thing users see
/// Sets the warm, inviting tone and explains what to expect
struct WelcomeView: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        ZStack {
            // Warm gradient background
            LinearGradient(
                colors: [Color(hex: "F5F0EB"), Color(hex: "E8E0D5")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // App icon/logo area
                ZStack {
                    Circle()
                        .fill(Color(hex: "7A9E7E").opacity(0.2))
                        .frame(width: 120, height: 120)

                    Circle()
                        .fill(Color(hex: "7A9E7E").opacity(0.4))
                        .frame(width: 80, height: 80)

                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(Color(hex: "7A9E7E"))
                }

                // Welcome message
                VStack(spacing: 16) {
                    Text("Welcome")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "3D3D3D"))

                    Text("Let's discover the social connections\nthat will truly light you up.")
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "666666"))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer()

                // Explanation card
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "7A9E7E"))

                        Text("How it works")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "3D3D3D"))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ExplanationRow(
                            number: "1",
                            text: "We'll have a 5-minute voice conversation"
                        )
                        ExplanationRow(
                            number: "2",
                            text: "I'll learn about your interests and values"
                        )
                        ExplanationRow(
                            number: "3",
                            text: "You'll get a personalized activity recommendation"
                        )
                    }
                }
                .padding(24)
                .background(Color.white.opacity(0.8))
                .cornerRadius(20)
                .padding(.horizontal, 24)

                Spacer()

                // Start button
                Button(action: {
                    sessionManager.startConversation()
                }) {
                    HStack {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18))
                        Text("Start Conversation")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color(hex: "7A9E7E"))
                    .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
    }
}

/// A single row in the explanation list
struct ExplanationRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color(hex: "7A9E7E"))
                .cornerRadius(12)

            Text(text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "4A4A4A"))
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    WelcomeView(sessionManager: SessionManager())
}
