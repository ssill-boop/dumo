import Contacts
import Foundation

/// Maps Catalyst-Messages display names ("Sofia Sill") to the phone numbers
/// and email handles stored in chat.db. Uses the macOS Contacts framework.
@MainActor
final class ContactsResolver {
    private let store = CNContactStore()
    private var handleCache: [String: [String]] = [:]
    private var nameCache: [String: String] = [:]

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
    /// Nil results are intentionally NOT cached so a subsequent successful
    /// lookup (after permission is granted, or after a Contacts.app edit)
    /// is picked up without restarting the app.
    func displayName(forHandle handle: String) async -> String? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let cached = nameCache[trimmed] { return cached }
        guard await ensureAccess() else { return nil }
        guard let resolved = lookupName(handle: trimmed) else { return nil }
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
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]

        // 1. Try the predicate-based match first — fast, indexed.
        let predicate: NSPredicate
        if handle.contains("@") {
            predicate = CNContact.predicateForContacts(matchingEmailAddress: handle)
        } else {
            predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: handle))
        }
        if let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys),
           let first = contacts.first,
           let name = bestName(of: first) {
            return name
        }

        // 2. Fallback: predicateForContacts(matching: CNPhoneNumber) is
        //    sometimes flaky for E.164 numbers whose Contacts.app entry
        //    is stored in a different format. Walk every contact and
        //    match on trailing-10-digits. Slower (linear) but reliable.
        guard !handle.contains("@") else { return nil }
        let targetDigits = handle.filter(\.isNumber)
        let target = targetDigits.count >= 10 ? String(targetDigits.suffix(10)) : targetDigits
        guard !target.isEmpty else { return nil }

        var foundName: String?
        let request = CNContactFetchRequest(keysToFetch: keys)
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                for phone in contact.phoneNumbers {
                    let phoneDigits = phone.value.stringValue.filter(\.isNumber)
                    let phoneSuffix = phoneDigits.count >= 10 ? String(phoneDigits.suffix(10)) : phoneDigits
                    if phoneSuffix == target {
                        foundName = self.bestName(of: contact)
                        stop.pointee = true
                        return
                    }
                }
            }
        } catch {
            return nil
        }
        return foundName
    }

    private func bestName(of contact: CNContact) -> String? {
        if !contact.nickname.isEmpty { return contact.nickname }
        let combined = [contact.givenName, contact.familyName]
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
