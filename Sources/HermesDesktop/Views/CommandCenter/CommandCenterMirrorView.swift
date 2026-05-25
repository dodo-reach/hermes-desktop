import SwiftUI

struct CommandCenterMirrorView: View {
    @EnvironmentObject private var appState: AppState

    let section: AppSection

    var body: some View {
        HermesPageContainer(width: .analytics) {
            VStack(alignment: .leading, spacing: 24) {
                HermesPageHeader(
                    title: section.title,
                    subtitle: subtitle,
                    accessory: {
                        HermesRefreshButton(isRefreshing: appState.isRefreshingCaelWorkspace) {
                            Task { await appState.refreshCaelWorkspace() }
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

    private var subtitle: String {
        switch section {
        case .mail:
            return "Native command-center view for Google Workspace mail readiness, drafts, and approval gates."
        case .contacts:
            return "Native command-center view for people records, Google contacts readiness, and migration-safe homebase refs."
        case .calendar:
            return "Native command-center view for calendar readiness, agenda drafting policy, and approval gates."
        case .missionControl:
            return "Native command-center view for active runs, receipts, and gated promotions."
        case .operations:
            return "Native command-center view for automation health, n8n lanes, and runtime posture."
        case .swarm:
            return "Native command-center view for agent runs and team execution receipts."
        case .memory:
            return "Native command-center view for brain sources and durable memory artifacts."
        case .integrations:
            return "Native command-center view for provider readiness and Vault reference posture."
        case .mcp:
            return "Native command-center view for MCP/brain source availability and safe client boundaries."
        case .profiles:
            return "Native command-center view for the active default profile and available Hermes agent identities."
        default:
            return "Native Command Center mirror section."
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.isLoadingCaelWorkspace,
           appState.caelCommandCenterSummary == nil,
           appState.caelCommandCenterSections == nil {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading command center section...", minHeight: 320)
            }
        } else if let error = appState.caelWorkspaceError,
                  appState.caelCommandCenterSummary == nil,
                  appState.caelCommandCenterSections == nil {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load command center",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else {
            if let cacheNotice = appState.caelCommandCenterCacheNotice {
                HermesInsetSurface {
                    MirrorRow(title: "Last-known snapshot", detail: cacheNotice, badge: "Cached", tint: .orange)
                }
            }

            switch section {
            case .mail, .contacts, .calendar:
                workspaceDataSection
            case .missionControl, .swarm:
                runsAndGatesSection
            case .operations:
                operationsSection
            case .memory:
                memorySection
            case .integrations:
                integrationsSection
            case .mcp:
                mcpSection
            case .profiles:
                profilesSection
            default:
                ContentUnavailableView("Unsupported section", systemImage: "rectangle.slash")
            }
        }
    }

    private var workspaceDataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HermesSurfacePanel(title: "Provider Readiness", subtitle: "Mail, contacts, and calendars use the shared integrations contract before any mutation is allowed.") {
                LazyVGrid(columns: adaptiveColumns, spacing: 12) {
                    ForEach(relevantIntegrations) { integration in
                        MirrorListCard(title: integration.label, emptyText: "No integration detail reported.") {
                            MirrorRow(
                                title: integration.status.replacingOccurrences(of: "-", with: " "),
                                detail: integration.detail,
                                badge: integration.status,
                                tint: tint(forStatus: integration.status)
                            )
                            MirrorRow(title: "Safe mode", detail: integration.safeMode, tint: .secondary)
                        }
                    }
                }
            }

            if section == .contacts {
                homebaseRecordsPanel
            }

            actionGatesPanel
        }
    }

    private var runsAndGatesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            agentRunsPanel
            actionGatesPanel
        }
    }

    private var operationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HermesSurfacePanel(title: "Automation Lanes", subtitle: appState.caelCommandCenterSections?.automations?.data?.boundary ?? "Business and personal automation lanes remain separated.") {
                let instances = appState.caelCommandCenterSections?.automations?.data?.instances ?? []
                MirrorGridOrEmpty(items: instances, emptyText: "No automation lanes reported.") { instance in
                    MirrorListCard(title: instance.label, emptyText: "No automation detail reported.") {
                        MirrorRow(title: instance.health.ok ? "Online" : "Needs attention", detail: instance.health.detail, badge: instance.scope, tint: instance.health.ok ? .green : .orange)
                        MirrorRow(title: "Boundary", detail: instance.boundary, tint: .blue)
                        MirrorRow(title: "Recent failures", detail: "\(instance.failures.count) failure families", badge: "\(instance.failures.count)", tint: instance.failures.isEmpty ? .green : .orange)
                    }
                }
            }

            systemsPanel
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NativeKnowledgeFabricPanel()
            brainSourcesPanel
            memoryArtifactsPanel
        }
    }

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HermesSurfacePanel(title: "Integrations", subtitle: "Provider readiness is rendered from the same shared contract as the web app.") {
                MirrorGridOrEmpty(items: appState.caelCommandCenterSummary?.integrations ?? [], emptyText: "No integrations reported.") { integration in
                    MirrorListCard(title: integration.label, emptyText: "No integration detail reported.") {
                        MirrorRow(title: integration.status.replacingOccurrences(of: "-", with: " "), detail: integration.detail, badge: integration.status, tint: tint(forStatus: integration.status))
                        MirrorRow(title: "Safe mode", detail: integration.safeMode, tint: .secondary)
                    }
                }
            }
            vaultRefsPanel
        }
    }

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            brainSourcesPanel
            vaultRefsPanel
        }
    }

    private var profilesSection: some View {
        HermesSurfacePanel(title: "Agent Profiles", subtitle: "The base profile remains default; the agent display name is what changes per identity.") {
            let profiles = availableProfiles
            MirrorGridOrEmpty(items: profiles, emptyText: "No profiles reported by the active host.") { profile in
                MirrorListCard(title: profile.displayTitle, emptyText: "No profile detail reported.") {
                    MirrorRow(title: profile.isDefault ? "Default base profile" : "Agent profile", detail: profile.path, badge: profile.exists ? "Available" : "Missing", tint: profile.exists ? .green : .orange)
                    MirrorRow(title: "Profile name", detail: profile.name, tint: .blue)
                }
            }
        }
    }

    private var actionGatesPanel: some View {
        HermesSurfacePanel(title: "Action Gates", subtitle: "Mutating actions stay approval-gated and dry-run capable where supported.") {
            let gates = appState.caelCommandCenterSections?.actionGates?.data?.actions ?? []
            MirrorGridOrEmpty(items: gates, emptyText: "No approval gates surfaced.") { gate in
                MirrorListCard(title: gate.label, emptyText: "No gate detail reported.") {
                    MirrorRow(title: gate.status, detail: gate.detail, badge: gate.riskLevel.replacingOccurrences(of: "_", with: " "), tint: gate.approvalRequired ? .orange : .green)
                    MirrorRow(title: "Owner", detail: gate.ownerSystem, tint: .blue)
                    MirrorRow(title: "Rollback", detail: gate.rollback, tint: .secondary)
                }
            }
        }
    }

    private var agentRunsPanel: some View {
        HermesSurfacePanel(title: "Runs + Receipts", subtitle: "Runs and promotion receipts come from durable command-center references.") {
            let runs = appState.caelCommandCenterSections?.agentRuns?.data?.runs ?? []
            MirrorGridOrEmpty(items: runs, emptyText: "No agent runs reported.") { run in
                MirrorListCard(title: run.title, emptyText: "No run detail reported.") {
                    MirrorRow(title: run.status, detail: run.verification, badge: run.source, tint: tint(forStatus: run.status))
                    MirrorRow(title: "Updated", detail: run.updatedAt, tint: .secondary)
                    if let path = run.path {
                        MirrorRow(title: "Receipt path", detail: path, tint: .cyan)
                    }
                }
            }
        }
    }

    private var brainSourcesPanel: some View {
        HermesSurfacePanel(title: "Brain Sources", subtitle: "Sources are shown as references; secret stores are never exposed in the client.") {
            let sources = appState.caelCommandCenterSections?.brain?.data?.sources ?? appState.caelCommandCenterSummary?.brain?.sources ?? []
            MirrorGridOrEmpty(items: sources, emptyText: "No brain sources reported.") { source in
                MirrorListCard(title: source.label, emptyText: "No source detail reported.") {
                    MirrorRow(title: source.status, detail: source.category, badge: source.writable ? "Writable" : "Read only", tint: source.status == "available" ? .green : .orange)
                }
            }
        }
    }

    private var memoryArtifactsPanel: some View {
        HermesSurfacePanel(title: "Memory Artifacts", subtitle: "Durable handoffs and receipts are surfaced by path and excerpt only.") {
            let artifacts = appState.caelCommandCenterSections?.memoryArtifacts?.data?.artifacts ?? []
            MirrorGridOrEmpty(items: artifacts, emptyText: "No memory artifacts surfaced.") { artifact in
                MirrorListCard(title: artifact.title, emptyText: "No artifact detail reported.") {
                    MirrorRow(title: artifact.scope, detail: artifact.excerpt.isEmpty ? artifact.path : artifact.excerpt, badge: artifact.sensitivity, tint: artifact.sensitivity == "secret_ref" ? .orange : .mint)
                    MirrorRow(title: "Path", detail: artifact.path, tint: .secondary)
                }
            }
        }
    }

    private var vaultRefsPanel: some View {
        HermesSurfacePanel(title: "Vault References", subtitle: "Reference-only credential posture. Secret values are filtered before reaching the desktop client.") {
            let refs = appState.caelCommandCenterSections?.vaultRefs?.data?.refs ?? []
            MirrorGridOrEmpty(items: refs, emptyText: "No vault refs surfaced.") { ref in
                MirrorListCard(title: ref.displayName, emptyText: "No vault detail reported.") {
                    MirrorRow(title: ref.exists ? "Configured" : "Missing", detail: ref.scope, badge: ref.exists ? "Ref" : "Setup", tint: ref.exists ? .green : .orange)
                    MirrorRow(title: "Linked systems", detail: ref.linkedSystems.joined(separator: ", ").nilIfBlank ?? "No linked systems reported.", tint: .blue)
                }
            }
        }
    }

    private var homebaseRecordsPanel: some View {
        HermesSurfacePanel(title: "Homebase Records", subtitle: "Legacy Twenty and migrated records remain read-first until explicit approval gates exist.") {
            let records = appState.caelCommandCenterSections?.homebaseRecords?.data?.records ?? []
            MirrorGridOrEmpty(items: records, emptyText: "No homebase records reported.") { record in
                MirrorListCard(title: record.label, emptyText: "No record detail reported.") {
                    MirrorRow(title: record.kind, detail: record.updatedAt ?? "No update timestamp", tint: .secondary)
                }
            }
        }
    }

    private var systemsPanel: some View {
        HermesSurfacePanel(title: "Runtime Systems", subtitle: "Shared command-center posture for Desktop and Web.") {
            MirrorGridOrEmpty(items: appState.caelCommandCenterSummary?.systems ?? [], emptyText: "No system checks reported.") { system in
                MirrorListCard(title: system.label, emptyText: "No system detail reported.") {
                    MirrorRow(title: system.ok ? "Online" : "Needs attention", detail: system.detail, badge: system.lane, tint: system.ok ? .green : .orange)
                    MirrorRow(title: "Owner", detail: system.owner, tint: .blue)
                }
            }
        }
    }

    private var relevantIntegrations: [CaelCommandCenterIntegration] {
        let integrations = appState.caelCommandCenterSummary?.integrations ?? []
        switch section {
        case .mail, .contacts, .calendar:
            return integrations.filter { $0.id.contains("google") || $0.label.localizedCaseInsensitiveContains("google") }
        default:
            return integrations
        }
    }

    private var availableProfiles: [RemoteHermesProfile] {
        if let overview = appState.overview, !overview.availableProfiles.isEmpty {
            return overview.availableProfiles
        }

        guard let connection = appState.activeConnection else { return [] }
        return [
            RemoteHermesProfile(
                name: connection.resolvedHermesProfileName,
                path: connection.remoteHermesHomePath,
                isDefault: connection.usesDefaultHermesProfile,
                exists: true,
                displayName: connection.agentDisplayName
            )
        ]
    }

    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)]
    }

    private func tint(forStatus status: String) -> Color {
        switch status {
        case "ready", "available", "complete", "online", "ok": return .green
        case "active", "running": return .cyan
        case "setup-needed", "warning", "error", "needs_attention": return .orange
        default: return .blue
        }
    }
}

private struct MirrorGridOrEmpty<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let emptyText: String
    let content: (Item) -> Content

    var body: some View {
        if items.isEmpty {
            Text(emptyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(items) { item in
                    content(item)
                }
            }
        }
    }
}

private struct NativeKnowledgeFabricPanel: View {
    @EnvironmentObject private var appState: AppState

    @State private var query = "Hermes Cael parity"
    @State private var scope = "both"
    @State private var mode = "knowledge"
    @State private var agentSource = ""
    @State private var documentID = ""
    @State private var health: KnowledgeFabricHealthResponse?
    @State private var searchResponse: KnowledgeFabricSearchResponse?
    @State private var documentResponse: KnowledgeFabricSearchResponse?
    @State private var errorMessage: String?
    @State private var isLoadingHealth = false
    @State private var isSearching = false
    @State private var isLookingUpDocument = false

    var body: some View {
        HermesSurfacePanel(
            title: "Knowledge Fabric",
            subtitle: "Search the scoped second brain through the shared :3077 Memory Fabric contract."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                headerRow
                searchControls

                if let errorMessage {
                    MirrorRow(title: "Error", detail: errorMessage, badge: "Attention", tint: .orange)
                }

                if let searchResponse {
                    resultSection(title: "Search Results", response: searchResponse)
                }

                documentControls

                if let documentResponse {
                    resultSection(title: "Document Lookup", response: documentResponse)
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await refreshHealth()
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(health?.statusLabel ?? "Checking")
                    .font(.subheadline.weight(.semibold))
                Text(health?.endpoint ?? "https://memory.visualgraphx.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if isLoadingHealth {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Refresh") {
                Task { await refreshHealth() }
            }
            .disabled(isLoadingHealth)
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search Memory Fabric", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await runSearch() }
                }

            HStack(alignment: .center, spacing: 12) {
                Picker("Scope", selection: $scope) {
                    Text("Both").tag("both")
                    Text("Business").tag("business")
                    Text("Personal").tag("personal")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Picker("Mode", selection: $mode) {
                    Text("Knowledge").tag("knowledge")
                    Text("Agent").tag("agent")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                if mode == "agent" {
                    TextField("Agent source", text: $agentSource)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                }

                Button("Search") {
                    Task { await runSearch() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if isSearching {
                ProgressView("Searching Knowledge Fabric...")
                    .controlSize(.small)
            }
        }
    }

    private var documentControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Document lookup")
                .font(.headline)
            HStack(spacing: 12) {
                TextField("doc id or canonical id", text: $documentID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await lookupDocument() }
                    }
                Button("Lookup") {
                    Task { await lookupDocument() }
                }
                .disabled(isLookingUpDocument || documentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if isLookingUpDocument {
                ProgressView("Loading document...")
                    .controlSize(.small)
            }
        }
    }

    private func resultSection(title: String, response: KnowledgeFabricSearchResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            let results = response.scopedResults
            if results.isEmpty {
                Text("No scoped results returned.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(results) { result in
                        resultCard(result)
                    }
                }
            }
        }
    }

    private func resultCard(_ result: KnowledgeFabricScopedResult) -> some View {
        MirrorListCard(title: result.displayScope, emptyText: "No Knowledge Fabric detail reported.") {
            MirrorRow(
                title: result.ok == false ? "Unavailable" : "Result",
                detail: preview(result.summary, maxLength: 600),
                badge: result.ok == false ? "Error" : "Memory",
                tint: result.ok == false ? .orange : .green
            )

            let evidence = result.data?.evidence ?? []
            ForEach(Array(evidence.prefix(4))) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title ?? item.docID ?? "Evidence")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(preview(item.snippet ?? item.canonicalDocID ?? "", maxLength: 260))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let docID = item.docID ?? item.canonicalDocID {
                        Button("Lookup document") {
                            documentID = docID
                            scope = result.scopeKey == "personal" ? "personal" : "business"
                            Task { await lookupDocument() }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func refreshHealth() async {
        guard let connection = appState.activeConnection else { return }
        isLoadingHealth = true
        defer { isLoadingHealth = false }
        do {
            health = try await appState.caelWorkspaceAPIService.loadKnowledgeFabricHealth(connection: connection)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runSearch() async {
        guard let connection = appState.activeConnection else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            searchResponse = try await appState.caelWorkspaceAPIService.searchKnowledgeFabric(
                connection: connection,
                query: query,
                scope: scope,
                mode: mode,
                agentSource: agentSource
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func lookupDocument() async {
        guard let connection = appState.activeConnection else { return }
        isLookingUpDocument = true
        errorMessage = nil
        defer { isLookingUpDocument = false }
        do {
            documentResponse = try await appState.caelWorkspaceAPIService.lookupKnowledgeFabricDocument(
                connection: connection,
                docID: documentID,
                scope: scope
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func preview(_ value: String, maxLength: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= maxLength { return normalized.isEmpty ? "No preview available." : normalized }
        let index = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return String(normalized[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

private struct MirrorListCard<Content: View>: View {
    let title: String
    let emptyText: String
    let content: () -> Content

    init(title: String, emptyText: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.emptyText = emptyText
        self.content = content
    }

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                content()
            }
        }
    }
}

private struct MirrorRow: View {
    let title: String
    let detail: String
    var badge: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.capitalized)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let badge {
                    MirrorBadge(label: badge.capitalized, tint: tint)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

private struct MirrorBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
