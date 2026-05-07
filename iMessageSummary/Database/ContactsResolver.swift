import Contacts
import Foundation

/// Maps Catalyst-Messages display names ("Sofia Sill") to the phone numbers
/// and email handles stored in chat.db. Uses the macOS Contacts framework.
@MainActor
final class ContactsResolver {
    private let store = CNContactStore()
    private var cache: [String: [String]] = [:]

    /// Returns chat.db-style lookup patterns (digits-only or email) for the
    /// given display name. Empty if Contacts permission is denied or no
    /// matches were found.
    func handles(forDisplayName name: String) async -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let cached = cache[trimmed] { return cached }
        guard await ensureAccess() else { return [] }
        let patterns = lookup(name: trimmed)
        cache[trimmed] = patterns
        return patterns
    }

    private func ensureAccess() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                store.requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func lookup(name: String) -> [String] {
        let predicate = CNContact.predicateForContacts(matchingName: name)
        let keys: [CNKeyDescriptor] = [
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys) else {
            return []
        }
        var results: [String] = []
        for contact in contacts {
            for phone in contact.phoneNumbers {
                let raw = phone.value.stringValue
                let digits = raw.filter(\.isNumber)
                guard !digits.isEmpty else { continue }
                // Use the last 10 digits — chat.db stores numbers in E.164
                // (e.g. "+15551234567"), and "%5551234567%" matches that
                // safely without us guessing country codes.
                let pattern = digits.count > 10 ? String(digits.suffix(10)) : digits
                results.append(pattern)
            }
            for email in contact.emailAddresses {
                results.append(email.value as String)
            }
        }
        return results
    }
}
