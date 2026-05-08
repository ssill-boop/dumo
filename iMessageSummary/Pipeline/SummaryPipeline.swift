import AppKit
import Foundation

/// Orchestrates the full flow described in the spec:
///   ActiveThreadWatcher → chat.db lookup → Supabase contact + summary
///   → Anthropic generator → AppState mutation.
///
/// Falls back to UserDefaults caching when Supabase isn't configured.
@MainActor
final class SummaryPipeline {
    private let state: AppState
    private let watcher: ActiveThreadWatcher
    private var currentTask: Task<Void, Never>?
    private var currentRunToken: UUID = UUID()

    init(state: AppState, watcher: ActiveThreadWatcher? = nil) {
        self.state = state
        self.watcher = watcher ?? ActiveThreadWatcher()
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: .iMessageSummarySelectContact,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let contact = note.object as? Contact else { return }
            Task { @MainActor in self.handleManualSelect(contact: contact) }
        }
        NotificationCenter.default.addObserver(
            forName: .iMessageSummaryRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: .iMessageSummaryGenerate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.generateOnDemand() }
        }

        watcher.start { [weak self] event in
            Task { @MainActor in self?.handle(event: event) }
        }
    }

    func stop() {
        watcher.stop()
        currentTask?.cancel()
    }

    // MARK: - Watcher

    private func handle(event: ActiveThreadWatcher.Event) {
        switch event {
        case .permissionDenied:
            state.permissionStatus = .missingAccessibility
            state.viewState = .error("Accessibility permission is required to detect threads.")
        case .messagesNotRunning:
            state.activeContactDisplay = nil
            state.activeContact = nil
            state.activeHandleID = nil
            state.viewState = .empty
        case .selectionChanged(let display):
            state.activeContactDisplay = display
            handleSelection(query: display)
        }
    }

    private func handleSelection(query: String?) {
        currentTask?.cancel()
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            state.activeContact = nil
            state.activeHandleID = nil
            state.currentSummary = nil
            state.pendingMessageCount = 0
            state.viewState = .empty
            return
        }
        kickOff(query: query, generate: false)
    }

    private func handleManualSelect(contact: Contact) {
        currentTask?.cancel()
        state.activeContact = contact
        state.activeContactDisplay = contact.bestDisplayName
        state.activeHandleID = contact.phoneOrEmail
        state.searchQuery = ""
        kickOff(query: contact.phoneOrEmail, generate: false)
    }

    private func refresh() {
        guard let handle = state.activeHandleID else { return }
        kickOff(query: handle, generate: false)
    }

    /// Triggered by the "Generate" / "Update" buttons in the UI.
    private func generateOnDemand() {
        guard let handle = state.activeHandleID else { return }
        kickOff(query: handle, generate: true)
    }

    private func kickOff(query: String, generate: Bool) {
        currentTask?.cancel()
        let token = UUID()
        currentRunToken = token
        state.viewState = .loading(phase: generate ? "Generating summary…" : "Reading messages…")
        if !generate { state.pendingMessageCount = 0 }
        let window = state.messageWindow
        currentTask = Task<Void, Never> { [weak self] in
            await self?.process(handleQuery: query, window: window, token: token, generate: generate)
        }
    }

    /// Returns true only if `token` is still the most recently issued token.
    /// Every state mutation in `process` is gated on this so a slow
    /// in-flight run can't clobber state belonging to a newer thread switch.
    private func isStillCurrent(_ token: UUID) -> Bool {
        token == currentRunToken
    }

    // MARK: - Pipeline

    private enum ResolvedThread {
        case oneToOne(handleID: String, displayName: String)
        case group(chatID: Int64, chatGUID: String, displayName: String, participantNames: [String: String])

        /// Stable key for Supabase contacts.phone_or_email and the local cache.
        var supabaseKey: String {
            switch self {
            case .oneToOne(let h, _): return h
            case .group(_, let g, _, _): return "group:\(g)"
            }
        }

        var displayName: String {
            switch self {
            case .oneToOne(_, let d), .group(_, _, let d, _): return d
            }
        }

        var contextLine: String {
            switch self {
            case .oneToOne(let h, let d):
                return "Contact: \(d) (\(h))"
            case .group(_, _, let d, let names):
                let parts = names.values.sorted()
                let total = parts.count + 1 // including you
                return "Group chat: \(d) (\(total) participants: \(parts.joined(separator: ", ")), and you)"
            }
        }

        var threadKind: String {
            switch self {
            case .oneToOne: return "conversation thread"
            case .group: return "group chat thread"
            }
        }
    }

    private func process(handleQuery: String, window: MessageWindow, token: UUID, generate: Bool) async {
        let db = state.db
        do {
            try db.open()
        } catch {
            if isStillCurrent(token) {
                state.viewState = .error("Couldn't open chat.db: \(error)")
                state.permissionStatus = .missingFullDiskAccess
            }
            return
        }
        defer { db.close() }

        let thread: ResolvedThread
        do {
            guard let resolved = try await resolveThread(handleQuery: handleQuery, db: db) else {
                if isStillCurrent(token) {
                    state.viewState = .error("No iMessage thread matched '\(handleQuery)'.")
                }
                return
            }
            thread = resolved
        } catch {
            if isStillCurrent(token) {
                state.viewState = .error("chat.db lookup failed: \(error)")
            }
            return
        }

        guard isStillCurrent(token) else { return }
        state.activeHandleID = thread.supabaseKey
        state.activeContactDisplay = thread.displayName

        var contact: Contact?
        if let repo = state.contactsRepo {
            do {
                let resolved = try await repo.findOrCreate(
                    phoneOrEmail: thread.supabaseKey,
                    displayName: thread.displayName
                )
                guard isStillCurrent(token) else { return }
                contact = resolved
                state.activeContact = resolved
                state.isUsingLocalFallback = false
            } catch {
                print("[Pipeline] Supabase contact lookup failed: \(error); falling back to local cache.")
                if isStillCurrent(token) { state.isUsingLocalFallback = true }
            }
        } else {
            if isStillCurrent(token) { state.isUsingLocalFallback = true }
        }
        guard isStillCurrent(token) else { return }

        var prior: Summary?
        var localPrior: LocalSummaryCache.Entry?
        if let summariesRepo = state.summariesRepo, let contact {
            do {
                prior = try await summariesRepo.latestSummary(contactID: contact.id)
                print("[Pipeline] latestSummary -> \(prior == nil ? "nil" : "found row last_rowid=\(prior!.lastMessageRowID)")")
            } catch {
                print("[Pipeline] latestSummary failed: \(error)")
            }
        }
        if prior == nil {
            localPrior = state.cache.read(handle: thread.supabaseKey)
        }
        guard isStillCurrent(token) else { return }

        // Paused: surface whatever we already have, never call the generator.
        if contact?.isBlacklisted == true {
            if let prior {
                state.currentSummary = prior
            } else if let localPrior {
                state.currentSummary = synthesizeSummary(from: localPrior, contact: contact, handle: thread.supabaseKey)
            } else {
                state.currentSummary = nil
            }
            state.pendingMessageCount = 0
            state.viewState = .loaded(newMessageCount: 0)
            return
        }

        let messages: [Message]
        let isIncremental: Bool
        do {
            (messages, isIncremental) = try fetchMessages(
                thread: thread,
                prior: prior,
                localPrior: localPrior,
                window: window,
                db: db
            )
        } catch {
            if isStillCurrent(token) {
                state.viewState = .error("Couldn't read messages: \(error)")
            }
            return
        }

        print("[Pipeline] fetched \(messages.count) messages (incremental=\(isIncremental), generate=\(generate))")

        // Display-only path: surface whatever's cached + the count of pending
        // messages, but never call the API. The user clicks Generate / Update
        // to pay for tokens.
        if !generate {
            guard isStillCurrent(token) else { return }
            if let prior {
                state.currentSummary = prior
            } else if let localPrior {
                state.currentSummary = synthesizeSummary(from: localPrior, contact: contact, handle: thread.supabaseKey)
            } else {
                state.currentSummary = nil
            }
            state.pendingMessageCount = messages.count
            state.viewState = .loaded(newMessageCount: 0)
            return
        }

        if messages.isEmpty {
            guard isStillCurrent(token) else { return }
            if let prior {
                state.currentSummary = prior
            } else if let localPrior {
                state.currentSummary = synthesizeSummary(from: localPrior, contact: contact, handle: thread.supabaseKey)
            }
            state.pendingMessageCount = 0
            state.viewState = .loaded(newMessageCount: 0)
            return
        }

        guard let generator = state.generator else {
            if isStillCurrent(token) {
                state.viewState = .error("Anthropic API key is not configured.")
            }
            return
        }

        if isStillCurrent(token) {
            state.viewState = .loading(phase: "Generating summary…")
        }

        let rows = messages.map { msg -> SummaryGenerator.Row in
            (msg, senderLabel(for: msg, in: thread))
        }

        let output: SummaryGenerator.Output
        do {
            if isIncremental, let prior {
                output = try await generator.generateUpdate(
                    contextLine: thread.contextLine,
                    threadKind: thread.threadKind,
                    prior: prior,
                    newRows: rows
                )
            } else if isIncremental, let localPrior {
                let stub = synthesizeSummary(from: localPrior, contact: contact, handle: thread.supabaseKey)
                output = try await generator.generateUpdate(
                    contextLine: thread.contextLine,
                    threadKind: thread.threadKind,
                    prior: stub,
                    newRows: rows
                )
            } else {
                output = try await generator.generateInitial(
                    contextLine: thread.contextLine,
                    threadKind: thread.threadKind,
                    rows: rows
                )
            }
        } catch {
            if isStillCurrent(token) {
                state.viewState = .error("Summary generation failed: \(error)")
            }
            return
        }

        guard isStillCurrent(token) else { return }
        guard let last = messages.last else {
            state.viewState = .error("Generator returned but message list was empty.")
            return
        }

        let windowStart: Date? = isIncremental ? nil : window.cutoffDate()

        if let summariesRepo = state.summariesRepo, let contact {
            do {
                let inserted = try await summariesRepo.insert(NewSummary(
                    contact_id: contact.id,
                    summary_text: output.summaryText,
                    bullet_points: output.bulletPoints,
                    last_message_rowid: last.rowID,
                    last_message_date: last.date,
                    message_window_start: windowStart,
                    generated_by: state.config.machineID,
                    model_version: generator.model
                ))
                guard isStillCurrent(token) else { return }
                state.currentSummary = inserted
                state.pendingMessageCount = 0
                state.viewState = .loaded(newMessageCount: messages.count)
                state.isUsingLocalFallback = false
                Task { await state.reloadSummarizedContacts() }
                return
            } catch {
                print("[Pipeline] Supabase insert failed: \(error); writing to local cache.")
                if isStillCurrent(token) { state.isUsingLocalFallback = true }
            }
        }

        let entry = LocalSummaryCache.Entry(
            bulletPoints: output.bulletPoints,
            summaryText: output.summaryText,
            lastMessageRowID: last.rowID,
            lastMessageDate: last.date,
            generatedAt: Date(),
            generatedBy: state.config.machineID,
            modelVersion: generator.model
        )
        state.cache.write(handle: thread.supabaseKey, entry: entry)
        guard isStillCurrent(token) else { return }
        state.currentSummary = synthesizeSummary(from: entry, contact: contact, handle: thread.supabaseKey)
        state.pendingMessageCount = 0
        state.viewState = .loaded(newMessageCount: messages.count)
    }

    // MARK: - Resolution & helpers

    /// Resolves an AX-reported title or a stored contact key into either a
    /// 1:1 thread or a group thread.
    private func resolveThread(handleQuery: String, db: iMessageDB) async throws -> ResolvedThread? {
        // 0. Stored Supabase key for a previously-seen group ("group:<guid>").
        //    Used by the search dropdown when the user clicks on a group row.
        if handleQuery.hasPrefix("group:") {
            let guid = String(handleQuery.dropFirst("group:".count))
            if let chat = try db.findChat(byGUID: guid) {
                return await makeGroupThread(chat: chat, fallbackName: handleQuery, db: db)
            }
            return nil
        }

        // 1. Try resolving the title against chat.display_name first. Catches
        //    user-named chats whether they're 1:1 or groups.
        if let chat = try db.findChat(matchingDisplayName: handleQuery) {
            if chat.handleCount > 1 {
                return await makeGroupThread(chat: chat, fallbackName: handleQuery, db: db)
            }
            // Named 1:1 — derive the handle from the chat's participants.
            let participants = (try? db.participants(ofChatID: chat.chatID)) ?? []
            if let firstHandle = participants.first {
                let displayName = chat.displayName?.nilIfEmpty
                    ?? state.activeContactDisplay?.nilIfEmpty
                    ?? handleQuery
                return .oneToOne(handleID: firstHandle, displayName: displayName)
            }
        }

        // 2. Direct chat.db handle lookup (works when the AX query is a phone
        //    or email, e.g. on subsequent re-runs after we've cached the
        //    handle on AppState.activeHandleID).
        if let direct = try db.findContact(matching: handleQuery) {
            // Refuse if this person only appears in group chats with us.
            if (try? db.hasOneToOneChat(forHandleID: direct.handleID)) == false {
                return nil
            }
            let displayName = direct.displayName?.nilIfEmpty
                ?? state.activeContactDisplay?.nilIfEmpty
                ?? handleQuery
            return .oneToOne(handleID: direct.handleID, displayName: displayName)
        }

        // 3. Contacts framework: AX gave us a person's name and chat.db only
        //    knows them by phone.
        if let viaContacts = await resolveThroughContacts(displayName: handleQuery, db: db) {
            if (try? db.hasOneToOneChat(forHandleID: viaContacts.handleID)) == false {
                return nil
            }
            let displayName = viaContacts.displayName?.nilIfEmpty
                ?? state.activeContactDisplay?.nilIfEmpty
                ?? handleQuery
            return .oneToOne(handleID: viaContacts.handleID, displayName: displayName)
        }

        return nil
    }

    private func makeGroupThread(chat: iMessageDB.ChatInfo, fallbackName: String, db: iMessageDB) async -> ResolvedThread {
        let participantHandles = (try? db.participants(ofChatID: chat.chatID)) ?? []
        var names: [String: String] = [:]
        for handle in participantHandles {
            let resolved = await state.contactsResolver.displayName(forHandle: handle) ?? handle
            names[handle] = resolved
        }
        let displayName = chat.displayName?.nilIfEmpty
            ?? autoGroupName(participantNames: Array(names.values))
            ?? fallbackName
        return .group(
            chatID: chat.chatID,
            chatGUID: chat.guid,
            displayName: displayName,
            participantNames: names
        )
    }

    private func autoGroupName(participantNames: [String]) -> String? {
        let sorted = participantNames.sorted()
        guard !sorted.isEmpty else { return nil }
        if sorted.count <= 3 { return sorted.joined(separator: ", ") }
        return sorted.prefix(2).joined(separator: ", ") + " & \(sorted.count - 2) others"
    }

    private func fetchMessages(
        thread: ResolvedThread,
        prior: Summary?,
        localPrior: LocalSummaryCache.Entry?,
        window: MessageWindow,
        db: iMessageDB
    ) throws -> (messages: [Message], isIncremental: Bool) {
        switch thread {
        case .oneToOne(let handle, _):
            if let prior {
                return (try db.fetchMessages(forHandleID: handle, sinceRowID: prior.lastMessageRowID), true)
            }
            if let localPrior {
                return (try db.fetchMessages(forHandleID: handle, sinceRowID: localPrior.lastMessageRowID), true)
            }
            return (try db.fetchMessages(forHandleID: handle, window: window), false)
        case .group(let chatID, _, _, _):
            if let prior {
                return (try db.fetchMessages(forChatID: chatID, sinceRowID: prior.lastMessageRowID), true)
            }
            if let localPrior {
                return (try db.fetchMessages(forChatID: chatID, sinceRowID: localPrior.lastMessageRowID), true)
            }
            return (try db.fetchMessages(forChatID: chatID, window: window), false)
        }
    }

    private func senderLabel(for message: Message, in thread: ResolvedThread) -> String {
        if message.isFromMe { return "Me" }
        switch thread {
        case .oneToOne(_, let displayName):
            return displayName
        case .group(_, _, _, let names):
            if let h = message.senderHandleID, let name = names[h] {
                return name
            }
            return message.senderHandleID ?? "Unknown"
        }
    }

    /// chat.db has no name table — Catalyst Messages shows names from
    /// Contacts.app. When the AX-reported display name doesn't directly
    /// match a handle, ask Contacts for that person's phones / emails and
    /// retry the chat.db lookup with each one.
    private func resolveThroughContacts(displayName: String, db: iMessageDB) async -> ContactRow? {
        let candidates = await state.contactsResolver.handles(forDisplayName: displayName)
        guard !candidates.isEmpty else {
            print("[Pipeline] Contacts returned no handles for '\(displayName)'")
            return nil
        }
        for candidate in candidates {
            if let match = try? db.findContact(matching: candidate) {
                print("[Pipeline] Contacts resolved '\(displayName)' -> \(candidate) -> \(match.handleID)")
                return ContactRow(
                    handleRowID: match.handleRowID,
                    handleID: match.handleID,
                    displayName: match.displayName?.nilIfEmpty ?? displayName
                )
            }
        }
        print("[Pipeline] Contacts gave \(candidates.count) candidates but none matched chat.db")
        return nil
    }

    private func synthesizeSummary(
        from entry: LocalSummaryCache.Entry,
        contact: Contact?,
        handle: String
    ) -> Summary {
        Summary(
            id: UUID(),
            contactId: contact?.id ?? UUID(),
            summaryText: entry.summaryText,
            bulletPoints: entry.bulletPoints,
            lastMessageRowID: entry.lastMessageRowID,
            lastMessageDate: entry.lastMessageDate,
            messageWindowStart: nil,
            generatedBy: entry.generatedBy,
            modelVersion: entry.modelVersion,
            createdAt: entry.generatedAt
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
