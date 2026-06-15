#if canImport(UIKit)
@preconcurrency import Citadel
import Crypto
import Foundation
import NIOCore
@preconcurrency import NIOSSH
import Security
import SwiftUI
import UIKit

struct ChatInboxScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @State private var query = ""

    var body: some View {
        List {
            Section {
                ActiveWorkspaceStrip()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if let connection = store.activeConnection {
                Section {
                    if store.nativeChatStore.hasRestorableConversation {
                        BackgroundConversationCard(
                            session: activeConversationSummary,
                            chatStore: store.nativeChatStore,
                            onOpen: store.reopenActiveConversation,
                            onClose: {
                                Task { await store.nativeChatStore.closeChat() }
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    ConversationLaunchCard(
                        connection: connection,
                        chatStore: store.nativeChatStore,
                        onNewChat: store.openNewChat,
                        onOpenTerminal: store.ensureTerminalConnected
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if shouldShowSessionsLoadingState {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading chats…")
                            Spacer()
                        }
                    }
                } else if shouldShowSessionsLoadFailure {
                    Section {
                        ContentUnavailableView(
                            "Couldn't Load Chats",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Check the connection and try again.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                        Button("Retry", systemImage: "arrow.clockwise") {
                            Task { await store.loadSessions(query: query) }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(store.isLoadingSessions)
                    }
                } else if shouldShowEmptyConversationState {
                    Section(querySectionTitle) {
                        ContentUnavailableView(
                            emptyConversationTitle,
                            systemImage: "bubble.left.and.text.bubble.right",
                            description: Text(emptyConversationDescription)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                } else {
                    Section(querySectionTitle) {
                        ForEach(displayedSessions) { session in
                            Button {
                                store.continueSessionInChat(session)
                            } label: {
                                ConversationRow(
                                    session: session,
                                    isActiveConversation: store.nativeChatStore.isActiveConversation(session)
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Continue", systemImage: "bubble.left.and.bubble.right") {
                                    store.continueSessionInChat(session)
                                }
                                .tint(.blue)

                                Button("Terminal", systemImage: "terminal") {
                                    store.resumeSessionInTerminal(session)
                                }
                                .tint(.green)
                            }
                            .contextMenu {
                                Button {
                                    store.continueSessionInChat(session)
                                } label: {
                                    Label("Continue in Chat", systemImage: "bubble.left.and.bubble.right")
                                }

                                Button {
                                    store.chatNavigationPath.append(.transcript(session))
                                } label: {
                                    Label("View Transcript", systemImage: "text.bubble")
                                }

                                Button {
                                    store.resumeSessionInTerminal(session)
                                } label: {
                                    Label("Resume in Terminal", systemImage: "terminal")
                                }
                            }
                        }
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No Active Connection",
                        systemImage: "server.rack",
                        description: Text("Choose a saved SSH connection to browse profile-specific chats or start a new Hermes conversation.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Chats")
        .toolbar {
            if store.activeConnection != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.openNewChat()
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search past chats"
        )
        .onSubmit(of: .search) {
            Task { await store.loadSessions(query: query) }
        }
        .onChange(of: query) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { await store.loadSessions() }
            }
        }
        .task(id: store.activeWorkspaceScopeFingerprint) {
            await store.nativeChatStore.syncWithActiveConnection()
            await store.loadSessions()
            Task { await store.refreshOverview() }
            Task { await store.nativeChatStore.refreshBootstrapStatus() }
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                await store.nativeChatStore.warmGatewayIfUseful()
            }
        }
        .refreshable {
            await loadChatInbox(query: query)
            await store.nativeChatStore.refreshBootstrapStatus(force: true)
        }
    }

    @MainActor
    private func loadChatInbox(query: String = "") async {
        async let overviewTask: Void = store.refreshOverview()
        async let sessionsTask: Void = store.loadSessions(query: query)
        _ = await (overviewTask, sessionsTask)
    }

    private var shouldShowSessionsLoadingState: Bool {
        displayedSessions.isEmpty &&
            (store.isLoadingSessions ||
             store.sessionsLoadState == .pending ||
             store.sessionsLoadState == .loading)
    }

    private var shouldShowSessionsLoadFailure: Bool {
        displayedSessions.isEmpty && store.sessionsLoadState == .failed
    }

    private var shouldShowEmptyConversationState: Bool {
        displayedSessions.isEmpty && store.sessionsLoadState == .loaded
    }

    private var querySectionTitle: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Search Results"
        }
        return store.nativeChatStore.hasRestorableConversation ? "Other Conversations" : "Recent Conversations"
    }

    private var emptyConversationTitle: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Search Results"
        }
        return store.nativeChatStore.hasRestorableConversation ? "No Other Chats" : "No Chats Yet"
    }

    private var emptyConversationDescription: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try another search or clear the query to return to recent conversations."
        }
        if store.nativeChatStore.hasRestorableConversation {
            return "The open background chat is shown above. Other conversations for this profile will appear here."
        }
        return "Start a new Hermes chat with the selected profile. Your past conversations for this profile will appear here."
    }

    private var activeConversationSummary: SessionSummary? {
        store.sessions.first { store.nativeChatStore.isActiveConversation($0) }
    }

    private var displayedSessions: [SessionSummary] {
        guard store.nativeChatStore.hasRestorableConversation else { return store.sessions }
        return store.sessions.filter { !store.nativeChatStore.isActiveConversation($0) }
    }
}

struct BackgroundConversationCard: View {
    let session: SessionSummary?
    @ObservedObject var chatStore: HermesNativeChatStore
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title3)
                    .foregroundStyle(Color(red: 0.18, green: 0.72, blue: 0.62))
                    .frame(width: 34, height: 34)
                    .background(Color(red: 0.18, green: 0.72, blue: 0.62).opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(chatStore.restorableConversationPreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Menu {
                    Button("Open Chat", systemImage: "arrow.up.right.bubble") {
                        onOpen()
                    }
                    Button("Close Chat", systemImage: "xmark.circle", role: .destructive) {
                        onClose()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }

            HStack(spacing: 8) {
                DetailBadge(title: chatStore.restorableConversationStatus, tint: Color(red: 0.18, green: 0.72, blue: 0.62))

                if let model = session?.displayModel {
                    DetailBadge(title: model, tint: .blue)
                }

                if let updatedAt {
                    DetailBadge(title: DateFormatters.shortDateTimeString(from: updatedAt), tint: .secondary)
                }
            }

            Button(action: onOpen) {
                Label("Open Chat", systemImage: "arrow.up.right.bubble")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(red: 0.18, green: 0.72, blue: 0.62).opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open background chat")
    }

    private var title: String {
        session?.resolvedTitle ?? chatStore.restorableConversationTitle
    }

    private var updatedAt: Date? {
        chatStore.restorableConversationUpdatedAt ??
            session?.lastActive?.dateValue ??
            session?.startedAt?.dateValue
    }
}

struct ConversationLaunchCard: View {
    let connection: ConnectionProfile
    @ObservedObject var chatStore: HermesNativeChatStore
    let onNewChat: () -> Void
    let onOpenTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: onNewChat) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                        Text("New Chat")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onOpenTerminal) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                        Text("Terminal")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if !chatStore.canUseNativeChat, let fallbackReason = chatStore.fallbackReason {
                Text(fallbackReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.18, blue: 0.17),
                            Color(red: 0.06, green: 0.11, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat actions for \(connection.resolvedHermesProfileName)")
    }
}

struct ConversationRow: View {
    let session: SessionSummary
    let isActiveConversation: Bool

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
                if isActiveConversation {
                    DetailBadge(title: "Live", tint: Color(red: 0.18, green: 0.72, blue: 0.62))
                }

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

        return "Open this chat to review the transcript or continue it."
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
    let onContinueInChat: () -> Void
    let onResumeInTerminal: () -> Void

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

            HStack(spacing: 10) {
                Button(action: onContinueInChat) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                        Text("Continue in Chat")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onResumeInTerminal) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                        Text("Resume in Terminal")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
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
                    Text(content)
                        .font(.body)
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
                SessionSummaryCard(
                    session: session,
                    onContinueInChat: { store.continueSessionInChat(session) },
                    onResumeInTerminal: { store.resumeSessionInTerminal(session) }
                )
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
                        description: Text("Hermes did not expose transcript lines for this session yet. You can still continue it in chat or reopen it in the terminal.")
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
        .toolbar {
            Button("Chat") {
                store.continueSessionInChat(session)
            }

            Button("Resume") {
                store.resumeSessionInTerminal(session)
            }
        }
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
        } catch {
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
