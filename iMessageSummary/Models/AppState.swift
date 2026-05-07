import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum ViewState: Equatable {
        case empty
        case loading(phase: String)
        case loaded(newMessageCount: Int)
        case error(String)
    }

    enum PermissionStatus: Equatable {
        case unknown
        case ok
        case missingFullDiskAccess
        case missingAccessibility
    }

    // Published view state
    @Published var activeContact: Contact?
    @Published var activeContactDisplay: String?
    @Published var activeHandleID: String?
    @Published var currentSummary: Summary?
    @Published var viewState: ViewState = .empty
    @Published var searchQuery: String = ""
    @Published var allSummarizedContacts: [Contact] = []
    @Published var pendingMessageCount: Int = 0
    @Published var permissionStatus: PermissionStatus = .unknown
    @Published var isUsingLocalFallback: Bool

    // Settings (persisted)
    @Published var messageWindow: MessageWindow {
        didSet {
            UserDefaults.standard.set(messageWindow.rawValue, forKey: Self.messageWindowKey)
        }
    }

    // Collaborators
    let config: AppConfig
    let cache: LocalSummaryCache
    let db: iMessageDB
    let contactsResolver: ContactsResolver
    let supabase: SupabaseClient?
    let contactsRepo: ContactsRepository?
    let summariesRepo: SummariesRepository?
    let generator: SummaryGenerator?

    var hasSupabase: Bool { supabase != nil }
    var hasAnthropic: Bool { generator != nil }

    private static let messageWindowKey = "iMessageSummary.settings.messageWindow"

    init(config: AppConfig) {
        self.config = config
        self.cache = LocalSummaryCache()
        self.db = iMessageDB()
        self.contactsResolver = ContactsResolver()

        if let client = SupabaseClient(url: config.supabaseURL, anonKey: config.supabaseAnonKey) {
            self.supabase = client
            self.contactsRepo = ContactsRepository(client: client)
            self.summariesRepo = SummariesRepository(client: client)
        } else {
            self.supabase = nil
            self.contactsRepo = nil
            self.summariesRepo = nil
        }

        if let key = config.anthropicAPIKey {
            let model = config.anthropicModel ?? SummaryGenerator.defaultModel
            self.generator = SummaryGenerator(apiKey: key, model: model)
        } else {
            self.generator = nil
        }

        self.isUsingLocalFallback = (self.supabase == nil)

        let raw = UserDefaults.standard.string(forKey: Self.messageWindowKey)
        self.messageWindow = raw.flatMap(MessageWindow.init(rawValue:)) ?? .twoWeeks
    }

    /// Refresh the list of contacts that already have summaries (used by
    /// the search dropdown and the blacklist editor).
    func reloadSummarizedContacts() async {
        guard let contactsRepo, let summariesRepo else { return }
        do {
            self.allSummarizedContacts = try await summariesRepo.contactsWithSummaries(via: contactsRepo)
        } catch {
            print("[AppState] reloadSummarizedContacts failed: \(error)")
        }
    }
}
