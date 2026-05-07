import AppKit
import SwiftUI

@MainActor
final class SidebarWindowController {
    let panel: NSPanel
    private static let frameKey = "iMessageSummary.sidebar.frame"

    init(state: AppState) {
        let frame = SidebarWindowController.savedFrame() ?? SidebarWindowController.defaultFrame()
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Summaries"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 280, height: 400)
        panel.maxSize = NSSize(width: 480, height: .greatestFiniteMagnitude)
        panel.contentView = NSHostingView(rootView: SidebarView().environmentObject(state))
        self.panel = panel
        observeFrameChanges()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Position persistence

    private func observeFrameChanges() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.persistFrame()
        }
        center.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.persistFrame()
        }
    }

    private func persistFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    private static func savedFrame() -> NSRect? {
        guard let str = UserDefaults.standard.string(forKey: frameKey), !str.isEmpty else {
            return nil
        }
        let rect = NSRectFromString(str)
        return rect.isEmpty ? nil : rect
    }

    private static func defaultFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 100, y: 100, width: 320, height: 600)
        }
        let visible = screen.visibleFrame
        let width: CGFloat = 320
        return NSRect(
            x: visible.maxX - width,
            y: visible.minY,
            width: width,
            height: visible.height
        )
    }
}
