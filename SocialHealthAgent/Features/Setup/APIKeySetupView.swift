import SwiftUI

/// Screen for entering the OpenAI API key
/// Shown on first launch before the welcome screen
struct APIKeySetupView: View {
    @Binding var isConfigured: Bool
    @State private var apiKey = ""
    @State private var showError = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "F5F0EB"), Color(hex: "E8E0D5")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Icon
                Image(systemName: "key.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color(hex: "7A9E7E"))

                // Title
                VStack(spacing: 12) {
                    Text("One-Time Setup")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "3D3D3D"))

                    Text("Enter your OpenAI API key to enable\nthe AI conversation features.")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(Color(hex: "666666"))
                        .multilineTextAlignment(.center)
                }

                // Input field
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "666666"))

                    SecureField("sk-...", text: $apiKey)
                        .font(.system(size: 16, design: .monospaced))
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(showError ? Color.red.opacity(0.5) : Color(hex: "E0E0E0"), lineWidth: 1)
                        )

                    if showError {
                        Text("Please enter a valid API key (starts with sk-)")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 24)

                // Help text
                VStack(spacing: 8) {
                    Text("Don't have an API key?")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(Color(hex: "888888"))

                    Link("Get one from OpenAI →", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "7A9E7E"))
                }

                Spacer()

                // Save button
                Button(action: saveAPIKey) {
                    Text("Save & Continue")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(apiKey.isEmpty ? Color.gray : Color(hex: "7A9E7E"))
                        .cornerRadius(16)
                }
                .disabled(apiKey.isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Basic validation
        guard trimmedKey.hasPrefix("sk-") else {
            showError = true
            return
        }

        // Save the key
        OpenAIService.storedAPIKey = trimmedKey
        isConfigured = true
    }
}

#Preview {
    APIKeySetupView(isConfigured: .constant(false))
}
