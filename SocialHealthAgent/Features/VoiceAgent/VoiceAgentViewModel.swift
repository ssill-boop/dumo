import Foundation
import SwiftUI
import Combine

/// Manages the voice conversation flow and state
@MainActor
class VoiceAgentViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var statusText = "Tap to start speaking"
    @Published var showPermissionAlert = false
    @Published var permissionMessage = ""
    @Published var showError = false
    @Published var errorMessage = ""

    // MARK: - Private Properties

    private var sessionManager: SessionManager
    private var timer: Timer?
    private var startTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var lastProcessedText = ""
    private var isProcessingResponse = false

    // MARK: - Initialization

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        setupObservers()
    }

    // MARK: - Setup

    func setup() async {
        await sessionManager.speechService.requestPermissions()

        if !sessionManager.speechService.hasPermission {
            permissionMessage = sessionManager.speechService.errorMessage ?? "Microphone permission is required for the voice conversation."
            showPermissionAlert = true
            return
        }

        // Start the conversation with an AI greeting
        await startConversationWithGreeting()
    }

    private func setupObservers() {
        // Observe speech service state
        sessionManager.speechService.$isListening
            .receive(on: DispatchQueue.main)
            .sink { [weak self] listening in
                self?.isListening = listening
                self?.updateStatusText()
            }
            .store(in: &cancellables)

        sessionManager.speechService.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speaking in
                self?.isSpeaking = speaking
                self?.updateStatusText()
            }
            .store(in: &cancellables)

        // Observe transcribed text to detect when user stops speaking
        sessionManager.speechService.$transcribedText
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self = self,
                      !text.isEmpty,
                      text != self.lastProcessedText,
                      !self.isProcessingResponse else { return }

                self.lastProcessedText = text
                self.processUserInput(text)
            }
            .store(in: &cancellables)
    }

    // MARK: - Conversation Flow

    private func startConversationWithGreeting() async {
        statusText = "Getting ready..."

        do {
            let greeting = try await sessionManager.openAIService.sendConversationMessage(
                userMessage: "Start the conversation with a warm greeting.",
                conversationHistory: []
            )

            sessionManager.addMessage(role: .assistant, content: greeting)
            sessionManager.speechService.speak(greeting)

            // Start the timer
            startTimer()

        } catch {
            errorMessage = "Couldn't start the conversation: \(error.localizedDescription)"
            showError = true
        }
    }

    private func processUserInput(_ text: String) {
        guard !isProcessingResponse else { return }

        isProcessingResponse = true
        sessionManager.speechService.stopListening()

        // Add user message
        sessionManager.addMessage(role: .user, content: text)

        // Get AI response
        Task {
            do {
                let response = try await sessionManager.openAIService.sendConversationMessage(
                    userMessage: text,
                    conversationHistory: sessionManager.conversationMessages
                )

                sessionManager.addMessage(role: .assistant, content: response)
                sessionManager.speechService.speak(response)

            } catch {
                errorMessage = "Couldn't get a response: \(error.localizedDescription)"
                showError = true
            }

            isProcessingResponse = false
        }
    }

    // MARK: - Timer

    private func startTimer() {
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            let duration = Date().timeIntervalSince(startTime)
            Task { @MainActor in
                self.sessionManager.updateDuration(duration)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - User Actions

    func toggleListening() {
        if isListening {
            sessionManager.speechService.stopListening()
        } else {
            // Stop any current speech before listening
            if isSpeaking {
                sessionManager.speechService.stopSpeaking()
            }
            sessionManager.speechService.startListening()
        }
    }

    func finishConversation() {
        stopTimer()
        sessionManager.speechService.stopListening()
        sessionManager.speechService.stopSpeaking()

        // Generate activity recommendation
        Task {
            statusText = "Creating your perfect activity..."

            do {
                let activity = try await sessionManager.openAIService.generateActivityRecommendation(
                    transcript: sessionManager.session.fullTranscript
                )
                sessionManager.setGeneratedActivity(activity)
                sessionManager.showActivityRecommendation()

            } catch {
                errorMessage = "Couldn't generate activity: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    // MARK: - Helpers

    private func updateStatusText() {
        if isSpeaking {
            statusText = "Listening to you..."
        } else if isListening {
            statusText = "Speak now..."
        } else if isProcessingResponse {
            statusText = "Thinking..."
        } else {
            statusText = "Tap to speak"
        }
    }
}
