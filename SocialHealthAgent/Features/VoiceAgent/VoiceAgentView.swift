import SwiftUI

/// The main voice conversation screen
/// Shows the pulsing voice indicator, transcript, and timer
struct VoiceAgentView: View {
    @ObservedObject var sessionManager: SessionManager
    @StateObject private var viewModel: VoiceAgentViewModel

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        self._viewModel = StateObject(wrappedValue: VoiceAgentViewModel(sessionManager: sessionManager))
    }

    var body: some View {
        ZStack {
            // Background
            Color(hex: "F5F0EB")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Timer in top right
                HStack {
                    Spacer()
                    TimerView(duration: sessionManager.session.conversationDuration)
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                }

                Spacer()

                // Voice indicator
                VoiceIndicatorView(
                    isListening: viewModel.isListening,
                    isSpeaking: viewModel.isSpeaking
                )
                .padding(.bottom, 40)

                // Status text
                Text(viewModel.statusText)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "666666"))
                    .padding(.bottom, 32)

                Spacer()

                // Transcript area
                TranscriptView(messages: sessionManager.conversationMessages)
                    .frame(maxHeight: 300)
                    .padding(.horizontal, 24)

                Spacer()

                // Bottom controls
                VStack(spacing: 16) {
                    // Minimum time notice
                    if !sessionManager.hasReachedMinimumDuration {
                        HStack {
                            Image(systemName: "clock")
                                .font(.system(size: 14))
                            Text("Chat for at least 5 minutes to continue")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "999999"))
                    }

                    // Action buttons
                    HStack(spacing: 16) {
                        // Mic toggle button
                        Button(action: {
                            viewModel.toggleListening()
                        }) {
                            HStack {
                                Image(systemName: viewModel.isListening ? "mic.slash.fill" : "mic.fill")
                                Text(viewModel.isListening ? "Pause" : "Speak")
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(viewModel.isListening ? Color(hex: "E07A5F") : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(viewModel.isListening ? Color(hex: "E07A5F").opacity(0.15) : Color(hex: "7A9E7E"))
                            .cornerRadius(14)
                        }

                        // Continue button (enabled after 5 min)
                        Button(action: {
                            viewModel.finishConversation()
                        }) {
                            HStack {
                                Text("Continue")
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                sessionManager.hasReachedMinimumDuration
                                ? Color(hex: "7A9E7E")
                                : Color(hex: "CCCCCC")
                            )
                            .cornerRadius(14)
                        }
                        .disabled(!sessionManager.hasReachedMinimumDuration)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .task {
            await viewModel.setup()
        }
        .alert("Permission Required", isPresented: $viewModel.showPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.permissionMessage)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

/// Displays the conversation timer
struct TimerView: View {
    let duration: TimeInterval

    private var formattedTime: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var progress: Double {
        min(duration / Constants.minimumConversationDuration, 1.0)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color(hex: "E0E0E0"), lineWidth: 3)
                    .frame(width: 32, height: 32)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color(hex: "7A9E7E"), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
            }

            Text(formattedTime)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "4A4A4A"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.8))
        .cornerRadius(20)
    }
}

/// Animated voice indicator
struct VoiceIndicatorView: View {
    let isListening: Bool
    let isSpeaking: Bool

    @State private var animationAmount: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.0

    private var isActive: Bool {
        isListening || isSpeaking
    }

    private var activeColor: Color {
        isSpeaking ? Color(hex: "5B8C5A") : Color(hex: "7A9E7E")
    }

    var body: some View {
        ZStack {
            // Outer pulse rings
            ForEach(0..<3) { i in
                Circle()
                    .stroke(activeColor.opacity(pulseOpacity * (1 - Double(i) * 0.3)), lineWidth: 2)
                    .frame(width: 120 + CGFloat(i) * 40, height: 120 + CGFloat(i) * 40)
                    .scaleEffect(isActive ? animationAmount : 1.0)
            }

            // Main circle
            Circle()
                .fill(activeColor)
                .frame(width: 100, height: 100)
                .scaleEffect(isActive ? 1.0 + (animationAmount - 1.0) * 0.1 : 1.0)

            // Icon
            Image(systemName: isSpeaking ? "waveform" : "mic.fill")
                .font(.system(size: 36))
                .foregroundColor(.white)
        }
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true)
            ) {
                animationAmount = 1.3
                pulseOpacity = 0.6
            }
        }
    }
}

/// Scrolling conversation transcript
struct TranscriptView: View {
    let messages: [ConversationMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: messages.count) { _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color.white.opacity(0.5))
        .cornerRadius(16)
    }
}

/// Individual message bubble
struct MessageBubble: View {
    let message: ConversationMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "You" : "Coach")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "999999"))

                Text(message.content)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "3D3D3D"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color(hex: "7A9E7E").opacity(0.2) : Color.white)
                    .cornerRadius(16)
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 8)
    }
}

#Preview {
    VoiceAgentView(sessionManager: SessionManager())
}
