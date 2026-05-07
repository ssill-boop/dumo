import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Group {
                Text("Message window").font(.headline)
                Picker("", selection: $state.messageWindow) {
                    Text("1 month").tag(MessageWindow.oneMonth)
                    Text("3 months").tag(MessageWindow.threeMonths)
                    Text("6 months").tag(MessageWindow.sixMonths)
                    Text("1 year").tag(MessageWindow.oneYear)
                    Text("All time").tag(MessageWindow.allTime)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Group {
                Text("Machine ID").font(.headline)
                Text(state.config.machineID).font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }

            Group {
                Text("Permissions").font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Button("Open Privacy & Security…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Text("Re-grant Full Disk Access or Accessibility from System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                Text("Blacklist").font(.headline)
                BlacklistList()
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 540)
    }
}

private struct BlacklistList: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.allSummarizedContacts.isEmpty {
            Text("No contacts yet.")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(state.allSummarizedContacts) { contact in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(contact.bestDisplayName)
                                Text(contact.phoneOrEmail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { contact.isBlacklisted },
                                set: { newValue in
                                    Task { await setBlacklisted(contact, newValue) }
                                }
                            ))
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
    }

    private func setBlacklisted(_ contact: Contact, _ value: Bool) async {
        guard let repo = state.contactsRepo else { return }
        do {
            let updated = try await repo.setBlacklisted(contactID: contact.id, isBlacklisted: value)
            if let idx = state.allSummarizedContacts.firstIndex(where: { $0.id == contact.id }) {
                state.allSummarizedContacts[idx] = updated
            }
            if state.activeContact?.id == updated.id {
                state.activeContact = updated
            }
        } catch {
            print("[Settings] setBlacklisted failed: \(error)")
        }
    }
}
