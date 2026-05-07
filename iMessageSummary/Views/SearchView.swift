import SwiftUI

struct SearchView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let filtered = state.allSummarizedContacts.filter { match($0, query: state.searchQuery) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if filtered.isEmpty {
                    Text("No matching contacts")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ForEach(filtered) { contact in
                        ContactRow(contact: contact)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
    }

    private func match(_ contact: Contact, query: String) -> Bool {
        let q = query.lowercased()
        if contact.phoneOrEmail.lowercased().contains(q) { return true }
        if let name = contact.displayName?.lowercased(), name.contains(q) { return true }
        return false
    }
}

private struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.bestDisplayName).font(.body)
                Text(contact.phoneOrEmail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if contact.isBlacklisted {
                Image(systemName: "pause.circle").foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(
                name: .iMessageSummarySelectContact,
                object: contact
            )
        }
    }
}
