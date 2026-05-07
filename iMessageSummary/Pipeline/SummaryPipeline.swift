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
            forName: .iMessageSummaryRegenerate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.regenerate() }
        }
        NotificationCenter.default.addObserver(
            forName: .iMessageSummaryRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
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
            state.viewState = .empty
            return
        }
        kickOff(query: query, forceRegenerate: false)
    }

    private func handleManualSelect(contact: Contact) {
        currentTask?.cancel()
        state.activeContact = contact
        state.activeContactDisplay = contact.bestDisplayName
        state.activeHandleID = contact.phoneOrEmail
        state.searchQuery = ""
        kickOff(query: contact.phoneOrEmail, forceRegenerate: false)
    }

    private func regenerate() {
        guard let handle = state.activeHandleID else { return }
        currentTask?.cancel()
        kickOff(query: handle, forceRegenerate: true)
    }

    private func refresh() {
        guard let handle = state.activeHandleID else { return }
        currentTask?.cancel()
        kickOff(query: handle, forceRegenerate: false)
    }

    private func kickOff(query: String, forceRegenerate: Bool) {
        state.viewState = .loading(phase: "Reading messages…")
        let window = state.messageWindow
        currentTask = Task<Void, Never> { [weak self] in
            await self?.process(handleQuery: query, window: window, forceRegenerate: forceRegenerate)
        }
    }

    // MARK: - Pipeline

    private func process(handleQuery: String, window: MessageWindow, forceRegenerate: Bool) async {
        let db = state.db
        do {
            try db.open()
        } catch {
            state.viewState = .error("Couldn't open chat.db: \(error)")
            state.permissionStatus = .missingFullDiskAccess
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
                state.viewState = .error("No iMessage thread matched '\(handleQuery)'.")
                return
            }
        } catch {
            state.viewState = .error("chat.db lookup failed: \(error)")
            return
        }
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
                contact = resolved
                state.activeContact = resolved
                state.isUsingLocalFallback = false
            } catch {
                print("[Pipeline] Supabase contact lookup failed: \(error); falling back to local cache.")
                state.isUsingLocalFallback = true
            }
        } else {
            state.isUsingLocalFallback = true
        }

        var prior: Summary?
        var localPrior: LocalSummaryCache.Entry?
        if !forceRegenerate {
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
        }

        // Paused: surface whatever we already have, never call the generator.
        if contact?.isBlacklisted == true {
            if let prior {
                state.currentSummary = prior
            } else if let localPrior {
                state.currentSummary = synthesizeSummary(from: localPrior, contact: contact, handle: handle)
            } else {
                state.currentSummary = nil
            }
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
            state.viewState = .error("Couldn't read messages: \(error)")
            return
        }

        print("[Pipeline] fetched \(messages.count) messages (incremental=\(isIncremental))")

        if messages.isEmpty {
            if let prior {
                state.currentSummary = prior
                state.viewState = .loaded(newMessageCount: 0)
            } else if let localPrior {
                state.currentSummary = synthesizeSummary(from: localPrior, contact: contact, handle: handle)
                state.viewState = .loaded(newMessageCount: 0)
            } else {
                state.viewState = .error("No messages found in the selected window.")
            }
            return
        }

        guard let generator = state.generator else {
            state.viewState = .error("Anthropic API key is not configured.")
            return
        }

        state.viewState = .loading(phase: "Generating summary…")
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
            state.viewState = .error("Summary generation failed: \(error)")
            return
        }

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
                state.currentSummary = inserted
                state.viewState = .loaded(newMessageCount: messages.count)
                state.isUsingLocalFallback = false
                Task { await state.reloadSummarizedContacts() }
                return
            } catch {
                print("[Pipeline] Supabase insert failed: \(error); writing to local cache.")
                state.isUsingLocalFallback = true
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
        state.currentSummary = synthesizeSummary(from: entry, contact: contact, handle: handle)
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
