import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var state: AppState
    let newMessageCount: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                contactHeader
                if isPaused {
                    pausedBanner
                }
                content
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var content: some View {
        if let summary = state.currentSummary {
            if state.pendingMessageCount > 0, !isPaused {
                updateBanner
            }
            if newMessageCount > 0 {
                Label(
                    "Updated with \(newMessageCount) new message\(newMessageCount == 1 ? "" : "s")",
                    systemImage: "sparkles"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            bullets(summary.bulletPoints)
            if !summary.summaryText.isEmpty {
                Divider()
                Text(summary.summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            metadata(summary)
        } else if isPaused {
            Text("No summary yet. Unpause to generate one.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if state.pendingMessageCount > 0 {
            generateInitialSection
        } else {
            Text("No recent messages with this contact in the last \(windowDescription).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var contactHeader: some View {
        let displayName = state.activeContact?.bestDisplayName
            ?? state.activeContactDisplay
            ?? "Unknown"
        let raw = state.activeContact?.phoneOrEmail ?? state.activeHandleID ?? ""
        let isGroup = raw.hasPrefix("group:")
        let subtitle = isGroup ? "Group chat" : raw

        return VStack(alignment: .leading, spacing: 2) {
            Text(displayName).font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isPaused: Bool {
        state.activeContact?.isBlacklisted ?? false
    }

    private var pausedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.circle.fill")
            Text("Paused — not generating new summaries")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.orange)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private var updateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.pendingMessageCount) new message\(state.pendingMessageCount == 1 ? "" : "s")")
                    .font(.callout.weight(.medium))
                Text("not yet included in this summary")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Update") {
                NotificationCenter.default.post(name: .iMessageSummaryGenerate, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!state.hasAnthropic)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.12))
        )
    }

    private var generateInitialSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No summary yet")
                .font(.headline)
            Text("\(state.pendingMessageCount) message\(state.pendingMessageCount == 1 ? "" : "s") from the last \(windowDescription).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Generate Summary") {
                NotificationCenter.default.post(name: .iMessageSummaryGenerate, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!state.hasAnthropic)
            if !state.hasAnthropic {
                Text("Anthropic API key not configured.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var windowDescription: String {
        switch state.messageWindow {
        case .oneWeek: return "week"
        case .twoWeeks: return "2 weeks"
        case .oneMonth: return "month"
        }
    }

    private func bullets(_ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(point)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func metadata(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Updated \(Self.relative.localizedString(for: summary.createdAt, relativeTo: Date()))")
                Spacer()
                Button(isPaused ? "Unpause" : "Pause") {
                    Task { await SummaryActions.setBlacklisted(state, isBlacklisted: !isPaused) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text("Generated by \(summary.generatedBy) · \(summary.modelVersion)")
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

enum SummaryActions {
    @MainActor
    static func setBlacklisted(_ state: AppState, isBlacklisted: Bool) async {
        guard let contact = state.activeContact, let repo = state.contactsRepo else { return }
        do {
            let updated = try await repo.setBlacklisted(contactID: contact.id, isBlacklisted: isBlacklisted)
            state.activeContact = updated
            if let idx = state.allSummarizedContacts.firstIndex(where: { $0.id == updated.id }) {
                state.allSummarizedContacts[idx] = updated
            }
            // Unpausing re-runs the lookup so the user sees the latest cached
            // summary + fresh pending count.
            if !isBlacklisted, state.activeHandleID != nil {
                NotificationCenter.default.post(name: .iMessageSummaryRefresh, object: nil)
            }
        } catch {
            state.viewState = .error("Couldn't update pause state: \(error)")
        }
    }
}

extension Notification.Name {
    static let iMessageSummarySelectContact = Notification.Name("iMessageSummary.selectContact")
    static let iMessageSummaryRefresh = Notification.Name("iMessageSummary.refresh")
    static let iMessageSummaryGenerate = Notification.Name("iMessageSummary.generate")
}
