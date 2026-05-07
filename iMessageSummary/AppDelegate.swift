import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var config: AppConfig!
    private(set) var appState: AppState!
    private var sidebarController: SidebarWindowController?
    private var pipeline: SummaryPipeline?
    private var statusItem: NSStatusItem?

    private var onboardingWindow: NSWindow?
    private var onboardingCoordinator: OnboardingCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = AppConfig.load()
        appState = AppState(config: config)
        configureStatusItem()

        if needsOnboarding() {
            presentOnboarding()
        } else {
            startSidebar()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Onboarding gate

    private func needsOnboarding() -> Bool {
        if !canReadChatDB() { return true }
        if !AXIsProcessTrusted() { return true }
        if !config.hasAnthropicKey { return true }
        return false
    }

    private func canReadChatDB() -> Bool {
        let db = iMessageDB()
        do {
            try db.open()
            db.close()
            return true
        } catch {
            return false
        }
    }

    private func presentOnboarding() {
        let coordinator = OnboardingCoordinator { [weak self] in
            self?.onboardingDidComplete()
        }
        let view = OnboardingView(coordinator: coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
        onboardingCoordinator = coordinator
    }

    private func onboardingDidComplete() {
        onboardingWindow?.close()
        onboardingWindow = nil
        onboardingCoordinator = nil

        // Re-load config in case the user just added the API key.
        config = AppConfig.load()
        appState = AppState(config: config)
        startSidebar()
    }

    // MARK: - App startup

    private func startSidebar() {
        let sidebar = SidebarWindowController(state: appState)
        sidebar.show()
        sidebarController = sidebar

        let pipeline = SummaryPipeline(state: appState)
        pipeline.start()
        self.pipeline = pipeline

        Task { await appState.reloadSummarizedContacts() }
    }

    // MARK: - Status item

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "bubble.left.and.bubble.right",
                accessibilityDescription: "iMessage Summary"
            )
            button.action = #selector(toggleSidebar)
            button.target = self
        }
        statusItem = item
    }

    @objc private func toggleSidebar() {
        sidebarController?.toggle()
    }
}
