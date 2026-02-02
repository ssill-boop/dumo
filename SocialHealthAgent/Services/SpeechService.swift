import Foundation
import AVFoundation
import Speech

/// Handles speech-to-text and text-to-speech functionality
/// Uses Apple's built-in Speech framework for recognition
/// and AVSpeechSynthesizer for speaking responses
@MainActor
class SpeechService: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// Whether the service is currently listening for speech
    @Published var isListening = false

    /// Whether the service is currently speaking
    @Published var isSpeaking = false

    /// The current transcribed text from the user
    @Published var transcribedText = ""

    /// Error message if something goes wrong
    @Published var errorMessage: String?

    /// Whether microphone permission is granted
    @Published var hasPermission = false

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Initialization

    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        synthesizer.delegate = self
    }

    // MARK: - Permission Handling

    /// Request both microphone and speech recognition permissions
    func requestPermissions() async {
        // Request microphone permission
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Could not set up audio session: \(error.localizedDescription)"
            return
        }

        // Request speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        switch speechStatus {
        case .authorized:
            hasPermission = true
        case .denied:
            errorMessage = "Speech recognition permission was denied. Please enable it in Settings."
            hasPermission = false
        case .restricted:
            errorMessage = "Speech recognition is restricted on this device."
            hasPermission = false
        case .notDetermined:
            errorMessage = "Speech recognition permission not determined."
            hasPermission = false
        @unknown default:
            errorMessage = "Unknown speech recognition authorization status."
            hasPermission = false
        }
    }

    // MARK: - Speech Recognition (Listening)

    /// Start listening for speech input
    func startListening() {
        guard hasPermission else {
            errorMessage = "Microphone permission not granted"
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available"
            return
        }

        // Stop any existing recognition
        stopListening()

        // Reset transcribed text for new input
        transcribedText = ""

        do {
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }

            let inputNode = audioEngine.inputNode
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

            guard let recognitionRequest = recognitionRequest else {
                errorMessage = "Could not create recognition request"
                return
            }

            recognitionRequest.shouldReportPartialResults = true

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    Task { @MainActor in
                        self.transcribedText = result.bestTranscription.formattedString
                    }
                }

                if error != nil || (result?.isFinal ?? false) {
                    Task { @MainActor in
                        self.stopListening()
                    }
                }
            }

            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            errorMessage = nil

        } catch {
            errorMessage = "Could not start audio engine: \(error.localizedDescription)"
            stopListening()
        }
    }

    /// Stop listening for speech input
    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    // MARK: - Text-to-Speech (Speaking)

    /// Speak the given text aloud
    func speak(_ text: String) {
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9 // Slightly slower for clarity
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stop speaking immediately
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
