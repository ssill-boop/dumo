import AppKit
import ApplicationServices
import Combine
import SwiftUI

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published var fullDiskOK = false
    @Published var accessibilityOK = false
    @Published var anthropicOK = false

    private var pollTimer: Timer?
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        reload()
    }

    var canContinue: Bool {
        fullDiskOK && accessibilityOK && anthropicOK
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func reload() {
        fullDiskOK = canReadChatDB()
        accessibilityOK = AXIsProcessTrusted()
        anthropicOK = AppConfig.load().hasAnthropicKey
    }

    func openFullDiskSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestAccessibility() {
        _ = ActiveThreadWatcher.requestAccessibilityPermission(promptIfNeeded: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func revealEnvFile() {
        AppConfig.ensureEnvFileExists()
        NSWorkspace.shared.activateFileViewerSelecting([AppConfig.envFileURL])
    }

    func dismiss() {
        stopPolling()
        onComplete()
    }

    private func canReadChatDB() -> Bool {
        let path = iMessageDB.defaultPath
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let db = iMessageDB(path: path)
        do {
            try db.open()
            db.close()
            return true
        } catch {
            return false
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set up iMessage Summary")
                .font(.title2.bold())
            Text("Three things before we can read your messages and summarize them.")
                .font(.callout)
                .foregroundStyle(.secondary)

            stepRow(
                title: "Full Disk Access",
                detail: "iMessage Summary needs to read your messages database (~/Library/Messages/chat.db).",
                isOK: coordinator.fullDiskOK,
                buttonTitle: "Open System Settings…",
                action: coordinator.openFullDiskSettings
            )

            stepRow(
                title: "Accessibility Access",
                detail: "iMessage Summary needs to detect which conversation you're viewing.",
                isOK: coordinator.accessibilityOK,
                buttonTitle: "Open System Settings…",
                action: coordinator.requestAccessibility
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Anthropic API key").font(.headline)
                    Spacer()
                    Image(systemName: coordinator.anthropicOK ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(coordinator.anthropicOK ? .green : .secondary)
                }
                Text("Edit ~/.imessage-summary/.env to add ANTHROPIC_API_KEY (and optional Supabase keys).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reveal in Finder", action: coordinator.revealEnvFile)
                    Button("Reload", action: coordinator.reload)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Continue") { coordinator.dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!coordinator.canContinue)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 540)
        .onAppear { coordinator.startPolling() }
        .onDisappear { coordinator.stopPolling() }
    }

    private func stepRow(
        title: String,
        detail: String,
        isOK: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Image(systemName: isOK ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isOK ? .green : .secondary)
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(buttonTitle, action: action)
                Spacer()
            }
        }
    }
}
