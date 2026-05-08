import Contacts
import Foundation

/// Maps Catalyst-Messages display names ("Sofia Sill") to the phone numbers
/// and email handles stored in chat.db. Uses the macOS Contacts framework.
@MainActor
final class ContactsResolver {
    private let store = CNContactStore()
    private var handleCache: [String: [String]] = [:]
    private var nameCache: [String: String?] = [:]

    /// Returns chat.db-style lookup patterns (digits-only or email) for the
    /// given display name. Empty if Contacts permission is denied or no
    /// matches were found.
    func handles(forDisplayName name: String) async -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let cached = handleCache[trimmed] { return cached }
        guard await ensureAccess() else { return [] }
        let patterns = lookup(name: trimmed)
        handleCache[trimmed] = patterns
        return patterns
    }

    /// Reverse lookup: given a chat.db handle (phone or email), return the
    /// best display name from Contacts. Returns nil if Contacts can't find
    /// them. Used to attribute group-chat messages by participant name.
    func displayName(forHandle handle: String) async -> String? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let cached = nameCache[trimmed] { return cached }
        guard await ensureAccess() else {
            nameCache[trimmed] = nil
            return nil
        }
        let resolved = lookupName(handle: trimmed)
        nameCache[trimmed] = resolved
        return resolved
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

    private func lookupName(handle: String) -> String? {
        let predicate: NSPredicate
        if handle.contains("@") {
            predicate = CNContact.predicateForContacts(matchingEmailAddress: handle)
        } else {
            predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: handle))
        }
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
        ]
        guard
            let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys),
            let first = contacts.first
        else {
            return nil
        }
        if !first.nickname.isEmpty {
            return first.nickname
        }
        let combined = [first.givenName, first.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return combined.isEmpty ? nil : combined
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
