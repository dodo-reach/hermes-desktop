import SwiftUI

struct CaelWorkspaceWebView: View {
    @EnvironmentObject private var appState: AppState

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

    private var workspaceURL: URL {
        appState.activeConnection?.caelWorkspaceURL(path: "/cael-home") ?? ConnectionProfile().caelWorkspaceURL(path: "/cael-home")
    }

    @ViewBuilder
    private var content: some View {
        if appState.isLoadingCaelWorkspace,
           appState.caelWorkspaceStatus == nil,
           appState.caelIntegrationStatus == nil,
           appState.caelCommandCenterSummary == nil,
           appState.caelCommandCenterSections == nil {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading Cael workspace…", minHeight: 320)
            }
        } else if let error = appState.caelWorkspaceError,
                  appState.caelWorkspaceStatus == nil,
                  appState.caelCommandCenterSummary == nil,
                  appState.caelCommandCenterSections == nil {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load Cael workspace",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else {
            if let cacheNotice = appState.caelCommandCenterCacheNotice {
                HermesInsetSurface {
                    CaelCommandCenterRow(
                        title: "Last-known snapshot",
                        detail: cacheNotice,
                        badge: "Cached",
                        tint: .orange
                    )
                }
            }

            if let summary = appState.caelCommandCenterSummary {
                commandCenterSnapshot(summary, warnings: appState.caelCommandCenterWarnings)
            }

            if let sections = appState.caelCommandCenterSections {
                commandCenterSectionsSnapshot(sections)
            }

            if let status = appState.caelWorkspaceStatus {
                statusOverview(status)
                privateAccessMeshPanel(status)
                fastLanesPanel(status)
                contextBoundariesPanel(status)
            }

            n8nGovernancePanel(appState.caelN8nGovernance, error: appState.caelN8nGovernanceError)

            if let integrations = appState.caelIntegrationStatus {
                integrationsPanel(integrations)
            }

            nativeFeatureMap(appState.caelWorkspaceStatus?.links ?? [])
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

    private func privateAccessMeshPanel(_ status: CaelWorkspaceStatus) -> some View {
        HermesSurfacePanel(
            title: "Private Access Mesh",
            subtitle: "Same readiness surface as the web command center: Tailscale personal mesh, local APIs, and the Twingate business lane stay separate."
        ) {
            LazyVGrid(columns: adaptiveColumns(minWidth: 280), spacing: 12) {
                ForEach(status.services) { service in
                    CaelAccessMeshCard(service: service)
                }
            }
        }
    }

    private func fastLanesPanel(_ status: CaelWorkspaceStatus) -> some View {
        HermesSurfacePanel(
            title: "Fast Lanes",
            subtitle: "Web workspace routes mapped to native Desktop sections when the section already exists."
        ) {
            LazyVGrid(columns: adaptiveColumns(minWidth: 230), spacing: 12) {
                ForEach(status.links) { link in
                    CaelFastLaneCard(
                        link: link,
                        section: nativeSection(for: link.href),
                        url: workspaceURL(path: link.href)
                    )
                }
            }
        }
    }

    private func contextBoundariesPanel(_ status: CaelWorkspaceStatus) -> some View {
        HermesSurfacePanel(
            title: "Context Ownership and Boundaries",
            subtitle: "Rendered from /api/cael-status contextSurfaces so Desktop and Web carry the same operating boundaries."
        ) {
            let surfaces = status.contextSurfaces ?? []
            if surfaces.isEmpty {
                Text("No context boundary records were returned by the workspace API.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: adaptiveColumns(minWidth: 280), spacing: 12) {
                    ForEach(surfaces) { surface in
                        CaelContextBoundaryCard(surface: surface)
                    }
                }
            }
        }
    }

    private func n8nGovernancePanel(_ governance: CaelN8nGovernanceStatus?, error: String?) -> some View {
        HermesSurfacePanel(
            title: "n8n Governance",
            subtitle: "Health, failures, receipts, and safe actions for the personal BigMac n8n and business dev-server n8n estates."
        ) {
            if let governance {
                VStack(alignment: .leading, spacing: 16) {
                    Text(governance.boundary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(columns: adaptiveColumns(minWidth: 320), spacing: 12) {
                        ForEach(governance.instances) { instance in
                            CaelN8nInstanceCard(instance: instance)
                        }
                    }

                    LazyVGrid(columns: adaptiveColumns(minWidth: 300), spacing: 12) {
                        CaelCommandCenterListCard(
                            title: "Promotion Receipts",
                            emptyText: "No local receipt artifacts found.",
                            isEmpty: governance.promotionReceipts.isEmpty
                        ) {
                            ForEach(governance.promotionReceipts.prefix(5)) { receipt in
                                CaelCommandCenterRow(
                                    title: receipt.title,
                                    detail: receipt.path,
                                    badge: receipt.instance,
                                    tint: .cyan
                                )
                            }
                        }

                        CaelCommandCenterListCard(
                            title: "Safe Workflow Actions",
                            emptyText: "No workflow commands are registered.",
                            isEmpty: governance.safeWorkflowCommands.isEmpty
                        ) {
                            ForEach(governance.safeWorkflowCommands.prefix(5)) { command in
                                CaelCommandCenterRow(
                                    title: command.label,
                                    detail: command.description,
                                    badge: command.approvalRequired ? "Approval gated" : command.riskLevel,
                                    tint: command.approvalRequired ? .orange : .green
                                )
                            }
                        }
                    }

                    HermesInsetSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Guardrails")
                                .font(.headline)
                            ForEach(governance.guardrails, id: \.self) { guardrail in
                                Text("• \(guardrail)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else if let error {
                ContentUnavailableView(
                    "n8n governance unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                HermesLoadingState(label: "Loading n8n governance…", minHeight: 180)
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

    private func commandCenterSectionsSnapshot(_ snapshot: CaelCommandCenterSectionsSnapshot) -> some View {
        HermesSurfacePanel(
            title: "Command Center Sections",
            subtitle: "Dedicated /api/command-center/* section endpoints for Desktop, Web, and mobile mirrors. Secrets are represented as refs only."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if snapshot.warningCount > 0 {
                    HermesInsetSurface {
                        CaelCommandCenterRow(
                            title: "Section warnings",
                            detail: "\(snapshot.warningCount) degraded or setup-needed conditions are present across the section endpoints.",
                            badge: "Review",
                            tint: .orange
                        )
                    }
                }

                LazyVGrid(columns: adaptiveColumns(minWidth: 260), spacing: 12) {
                    CaelCommandCenterListCard(
                        title: "Action Gates",
                        emptyText: "No approval gates surfaced.",
                        isEmpty: snapshot.actionGates?.data?.actions.isEmpty ?? true
                    ) {
                        if let data = snapshot.actionGates?.data {
                            CaelCommandCenterRow(
                                title: "Approval required",
                                detail: "\(data.dryRun) actions support dry-run before promotion.",
                                badge: "\(data.approvalRequired)",
                                tint: data.approvalRequired > 0 ? .orange : .green
                            )
                            ForEach(data.actions.prefix(3)) { gate in
                                CaelCommandCenterRow(
                                    title: gate.label,
                                    detail: gate.sideEffects.nilIfEmpty ?? gate.detail,
                                    badge: gate.riskLevel.replacingOccurrences(of: "_", with: " "),
                                    tint: gate.approvalRequired ? .orange : .green
                                )
                            }
                        }
                    }

                    CaelCommandCenterListCard(
                        title: "Runs + Receipts",
                        emptyText: "No run or receipt details reported.",
                        isEmpty: snapshot.agentRuns?.data?.runs.isEmpty ?? true
                    ) {
                        if let data = snapshot.agentRuns?.data {
                            CaelCommandCenterRow(
                                title: "Receipt refs",
                                detail: "Run history is sourced from durable receipt references.",
                                badge: "\(data.receipts.count)",
                                tint: .cyan
                            )
                            ForEach(data.runs.prefix(3)) { run in
                                CaelCommandCenterRow(
                                    title: run.title,
                                    detail: run.verification,
                                    badge: run.status,
                                    tint: .cyan
                                )
                            }
                        }
                    }

                    CaelCommandCenterListCard(
                        title: "Brain + Memory",
                        emptyText: "No brain or memory artifacts reported.",
                        isEmpty: snapshot.brain?.data?.sources.isEmpty ?? true
                    ) {
                        if let brain = snapshot.brain?.data {
                            CaelCommandCenterRow(
                                title: "Brain sources",
                                detail: "\(brain.memoryArtifacts.count) memory artifact references are visible to the command center.",
                                badge: "\(brain.sources.count)",
                                tint: .mint
                            )
                        }
                        ForEach((snapshot.memoryArtifacts?.data?.artifacts ?? []).prefix(3)) { artifact in
                            CaelCommandCenterRow(
                                title: artifact.title,
                                detail: artifact.excerpt.nilIfEmpty ?? artifact.scope,
                                badge: artifact.sensitivity,
                                tint: artifact.sensitivity == "secret_ref" ? .orange : .mint
                            )
                        }
                    }

                    CaelCommandCenterListCard(
                        title: "Automations",
                        emptyText: "No automation lanes reported.",
                        isEmpty: snapshot.automations?.data?.instances.isEmpty ?? true
                    ) {
                        if let automations = snapshot.automations?.data {
                            ForEach(automations.instances) { instance in
                                CaelCommandCenterRow(
                                    title: instance.label,
                                    detail: instance.health.detail,
                                    badge: "\(instance.failures.count) failures",
                                    tint: instance.health.ok ? .green : .orange
                                )
                            }
                        }
                    }

                    CaelCommandCenterListCard(
                        title: "Vault + Models",
                        emptyText: "No vault refs or model monitors reported."
                    ) {
                        let vaultRefs = snapshot.vaultRefs?.data?.refs ?? []
                        let providers = snapshot.usageLimits?.data?.providers.filter { $0.monitorKind == "cael" || $0.caelDefault } ?? []
                        CaelCommandCenterRow(
                            title: "Vault refs",
                            detail: "Reference-only pointers; secret values are not returned to the client.",
                            badge: "\(vaultRefs.count)",
                            tint: .orange
                        )
                        CaelCommandCenterRow(
                            title: "Cael model monitors",
                            detail: providers.map { $0.caelModel ?? $0.label }.joined(separator: ", ").nilIfEmpty ?? "No active model monitors reported.",
                            badge: "\(providers.count)",
                            tint: .blue
                        )
                    }

                    CaelCommandCenterListCard(
                        title: "Homebase",
                        emptyText: "Homebase records are unavailable or degraded.",
                        isEmpty: snapshot.homebaseRecords?.data?.records.isEmpty ?? true
                    ) {
                        if let homebase = snapshot.homebaseRecords?.data {
                            CaelCommandCenterRow(
                                title: homebase.status,
                                detail: homebase.detail,
                                badge: "\(homebase.records.count)",
                                tint: homebase.status == "available" ? .green : .orange
                            )
                            ForEach(homebase.records.prefix(3)) { record in
                                CaelCommandCenterRow(
                                    title: record.label,
                                    detail: record.updatedAt ?? "No update timestamp",
                                    badge: record.kind,
                                    tint: .secondary
                                )
                            }
                        }
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

    private func nativeFeatureMap(_ links: [CaelWorkspaceLink]) -> some View {
        HermesSurfacePanel(
            title: "Native Feature Map",
            subtitle: "Feature lanes from the web app are mapped to Desktop sections; unsupported lanes remain visible through the Fast Lanes fallback."
        ) {
            LazyVGrid(columns: adaptiveColumns(minWidth: 240), spacing: 12) {
                ForEach(links.filter { nativeSection(for: $0.href) != nil }) { link in
                    if let section = nativeSection(for: link.href) {
                        CaelNativeFeatureCard(title: link.label, detail: link.description, section: section)
                    }
                }
            }
        }
    }

    private func workspaceURL(path: String) -> URL {
        appState.activeConnection?.caelWorkspaceURL(path: path) ?? ConnectionProfile().caelWorkspaceURL(path: path)
    }

    private func nativeSection(for href: String) -> AppSection? {
        switch href {
        case "/cael-home", "/dashboard": .overview
        case "/desktop": .overview
        case "/usage": .usage
        case "/mail": .mail
        case "/contacts": .contacts
        case "/calendar": .calendar
        case "/integrations": .integrations
        case "/chat": .sessions
        case "/conductor": .missionControl
        case "/operations": .operations
        case "/memory": .memory
        case "/terminal": .terminal
        case "/tasks": .kanban
        case "/artifacts": .files
        case "/watchdogs": .cronjobs
        case "/skills": .skills
        case "/mcp": .mcp
        case "/profiles": .profiles
        default: nil
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


private struct CaelAccessMeshCard: View {
    let service: CaelWorkspaceServiceCheck

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.label)
                            .font(.headline)
                        Text([service.lane, service.owner].compactMap { $0?.nilIfEmpty }.joined(separator: " / "))
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    CaelStatusBadge(label: service.ok ? "Online" : "Needs attention", tint: service.ok ? .green : .orange)
                }

                Text(service.description?.nilIfEmpty ?? service.target)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.4)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Target")
                            .foregroundStyle(.secondary)
                        Text(service.target)
                    }
                    GridRow {
                        Text("Health")
                            .foregroundStyle(.secondary)
                        Text(service.detail + latencySuffix)
                    }
                }
                .font(.caption)
            }
        }
    }

    private var latencySuffix: String {
        guard let latencyMs = service.latencyMs else { return "" }
        return " - \(Int(latencyMs))ms"
    }
}

private struct CaelFastLaneCard: View {
    @EnvironmentObject private var appState: AppState

    let link: CaelWorkspaceLink
    let section: AppSection?
    let url: URL

    var body: some View {
        if let section {
            Button {
                appState.requestSectionSelection(section)
            } label: {
                cardContent(systemImage: section.systemImage, trailingImage: "chevron.right")
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: url) {
                cardContent(systemImage: "safari", trailingImage: "arrow.up.right")
            }
            .buttonStyle(.plain)
        }
    }

    private func cardContent(systemImage: String, trailingImage: String) -> some View {
        HermesInsetSurface {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text(link.label)
                        .font(.headline)
                    Text(link.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: trailingImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct CaelContextBoundaryCard: View {
    let surface: CaelWorkspaceContextSurface

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(surface.surface)
                            .font(.headline)
                        Text(surface.owner)
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(surface.context)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 8) {
                    labeledText("Access", surface.access)
                    labeledText("Boundary", surface.boundary)
                }
            }
        }
    }

    private func labeledText(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CaelN8nInstanceCard: View {
    let instance: CaelCommandCenterAutomationInstance

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(instance.label)
                            .font(.headline)
                        Text(instance.scope)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    CaelStatusBadge(label: instance.health.ok ? "Online" : "Needs attention", tint: instance.health.ok ? .green : .orange)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    CaelMiniFact(title: "Access", value: instance.access)
                    CaelMiniFact(title: "Boundary", value: instance.boundary)
                    CaelMiniFact(title: "Health", value: instance.health.detail + healthLatency)
                    CaelMiniFact(title: "Checked", value: instance.health.checkedAt)
                }

                if instance.failures.isEmpty {
                    Text("No recent failure families reported by the read-only query.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent failure families")
                            .font(.subheadline.weight(.semibold))
                        ForEach(instance.failures.prefix(4)) { failure in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(failure.workflowName)
                                        .font(.caption.weight(.semibold))
                                    Text("Last seen \(failure.lastSeen)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                CaelStatusBadge(label: "\(failure.status) - \(failure.count)", tint: .orange)
                            }
                            .padding(10)
                            .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var healthLatency: String {
        guard let latency = instance.health.latencyMs else { return "" }
        return " - \(Int(latency))ms"
    }
}

private struct CaelMiniFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
