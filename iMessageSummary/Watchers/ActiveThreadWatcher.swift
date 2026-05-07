import AppKit
import ApplicationServices
import Foundation

/// Detects which iMessage conversation is currently active.
///
/// On modern macOS, Messages is a Catalyst app whose conversation list is an
/// `AXGroup` (`CKConversationListCollectionView`) — it does *not* expose
/// `AXSelectedRows` the way a native AppKit `AXOutline` would. AXObservers for
/// selection notifications never fire. Two signals are reliable:
///
/// 1. The Messages main window's title changes to the active contact's name.
/// 2. An `AXButton` with `AXIdentifier == "ConversationTitle"` sits at the top
///    of the message pane and exposes the same name as a fallback.
///
/// We poll those at ~1 Hz instead of relying on accessibility notifications.
@MainActor
final class ActiveThreadWatcher {
    enum Event {
        case permissionDenied
        case messagesNotRunning
        case selectionChanged(displayString: String?)
    }

    private(set) var isWatching = false
    private var onEvent: ((Event) -> Void)?
    private var pollTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastReported: String?
    private var sawMessagesProcess = true

    private static let messagesBundleID = "com.apple.MobileSMS"
    private static let pollInterval: TimeInterval = 1.0

    deinit {
        for token in workspaceObservers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func start(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        guard hasAccessibilityPermission(promptIfNeeded: false) else {
            print("[Watcher] no AX permission")
            onEvent(.permissionDenied)
            return
        }
        print("[Watcher] starting (polling mode)")
        isWatching = true
        registerWorkspaceObservers()
        startPolling()
        poll()
    }

    func stop() {
        isWatching = false
        pollTimer?.invalidate()
        pollTimer = nil
        for token in workspaceObservers {
            NotificationCenter.default.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - Permission

    @discardableResult
    static func requestAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func hasAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        ActiveThreadWatcher.requestAccessibilityPermission(promptIfNeeded: promptIfNeeded)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.messagesBundleID).first else {
            if sawMessagesProcess {
                sawMessagesProcess = false
                lastReported = nil
                print("[Watcher] Messages not running")
                onEvent?(.messagesNotRunning)
            }
            return
        }
        sawMessagesProcess = true
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        let display = readActiveConversation(appEl: appEl)
        if display != lastReported {
            lastReported = display
            print("[Watcher] active conversation: \(display ?? "nil")")
            onEvent?(.selectionChanged(displayString: display))
        }
    }

    private func readActiveConversation(appEl: AXUIElement) -> String? {
        // Primary: window title (Messages updates this to the active contact name).
        if let title = mainWindowTitle(appEl: appEl), !isGenericWindowTitle(title) {
            return title
        }
        // Fallback: the ConversationTitle button at the top of the message pane.
        if let button = findElement(in: appEl, where: { el in
            self.string(of: el, attribute: "AXIdentifier" as CFString) == "ConversationTitle"
        }) {
            for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
                if let s = string(of: button, attribute: attr as CFString),
                   !s.isEmpty,
                   !isGenericWindowTitle(s) {
                    return s
                }
            }
        }
        return nil
    }

    private func mainWindowTitle(appEl: AXUIElement) -> String? {
        if let main = attributeValue(of: appEl, attribute: kAXMainWindowAttribute as CFString) as AXUIElement?,
           let title = string(of: main, attribute: kAXTitleAttribute as CFString) {
            return title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if let windows: [AXUIElement] = children(of: appEl, attribute: kAXWindowsAttribute),
           let first = windows.first,
           let title = string(of: first, attribute: kAXTitleAttribute as CFString) {
            return title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return nil
    }

    private func isGenericWindowTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return lowered == "messages" || lowered == "new message" || lowered == "imessage"
    }

    // MARK: - Workspace observers

    private func registerWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let activated = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == ActiveThreadWatcher.messagesBundleID
            else { return }
            Task { @MainActor in self?.poll() }
        }
        let launched = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == ActiveThreadWatcher.messagesBundleID
            else { return }
            Task { @MainActor in self?.poll() }
        }
        workspaceObservers = [activated, launched]
    }

    // MARK: - BFS

    private func findElement(
        in appEl: AXUIElement,
        where predicate: (AXUIElement) -> Bool,
        maxDepth: Int = 20
    ) -> AXUIElement? {
        let skipRoles: Set<String> = ["AXMenuBar", "AXMenu", "AXMenuItem", "AXMenuButton"]
        let windows: [AXUIElement] = children(of: appEl, attribute: kAXWindowsAttribute) ?? [appEl]
        for window in windows {
            var queue: [(AXUIElement, Int)] = [(window, 0)]
            while !queue.isEmpty {
                let (node, depth) = queue.removeFirst()
                if depth > maxDepth { continue }
                let role = string(of: node, attribute: kAXRoleAttribute as CFString) ?? ""
                if skipRoles.contains(role) { continue }
                if predicate(node) { return node }
                if let kids = children(of: node, attribute: kAXChildrenAttribute) {
                    for kid in kids { queue.append((kid, depth + 1)) }
                }
            }
        }
        return nil
    }

    // MARK: - AX helpers

    private func attributeValue<T>(of element: AXUIElement, attribute: CFString) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? T
    }

    private func string(of element: AXUIElement, attribute: CFString) -> String? {
        attributeValue(of: element, attribute: attribute)
    }

    private func children(of element: AXUIElement, attribute: String) -> [AXUIElement]? {
        attributeValue(of: element, attribute: attribute as CFString)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
