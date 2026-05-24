import SwiftUI

struct CaelWorkspaceWebView: View {
    @EnvironmentObject private var appState: AppState

    private let workspaceURL = URL(string: "http://100.97.216.111:3077/cael-home")!

    var body: some View {
        HermesPageContainer(width: .analytics) {
            VStack(alignment: .leading, spacing: 24) {
                HermesPageHeader(
                    title: "Cael Homebase",
                    subtitle: "Native cockpit for the BigMac workspace runtime. Web Workspace stays available as a fallback, but this surface is rendered by the desktop app.",
                    accessory: {
                        HStack(spacing: 10) {
                            HermesRefreshButton(isRefreshing: appState.isRefreshingCaelWorkspace) {
                                Task { await appState.refreshCaelWorkspace() }
                            }

                            Link(destination: workspaceURL) {
                                Label("Open Web Workspace", systemImage: "safari")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                )

                content
            }
        }
        .task(id: appState.activeConnectionID) {
            await appState.loadCaelWorkspace()
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.isLoadingCaelWorkspace,
           appState.caelWorkspaceStatus == nil,
           appState.caelIntegrationStatus == nil {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading Cael workspace…", minHeight: 320)
            }
        } else if let error = appState.caelWorkspaceError,
                  appState.caelWorkspaceStatus == nil {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load Cael workspace",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else {
            if let summary = appState.caelCommandCenterSummary {
                commandCenterSnapshot(summary, warnings: appState.caelCommandCenterWarnings)
            }

            if let status = appState.caelWorkspaceStatus {
                statusOverview(status)
                systemsPanel(status)
            }

            if let integrations = appState.caelIntegrationStatus {
                integrationsPanel(integrations)
            }

            nativeFeatureMap
        }
    }

    private func statusOverview(_ status: CaelWorkspaceStatus) -> some View {
        LazyVGrid(columns: adaptiveColumns(minWidth: 220), spacing: 14) {
            CaelHomebaseMetricCard(
                title: "Runtime",
                value: status.host,
                subtitle: "BigMac personal runtime host",
                systemImage: "desktopcomputer",
                tint: .cyan
            )
            CaelHomebaseMetricCard(
                title: "Bind",
                value: status.posture.bind,
                subtitle: status.posture.remoteAccess,
                systemImage: "network",
                tint: .blue
            )
            CaelHomebaseMetricCard(
                title: "Auth",
                value: status.ok ? "Ready" : "Needs attention",
                subtitle: status.posture.auth,
                systemImage: status.ok ? "checkmark.shield" : "exclamationmark.shield",
                tint: status.ok ? .green : .orange
            )
            CaelHomebaseMetricCard(
                title: "Exposure",
                value: status.posture.publicInternet,
                subtitle: "Personal mesh only",
                systemImage: "lock.shield",
                tint: .mint
            )
        }
    }

    private func systemsPanel(_ status: CaelWorkspaceStatus) -> some View {
        HermesSurfacePanel(
            title: "Systems",
            subtitle: "Native status cards sourced from the workspace readiness API."
        ) {
            LazyVGrid(columns: adaptiveColumns(minWidth: 280), spacing: 12) {
                ForEach(status.services) { service in
                    CaelSystemCard(service: service)
                }
            }
        }
    }

    private func integrationsPanel(_ status: CaelIntegrationStatus) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HermesSurfacePanel(
                title: "Integrations",
                subtitle: "Provider readiness for Google Workspace, Vaultwarden, and legacy Twenty. Mutations stay approval-gated."
            ) {
                LazyVGrid(columns: adaptiveColumns(minWidth: 280), spacing: 12) {
                    ForEach(status.integrations) { integration in
                        CaelIntegrationCard(integration: integration)
                    }
                }
            }

            HermesSurfacePanel(title: "Policy") {
                LazyVGrid(columns: adaptiveColumns(minWidth: 280), spacing: 12) {
                    ForEach(status.policy.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HermesInsetSurface {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(key)
                                    .font(.caption.weight(.semibold))
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                                Text(value)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }



    private func commandCenterSnapshot(
        _ summary: CaelCommandCenterSummary,
        warnings: [String]
    ) -> some View {
        HermesSurfacePanel(
            title: "Shared Command Center",
            subtitle: "Snapshot from /api/command-center/summary. Desktop and Web render the same contract."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if !warnings.isEmpty {
                    HermesInsetSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Warnings")
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(.orange)
                            ForEach(warnings, id: \.self) { warning in
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                LazyVGrid(columns: adaptiveColumns(minWidth: 260), spacing: 12) {
                    CaelCommandCenterListCard(
                        title: "Now / Next",
                        emptyText: "No focus items reported."
                    ) {
                        ForEach(summary.nowNext.prefix(5)) { item in
                            CaelCommandCenterRow(
                                title: item.label,
                                detail: item.detail,
                                tint: tint(for: item.tone)
                            )
                        }
                    }

                    CaelCommandCenterListCard(
                        title: "Action Gates",
                        emptyText: "No approval gates surfaced.",
                        isEmpty: summary.actionGates.isEmpty
                    ) {
                        ForEach(summary.actionGates.prefix(4)) { gate in
                            CaelCommandCenterRow(
                                title: gate.label,
                                detail: gate.detail,
                                badge: gate.riskLevel.replacingOccurrences(of: "_", with: " "),
                                tint: gate.approvalRequired ? .orange : .green
                            )
                        }
                    }

                    CaelCommandCenterListCard(
                        title: "Recent Receipts",
                        emptyText: "No receipt summaries found.",
                        isEmpty: summary.agentRuns.isEmpty
                    ) {
                        ForEach(summary.agentRuns.prefix(4)) { run in
                            CaelCommandCenterRow(
                                title: run.title,
                                detail: run.status,
                                badge: run.source,
                                tint: .cyan
                            )
                        }
                    }

                    CaelCommandCenterListCard(
                        title: "Models + Brain",
                        emptyText: "No model or brain snapshot reported."
                    ) {
                        let providers = summary.usage?.providers.filter { $0.monitorKind == "cael" || $0.caelDefault } ?? []
                        CaelCommandCenterRow(
                            title: "Cael model monitors",
                            detail: providers.map { $0.caelModel ?? $0.label }.joined(separator: ", ").nilIfEmpty ?? "No active model monitors reported.",
                            badge: "\(providers.count)",
                            tint: .blue
                        )
                        let brainCount = summary.brain?.sources.filter { $0.status == "available" }.count ?? 0
                        CaelCommandCenterRow(
                            title: "Available brain sources",
                            detail: "Reference-only sources; secrets stay filtered.",
                            badge: "\(brainCount)",
                            tint: .mint
                        )
                    }
                }
            }
        }
    }

    private func tint(for tone: String) -> Color {
        switch tone {
        case "success": .green
        case "warning": .orange
        case "danger": .red
        default: .blue
        }
    }

    private var nativeFeatureMap: some View {
        HermesSurfacePanel(
            title: "Native Feature Map",
            subtitle: "These web workspace lanes are being promoted into the desktop shell instead of duplicated inside an embedded browser."
        ) {
            LazyVGrid(columns: adaptiveColumns(minWidth: 240), spacing: 12) {
                CaelNativeFeatureCard(title: "Chat", detail: "Native Cael Sessions composer and resume flow.", section: .sessions)
                CaelNativeFeatureCard(title: "Terminal", detail: "Native remote terminal tabs over SSH.", section: .terminal)
                CaelNativeFeatureCard(title: "Artifacts", detail: "Native file browser and editor.", section: .files)
                CaelNativeFeatureCard(title: "Watchdogs", detail: "Native scheduled job manager.", section: .cronjobs)
                CaelNativeFeatureCard(title: "Tasks", detail: "Native Kanban task board.", section: .kanban)
                CaelNativeFeatureCard(title: "Skills", detail: "Native skills browser and installer.", section: .skills)
            }
        }
    }

    private func adaptiveColumns(minWidth: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minWidth), spacing: 12, alignment: .top)]
    }
}



private struct CaelCommandCenterListCard<Content: View>: View {
    let title: String
    let emptyText: String
    var isEmpty = false
    let content: () -> Content

    init(
        title: String,
        emptyText: String,
        isEmpty: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.emptyText = emptyText
        self.isEmpty = isEmpty
        self.content = content
    }

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                if isEmpty {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    content()
                }
            }
        }
    }
}

private struct CaelCommandCenterRow: View {
    let title: String
    let detail: String
    var badge: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let badge {
                    CaelStatusBadge(label: badge.capitalized, tint: tint)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct CaelHomebaseMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HermesSurfacePanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct CaelSystemCard: View {
    let service: CaelWorkspaceServiceCheck

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.label)
                            .font(.headline)
                        Text(service.target)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                    CaelStatusBadge(label: service.ok ? "Online" : "Attention", tint: service.ok ? .green : .orange)
                }

                Text(service.detail + latencySuffix)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var latencySuffix: String {
        guard let latencyMs = service.latencyMs else { return "" }
        return " · \(Int(latencyMs))ms"
    }
}

private struct CaelIntegrationCard: View {
    let integration: CaelIntegrationCheck

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(integration.label)
                        .font(.headline)
                    Spacer()
                    CaelStatusBadge(label: badgeLabel, tint: badgeTint)
                }

                Text(integration.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(integration.safeMode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var badgeLabel: String {
        switch integration.status {
        case "ready": "Ready"
        case "warning": "Legacy"
        case "setup-needed": "Setup needed"
        default: "Unknown"
        }
    }

    private var badgeTint: Color {
        switch integration.status {
        case "ready": .green
        case "warning": .yellow
        case "setup-needed": .orange
        default: .secondary
        }
    }
}

private struct CaelNativeFeatureCard: View {
    @EnvironmentObject private var appState: AppState

    let title: String
    let detail: String
    let section: AppSection

    var body: some View {
        Button {
            appState.requestSectionSelection(section)
        } label: {
            HermesInsetSurface {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: section.systemImage)
                        .font(.title3)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CaelStatusBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}
