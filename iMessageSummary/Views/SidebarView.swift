import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 480)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(state)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            SearchBar()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .regular))
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if !state.searchQuery.isEmpty {
            SearchView()
        } else {
            switch state.viewState {
            case .empty:
                EmptyStateView()
            case .loading(let phase):
                LoadingView(phase: phase, contactDisplay: state.activeContactDisplay)
            case .loaded(let newCount):
                SummaryView(newMessageCount: newCount)
            case .error(let message):
                ErrorStateView(message: message)
            case .blacklisted:
                BlacklistedStateView()
            }
        }
    }

    private var footer: some View {
        HStack {
            if state.isUsingLocalFallback {
                Label("Local mode — not syncing", systemImage: "icloud.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(state.config.machineID)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct SearchBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search contacts", text: $state.searchQuery)
                .textFieldStyle(.plain)
            if !state.searchQuery.isEmpty {
                Button {
                    state.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
