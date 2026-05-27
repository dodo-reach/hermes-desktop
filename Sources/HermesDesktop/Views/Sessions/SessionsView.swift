import AppKit
import SwiftUI

struct SessionsView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var splitLayout: HermesSplitLayout
    let isActive: Bool
    @State private var searchText = ""
    @State private var sessionToDelete: SessionSummary?

    var body: some View {
        HermesCollapsibleHSplitView(layout: $splitLayout, detailMinWidth: 420) {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Sessions",
                    subtitle: "Browse the recent Hermes conversations discovered on the active host."
                ) {
                    HermesExpandableSearchField(
                        text: $searchText,
                        prompt: L10n.string("Search sessions"),
                        expandedWidth: 220,
                        focusRequestID: appState.searchFocusRequestID
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }

                sessionsToolbar
                sessionsContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        } detail: {
            SessionDetailView(
                connection: appState.activeConnection,
                session: selectedSession,
                messages: appState.sessionMessageDisplays,
                errorMessage: appState.sessionsError,
                conversationError: appState.sessionConversationError,
                isSendingMessage: appState.isSendingSessionMessage,
                isDeletingSession: selectedSession.map { selectedSession in
                    appState.isDeletingSession && appState.selectedSessionID == selectedSession.id
                } ?? false,
                isSessionPinned: selectedSession.map { appState.isSessionPinned($0.id) } ?? false,
                sessionCompactionNotice: appState.sessionCompactionNotice,
                activeRun: appState.workspaceSessionActiveRun,
                pendingTurn: appState.pendingSessionTurn,
                liveMessages: appState.liveSessionMessageDisplays,
                liveToolActivityCards: appState.liveToolActivityCards,
                promptCards: appState.sessionPromptCards,
                mode: appState.selectedSessionDetailMode,
                terminal: appState.sessionTUITerminal,
                terminalTheme: appState.connectionStore.terminalTheme,
                terminalAppearance: appState.connectionStore.terminalTheme.resolvedAppearance,
                isActive: isActive,
                savedScrollOffset: selectedSession.flatMap { selectedSession in
                    appState.savedSessionScrollOffset(for: selectedSession.id)
                },
                onSaveScrollOffset: { sessionID, offset in
                    appState.saveSessionScrollOffset(offset, for: sessionID)
                },
                onResumeInTerminal: { session in
                    appState.resumeSessionInTerminal(session)
                },
                onDeleteSession: { session in
                    await appState.deleteSession(session)
                },
                onToggleSessionPin: { session in
                    appState.toggleSessionPin(session)
                },
                onModeChange: { mode in
                    appState.setSessionDetailMode(mode)
                },
                onStartChat: {
                    appState.startSelectedSessionChat()
                },
                onStartSession: { prompt, autoApproveCommands, attachments in
                    await appState.startNewSession(with: prompt, autoApproveCommands: autoApproveCommands, attachments: attachments)
                },
                onSendMessage: { prompt, autoApproveCommands, attachments in
                    await appState.sendMessageToSelectedSession(prompt, autoApproveCommands: autoApproveCommands, attachments: attachments)
                },
                onRespondToPrompt: { card, response in
                    await appState.respondToSessionPrompt(card, response: response)
                },
                onUpdateTerminalTheme: { newValue in
                    appState.connectionStore.terminalTheme = newValue
                },
                onTerminalExitRefresh: {
                    await appState.refreshSessionsAfterChat()
                }
            )
            .hermesSplitDetailColumn(minWidth: 420, idealWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: sessionsLoadTaskID) {
            guard isActive else { return }
            if appState.sessions.isEmpty {
                await appState.loadSessions(reset: true)
            }
        }
        .task(id: searchTaskID) {
            guard isActive else { return }
            guard appState.activeConnectionID != nil else { return }

            let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedQuery != appState.sessionSearchQuery else { return }

            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await appState.loadSessions(reset: true, query: searchText)
        }
        .alert(L10n.string("Delete this session?"), isPresented: deleteConfirmationBinding, presenting: sessionToDelete) { session in
            Button(L10n.string("Delete"), role: .destructive) {
                Task {
                    await appState.deleteSession(session)
                }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: { session in
            Text(L10n.string(
                "“%@” will be removed from Hermes Desktop and deleted on the remote Hermes host as well. This action cannot be undone.",
                session.resolvedTitle
            ))
        }
    }

    private var sessionsLoadTaskID: String {
        "\(isActive):\(appState.activeConnectionID?.uuidString ?? "none")"
    }

    private var searchTaskID: String {
        "\(isActive):\(searchText)"
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding {
            sessionToDelete != nil
        } set: { isPresented in
            if !isPresented {
                sessionToDelete = nil
            }
        }
    }

    @ViewBuilder
    private var sessionsContent: some View {
        sessionsPanel
    }

    @ViewBuilder
    private var sessionsPanel: some View {
        if appState.isLoadingSessions && !hasVisibleSessions {
            HermesSurfacePanel {
                HermesLoadingState(
                    label: "Loading sessions…",
                    minHeight: 300
                )
            }
        } else if let error = appState.sessionsError, !hasVisibleSessions {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Unable to load sessions"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if !hasVisibleSessions && !appState.sessionSearchQuery.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No matching sessions"),
                    systemImage: "magnifyingglass",
                    description: Text(L10n.string("Try searching by session name, ID, preview text, or message content."))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if !hasVisibleSessions {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No sessions found"),
                    systemImage: "tray",
                    description: Text(L10n.string("No readable Hermes sessions were discovered yet for this SSH target."))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else {
            HermesSurfacePanel(
                title: panelTitle,
                subtitle: "Select a session to continue the chat and inspect its metadata and last activity."
            ) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !visiblePinnedSessions.isEmpty {
                            SessionSectionHeader(
                                title: L10n.string(
                                    "Pinned Sessions (%@)",
                                    "\(visiblePinnedSessions.count)"
                                )
                            )

                            ForEach(visiblePinnedSessions) { session in
                                sessionRow(session)
                            }

                            if !visibleStoredSessions.isEmpty {
                                Divider()
                                    .padding(.vertical, 2)

                                SessionSectionHeader(
                                    title: L10n.string("All Sessions (%@)", "\(appState.totalSessionsCount)")
                                )
                            }
                        }

                        ForEach(visibleStoredSessions) { session in
                            sessionRow(session)
                        }

                        if appState.hasMoreSessions {
                            Button(L10n.string("Load More")) {
                                Task { await appState.loadSessions(reset: false) }
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingSessions && !appState.isRefreshingSessions && !appState.sessions.isEmpty {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowPinnedSessions: Bool {
        appState.sessionSearchQuery.isEmpty && trimmedSearchText.isEmpty
    }

    private var visiblePinnedSessions: [SessionSummary] {
        shouldShowPinnedSessions ? appState.pinnedSessionSummaries : []
    }

    private var visibleStoredSessions: [SessionSummary] {
        shouldShowPinnedSessions ? appState.unpinnedSessions : appState.sessions
    }

    private var hasVisibleSessions: Bool {
        !visiblePinnedSessions.isEmpty || !visibleStoredSessions.isEmpty
    }

    private func sessionRow(_ session: SessionSummary) -> some View {
        let isPinned = appState.isSessionPinned(session.id)

        return SessionCardRow(
            session: session,
            isSelected: session.id == appState.selectedSessionID,
            isPinned: isPinned,
            onTogglePin: {
                appState.toggleSessionPin(session)
            },
            onDelete: {
                sessionToDelete = session
            }
        ) {
            Task {
                await appState.loadSessionDetail(sessionID: session.id)
            }
        }
        // Rows move between two LazyVStack sections when pinned. Include the pin state
        // in the row identity so the pin button subtree is rebuilt with the move.
        .id(SessionCardRowIdentity(sessionID: session.id, isPinned: isPinned))
    }

    private var sessionsToolbar: some View {
        HStack(spacing: 10) {
            HermesCreateActionButton("New Chat") {
                searchText = ""
                appState.startNewSessionChat()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var panelTitle: String {
        if appState.sessionSearchQuery.isEmpty {
            return L10n.string("Sessions Library (%@)", "\(appState.totalSessionsCount)")
        }

        return L10n.string("Matching Sessions (%@)", "\(appState.totalSessionsCount)")
    }

    private var selectedSession: SessionSummary? {
        guard let selectedSessionID = appState.selectedSessionID else { return nil }
        return appState.sessionSummary(for: selectedSessionID)
    }
}

private struct SessionCardRowIdentity: Hashable {
    let sessionID: String
    let isPinned: Bool
}

private struct SessionSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }
}

private struct SessionCardRow: View {
    let session: SessionSummary
    let isSelected: Bool
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            content
                .padding(.trailing, 34)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                        .fill(isSelected ? HermesTheme.selectedFill : HermesTheme.rowFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                        .strokeBorder(isSelected ? HermesTheme.selectedStroke : HermesTheme.subtleStroke, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isPinned || isSelected || isHovering {
                VStack(spacing: 6) {
                    pinButton
                    deleteButton
                }
                    .padding(.top, 10)
                    .padding(.trailing, 14)
                    .transition(.opacity)
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(pinHelpText, action: onTogglePin)
            Button(L10n.string("Delete session"), role: .destructive, action: onDelete)

            Button(L10n.string("Copy Session ID")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
        }
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isPinned ? Color.orange : Color.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isPinned ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.08))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(pinHelpText)
        .accessibilityLabel(pinHelpText)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.red)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.red.opacity(0.12))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L10n.string("Delete session"))
        .accessibilityLabel(L10n.string("Delete session"))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.resolvedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(session.id)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if let count = session.messageCount {
                    HermesBadge(text: L10n.string("%@ messages", "\(count)"), tint: .secondary)
                }
            }

            if let searchMatch = session.searchMatch,
               let snippet = searchMatch.snippet,
               !snippet.isEmpty {
                searchMatchPreview(searchMatch, snippet: snippet)
            } else if let preview = session.preview, !preview.isEmpty {
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    if let startedAt = session.startedAt?.dateValue {
                        metaLabel(L10n.string("Started %@", DateFormatters.relativeFormatter().localizedString(for: startedAt, relativeTo: .now)))
                    }

                    if let lastActive = session.lastActive?.dateValue {
                        metaLabel(L10n.string("Active %@", DateFormatters.relativeFormatter().localizedString(for: lastActive, relativeTo: .now)))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let startedAt = session.startedAt?.dateValue {
                        metaLabel(L10n.string("Started %@", DateFormatters.relativeFormatter().localizedString(for: startedAt, relativeTo: .now)))
                    }

                    if let lastActive = session.lastActive?.dateValue {
                        metaLabel(L10n.string("Active %@", DateFormatters.relativeFormatter().localizedString(for: lastActive, relativeTo: .now)))
                    }
                }
            }
        }
    }

    private func searchMatchPreview(_ match: SessionSearchMatch, snippet: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                Text(searchMatchLabel(match))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(snippet)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private func searchMatchLabel(_ match: SessionSearchMatch) -> String {
        let countText = match.matchCount == 1
            ? L10n.string("1 match")
            : L10n.string("%@ matches", "\(match.matchCount)")

        guard let role = match.role else {
            return countText
        }

        return "\(role.displayTitle) - \(countText)"
    }

    private var pinHelpText: String {
        L10n.string(isPinned ? "Unpin session" : "Pin session")
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
