import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HermesPageContainer(width: .dashboard) {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let activeConnection = appState.activeConnection,
                   let overview = appState.overview {
                    overviewLayout(activeConnection: activeConnection, overview: overview)
                } else if let overviewError = appState.overviewError {
                    HermesSurfacePanel {
                        ContentUnavailableView(
                            "Discovery failed",
                            systemImage: "exclamationmark.triangle",
                            description: Text(overviewError)
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                } else {
                    HermesSurfacePanel {
                        HermesLoadingState(
                            label: "Discovering the active Hermes workspace…",
                            minHeight: 320
                        )
                    }
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            if appState.overview == nil {
                await appState.refreshOverview()
            }
        }
    }

    private var header: some View {
        HermesPageHeader(
            title: "Overview",
            subtitle: "See which host Hermes is connected to, where its files live, and which source powers Sessions, Cron Jobs, and Usage."
        )
    }

    @ViewBuilder
    private func overviewLayout(activeConnection: ConnectionProfile, overview: RemoteDiscovery) -> some View {
        ViewThatFits(in: .horizontal) {
            regularLayout(activeConnection: activeConnection, overview: overview)
            compactLayout(activeConnection: activeConnection, overview: overview)
        }
    }

    private func regularLayout(activeConnection: ConnectionProfile, overview: RemoteDiscovery) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                currentHostPanel(activeConnection)
                    .frame(minWidth: 230, maxWidth: .infinity)

                workspacePanel(overview)
                    .frame(minWidth: 270, maxWidth: .infinity)

                statusPanel(for: overview)
                    .frame(minWidth: 230, maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 16) {
                workspaceFilesPanel(overview)
                    .frame(minWidth: 420, maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    chatPanel(overview)
                    kanbanPanel(overview)
                }
                .frame(minWidth: 420, maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func compactLayout(activeConnection: ConnectionProfile, overview: RemoteDiscovery) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            currentHostPanel(activeConnection)
            workspacePanel(overview)
            statusPanel(for: overview)
            workspaceFilesPanel(overview)
            chatPanel(overview)
            kanbanPanel(overview)
        }
    }

    private func currentHostPanel(_ activeConnection: ConnectionProfile) -> some View {
        HermesSurfacePanel(
            title: "Current Host",
            subtitle: "The active SSH connection for this workspace."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeConnection.label)
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(activeConnection.displayDestination)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HermesInspectorFieldList(fields: currentHostFields(activeConnection), labelWidth: 96)
            }
        }
    }

    private func workspacePanel(_ overview: RemoteDiscovery) -> some View {
        HermesSurfacePanel(
            title: "Workspace",
            subtitle: "The active Hermes profile and the folders it resolves to on the current host."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HermesInspectorFieldList(fields: workspaceFields(overview), labelWidth: 96)

                if !overview.availableProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("Discovered profiles"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HermesWrappingFlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                            ForEach(overview.availableProfiles) { profile in
                                HermesBadge(
                                    text: profile.name,
                                    tint: profile.name == overview.activeProfile.name ? .accentColor : .secondary
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusPanel(for overview: RemoteDiscovery) -> some View {
        let statusItems = makeStatusItems(for: overview)
        let readyCount = statusItems.filter(\.isReady).count
        let summaryTitle = readyCount == statusItems.count ? "Ready" : "Needs attention"
        let summaryDetail = readyCount == statusItems.count
            ? "All \(statusItems.count) checks passed"
            : "\(readyCount) of \(statusItems.count) checks passed"

        return HermesSurfacePanel(
            title: "Status",
            subtitle: "Quick checks to confirm the active host is ready for files, sessions, usage, and terminal access."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    HermesBadge(
                        text: summaryTitle,
                        tint: readyCount == statusItems.count ? .green : .orange
                    )

                    Text(summaryDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(statusItems) { item in
                        OverviewStatusRow(item: item)
                    }
                }

                HStack(spacing: 10) {
                    Button(L10n.string("Refresh Checks")) {
                        Task {
                            await appState.refreshOverview(manual: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L10n.string("Connections")) {
                        appState.requestSectionSelection(.connections)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func workspaceFilesPanel(_ overview: RemoteDiscovery) -> some View {
        HermesSurfacePanel(
            title: "Workspace Files",
            subtitle: "Expected Hermes files and folders on the active host."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                OverviewPathRow(
                    title: "User file",
                    badge: "USER.md",
                    value: overview.paths.user,
                    isReady: overview.exists.user
                )

                OverviewPathRow(
                    title: "Memory file",
                    badge: "MEMORY.md",
                    value: overview.paths.memory,
                    isReady: overview.exists.memory
                )

                OverviewPathRow(
                    title: "Soul file",
                    badge: "SOUL.md",
                    value: overview.paths.soul,
                    isReady: overview.exists.soul
                )

                OverviewPathRow(
                    title: "Session artifacts",
                    badge: "Sessions",
                    value: overview.paths.sessionsDir,
                    isReady: overview.exists.sessionsDir
                )

                OverviewPathRow(
                    title: "Cron jobs registry",
                    badge: "Cron",
                    value: overview.paths.cronJobs,
                    isReady: overview.exists.cronJobs
                )

                OverviewPathRow(
                    title: "Kanban board",
                    badge: "Kanban",
                    value: overview.paths.kanbanDatabase ?? "~/.hermes/kanban.db",
                    isReady: overview.exists.kanbanDatabase ?? false
                )
            }
        }
    }

    private func chatPanel(_ overview: RemoteDiscovery) -> some View {
        HermesSurfacePanel(
            title: "Chat",
            subtitle: "Readiness for native chat and the persisted session history read back from the host."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "terminal.fill")
                        .font(.title3)
                        .foregroundStyle(isTUIChatReady ? Color.accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string(chatReadinessTitle))
                            .font(.headline)

                        Text(L10n.string(chatReadinessDetail))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    HermesBadge(
                        text: isTUIChatReady ? "TUI ready" : "Check host",
                        tint: isTUIChatReady ? .green : .orange
                    )
                }

                HermesInspectorFieldList(fields: chatFields(overview), labelWidth: 110)

                HStack(spacing: 10) {
                    Button(L10n.string("New Chat")) {
                        appState.requestNewSessionFromCommand()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L10n.string("Open Sessions")) {
                        appState.requestSectionSelection(.sessions)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func kanbanPanel(_ overview: RemoteDiscovery) -> some View {
        HermesSurfacePanel(
            title: "Kanban Board",
            subtitle: "Host-wide coordination state shared by Hermes profiles on this SSH target."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "rectangle.3.group")
                        .font(.title3)
                        .foregroundStyle(overview.kanban?.exists == true ? Color.accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string(overview.kanban?.exists == true ? "Kanban database detected" : "Kanban database not initialized"))
                            .font(.headline)

                        Text(L10n.string("Desktop reads and updates this board over SSH without using the web dashboard API."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    HermesBadge(text: "Host-wide", tint: .accentColor)
                }

                HermesInspectorFieldList(fields: [
                    HermesInspectorField(
                        id: "database-path",
                        label: "Database path",
                        value: overview.kanban?.databasePath ?? overview.paths.kanbanDatabase ?? "~/.hermes/kanban.db",
                        isMonospaced: true,
                        emphasizeValue: true
                    )
                ], labelWidth: 104)

                HStack(spacing: 10) {
                    HermesBadge(
                        text: overview.kanban?.hasHermesCLI == true ? "CLI ready" : "CLI missing",
                        tint: overview.kanban?.hasHermesCLI == true ? .green : .orange
                    )

                    HermesBadge(
                        text: overview.kanban?.hasKanbanModule == true ? "Module ready" : "Module fallback",
                        tint: overview.kanban?.hasKanbanModule == true ? .green : .secondary
                    )

                    if let dispatcher = overview.kanban?.dispatcher,
                       let running = dispatcher.running {
                        HermesBadge(
                            text: running ? "Dispatcher active" : "Dispatcher inactive",
                            tint: running ? .green : .orange
                        )
                    }
                }

                if overview.kanban?.dispatcher?.isKnownInactive == true,
                   let message = overview.kanban?.dispatcher?.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func makeStatusItems(for overview: RemoteDiscovery) -> [OverviewStatusItem] {
        [
            OverviewStatusItem(
                id: "profile",
                title: "Selected profile home",
                isReady: overview.activeProfile.exists
            ),
            OverviewStatusItem(
                id: "files",
                title: "Workspace files",
                isReady: overview.exists.user && overview.exists.memory && overview.exists.soul
            ),
            OverviewStatusItem(
                id: "sessions",
                title: "Sessions/Usage source",
                isReady: overview.sessionStore != nil || overview.exists.sessionsDir
            ),
            OverviewStatusItem(
                id: "chat-tui",
                title: "Chat TUI",
                isReady: isTUIChatReady
            ),
            OverviewStatusItem(
                id: "kanban",
                title: "Host-wide Kanban board",
                isReady: overview.kanban?.exists == true || overview.kanban?.hasHermesCLI == true || overview.kanban?.hasKanbanModule == true
            )
        ]
    }

    private func currentHostFields(_ activeConnection: ConnectionProfile) -> [HermesInspectorField] {
        var fields = [
            HermesInspectorField(
                id: "connection",
                label: "Connection",
                value: "SSH",
                emphasizeValue: true
            )
        ]

        if let alias = activeConnection.trimmedAlias {
            fields.append(HermesInspectorField(
                id: "alias",
                label: "Alias",
                value: alias,
                isMonospaced: true
            ))
        } else if let host = activeConnection.trimmedHost {
            fields.append(HermesInspectorField(
                id: "host",
                label: "Host",
                value: host,
                isMonospaced: true
            ))
        }

        if let lastConnectedAt = activeConnection.lastConnectedAt {
            fields.append(HermesInspectorField(
                id: "last-connected",
                label: "Last connected",
                value: DateFormatters.relativeFormatter().localizedString(for: lastConnectedAt, relativeTo: .now)
            ))
        }

        return fields
    }

    private func workspaceFields(_ overview: RemoteDiscovery) -> [HermesInspectorField] {
        [
            HermesInspectorField(
                id: "active-profile",
                label: "Active profile",
                value: overview.activeProfile.name,
                emphasizeValue: true
            ),
            HermesInspectorField(
                id: "home-folder",
                label: "Home folder",
                value: overview.remoteHome,
                isMonospaced: true
            ),
            HermesInspectorField(
                id: "hermes-home",
                label: "Hermes home",
                value: overview.hermesHome,
                isMonospaced: true,
                emphasizeValue: true
            )
        ]
    }

    private func sessionStoreFields(_ sessionStore: RemoteSessionStore) -> [HermesInspectorField] {
        var fields = [
            HermesInspectorField(
                id: "database-path",
                label: "Database path",
                value: sessionStore.path,
                isMonospaced: true,
                emphasizeValue: true
            )
        ]

        if let sessionTable = sessionStore.sessionTable {
            fields.append(HermesInspectorField(
                id: "sessions-table",
                label: "Sessions table",
                value: sessionTable,
                isMonospaced: true
            ))
        }

        if let messageTable = sessionStore.messageTable {
            fields.append(HermesInspectorField(
                id: "messages-table",
                label: "Messages table",
                value: messageTable,
                isMonospaced: true
            ))
        }

        return fields
    }

    private func chatFields(_ overview: RemoteDiscovery) -> [HermesInspectorField] {
        var fields = [
            HermesInspectorField(
                id: "transport",
                label: "Transport",
                value: "Hermes TUI over SSH",
                emphasizeValue: true
            ),
            HermesInspectorField(
                id: "session-source",
                label: "Session source",
                value: overview.sessionStore?.kind.displayName ?? "Session history files"
            )
        ]

        if let sessionStore = overview.sessionStore {
            fields.append(
                HermesInspectorField(
                    id: "session-store-path",
                    label: "Storage path",
                    value: sessionStore.path,
                    isMonospaced: true,
                    emphasizeValue: true
                )
            )
        } else {
            fields.append(
                HermesInspectorField(
                    id: "session-history-folder",
                    label: "Storage path",
                    value: overview.paths.sessionsDir,
                    isMonospaced: true,
                    emphasizeValue: true
                )
            )
        }

        return fields
    }

    private var isTUIChatReady: Bool {
        appState.nativeChatBootstrapStatus?.sshConnected == true &&
            appState.nativeChatBootstrapStatus?.hermesCLIAvailable == true
    }

    private var chatReadinessTitle: String {
        isTUIChatReady ? "Hermes TUI ready" : "Hermes TUI needs attention"
    }

    private var chatReadinessDetail: String {
        if isTUIChatReady {
            return "Chat is ready; Sessions reads persisted conversation history from the host."
        }

        return appState.nativeChatBootstrapStatus?.fallbackReason ??
            "Hermes Desktop is checking whether this host can launch the embedded Chat TUI."
    }
}

private struct OverviewPathRow: View {
    let title: String
    let badge: String
    let value: String
    let isReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(L10n.string(title))
                    .font(.subheadline.weight(.semibold))

                HermesBadge(text: badge, tint: .secondary)

                Spacer(minLength: 12)

                HermesBadge(text: isReady ? "Ready" : "Missing", tint: isReady ? .green : .orange)
            }

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(HermesTheme.rowFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
        }
    }
}

private struct OverviewStatusItem: Identifiable {
    let id: String
    let title: String
    let isReady: Bool
}

private struct OverviewStatusRow: View {
    let item: OverviewStatusItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(item.isReady ? .green : .orange)

            Text(L10n.string(item.title))
                .font(.callout)

            Spacer()

            Text(L10n.string(item.isReady ? "Ready" : "Missing"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.isReady ? .green : .orange)
        }
    }
}
