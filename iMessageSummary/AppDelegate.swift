import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var config: AppConfig!
    private(set) var appState: AppState!
    private var sidebarController: SidebarWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = AppConfig.load()
        appState = AppState(config: config)

        sidebarController = SidebarWindowController(state: appState)
        sidebarController?.show()
        configureStatusItem()

        Task { await appState.reloadSummarizedContacts() }

        #if DEBUG
        iMessageDB.runConsoleSmokeTest()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

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
