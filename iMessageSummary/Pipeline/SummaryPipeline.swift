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
    private var lastResolvedHandle: String?

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

        let row: ContactRow
        do {
            if let direct = try db.findContact(matching: handleQuery) {
                row = direct
            } else if let viaContacts = await resolveThroughContacts(displayName: handleQuery, db: db) {
                row = viaContacts
            } else {
                if isStillCurrent(token) {
                    state.viewState = .error("No iMessage thread matched '\(handleQuery)'.")
                }
                return
            }
        } catch {
            if isStillCurrent(token) {
                state.viewState = .error("chat.db lookup failed: \(error)")
            }
            return
        }
        guard isStillCurrent(token) else { return }
        let handle = row.handleID
        let displayName = row.displayName?.nilIfEmpty ?? handleQuery
        state.activeHandleID = handle
        state.activeContactDisplay = displayName
        lastResolvedHandle = handle

        var contact: Contact?
        if let repo = state.contactsRepo {
            do {
                let resolved = try await repo.findOrCreate(
                    phoneOrEmail: handle,
                    displayName: row.displayName?.nilIfEmpty ?? displayName
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
            localPrior = state.cache.read(handle: handle)
        }
        guard isStillCurrent(token) else { return }

        // Paused: surface whatever we already have, never call the generator.
        if contact?.isBlacklisted == true {
            if let prior {
                state.currentSummary = prior
            } else if let localPrior {
                state.currentSummary = synthesizeSummary(from: localPrior, contact: contact, handle: handle)
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
            if let prior {
                messages = try db.fetchMessages(forHandleID: handle, sinceRowID: prior.lastMessageRowID)
                isIncremental = true
            } else if let localPrior {
                messages = try db.fetchMessages(forHandleID: handle, sinceRowID: localPrior.lastMessageRowID)
                isIncremental = true
            } else {
                messages = try db.fetchMessages(forHandleID: handle, window: window)
                isIncremental = false
            }
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
                state.currentSummary = synthesizeSummary(from: localPrior, contact: contact, handle: handle)
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
                state.currentSummary = synthesizeSummary(from: localPrior, contact: contact, handle: handle)
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
        let output: SummaryGenerator.Output
        do {
            if isIncremental, let prior {
                output = try await generator.generateUpdate(
                    displayName: displayName,
                    handle: handle,
                    prior: prior,
                    newMessages: messages
                )
            } else if isIncremental, let localPrior {
                let stub = synthesizeSummary(from: localPrior, contact: contact, handle: handle)
                output = try await generator.generateUpdate(
                    displayName: displayName,
                    handle: handle,
                    prior: stub,
                    newMessages: messages
                )
            } else {
                output = try await generator.generateInitial(
                    displayName: displayName,
                    handle: handle,
                    messages: messages
                )
            }
        } catch {
            if isStillCurrent(token) {
                state.viewState = .error("Summary generation failed: \(error)")
            }
            return
        }

        // Newer thread switch happened while we were waiting for the API.
        // Drop the result rather than overwriting the new selection.
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
                // The insert is always real — it belongs to this contact_id.
                // But only push it into the UI if the user is still on this thread.
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
        state.cache.write(handle: handle, entry: entry)
        guard isStillCurrent(token) else { return }
        state.currentSummary = synthesizeSummary(from: entry, contact: contact, handle: handle)
        state.pendingMessageCount = 0
        state.viewState = .loaded(newMessageCount: messages.count)
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
