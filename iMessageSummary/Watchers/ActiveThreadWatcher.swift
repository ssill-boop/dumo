import AppKit
import ApplicationServices
import Foundation

/// Observes which conversation row is selected in iMessage and emits the
/// row's display string (a contact name or a phone/email) on each change.
///
/// Strategy:
///   1. Find the running iMessage process (`com.apple.MobileSMS`).
///   2. Build an AXUIElement for it and search the window subtree for an
///      AXOutline / AXTable whose selected row carries the conversation
///      identifier.
///   3. Install an AX observer for AXSelectedRowsChangedNotification on
///      that element so we update without polling.
///   4. Reattach when iMessage is launched / activated.
///
/// If AX permission isn't granted (`AXIsProcessTrusted` is false), the
/// watcher reports `.permissionDenied` and stops; the onboarding flow
/// surfaces the prompt to System Settings.
@MainActor
final class ActiveThreadWatcher {
    enum Event {
        case permissionDenied
        case messagesNotRunning
        case selectionChanged(displayString: String?)
    }

    private(set) var isWatching = false
    private var onEvent: ((Event) -> Void)?

    private var messagesPID: pid_t?
    private var appElement: AXUIElement?
    private var observer: AXObserver?
    private var observedElement: AXUIElement?
    private var workspaceObservers: [NSObjectProtocol] = []

    private static let messagesBundleID = "com.apple.MobileSMS"

    deinit {
        // observers are torn down explicitly below, but make sure timers stop
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
        print("[Watcher] starting")
        isWatching = true
        registerWorkspaceObservers()
        attach()
    }

    func stop() {
        isWatching = false
        detach()
        for token in workspaceObservers {
            NotificationCenter.default.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - Permission

    /// `AXIsProcessTrustedWithOptions` triggers the system's "untrusted app"
    /// banner the first time we ask with prompt=true. The onboarding flow
    /// passes prompt=true; the watcher itself prefers prompt=false.
    @discardableResult
    static func requestAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func hasAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        ActiveThreadWatcher.requestAccessibilityPermission(promptIfNeeded: promptIfNeeded)
    }

    // MARK: - Lifecycle

    private func registerWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let activated = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == ActiveThreadWatcher.messagesBundleID
            else { return }
            Task { @MainActor in self.attach() }
        }
        let launched = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == ActiveThreadWatcher.messagesBundleID
            else { return }
            Task { @MainActor in self.attach() }
        }
        let terminated = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == ActiveThreadWatcher.messagesBundleID
            else { return }
            Task { @MainActor in
                self.detach()
                self.onEvent?(.messagesNotRunning)
            }
        }
        workspaceObservers = [activated, launched, terminated]
    }

    private func attach() {
        detach()
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.messagesBundleID).first else {
            print("[Watcher] Messages not running")
            onEvent?(.messagesNotRunning)
            return
        }
        let pid = app.processIdentifier
        messagesPID = pid
        print("[Watcher] attaching to Messages pid=\(pid)")
        let appEl = AXUIElementCreateApplication(pid)
        appElement = appEl

        guard let outline = findOutline(in: appEl) else {
            print("[Watcher] no AXOutline / AXTable / AXList found in Messages — dumping role tree:")
            dumpRoles(of: appEl, depth: 0, maxDepth: 6)
            onEvent?(.selectionChanged(displayString: nil))
            return
        }
        observedElement = outline
        let foundRole = string(of: outline, attribute: kAXRoleAttribute as CFString) ?? "?"
        print("[Watcher] observing element role=\(foundRole)")

        // Install observer
        var observer: AXObserver?
        let result = AXObserverCreate(pid, ActiveThreadWatcher.axObserverCallback, &observer)
        guard result == .success, let observer else {
            print("[Watcher] AXObserverCreate failed result=\(result.rawValue)")
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let r1 = AXObserverAddNotification(observer, outline, kAXSelectedRowsChangedNotification as CFString, context)
        let r2 = AXObserverAddNotification(observer, outline, kAXSelectedChildrenChangedNotification as CFString, context)
        print("[Watcher] observer install: rowsChanged=\(r1.rawValue) childrenChanged=\(r2.rawValue)")
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        self.observer = observer

        // Emit current state right away.
        emitSelection(from: outline)
    }

    /// Diagnostic: prints the AX role tree to stdout so we can see where the
    /// conversation list actually lives in this build of Messages.
    private func dumpRoles(of element: AXUIElement, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else { return }
        let role = string(of: element, attribute: kAXRoleAttribute as CFString) ?? "?"
        let subrole = string(of: element, attribute: kAXSubroleAttribute as CFString) ?? ""
        let title = string(of: element, attribute: kAXTitleAttribute as CFString) ?? ""
        let id = string(of: element, attribute: "AXIdentifier" as CFString) ?? ""
        let pad = String(repeating: "  ", count: depth)
        var line = "\(pad)- \(role)"
        if !subrole.isEmpty { line += " (\(subrole))" }
        if !title.isEmpty { line += " title=\(title)" }
        if !id.isEmpty { line += " id=\(id)" }
        print(line)
        if let kids = children(of: element, attribute: kAXChildrenAttribute) {
            for kid in kids { dumpRoles(of: kid, depth: depth + 1, maxDepth: maxDepth) }
        }
    }

    private func detach() {
        if let observer, let observedElement {
            AXObserverRemoveNotification(observer, observedElement, kAXSelectedRowsChangedNotification as CFString)
            AXObserverRemoveNotification(observer, observedElement, kAXSelectedChildrenChangedNotification as CFString)
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        observedElement = nil
        appElement = nil
        messagesPID = nil
    }

    // MARK: - AX traversal

    /// BFS for an element that has selectable rows (or selectable children).
    /// iMessage's conversation list is typically an AXOutline / AXTable on
    /// modern macOS, but we fall back to anything that exposes a selection.
    private func findOutline(in root: AXUIElement, maxDepth: Int = 16) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        let preferredRoles: Set<String> = ["AXOutline", "AXTable", "AXList"]
        var fallback: AXUIElement?

        while !queue.isEmpty {
            let (node, depth) = queue.removeFirst()
            if depth > maxDepth { continue }
            let role = string(of: node, attribute: kAXRoleAttribute as CFString) ?? ""
            let hasSelectedRows = children(of: node, attribute: kAXSelectedRowsAttribute) != nil
            let hasSelectedChildren = children(of: node, attribute: kAXSelectedChildrenAttribute) != nil

            if preferredRoles.contains(role), hasSelectedRows || hasSelectedChildren {
                return node
            }
            if (hasSelectedRows || hasSelectedChildren), fallback == nil {
                fallback = node
            }
            if let kids = children(of: node, attribute: kAXChildrenAttribute) {
                for kid in kids { queue.append((kid, depth + 1)) }
            }
        }
        return fallback
    }

    fileprivate func emitSelection(from element: AXUIElement) {
        let selected = children(of: element, attribute: kAXSelectedRowsAttribute)
            ?? children(of: element, attribute: kAXSelectedChildrenAttribute)
            ?? []
        print("[Watcher] selection fired, selectedCount=\(selected.count)")
        guard let row = selected.first else {
            onEvent?(.selectionChanged(displayString: nil))
            return
        }
        let display = displayString(for: row)
        print("[Watcher] selection display=\(display ?? "nil")")
        onEvent?(.selectionChanged(displayString: display))
    }

    /// Drill into a row to find the most descriptive label. The row itself
    /// usually exposes AXValue (a comma-joined contact summary) plus child
    /// AXStaticText elements for the contact name and last message.
    private func displayString(for row: AXUIElement) -> String? {
        if let v = string(of: row, attribute: kAXValueAttribute as CFString), !v.isEmpty {
            return primaryComponent(of: v)
        }
        if let v = string(of: row, attribute: kAXTitleAttribute as CFString), !v.isEmpty {
            return primaryComponent(of: v)
        }
        if let v = string(of: row, attribute: kAXDescriptionAttribute as CFString), !v.isEmpty {
            return primaryComponent(of: v)
        }
        if let kids = children(of: row, attribute: kAXChildrenAttribute) {
            for kid in kids {
                if let label = displayString(for: kid) { return label }
                if let role = string(of: kid, attribute: kAXRoleAttribute as CFString),
                   role == "AXStaticText",
                   let v = string(of: kid, attribute: kAXValueAttribute as CFString),
                   !v.isEmpty {
                    return primaryComponent(of: v)
                }
            }
        }
        return nil
    }

    /// AX rows often surface the full conversation summary as one comma-
    /// separated string ("Momma, 2:14 PM, hey just landed"). Take the head.
    private func primaryComponent(of raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = trimmed.firstIndex(of: ",") {
            return String(trimmed[..<comma]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    // MARK: - AX helpers

    private func string(of element: AXUIElement, attribute: CFString) -> String? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &ref)
        guard result == .success else { return nil }
        return ref as? String
    }

    private func children(of element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard result == .success else { return nil }
        return ref as? [AXUIElement]
    }

    // MARK: - C callback

    private static let axObserverCallback: AXObserverCallback = { _, element, _, refcon in
        guard let refcon else { return }
        let watcher = Unmanaged<ActiveThreadWatcher>.fromOpaque(refcon).takeUnretainedValue()
        let captured = element
        Task { @MainActor in
            watcher.emitSelection(from: captured)
        }
    }
}
