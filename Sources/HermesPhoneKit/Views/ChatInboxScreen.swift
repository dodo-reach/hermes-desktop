#if canImport(UIKit)
@preconcurrency import Citadel
import Crypto
import Foundation
import NIOCore
@preconcurrency import NIOSSH
import Security
import SwiftUI
import UIKit

struct ConversationRow: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.resolvedTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(timestampText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Text(previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let model = session.displayModel {
                    DetailBadge(title: model, tint: .blue)
                }

                if let count = session.messageCount {
                    DetailBadge(title: "\(count) msgs", tint: .secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var previewText: String {
        if let snippet = session.searchMatch?.snippet?.trimmingCharacters(in: .whitespacesAndNewlines),
           !snippet.isEmpty {
            return snippet
        }

        if let preview = session.preview?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return preview
        }

        return "Open this session to inspect its transcript."
    }

    private var timestampText: String {
        if let date = session.lastActive?.dateValue ?? session.startedAt?.dateValue {
            return DateFormatters.shortDateTimeString(from: date)
        }
        return "No date"
    }
}

struct SessionSummaryCard: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.resolvedTitle)
                    .font(.headline)

                if let preview = session.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            HStack(spacing: 8) {
                if let model = session.displayModel {
                    DetailBadge(title: model, tint: .blue)
                }

                if let count = session.messageCount {
                    DetailBadge(title: "\(count) msgs", tint: .secondary)
                }

                if let lastActive = session.lastActive?.dateValue ?? session.startedAt?.dateValue {
                    DetailBadge(title: DateFormatters.shortDateTimeString(from: lastActive), tint: .secondary)
                }
            }

            Text("Read-only remote transcript")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct TranscriptMessageRow: View {
    let message: SessionMessage
    @State private var isDetailExpanded: Bool
    @State private var isReasoningExpanded = false
    @State private var isMetadataExpanded = false

    init(message: SessionMessage) {
        self.message = message
        _isDetailExpanded = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(message.role.displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(roleTint)

                Spacer()

                if let date = message.timestamp?.dateValue {
                    Text(DateFormatters.shortDateTimeString(from: date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if isPrimaryConversationTurn {
                if let content = message.content, !content.isEmpty {
                    Text(renderedMarkdown(content))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                DisclosureGroup(isExpanded: $isDetailExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        transcriptExpandedContent
                        transcriptSupplementalSections
                    }
                    .padding(.top, 8)
                } label: {
                    transcriptCollapsedSummary
                }
                .tint(roleTint)
            }

            if isPrimaryConversationTurn {
                transcriptSupplementalSections
            }
        }
        .padding(14)
        .background(roleBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            if let content = message.content, !content.isEmpty {
                Button {
                    UIPasteboard.general.string = content
                } label: {
                    Label("Copy Message", systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptExpandedContent: some View {
        if let toolSummary {
            VStack(alignment: .leading, spacing: 8) {
                Text(toolSummary.title)
                    .font(.subheadline.weight(.semibold))

                if let preview = SessionToolMessageSummary.detailPreview(from: message.content), !preview.isEmpty {
                    Text(preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if toolSummary.isDetailPreviewTruncated {
                    Text("Preview truncated")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else if let content = message.content, !content.isEmpty {
            Text(content)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var transcriptCollapsedSummary: some View {
        if let toolSummary {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label(toolSummary.title, systemImage: toolStatusIconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(roleTint)

                    if let statusText = toolSummary.statusText {
                        Text(statusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(toolStatusTint)
                    }

                    if let sizeText = toolSummary.sizeText {
                        Text(sizeText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let preview = toolSummary.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(collapsedSummaryTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let collapsedPreviewText, !collapsedPreviewText.isEmpty {
                    Text(collapsedPreviewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptSupplementalSections: some View {
        if !reasoningMetadataItems.isEmpty {
            DisclosureGroup(isExpanded: $isReasoningExpanded) {
                TranscriptMetadataBlock(items: reasoningMetadataItems)
                    .padding(.top, 8)
            } label: {
                Label("Reasoning", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .tint(.secondary)
        }

        if !plainMetadataItems.isEmpty {
            DisclosureGroup(isExpanded: $isMetadataExpanded) {
                TranscriptMetadataBlock(items: plainMetadataItems)
                    .padding(.top, 8)
            } label: {
                Label("Metadata", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .tint(.secondary)
        }
    }

    private var isPrimaryConversationTurn: Bool {
        switch message.role {
        case .user, .assistant:
            return true
        case .system, .event, .custom:
            return false
        }
    }

    private var toolSummary: SessionToolMessageSummary? {
        message.role.isToolRole ? SessionToolMessageSummary(content: message.content) : nil
    }

    private var reasoningMetadataItems: [SessionMetadataDisplayItem] {
        metadataItems.filter { item in
            let normalizedKey = item.key.lowercased()
            return normalizedKey.contains("reasoning")
        }
    }

    private var plainMetadataItems: [SessionMetadataDisplayItem] {
        metadataItems.filter { item in
            let normalizedKey = item.key.lowercased()
            return !normalizedKey.contains("reasoning")
        }
    }

    private var metadataItems: [SessionMetadataDisplayItem] {
        let metadata = message.displayMetadata ?? [:]
        return metadata.keys.sorted().compactMap { key in
            guard let value = metadata[key] else { return nil }
            return SessionMetadataDisplayItem(key: key, value: value)
        }
    }

    private var collapsedSummaryTitle: String {
        switch message.role {
        case .system:
            return "System note"
        case .event:
            return "Event details"
        case .custom(let value):
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        case .user, .assistant:
            return message.role.displayTitle
        }
    }

    private var collapsedPreviewText: String? {
        let source = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !source.isEmpty else {
            if !reasoningMetadataItems.isEmpty {
                return "Contains reasoning details"
            }
            if !plainMetadataItems.isEmpty {
                return "Contains metadata"
            }
            return nil
        }

        let normalized = source
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard normalized.count > 140 else { return normalized }
        return String(normalized.prefix(137)) + "..."
    }

    private var toolStatusTint: Color {
        guard let toolSummary else { return roleTint }
        switch toolSummary.statusKind {
        case .success:
            return .green
        case .failure:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private var toolStatusIconName: String {
        guard let toolSummary else { return "wrench.and.screwdriver" }
        switch toolSummary.statusKind {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.octagon.fill"
        case .neutral:
            return "wrench.and.screwdriver"
        }
    }

    private var roleTint: Color {
        switch message.role {
        case .user:
            return Color(red: 0.18, green: 0.72, blue: 0.62)
        case .assistant:
            return .secondary
        case .system:
            return .blue
        case .event:
            return .purple
        case .custom:
            return message.role.isToolRole ? .orange : .red
        }
    }

    private var roleBackground: Color {
        switch message.role {
        case .user:
            return Color(red: 0.18, green: 0.72, blue: 0.62).opacity(0.12)
        case .assistant:
            return Color(.secondarySystemBackground)
        case .system:
            return Color.blue.opacity(0.10)
        case .event:
            return Color.purple.opacity(0.08)
        case .custom:
            return message.role.isToolRole ? Color.orange.opacity(0.10) : Color.red.opacity(0.10)
        }
    }

    private func renderedMarkdown(_ content: String) -> AttributedString {
        (try? AttributedString(markdown: content)) ?? AttributedString(content)
    }
}

struct TranscriptMetadataBlock: View {
    let items: [SessionMetadataDisplayItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.key.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(item.displayValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct DetailBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isNeutral ? Color.secondary : tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((isNeutral ? Color(.tertiarySystemFill) : tint.opacity(0.12)), in: Capsule())
    }

    private var isNeutral: Bool {
        title.hasSuffix("msgs") || title.contains(":")
    }
}

struct SessionTranscriptScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    let session: SessionSummary
    @State private var loadState: TranscriptLoadState = .loading(sessionID: nil)

    var body: some View {
        List {
            Section {
                SessionSummaryCard(session: session)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            switch displayedLoadState {
            case .loading(_):
                Section("Transcript") {
                    HStack {
                        Spacer()
                        ProgressView("Loading transcript…")
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            case .loaded(_, let messages) where messages.isEmpty:
                Section("Transcript") {
                    ContentUnavailableView(
                        "No Transcript Available",
                        systemImage: "text.bubble",
                        description: Text("Hermes did not expose transcript lines for this session yet.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            case .loaded(_, let messages):
                Section("Transcript") {
                    ForEach(messages) { message in
                        TranscriptMessageRow(message: message)
                            .listRowSeparator(.hidden)
                    }
                }
            case .failed(_, let message):
                Section("Transcript") {
                    ContentUnavailableView(
                        "Transcript Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.resolvedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.id) {
            await loadTranscript()
        }
        .refreshable {
            await loadTranscript()
        }
    }

    private func loadTranscript() async {
        if let cached = store.cachedTranscript(for: session.id), !cached.isEmpty {
            loadState = .loaded(sessionID: session.id, cached)
        } else {
            loadState = .loading(sessionID: session.id)
        }
        do {
            loadState = .loaded(sessionID: session.id, try await store.transcript(for: session.id))
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return
        } catch {
            if let cached = store.cachedTranscript(for: session.id), !cached.isEmpty {
                loadState = .loaded(sessionID: session.id, cached)
                return
            }
            if case .loaded = loadState {
                return
            }
            loadState = .failed(sessionID: session.id, error.localizedDescription)
        }
    }

    private var displayedLoadState: TranscriptLoadState {
        guard loadState.sessionID == session.id else {
            return .loading(sessionID: session.id)
        }
        return loadState
    }
}

struct SessionsScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @State private var query = ""

    var body: some View {
        List {
            Section {
                ActiveWorkspaceStrip(compact: true)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if store.sessions.isEmpty && store.isLoadingSessions {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading sessions…")
                        Spacer()
                    }
                }
            } else if store.sessions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "text.bubble",
                        description: Text("Remote Hermes sessions for the selected host and profile will appear here.")
                    )
                }
            } else {
                Section("Remote Sessions") {
                    ForEach(store.sessions) { session in
                        NavigationLink(value: HermesPhoneSessionRoute.transcript(session)) {
                            ConversationRow(session: session)
                        }
                    }

                    if store.hasMoreSessions {
                        Button {
                            Task { await store.loadMoreSessions() }
                        } label: {
                            HStack {
                                Spacer()
                                if store.isLoadingSessions {
                                    ProgressView()
                                } else {
                                    Text("Load More")
                                }
                                Spacer()
                            }
                        }
                        .disabled(store.isLoadingSessions)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .searchable(text: $query, prompt: "Search transcripts")
        .task(id: store.activeWorkspaceScopeFingerprint) {
            await store.refreshOverview()
        }
        .task(id: "\(store.activeWorkspaceScopeFingerprint ?? "")|\(query)") {
            if !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            await store.loadSessions(query: query)
        }
        .refreshable {
            await store.loadSessions(query: query)
        }
    }
}

enum TranscriptLoadState {
    case loading(sessionID: String?)
    case loaded(sessionID: String, [SessionMessage])
    case failed(sessionID: String, String)

    var sessionID: String? {
        switch self {
        case .loading(let sessionID):
            return sessionID
        case .loaded(let sessionID, _):
            return sessionID
        case .failed(let sessionID, _):
            return sessionID
        }
    }
}

#endif
