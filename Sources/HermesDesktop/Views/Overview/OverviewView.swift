import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
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
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task(id: appState.activeConnectionID) {
            if appState.overview == nil {
                await appState.refreshOverview()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Overview")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("See which host Hermes is connected to, where its files live, and which source powers Sessions, Cron Jobs, and Usage.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            HermesRefreshButton(isRefreshing: appState.isRefreshingOverview) {
                Task {
                    await appState.refreshOverview(manual: true)
                }
            }
            .disabled(appState.isBusy)
        }
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

                sessionHistoryPanel(overview)
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
        }
    }

    private func compactLayout(activeConnection: ConnectionProfile, overview: RemoteDiscovery) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            currentHostPanel(activeConnection)
            workspacePanel(overview)
            statusPanel(for: overview)
            workspaceFilesPanel(overview)
            sessionHistoryPanel(overview)
        }
    }

    private func currentHostPanel(_ activeConnection: ConnectionProfile) -> some View {
        OverviewPanel(
            title: "Current Host",
            subtitle: "The active SSH connection for this workspace."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeConnection.label)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(activeConnection.displayDestination)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                OverviewDetailBlock(
                    label: "Connection",
                    value: "SSH",
                    emphasizeValue: true
                )

                if let alias = activeConnection.trimmedAlias {
                    OverviewDetailBlock(
                        label: "Alias",
                        value: alias,
                        isMonospaced: true
                    )
                } else if let host = activeConnection.trimmedHost {
                    OverviewDetailBlock(
                        label: "Host",
                        value: host,
                        isMonospaced: true
                    )
                }

                if let lastConnectedAt = activeConnection.lastConnectedAt {
                    OverviewDetailBlock(
                        label: "Last connected",
                        value: DateFormatters.relativeFormatter().localizedString(for: lastConnectedAt, relativeTo: .now)
                    )
                }
            }
        }
    }

    private func workspacePanel(_ overview: RemoteDiscovery) -> some View {
        OverviewPanel(
            title: "Workspace",
            subtitle: "The active Hermes profile and the folders it resolves to on the current host."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OverviewDetailBlock(
                    label: "Active profile",
                    value: overview.activeProfile.name,
                    emphasizeValue: true
                )

                OverviewDetailBlock(
                    label: "Home folder",
                    value: overview.remoteHome,
                    isMonospaced: true
                )

                OverviewDetailBlock(
                    label: "Hermes home",
                    value: overview.hermesHome,
                    isMonospaced: true,
                    emphasizeValue: true
                )

                if !overview.availableProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Discovered profiles")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(overview.availableProfiles) { profile in
                                OverviewBadge(
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

        return OverviewPanel(
            title: "Status",
            subtitle: "Quick checks to confirm the active host is ready for files, sessions, usage, and terminal access."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    OverviewBadge(
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
            }
        }
    }

    private func workspaceFilesPanel(_ overview: RemoteDiscovery) -> some View {
        OverviewPanel(
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
            }
        }
    }

    private func sessionHistoryPanel(_ overview: RemoteDiscovery) -> some View {
        OverviewPanel(
            title: "Session History",
            subtitle: "The source Hermes uses for Sessions and Usage on the active host."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if let sessionStore = overview.sessionStore {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "internaldrive.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("SQLite database detected")
                                .font(.headline)

                            Text("Hermes can read structured session and message records directly.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        OverviewBadge(text: displaySessionStoreKind(sessionStore.kind), tint: .accentColor)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        OverviewDetailBlock(
                            label: "Database path",
                            value: sessionStore.path,
                            isMonospaced: true,
                            emphasizeValue: true
                        )

                        if let sessionTable = sessionStore.sessionTable {
                            OverviewDetailBlock(
                                label: "Sessions table",
                                value: sessionTable,
                                isMonospaced: true
                            )
                        }

                        if let messageTable = sessionStore.messageTable {
                            OverviewDetailBlock(
                                label: "Messages table",
                                value: messageTable,
                                isMonospaced: true
                            )
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Using transcript files")
                                .font(.headline)

                            Text("No SQLite database was found, so Hermes will fall back to session transcript artifacts when available.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        OverviewBadge(text: "JSONL", tint: .secondary)
                    }

                    OverviewDetailBlock(
                        label: "Transcript folder",
                        value: overview.paths.sessionsDir,
                        isMonospaced: true,
                        emphasizeValue: true
                    )
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
            )
        ]
    }

    private func displaySessionStoreKind(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "sqlite":
            "SQLite"
        default:
            rawValue.capitalized
        }
    }
}

private struct OverviewPanel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

private struct OverviewDetailBlock: View {
    let label: String
    let value: String
    var isMonospaced = false
    var emphasizeValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(valueFont)
                .foregroundStyle(emphasizeValue ? .primary : .secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var valueFont: Font {
        if isMonospaced {
            return .system(.subheadline, design: .monospaced)
        }
        return emphasizeValue ? .headline : .subheadline
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
                Text(title)
                    .font(.headline)

                OverviewBadge(text: badge, tint: .secondary)

                Spacer(minLength: 12)

                OverviewBadge(text: isReady ? "Ready" : "Missing", tint: isReady ? .green : .orange)
            }

            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
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

            Text(item.title)
                .font(.subheadline)

            Spacer()

            Text(item.isReady ? "Ready" : "Missing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.isReady ? .green : .orange)
        }
    }
}

private struct OverviewBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
