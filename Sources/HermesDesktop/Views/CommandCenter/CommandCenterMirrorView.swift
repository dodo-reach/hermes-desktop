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
            case .missionControl:
                runsAndGatesSection
            case .swarm:
                swarmSection
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

    private var swarmSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NativeSwarmPanel()
            NativeConductorPanel()
            agentRunsPanel
            actionGatesPanel
        }
    }

    private var operationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NativeOperationsAgentsPanel()

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
            NativeMemoryKnowledgeFilesPanel()
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
            NativeMCPPanel()
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


private struct NativeOperationsAgentsPanel: View {
    @EnvironmentObject private var appState: AppState

    @State private var profiles: [CaelProfileSummary] = []
    @State private var crew: [WorkspaceCrewMember] = []
    @State private var jobs: [CronJob] = []
    @State private var activeProfileName = "default"
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var isStartingRuntime = false
    @State private var isSavingProfile = false
    @State private var isLoadingEditDetail = false
    @State private var operationProfileName: String?
    @State private var operationJobID: String?
    @State private var operationSessionKey: String?
    @State private var errorMessage: String?
    @State private var runtimeMessage: String?
    @State private var newAgentName = ""
    @State private var newAgentModel = ""
    @State private var editingProfile: CaelProfileSummary?
    @State private var editModel = ""
    @State private var editProvider = ""
    @State private var editDescription = ""
    @State private var editSystemPrompt = ""
    @State private var operationChatDrafts: [String: String] = [:]
    @State private var operationChatMessages: [String: [SessionMessage]] = [:]
    @State private var operationChatNotices: [String: String] = [:]
    @State private var profilePendingDelete: CaelProfileSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HermesSurfacePanel(
                title: "Operations Agents",
                subtitle: "Native controls for the same profile-backed agents used by the web Operations screen."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    controlsRow
                    createRow
                    crewSummaryRow

                    if let errorMessage {
                        MirrorRow(title: "Error", detail: errorMessage, badge: "Attention", tint: .orange)
                    }

                    if let runtimeMessage {
                        MirrorRow(title: "Runtime", detail: runtimeMessage, badge: "Start", tint: .green)
                    }

                    MirrorGridOrEmpty(items: profiles, emptyText: "No profile-backed operations agents reported.") { profile in
                        agentCard(profile)
                    }
                }
            }

            HermesSurfacePanel(title: "Recent Agent Runs", subtitle: "Durable run receipts from the shared command-center ledger.") {
                let runs = Array((appState.caelCommandCenterSections?.agentRuns?.data?.runs ?? []).prefix(4))
                MirrorGridOrEmpty(items: runs, emptyText: "No recent agent runs reported.") { run in
                    MirrorListCard(title: run.title, emptyText: "No run detail reported.") {
                        MirrorRow(title: run.status, detail: run.verification, badge: run.source, tint: tint(forStatus: run.status))
                        MirrorRow(title: "Updated", detail: run.updatedAt, tint: .secondary)
                    }
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await loadAll()
        }
        .alert(
            "Delete operations agent?",
            isPresented: Binding(
                get: { profilePendingDelete != nil },
                set: { if !$0 { profilePendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                profilePendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                guard let profile = profilePendingDelete else { return }
                profilePendingDelete = nil
                Task { await deleteProfile(profile) }
            }
        } message: {
            Text("This removes the server-side Hermes profile for this operations agent.")
        }
        .sheet(item: $editingProfile) { profile in
            editSheet(profile)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await loadAll() }
            } label: {
                Label("Refresh Agents", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading || appState.activeConnection == nil)

            Button {
                Task { await startRuntime() }
            } label: {
                Label(isStartingRuntime ? "Starting Runtime" : "Start Runtime", systemImage: "play.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isStartingRuntime || appState.activeConnection == nil)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 10)

            Text("Active: \(activeProfileName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var createRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create profile-backed agent")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                TextField("agent-name", text: $newAgentName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                TextField("model", text: $newAgentModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Button {
                    Task { await createAgent() }
                } label: {
                    Label(isCreating ? "Creating" : "Create", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(isCreating || appState.activeConnection == nil || !isValidProfileName(newAgentName))
            }
        }
    }

    private var crewSummaryRow: some View {
        HStack(spacing: 10) {
            OperationMiniStat(label: "profiles", value: "\(profiles.count)")
            OperationMiniStat(label: "crew", value: "\(crew.count)")
            OperationMiniStat(label: "running", value: "\(crew.filter(\.processAlive).count)")
            OperationMiniStat(label: "sessions", value: "\(crew.reduce(0) { $0 + $1.sessionCount })")
            OperationMiniStat(label: "jobs", value: "\(crew.reduce(0) { $0 + $1.cronJobCount })")
            OperationMiniStat(label: "ops jobs", value: "\(jobs.filter { $0.name.hasPrefix("ops:") }.count)")
        }
    }

    private func agentCard(_ profile: CaelProfileSummary) -> some View {
        let crewMember = crewMember(for: profile)
        return MirrorListCard(title: profile.resolvedDisplayName, emptyText: "No operations agent detail reported.") {
            MirrorRow(
                title: profile.active ? "Active profile" : "Profile agent",
                detail: profile.description?.nilIfBlank ?? profile.path,
                badge: profile.active ? "Active" : (profile.exists ? "Ready" : "Missing"),
                tint: profile.active ? .green : (profile.exists ? .blue : .orange)
            )
            MirrorRow(title: "Model", detail: profile.model?.nilIfBlank ?? crewMember?.model.nilIfBlank ?? "Not configured", badge: profile.provider?.nilIfBlank ?? crewMember?.provider.nilIfBlank, tint: (profile.model?.nilIfBlank ?? crewMember?.model.nilIfBlank) == nil ? .orange : .cyan)
            if let crewMember {
                MirrorRow(
                    title: "Gateway",
                    detail: crewMember.processAlive ? "Process alive; \(crewMember.gatewayState)." : "No live process reported; \(crewMember.gatewayState).",
                    badge: crewMember.profileFound ? "Profile" : "Missing",
                    tint: crewMember.processAlive ? .green : .orange
                )
                MirrorRow(
                    title: "Workload",
                    detail: "\(crewMember.sessionCount) sessions, \(crewMember.messageCount) messages, \(crewMember.toolCallCount) tool calls, \(crewMember.cronJobCount) jobs, \(crewMember.assignedTaskCount) tasks.",
                    tint: .secondary
                )
                if let lastSessionAt = crewMember.lastSessionAt {
                    MirrorRow(title: "Last session", detail: formatTimestamp(lastSessionAt), tint: .secondary)
                }
            }
            HStack(spacing: 10) {
                OperationMiniStat(label: "skills", value: "\(profile.skillCount)")
                OperationMiniStat(label: "sessions", value: "\(profile.sessionCount)")
                if profile.hasEnv {
                    OperationMiniStat(label: "env", value: "yes")
                }
            }
            actionButtons(profile)
            operationJobsPanel(profile)
            operationChatPanel(profile)
        }
    }

    private func actionButtons(_ profile: CaelProfileSummary) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await beginEdit(profile) }
            } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .disabled(operationProfileName != nil)

            Button {
                Task { await activateProfile(profile) }
            } label: {
                Label("Activate", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(profile.active || operationProfileName != nil)

            Button(role: .destructive) {
                profilePendingDelete = profile
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(profile.name == "default" || operationProfileName != nil)
        }
        .controlSize(.small)
    }


    private func operationJobsPanel(_ profile: CaelProfileSummary) -> some View {
        let profileJobs = operationJobs(for: profile)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Operations jobs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") {
                    Task { await loadOperationJobs() }
                }
                .buttonStyle(.plain)
                .font(.caption)
            }

            if profileJobs.isEmpty {
                Text("No `ops:\(profile.name):` jobs reported by /api/claude-jobs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(profileJobs.prefix(4)) { job in
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(operationJobTitle(job, profile: profile))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(job.resolvedScheduleDisplay)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Button {
                                Task { await toggleOperationJob(job) }
                            } label: {
                                Image(systemName: job.isPaused || !job.enabled ? "play.circle" : "pause.circle")
                            }
                            .help(job.isPaused || !job.enabled ? "Resume job" : "Pause job")
                            .disabled(operationJobID == job.id)

                            Button {
                                Task { await runOperationJob(job) }
                            } label: {
                                Image(systemName: "bolt.circle")
                            }
                            .help("Run job now")
                            .disabled(operationJobID == job.id)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private func operationChatPanel(_ profile: CaelProfileSummary) -> some View {
        let sessionKey = operationSessionKey(for: profile)
        let messages = Array((operationChatMessages[profile.name] ?? []).suffix(4))
        let draft = Binding(
            get: { operationChatDrafts[profile.name] ?? "" },
            set: { operationChatDrafts[profile.name] = $0 }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Operations chat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(sessionKey)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Refresh") {
                    Task { await loadOperationChat(profile) }
                }
                .buttonStyle(.plain)
                .font(.caption)
            }

            if messages.isEmpty {
                Text("No recent messages in the shared agent session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.role.displayTitle)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(message.role == .user ? Color.accentColor : Color.secondary)
                            Text(message.content?.nilIfBlank ?? "No message content.")
                                .font(.caption)
                                .lineLimit(3)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            if let notice = operationChatNotices[profile.name]?.nilIfBlank {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Message \(profile.resolvedDisplayName)", text: draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await sendOperationChat(profile) }
                    }
                Button {
                    Task { await sendOperationChat(profile) }
                } label: {
                    Label(operationSessionKey == sessionKey ? "Sending" : "Send", systemImage: "paperplane")
                }
                .buttonStyle(.borderedProminent)
                .disabled(operationSessionKey == sessionKey || draft.wrappedValue.nilIfBlank == nil)
            }
        }
        .task(id: profile.name) {
            await loadOperationChat(profile)
        }
    }

    private func editSheet(_ profile: CaelProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Operations Agent")
                        .font(.title3.weight(.semibold))
                    Text(profile.name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoadingEditDetail || isSavingProfile {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextField("Model", text: $editModel)
                .textFieldStyle(.roundedBorder)
            TextField("Provider", text: $editProvider)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: $editDescription)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text("System prompt")
                    .font(.subheadline.weight(.semibold))
                TextEditor(text: $editSystemPrompt)
                    .font(.body)
                    .frame(minHeight: 180)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    editingProfile = nil
                }
                Button(isSavingProfile ? "Saving" : "Save") {
                    Task { await saveProfileEdits() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingProfile || appState.activeConnection == nil)
            }
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 520)
    }

    private func loadAll() async {
        await loadProfiles()
        await loadCrewStatus()
        await loadOperationJobs()
    }

    private func loadProfiles() async {
        guard let connection = appState.activeConnection else {
            profiles = []
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let response = try await appState.caelWorkspaceAPIService.loadProfiles(connection: connection)
            profiles = response.profiles
            activeProfileName = response.activeProfile
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func loadCrewStatus() async {
        guard let connection = appState.activeConnection else {
            crew = []
            return
        }

        do {
            let response = try await appState.caelWorkspaceAPIService.loadCrewStatus(connection: connection)
            crew = response.crew
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    private func loadOperationJobs() async {
        guard let connection = appState.activeConnection else {
            jobs = []
            return
        }

        do {
            jobs = try await appState.caelWorkspaceAPIService.loadWorkspaceCronJobs(connection: connection)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func operationJobs(for profile: CaelProfileSummary) -> [CronJob] {
        let prefix = "ops:\(profile.name):"
        return jobs
            .filter { $0.name.hasPrefix(prefix) }
            .sorted { left, right in
                let leftDate = left.nextRunAt ?? left.lastRunAt ?? .distantFuture
                let rightDate = right.nextRunAt ?? right.lastRunAt ?? .distantFuture
                return leftDate < rightDate
            }
    }

    private func operationJobTitle(_ job: CronJob, profile: CaelProfileSummary) -> String {
        let prefix = "ops:\(profile.name):"
        if job.name.hasPrefix(prefix) {
            return job.name.dropFirst(prefix.count).replacingOccurrences(of: "-", with: " ").capitalized
        }
        return job.resolvedName
    }

    private func runOperationJob(_ job: CronJob) async {
        guard let connection = appState.activeConnection else { return }
        operationJobID = job.id
        errorMessage = nil
        do {
            try await appState.caelWorkspaceAPIService.triggerWorkspaceCronJob(connection: connection, jobID: job.id)
            operationJobID = nil
            await loadOperationJobs()
        } catch {
            operationJobID = nil
            errorMessage = error.localizedDescription
        }
    }

    private func toggleOperationJob(_ job: CronJob) async {
        guard let connection = appState.activeConnection else { return }
        operationJobID = job.id
        errorMessage = nil
        do {
            if job.isPaused || !job.enabled {
                try await appState.caelWorkspaceAPIService.resumeWorkspaceCronJob(connection: connection, jobID: job.id)
            } else {
                try await appState.caelWorkspaceAPIService.pauseWorkspaceCronJob(connection: connection, jobID: job.id)
            }
            operationJobID = nil
            await loadOperationJobs()
        } catch {
            operationJobID = nil
            errorMessage = error.localizedDescription
        }
    }

    private func operationSessionKey(for profile: CaelProfileSummary) -> String {
        "agent:main:ops-\(profile.name)"
    }

    private func loadOperationChat(_ profile: CaelProfileSummary) async {
        guard let connection = appState.activeConnection else { return }
        do {
            let response = try await appState.caelWorkspaceAPIService.loadWorkspaceSessionHistory(
                connection: connection,
                sessionKey: operationSessionKey(for: profile),
                limit: 50
            )
            operationChatMessages[profile.name] = response.messages
            operationChatNotices[profile.name] = response.ok == false ? (response.error ?? "Session history unavailable.") : nil
        } catch {
            operationChatNotices[profile.name] = error.localizedDescription
        }
    }

    private func sendOperationChat(_ profile: CaelProfileSummary) async {
        guard let connection = appState.activeConnection,
              let message = operationChatDrafts[profile.name]?.nilIfBlank else { return }
        let sessionKey = operationSessionKey(for: profile)
        operationSessionKey = sessionKey
        operationChatNotices[profile.name] = nil
        do {
            _ = try await appState.caelWorkspaceAPIService.sendWorkspaceSessionMessage(
                connection: connection,
                sessionKey: sessionKey,
                message: message,
                autoApproveCommands: false
            )
            operationChatDrafts[profile.name] = ""
            operationChatNotices[profile.name] = "Accepted by shared Workspace session runner."
            operationSessionKey = nil
            await loadOperationChat(profile)
            await appState.refreshCaelWorkspace()
        } catch {
            operationSessionKey = nil
            operationChatNotices[profile.name] = error.localizedDescription
        }
    }

    private func createAgent() async {
        guard let connection = appState.activeConnection else { return }
        let name = normalizedProfileName(newAgentName)
        isCreating = true
        errorMessage = nil
        do {
            _ = try await appState.caelWorkspaceAPIService.createProfile(
                connection: connection,
                name: name,
                cloneFrom: "default",
                model: newAgentModel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            )
            newAgentName = ""
            newAgentModel = ""
            isCreating = false
            await loadAll()
        } catch {
            isCreating = false
            errorMessage = error.localizedDescription
        }
    }

    private func beginEdit(_ profile: CaelProfileSummary) async {
        editModel = profile.model ?? ""
        editProvider = profile.provider ?? ""
        editDescription = profile.description ?? ""
        editSystemPrompt = ""
        editingProfile = profile
        guard let connection = appState.activeConnection else { return }
        isLoadingEditDetail = true
        do {
            let detail = try await appState.caelWorkspaceAPIService.readProfile(connection: connection, name: profile.name)
            guard editingProfile?.name == profile.name else { return }
            editModel = stringValue(detail.config["model"]) ?? editModel
            editProvider = stringValue(detail.config["provider"]) ?? editProvider
            editSystemPrompt = stringValue(detail.config["system_prompt"]) ?? ""
            editDescription = detail.description
            isLoadingEditDetail = false
        } catch {
            isLoadingEditDetail = false
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfileEdits() async {
        guard let connection = appState.activeConnection,
              let editingProfile else { return }
        isSavingProfile = true
        errorMessage = nil
        do {
            _ = try await appState.caelWorkspaceAPIService.updateProfileOperationsConfig(
                connection: connection,
                name: editingProfile.name,
                model: editModel,
                provider: editProvider,
                systemPrompt: editSystemPrompt,
                description: editDescription
            )
            isSavingProfile = false
            self.editingProfile = nil
            await loadAll()
        } catch {
            isSavingProfile = false
            errorMessage = error.localizedDescription
        }
    }

    private func activateProfile(_ profile: CaelProfileSummary) async {
        guard let connection = appState.activeConnection else { return }
        operationProfileName = profile.name
        errorMessage = nil
        do {
            _ = try await appState.caelWorkspaceAPIService.activateProfile(connection: connection, name: profile.name)
            await appState.switchHermesProfile(to: profile.name)
            operationProfileName = nil
            await loadAll()
        } catch {
            operationProfileName = nil
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProfile(_ profile: CaelProfileSummary) async {
        guard let connection = appState.activeConnection else { return }
        operationProfileName = profile.name
        errorMessage = nil
        do {
            _ = try await appState.caelWorkspaceAPIService.deleteProfile(connection: connection, name: profile.name)
            operationProfileName = nil
            await loadAll()
        } catch {
            operationProfileName = nil
            errorMessage = error.localizedDescription
        }
    }

    private func startRuntime() async {
        guard let connection = appState.activeConnection else { return }
        isStartingRuntime = true
        errorMessage = nil
        runtimeMessage = nil
        do {
            let response = try await appState.caelWorkspaceAPIService.startWorkspaceAgentRuntime(connection: connection)
            runtimeMessage = response.pid.map { "\(response.displayMessage) pid \($0)" } ?? response.displayMessage
            isStartingRuntime = false
            await appState.refreshCaelWorkspace()
            await loadAll()
        } catch {
            isStartingRuntime = false
            errorMessage = error.localizedDescription
        }
    }

    private func crewMember(for profile: CaelProfileSummary) -> WorkspaceCrewMember? {
        let crewID = profile.name == "default" ? "workspace" : profile.name
        return crew.first { $0.id == crewID }
    }

    private func normalizedProfileName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }

    private func isValidProfileName(_ value: String) -> Bool {
        let normalized = normalizedProfileName(value)
        guard !normalized.isEmpty, normalized != "default", normalized.count <= 64 else { return false }
        return normalized.range(of: #"^[a-z0-9][a-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private func stringValue(_ value: CaelJSONValue?) -> String? {
        guard case let .string(text) = value else { return nil }
        return text
    }

    private func formatTimestamp(_ value: Double) -> String {
        let seconds = value > 1_000_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .shortened)
    }

    private func tint(forStatus status: String) -> Color {
        switch status.lowercased() {
        case "ready", "available", "complete", "online", "ok", "running": return .green
        case "active": return .cyan
        case "setup-needed", "warning", "error", "needs_attention", "unknown": return .orange
        default: return .blue
        }
    }
}

private struct OperationMiniStat: View {
    let label: String
    let value: String

    var body: some View {
        Text("\(value) \(label)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

private struct NativeSwarmPanel: View {
    @EnvironmentObject private var appState: AppState

    @State private var health: WorkspaceSwarmHealthResponse?
    @State private var runtime: WorkspaceSwarmRuntimeResponse?
    @State private var missions: WorkspaceSwarmMissionsResponse?
    @State private var selectedWorkerID: String?
    @State private var dispatchPrompt = "Reply with exactly: SWARM_PING_OK"
    @State private var statusMessage: String?
    @State private var isLoading = false
    @State private var profileMemory: WorkspaceSwarmMemoryResponse?
    @State private var episodicMemory: WorkspaceSwarmMemoryResponse?
    @State private var reportSnapshot: WorkspaceSwarmReportsResponse?
    @State private var memorySearchResults: WorkspaceSwarmMemorySearchResponse?
    @State private var memorySearchQuery = ""
    @State private var isLoadingMemory = false
    @State private var mutatingWorkerID: String?
    @State private var dispatchingWorkerID: String?

    private var workers: [WorkspaceSwarmWorkerHealth] {
        (health?.workers ?? []).sorted { left, right in
            swarmSortKey(left.workerId) < swarmSortKey(right.workerId)
        }
    }

    private var selectedWorker: WorkspaceSwarmWorkerHealth? {
        guard let selectedWorkerID else { return workers.first }
        return workers.first { $0.workerId == selectedWorkerID } ?? workers.first
    }

    var body: some View {
        HermesSurfacePanel(
            title: "Swarm Runtime",
            subtitle: "Native worker health, live runtime, tmux lifecycle, and direct dispatch through the shared Workspace Swarm APIs."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let statusMessage {
                    MirrorRow(title: "Status", detail: statusMessage, tint: statusMessage.lowercased().contains("error") ? .orange : .blue)
                }

                workerGrid
                dispatchPanel
                missionsPanel
                memoryReportsPanel
            }
        }
        .task(id: appState.activeConnectionID) {
            await loadAll()
        }
        .onChange(of: selectedWorkerID) { _, workerID in
            Task { await loadWorkerMemoryReports(workerID: workerID) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(health?.summary.degraded == true ? "Needs attention" : "Runtime ready")
                    .font(.headline)
                Text(summaryDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Refresh") {
                Task { await loadAll() }
            }
            .disabled(isLoading)
        }
    }

    private var summaryDetail: String {
        guard let health else { return "Load Swarm health from /api/swarm-health." }
        let providers = health.summary.distinctProviders.prefix(3).joined(separator: ", ")
        return [
            "\(health.summary.totalWorkers) workers",
            "\(health.summary.wrappersConfigured ?? 0) wrappers",
            "\(runtime?.entries.filter(\.tmuxAttachable).count ?? 0) tmux attached",
            providers.isEmpty ? nil : providers
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var workerGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workers")
                    .font(.headline)
                Spacer()
                if let runtime {
                    Text(runtime.tmuxAvailable ? "tmux available" : "tmux unavailable")
                        .font(.caption)
                        .foregroundStyle(runtime.tmuxAvailable ? Color.green : Color.orange)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(workers) { worker in
                    workerCard(worker)
                }
            }

            if health != nil && workers.isEmpty {
                Text("No swarm workers reported by the active Workspace.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func workerCard(_ worker: WorkspaceSwarmWorkerHealth) -> some View {
        let runtimeEntry = runtimeEntry(for: worker.workerId)
        let isSelected = selectedWorker?.workerId == worker.workerId
        return MirrorListCard(title: worker.humanLabel, emptyText: "No worker detail reported.") {
            MirrorRow(
                title: runtimeEntry?.state ?? worker.modelAuthStatus,
                detail: workerDetail(worker, runtimeEntry: runtimeEntry),
                badge: runtimeEntry?.tmuxAttachable == true ? "tmux" : (worker.wrapperFound ? "ready" : "setup"),
                tint: workerTint(worker, runtimeEntry: runtimeEntry)
            )
            if let currentTask = runtimeEntry?.currentTask?.nilIfBlank {
                MirrorRow(title: "Current task", detail: currentTask, tint: .blue)
            }
            if let tail = runtimeEntry?.recentLogTail?.nilIfBlank {
                MirrorRow(title: "Recent log", detail: preview(tail, maxLength: 260), tint: .secondary)
            }

            HStack(spacing: 8) {
                Button(isSelected ? "Selected" : "Select") {
                    selectedWorkerID = worker.workerId
                }

                Button(runtimeEntry?.tmuxAttachable == true ? "Attach Ready" : "Start tmux") {
                    Task { await startWorker(worker.workerId) }
                }
                .disabled(mutatingWorkerID != nil || runtimeEntry?.tmuxAttachable == true)

                Button("Stop", role: .destructive) {
                    Task { await stopWorker(worker.workerId) }
                }
                .disabled(mutatingWorkerID != nil || runtimeEntry?.tmuxAttachable != true)
            }
            .font(.caption)
        }
    }

    private var dispatchPanel: some View {
        MirrorListCard(title: "Direct Dispatch", emptyText: "Select a worker before dispatching.") {
            if let worker = selectedWorker {
                MirrorRow(
                    title: worker.workerId,
                    detail: worker.mission ?? worker.specialty ?? worker.role,
                    badge: dispatchingWorkerID == worker.workerId ? "Sending" : "Selected",
                    tint: .cyan
                )

                TextEditor(text: $dispatchPrompt)
                    .font(.body)
                    .frame(minHeight: 88)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    }

                HStack {
                    Spacer()
                    Button(dispatchingWorkerID == worker.workerId ? "Dispatching..." : "Dispatch to \(worker.workerId)") {
                        Task { await dispatch(to: worker.workerId) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(dispatchingWorkerID != nil || dispatchPrompt.nilIfBlank == nil)
                }
            } else {
                Text("No workers available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var missionsPanel: some View {
        MirrorListCard(title: "Recent Missions", emptyText: "No swarm missions reported.") {
            let missionList = missions?.missions ?? []
            if missionList.isEmpty {
                Text("Mission history is loaded from /api/swarm-missions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(missionList.prefix(6)) { mission in
                    MirrorRow(
                        title: mission.title,
                        detail: "\(mission.assignments.count) assignments · \(mission.updatedAt ?? mission.createdAt ?? "unknown time")",
                        badge: mission.state,
                        tint: tint(forStatus: mission.state)
                    )
                }
            }
        }
    }

    private var memoryReportsPanel: some View {
        MirrorListCard(title: "Worker Memory + Reports", emptyText: "Select a worker to inspect memory and reports.") {
            if let worker = selectedWorker {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    MirrorRow(
                        title: worker.workerId,
                        detail: "Reads profile memory, episodic memory, search results, and checkpoint reports through shared Swarm APIs.",
                        badge: isLoadingMemory ? "Loading" : "Selected",
                        tint: .purple
                    )
                    Spacer()
                    Button("Refresh") {
                        Task { await loadWorkerMemoryReports(workerID: worker.workerId) }
                    }
                    .disabled(isLoadingMemory)
                }

                HStack(spacing: 8) {
                    TextField("Search worker memory", text: $memorySearchQuery)
                        .textFieldStyle(.roundedBorder)
                    Button("Search") {
                        Task { await searchMemory(workerID: worker.workerId) }
                    }
                    .disabled(isLoadingMemory || memorySearchQuery.nilIfBlank == nil)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                    memoryCard(title: "Profile Memory", memory: profileMemory)
                    memoryCard(title: "Episodic Memory", memory: episodicMemory)
                    reportsCard
                    searchResultsCard
                }
            } else {
                Text("No workers available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func memoryCard(title: String, memory: WorkspaceSwarmMemoryResponse?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let error = memory?.error?.nilIfBlank {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let files = memory?.files, !files.isEmpty {
                ForEach(files.prefix(3)) { file in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.name)
                            .font(.caption.weight(.semibold))
                        Text(preview(file.content, maxLength: 220))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if files.count > 3 {
                    Text("+ \(files.count - 3) more memory files")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(memory == nil ? "Not loaded yet." : "No memory files reported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var reportsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Checkpoint Reports")
                .font(.subheadline.weight(.semibold))
            let reports = reportSnapshot?.reports ?? []
            if reports.isEmpty {
                Text(reportSnapshot == nil ? "Not loaded yet." : "No checkpoint reports for this worker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reports.prefix(4)) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reportTitle(report))
                            .font(.caption.weight(.semibold))
                        Text(reportDetail(report))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var searchResultsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Memory Search")
                .font(.subheadline.weight(.semibold))
            let results = memorySearchResults?.results ?? []
            if results.isEmpty {
                Text(memorySearchResults == nil ? "Run a search to inspect worker memory." : "No matching memory snippets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results.prefix(5)) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(result.path):\(result.line)")
                            .font(.caption.weight(.semibold))
                        Text(preview(result.snippet, maxLength: 180))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func loadAll() async {
        guard let connection = appState.activeConnection else { return }
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }
        do {
            async let healthResponse = appState.caelWorkspaceAPIService.loadSwarmHealth(connection: connection)
            async let runtimeResponse = appState.caelWorkspaceAPIService.loadSwarmRuntime(connection: connection)
            async let missionsResponse = appState.caelWorkspaceAPIService.loadSwarmMissions(connection: connection, limit: 8)
            let (loadedHealth, loadedRuntime, loadedMissions) = try await (healthResponse, runtimeResponse, missionsResponse)
            health = loadedHealth
            runtime = loadedRuntime
            missions = loadedMissions
            if selectedWorkerID == nil {
                selectedWorkerID = loadedHealth.workers.first?.workerId
            }
            statusMessage = "Loaded \(loadedHealth.summary.totalWorkers) workers and \(loadedMissions.missions.count) recent missions."
            await loadWorkerMemoryReports(workerID: selectedWorkerID)
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func loadWorkerMemoryReports(workerID: String?) async {
        guard let connection = appState.activeConnection,
              let workerID = workerID?.nilIfBlank else { return }
        isLoadingMemory = true
        defer { isLoadingMemory = false }
        async let profile: WorkspaceSwarmMemoryResponse? = try? appState.caelWorkspaceAPIService.loadSwarmMemory(
            connection: connection,
            workerID: workerID,
            kind: "profile"
        )
        async let episodic: WorkspaceSwarmMemoryResponse? = try? appState.caelWorkspaceAPIService.loadSwarmMemory(
            connection: connection,
            workerID: workerID,
            kind: "episodic"
        )
        async let reports: WorkspaceSwarmReportsResponse? = try? appState.caelWorkspaceAPIService.loadSwarmReports(
            connection: connection,
            workerID: workerID,
            limit: 8
        )
        profileMemory = await profile
        episodicMemory = await episodic
        reportSnapshot = await reports
    }

    private func searchMemory(workerID: String) async {
        guard let connection = appState.activeConnection,
              let query = memorySearchQuery.nilIfBlank else { return }
        isLoadingMemory = true
        defer { isLoadingMemory = false }
        do {
            memorySearchResults = try await appState.caelWorkspaceAPIService.searchSwarmMemory(
                connection: connection,
                workerID: workerID,
                query: query,
                scope: "worker",
                limit: 10
            )
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func startWorker(_ workerID: String) async {
        guard let connection = appState.activeConnection else { return }
        mutatingWorkerID = workerID
        statusMessage = nil
        defer { mutatingWorkerID = nil }
        do {
            let response = try await appState.caelWorkspaceAPIService.startSwarmWorkerTmux(connection: connection, workerID: workerID)
            statusMessage = response.alreadyRunning == true ? "\(workerID) already had a tmux session." : "Started \(response.sessionName ?? workerID)."
            await loadAll()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func stopWorker(_ workerID: String) async {
        guard let connection = appState.activeConnection else { return }
        mutatingWorkerID = workerID
        statusMessage = nil
        defer { mutatingWorkerID = nil }
        do {
            let response = try await appState.caelWorkspaceAPIService.stopSwarmWorkerTmux(connection: connection, workerID: workerID)
            statusMessage = response.wasRunning == true ? "Stopped \(response.sessionName ?? workerID)." : "\(workerID) was not running."
            await loadAll()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func dispatch(to workerID: String) async {
        guard let connection = appState.activeConnection, let prompt = dispatchPrompt.nilIfBlank else { return }
        dispatchingWorkerID = workerID
        statusMessage = nil
        defer { dispatchingWorkerID = nil }
        do {
            let response = try await appState.caelWorkspaceAPIService.dispatchSwarmPrompt(
                connection: connection,
                workerID: workerID,
                prompt: prompt,
                timeoutSeconds: 60,
                allowAsync: false
            )
            if let result = response.results?.first {
                statusMessage = result.ok
                    ? "\(workerID) replied in \(String(format: "%.1f", (result.durationMs ?? 0) / 1000))s: \(preview(result.output, maxLength: 120))"
                    : "\(workerID) failed: \(result.error ?? "unknown error")"
            } else {
                statusMessage = response.ok == false ? (response.error ?? "Dispatch failed.") : "Dispatch accepted."
            }
            await loadAll()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func runtimeEntry(for workerID: String) -> WorkspaceSwarmRuntimeEntry? {
        runtime?.entries.first { $0.workerId == workerID }
    }

    private func workerDetail(_ worker: WorkspaceSwarmWorkerHealth, runtimeEntry: WorkspaceSwarmRuntimeEntry?) -> String {
        [
            worker.specialty?.nilIfBlank ?? worker.role,
            "\(worker.provider) / \(worker.model)",
            runtimeEntry?.tmuxSession?.nilIfBlank.map { "tmux: \($0)" },
            runtimeEntry?.lastOutputAt.map { "last output \(formatTimestamp($0))" },
            worker.lastErrorMessage?.nilIfBlank
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private func swarmSortKey(_ workerID: String) -> String {
        let number = Int(workerID.replacingOccurrences(of: #"^\D+"#, with: "", options: .regularExpression)) ?? 9999
        return String(format: "%04d-%@", number, workerID)
    }

    private func workerTint(_ worker: WorkspaceSwarmWorkerHealth, runtimeEntry: WorkspaceSwarmRuntimeEntry?) -> Color {
        if worker.recentAuthErrors > 0 || worker.fallbackActive || runtimeEntry?.needsHuman == true { return .orange }
        if runtimeEntry?.tmuxAttachable == true || runtimeEntry?.state.lowercased() == "running" { return .green }
        if worker.wrapperFound { return .blue }
        return .secondary
    }

    private func tint(forStatus status: String) -> Color {
        switch status.lowercased() {
        case "complete", "done", "running", "executing": return .green
        case "blocked", "failed", "cancelled", "error": return .orange
        default: return .blue
        }
    }

    private func reportTitle(_ report: WorkspaceSwarmReport) -> String {
        let status = report.checkpointStatus?.nilIfBlank ?? report.stateLabel?.nilIfBlank ?? "checkpoint"
        return "\(report.workerId) · \(status)"
    }

    private func reportDetail(_ report: WorkspaceSwarmReport) -> String {
        [
            report.recordedAt.map { formatTimestamp($0) },
            report.result?.nilIfBlank.map { "Result: \(preview($0, maxLength: 140))" },
            report.blocker?.nilIfBlank.map { "Blocker: \(preview($0, maxLength: 140))" },
            report.nextAction?.nilIfBlank.map { "Next: \(preview($0, maxLength: 140))" },
            report.commandsRun?.nilIfBlank.map { "Commands: \(preview($0, maxLength: 100))" },
            report.filesChanged?.nilIfBlank.map { "Files: \(preview($0, maxLength: 100))" }
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private func formatTimestamp(_ value: Double) -> String {
        let seconds = value > 1_000_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .shortened)
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

private struct NativeConductorPanel: View {
    @EnvironmentObject private var appState: AppState

    @State private var goal = ""
    @State private var missionID = ""
    @State private var orchestratorModel = ""
    @State private var workerModel = ""
    @State private var projectsDir = "~/conductor-projects"
    @State private var maxParallel = 1.0
    @State private var supervised = false
    @State private var launchResponse: WorkspaceConductorSpawnResponse?
    @State private var missionResponse: WorkspaceConductorMissionResponse?
    @State private var statusMessage: String?
    @State private var isLaunching = false
    @State private var isLoadingMission = false
    @State private var isStopping = false

    var body: some View {
        HermesSurfacePanel(
            title: "Conductor Mission Control",
            subtitle: "Launch and inspect mission-level orchestration through /api/conductor-spawn and /api/conductor-stop. Real work stays server-side."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                launchControls
                missionControls
                missionStatus
            }
        }
    }

    private var launchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Launch mission")
                .font(.headline)
            TextEditor(text: $goal)
                .font(.body)
                .frame(minHeight: 96)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                }

            HStack(spacing: 12) {
                TextField("Orchestrator model", text: $orchestratorModel)
                    .textFieldStyle(.roundedBorder)
                TextField("Worker model", text: $workerModel)
                    .textFieldStyle(.roundedBorder)
                TextField("Projects dir", text: $projectsDir)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max parallel: \(Int(maxParallel))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $maxParallel, in: 1...5, step: 1)
                        .frame(maxWidth: 220)
                }
                Toggle("Supervised", isOn: $supervised)
                    .toggleStyle(.checkbox)
                Spacer()
                Button(isLaunching ? "Launching..." : "Launch Mission") {
                    Task { await launchMission() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLaunching || goal.nilIfBlank == nil)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var missionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Mission ID", text: $missionID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await loadMission() }
                    }
                Button(isLoadingMission ? "Checking..." : "Check Status") {
                    Task { await loadMission() }
                }
                .disabled(isLoadingMission || missionID.nilIfBlank == nil)
                Button(isStopping ? "Stopping..." : "Stop Mission", role: .destructive) {
                    Task { await stopMission() }
                }
                .disabled(isStopping || missionID.nilIfBlank == nil)
            }

            if let statusMessage {
                MirrorRow(title: "Status", detail: statusMessage, tint: statusMessage.lowercased().contains("error") ? .orange : .blue)
            }

            if let launchResponse {
                MirrorRow(
                    title: launchResponse.jobName ?? launchResponse.missionId ?? "Conductor mission",
                    detail: launchDetail(launchResponse),
                    badge: launchResponse.mode ?? "conductor",
                    tint: launchResponse.ok ? .green : .orange
                )
            }
        }
    }

    private var missionStatus: some View {
        MirrorListCard(title: "Mission Status", emptyText: "No mission status loaded.") {
            if let record = missionResponse?.mission {
                MirrorRow(
                    title: record.name ?? record.id ?? "Mission",
                    detail: [
                        record.error?.nilIfBlank,
                        record.updatedAt?.nilIfBlank,
                        record.modeNote?.nilIfBlank
                    ].compactMap { $0 }.joined(separator: "\n"),
                    badge: record.status ?? "unknown",
                    tint: tint(forStatus: record.status ?? "")
                )

                let assignments = record.assignments ?? []
                ForEach(assignments.prefix(6)) { assignment in
                    MirrorRow(
                        title: assignment.workerId,
                        detail: assignment.task,
                        badge: assignment.state ?? "assigned",
                        tint: tint(forStatus: assignment.state ?? "")
                    )
                }

                if let lines = record.lines, !lines.isEmpty {
                    Text(lines.suffix(10).joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(12)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            } else {
                Text("Launch a mission or paste a mission id to inspect its current server-side status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func launchMission() async {
        guard let connection = appState.activeConnection, let goalText = goal.nilIfBlank else { return }
        isLaunching = true
        statusMessage = nil
        defer { isLaunching = false }
        do {
            let response = try await appState.caelWorkspaceAPIService.spawnConductorMission(
                connection: connection,
                goal: goalText,
                orchestratorModel: orchestratorModel,
                workerModel: workerModel,
                projectsDir: projectsDir,
                maxParallel: Int(maxParallel),
                supervised: supervised
            )
            launchResponse = response
            missionID = response.missionId ?? response.jobId ?? missionID
            statusMessage = response.missionId.map { "Mission launched: \($0)" } ?? "Conductor accepted the mission."
            goal = ""
            await loadMission()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func loadMission() async {
        guard let connection = appState.activeConnection, let mission = missionID.nilIfBlank else { return }
        isLoadingMission = true
        statusMessage = nil
        defer { isLoadingMission = false }
        do {
            missionResponse = try await appState.caelWorkspaceAPIService.loadConductorMission(connection: connection, missionID: mission)
            let record = missionResponse?.mission
            statusMessage = record?.status.map { "Mission status: \($0)" } ?? "Mission status loaded."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func stopMission() async {
        guard let connection = appState.activeConnection, let mission = missionID.nilIfBlank else { return }
        isStopping = true
        statusMessage = nil
        defer { isStopping = false }
        do {
            let response = try await appState.caelWorkspaceAPIService.stopConductorMission(connection: connection, missionIDs: [mission])
            statusMessage = "Stopped \(response.stoppedMissions ?? 0) dashboard missions; cancelled \(response.cancelledNativeMissions ?? 0) native missions."
            await loadMission()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func launchDetail(_ response: WorkspaceConductorSpawnResponse) -> String {
        [
            response.modeNote?.nilIfBlank,
            response.sessionKey?.nilIfBlank.map { "session: \($0)" },
            response.assignments.map { "\($0.count) assignments" },
            (response.warnings?.joined(separator: "\n"))?.nilIfBlank
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private func tint(forStatus status: String) -> Color {
        switch status.lowercased() {
        case "complete", "completed", "running", "executing": return .green
        case "blocked", "failed", "cancelled", "error": return .orange
        default: return .blue
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
    @State private var sessionStateResponse: KnowledgeFabricSessionStateResponse?
    @State private var sessionSummary = ""
    @State private var sessionScope = "business"
    @State private var sessionAgentSource = "Cael Desktop"
    @State private var sessionID = ""
    @State private var sessionProject = "Hermes/Cael"
    @State private var errorMessage: String?
    @State private var isLoadingHealth = false
    @State private var isSearching = false
    @State private var isLookingUpDocument = false
    @State private var isRecordingSessionState = false

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

                sessionStateControls

                if let sessionStateResponse {
                    MirrorRow(
                        title: sessionStateResponse.ok == false ? "Session state failed" : "Session state recorded",
                        detail: sessionStateResponse.data ?? sessionStateResponse.error ?? "Knowledge Fabric accepted the session-state receipt.",
                        badge: sessionStateResponse.ok == false ? "Error" : "Memory",
                        tint: sessionStateResponse.ok == false ? .orange : .green
                    )
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

    private var sessionStateControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Record session state")
                .font(.headline)
            TextEditor(text: $sessionSummary)
                .font(.body)
                .frame(minHeight: 88)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                }
            HStack(spacing: 12) {
                Picker("Scope", selection: $sessionScope) {
                    Text("Business").tag("business")
                    Text("Personal").tag("personal")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                TextField("Agent source", text: $sessionAgentSource)
                    .textFieldStyle(.roundedBorder)
                TextField("Session id", text: $sessionID)
                    .textFieldStyle(.roundedBorder)
                TextField("Project", text: $sessionProject)
                    .textFieldStyle(.roundedBorder)
                Button(isRecordingSessionState ? "Recording..." : "Record") {
                    Task { await recordSessionState() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRecordingSessionState || sessionSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func recordSessionState() async {
        guard let connection = appState.activeConnection else { return }
        isRecordingSessionState = true
        errorMessage = nil
        defer { isRecordingSessionState = false }
        do {
            sessionStateResponse = try await appState.caelWorkspaceAPIService.recordKnowledgeFabricSessionState(
                connection: connection,
                summary: sessionSummary,
                memoryScope: sessionScope,
                agentSource: sessionAgentSource,
                sessionId: sessionID,
                project: sessionProject
            )
            sessionSummary = ""
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



private struct NativeMCPPanel: View {
    @EnvironmentObject private var appState: AppState

    @State private var search = ""
    @State private var category = "All"
    @State private var response: WorkspaceMCPListResponse?
    @State private var testResults: [String: WorkspaceMCPTestResponse] = [:]
    @State private var discoverResults: [String: WorkspaceMCPDiscoverResponse] = [:]
    @State private var logResults: [String: WorkspaceMCPLogsResponse] = [:]
    @State private var hubSources: [WorkspaceMCPHubSource] = []
    @State private var presets: [WorkspaceMCPPreset] = []
    @State private var hubSearch = "github"
    @State private var hubSearchResults: [WorkspaceMCPHubEntry] = []
    @State private var hubSearchSummary: String?
    @State private var statusMessage: String?
    @State private var isLoading = false
    @State private var isSearchingHub = false
    @State private var testingServer: String?
    @State private var discoveringServer: String?
    @State private var loadingLogsServer: String?
    @State private var mutatingServer: String?
    @State private var newServerName = ""
    @State private var newServerCommand = ""
    @State private var newServerArgs = ""
    @State private var newServerEnabled = true

    private var servers: [WorkspaceMCPServer] {
        response?.servers ?? []
    }

    private var categories: [String] {
        let values = response?.categories ?? ["All", "Connected", "Failed", "Disabled"]
        return values.isEmpty ? ["All"] : values
    }

    private var isMCPCapabilityAvailable: Bool {
        response?.ok != false
    }

    var body: some View {
        HermesSurfacePanel(
            title: "MCP Servers",
            subtitle: "Native MCP list and probe surface backed by the shared :3077 /api/mcp contract."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TextField("Search MCP servers", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task { await loadServers() }
                        }
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .frame(maxWidth: 180)
                    Button("Refresh") {
                        Task { await loadServers() }
                    }
                    .disabled(isLoading)
                }

                if isLoading {
                    ProgressView("Loading MCP servers...")
                        .controlSize(.small)
                }

                if let statusMessage {
                    MirrorRow(title: "Status", detail: statusMessage, tint: statusMessage.lowercased().contains("error") ? .orange : .blue)
                }

                createServerForm

                registrySummary

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(servers) { server in
                        serverCard(server)
                    }
                }

                if response != nil && servers.isEmpty {
                    Text("No MCP servers matched the current filter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await loadServers()
        }
    }

    private var createServerForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add command MCP server")
                .font(.headline)
            HStack(spacing: 10) {
                TextField("Name", text: $newServerName)
                    .textFieldStyle(.roundedBorder)
                TextField("Command", text: $newServerCommand)
                    .textFieldStyle(.roundedBorder)
                TextField("Args", text: $newServerArgs)
                    .textFieldStyle(.roundedBorder)
                Toggle("Enabled", isOn: $newServerEnabled)
                    .toggleStyle(.checkbox)
                Button(mutatingServer == "__create__" ? "Adding..." : "Add") {
                    Task { await createServer() }
                }
                .disabled(!isMCPCapabilityAvailable || !canCreateServer || mutatingServer != nil)
            }
            Text("Secrets stay server-side. This form only creates stdio command servers with authType=none.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var canCreateServer: Bool {
        !newServerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !newServerCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var registrySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("MCP registry")
                    .font(.headline)
                Spacer()
                Button("Load Registry") {
                    Task { await loadMCPRegistry() }
                }
                .disabled(isLoading)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                MirrorListCard(title: "Hub Sources", emptyText: "No hub sources loaded.") {
                    if hubSources.isEmpty {
                        Text("Registry sources are loaded on demand from the shared Workspace API.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(hubSources.prefix(4)) { source in
                            MirrorRow(
                                title: source.name,
                                detail: registrySourceDetail(source),
                                badge: source.enabled == false ? "Disabled" : source.trust,
                                tint: source.enabled == false ? .orange : .green
                            )
                        }
                    }
                }

                MirrorListCard(title: "Presets", emptyText: "No presets loaded.") {
                    if presets.isEmpty {
                        Text("Presets stay server-side; Desktop only renders safe metadata and command templates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(presets.prefix(6)) { preset in
                            MirrorRow(title: preset.name ?? preset.id, detail: presetDetail(preset), badge: preset.category, tint: .blue)
                        }
                    }
                }
            }

            marketplaceSearchPanel
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var marketplaceSearchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Marketplace search")
                    .font(.headline)
                TextField("Search MCP catalog", text: $hubSearch)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await searchMCPMarketplace() }
                    }
                Button(isSearchingHub ? "Searching..." : "Search Hub") {
                    Task { await searchMCPMarketplace() }
                }
                .disabled(isSearchingHub || hubSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let hubSearchSummary {
                Text(hubSearchSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hubSearchResults.isEmpty {
                Text("Search uses /api/mcp/hub-search. Results can be staged into the Add Server form; writes still obey the active gateway capability state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10, alignment: .top)], spacing: 10) {
                    ForEach(hubSearchResults.prefix(9)) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            MirrorRow(
                                title: entry.name,
                                detail: hubEntryDetail(entry),
                                badge: entry.installed == true ? "Installed" : entry.trust,
                                tint: entry.installed == true ? .green : .blue
                            )
                            HStack {
                                Spacer()
                                Button("Stage") {
                                    stageHubEntry(entry)
                                }
                                .disabled(entry.template?.command?.nilIfBlank == nil)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private func serverCard(_ server: WorkspaceMCPServer) -> some View {
        MirrorListCard(title: server.name, emptyText: "No MCP server detail reported.") {
            MirrorRow(
                title: server.status,
                detail: serverDetail(server),
                badge: server.enabled ? "Enabled" : "Disabled",
                tint: tint(server.status)
            )
            MirrorRow(title: "Tools", detail: "\(server.discoveredToolsCount) discovered", badge: server.transportType, tint: .blue)
            if let result = testResults[server.name] {
                MirrorRow(
                    title: "Last test: \(result.status)",
                    detail: testDetail(result),
                    badge: "\(result.discoveredTools.count) tools",
                    tint: result.ok ? .green : .orange
                )
            }
            if let discovery = discoverResults[server.name] {
                MirrorRow(
                    title: "Discovery",
                    detail: discoverDetail(discovery),
                    badge: "\(discovery.tools.count) tools",
                    tint: discovery.ok ? .green : .orange
                )
            }
            if let logs = logResults[server.name] {
                MirrorRow(
                    title: logs.ok ? "Log tail" : "Log tail unavailable",
                    detail: logDetail(logs),
                    badge: logs.lines.isEmpty ? nil : "\(logs.lines.count) lines",
                    tint: logs.ok ? .blue : .orange
                )
            }
            HStack(spacing: 8) {
                Button(testingServer == server.name ? "Testing..." : "Test") {
                    Task { await testServer(server.name) }
                }
                .disabled(!isMCPCapabilityAvailable || testingServer != nil || !server.enabled)

                Button(discoveringServer == server.name ? "Discovering..." : "Discover") {
                    Task { await discoverServer(server) }
                }
                .disabled(!isMCPCapabilityAvailable || discoveringServer != nil || !server.enabled)

                Button(loadingLogsServer == server.name ? "Loading..." : "Logs") {
                    Task { await loadLogs(server.name) }
                }
                .disabled(loadingLogsServer != nil)

                Button(server.enabled ? "Disable" : "Enable") {
                    Task { await setServer(server.name, enabled: !server.enabled) }
                }
                .disabled(!isMCPCapabilityAvailable || mutatingServer != nil)

                Button("Delete", role: .destructive) {
                    Task { await deleteServer(server.name) }
                }
                .disabled(!isMCPCapabilityAvailable || mutatingServer != nil)
            }
        }
    }

    private func loadServers() async {
        guard let connection = appState.activeConnection else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await appState.caelWorkspaceAPIService.listMCPServers(
                connection: connection,
                search: search,
                category: category
            )
            if response?.ok == false {
                statusMessage = response?.error ?? "MCP capability unavailable on the active Workspace gateway."
            } else {
                statusMessage = "Loaded \(response?.total ?? servers.count) MCP servers."
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func createServer() async {
        guard let connection = appState.activeConnection else { return }
        let name = newServerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = newServerCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !command.isEmpty else { return }
        mutatingServer = "__create__"
        defer { mutatingServer = nil }
        do {
            _ = try await appState.caelWorkspaceAPIService.createMCPCommandServer(
                connection: connection,
                name: name,
                command: command,
                args: shellWords(newServerArgs),
                enabled: newServerEnabled
            )
            newServerName = ""
            newServerCommand = ""
            newServerArgs = ""
            statusMessage = "Added MCP server \(name)."
            await loadServers()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func setServer(_ name: String, enabled: Bool) async {
        guard let connection = appState.activeConnection else { return }
        mutatingServer = name
        defer { mutatingServer = nil }
        do {
            _ = try await appState.caelWorkspaceAPIService.configureMCPServer(
                connection: connection,
                name: name,
                enabled: enabled
            )
            statusMessage = "Updated MCP server \(name)."
            await loadServers()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func deleteServer(_ name: String) async {
        guard let connection = appState.activeConnection else { return }
        mutatingServer = name
        defer { mutatingServer = nil }
        do {
            _ = try await appState.caelWorkspaceAPIService.deleteMCPServer(connection: connection, name: name)
            testResults[name] = nil
            discoverResults[name] = nil
            logResults[name] = nil
            statusMessage = "Deleted MCP server \(name)."
            await loadServers()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func shellWords(_ value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
    }

    private func testServer(_ name: String) async {
        guard let connection = appState.activeConnection else { return }
        testingServer = name
        defer { testingServer = nil }
        do {
            let result = try await appState.caelWorkspaceAPIService.testMCPServer(connection: connection, name: name)
            testResults[name] = result
            statusMessage = "Tested \(name): \(result.status)."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func loadMCPRegistry() async {
        guard let connection = appState.activeConnection else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let sourcesResponse = appState.caelWorkspaceAPIService.loadMCPHubSources(connection: connection)
            async let presetsResponse = appState.caelWorkspaceAPIService.loadMCPPresets(connection: connection)
            let (sources, loadedPresets) = try await (sourcesResponse, presetsResponse)
            hubSources = sources.sources
            presets = loadedPresets.presets
            let sourceWarning = sources.ok == false ? sources.error?.nilIfBlank : nil
            let presetWarning = loadedPresets.ok == false ? loadedPresets.error?.nilIfBlank : nil
            statusMessage = [
                "Loaded \(hubSources.count) MCP hub sources and \(presets.count) presets.",
                sourceWarning,
                presetWarning
            ].compactMap { $0 }.joined(separator: " ")
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func discoverServer(_ server: WorkspaceMCPServer) async {
        guard let connection = appState.activeConnection else { return }
        discoveringServer = server.name
        defer { discoveringServer = nil }
        do {
            let result = try await appState.caelWorkspaceAPIService.discoverMCPServer(connection: connection, server: server)
            discoverResults[server.name] = result
            statusMessage = "Discovered \(result.tools.count) tools for \(server.name)."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func loadLogs(_ name: String) async {
        guard let connection = appState.activeConnection else { return }
        loadingLogsServer = name
        defer { loadingLogsServer = nil }
        do {
            let result = try await appState.caelWorkspaceAPIService.loadMCPServerLogs(connection: connection, name: name)
            logResults[name] = result
            if result.ok {
                statusMessage = result.lines.isEmpty ? "No recent MCP logs for \(name)." : "Loaded \(result.lines.count) log lines for \(name)."
            } else {
                statusMessage = "MCP logs unavailable for \(name): \(result.error ?? "unknown error")."
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func searchMCPMarketplace() async {
        guard let connection = appState.activeConnection else { return }
        let query = hubSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearchingHub = true
        defer { isSearchingHub = false }
        do {
            let result = try await appState.caelWorkspaceAPIService.searchMCPHub(connection: connection, query: query)
            hubSearchResults = result.results
            let warning = result.warnings?.first?.nilIfBlank
            hubSearchSummary = [
                "\(result.results.count) of \(result.total ?? result.results.count) results from \(result.source ?? "hub").",
                result.ok == false ? result.error?.nilIfBlank : nil,
                warning
            ].compactMap { $0 }.joined(separator: " ")
        } catch {
            hubSearchSummary = "Error: \(error.localizedDescription)"
        }
    }

    private func stageHubEntry(_ entry: WorkspaceMCPHubEntry) {
        guard let template = entry.template, let command = template.command?.nilIfBlank else {
            statusMessage = "Only command-backed MCP templates can be staged in Desktop right now."
            return
        }
        newServerName = template.name?.nilIfBlank ?? entry.name
        newServerCommand = command
        newServerArgs = (template.args ?? []).joined(separator: " ")
        newServerEnabled = true
        statusMessage = "Staged MCP template \(entry.name). Review the Add command MCP server form before adding."
    }

    private func hubEntryDetail(_ entry: WorkspaceMCPHubEntry) -> String {
        [
            entry.description?.nilIfBlank,
            entry.source?.nilIfBlank.map { "Source: \($0)" },
            entry.tags?.prefix(4).joined(separator: ", ").nilIfBlank
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private func serverDetail(_ server: WorkspaceMCPServer) -> String {
        let target = server.url ?? [server.command, server.args.joined(separator: " ")].compactMap { $0 }.joined(separator: " ")
        if let lastError = server.lastError, !lastError.isEmpty {
            return "\(target)\n\(lastError)"
        }
        return target.isEmpty ? "No target reported." : target
    }

    private func testDetail(_ result: WorkspaceMCPTestResponse) -> String {
        if let error = result.error, !error.isEmpty { return error }
        let tools = result.discoveredTools.prefix(6).map(\.name).joined(separator: ", ")
        if !tools.isEmpty { return tools }
        if let latency = result.latencyMs { return "\(Int(latency)) ms" }
        return "No tools reported."
    }

    private func discoverDetail(_ result: WorkspaceMCPDiscoverResponse) -> String {
        if let error = result.error, !error.isEmpty { return error }
        let tools = result.tools.prefix(8).map(\.name).joined(separator: ", ")
        return tools.isEmpty ? "No tools reported by discovery." : tools
    }

    private func logDetail(_ result: WorkspaceMCPLogsResponse) -> String {
        if !result.lines.isEmpty {
            return result.lines.suffix(12).joined(separator: "\n")
        }
        if let error = result.error, !error.isEmpty { return error }
        return "The shared logs endpoint opened, but no log lines were emitted before the desktop timeout."
    }

    private func registrySourceDetail(_ source: WorkspaceMCPHubSource) -> String {
        [
            source.url,
            source.format?.nilIfBlank.map { "format: \($0)" },
            source.builtin == true ? "built-in" : nil
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private func presetDetail(_ preset: WorkspaceMCPPreset) -> String {
        let template = preset.template
        let target = template?.url?.nilIfBlank ?? [template?.command, template?.args?.joined(separator: " ")]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " ")
            .nilIfBlank
        return [
            preset.description?.nilIfBlank,
            target,
            template?.transportType?.nilIfBlank.map { "transport: \($0)" }
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private func tint(_ status: String) -> Color {
        switch status.lowercased() {
        case "connected": return .green
        case "failed": return .orange
        default: return .secondary
        }
    }
}

private struct NativeMemoryKnowledgeFilesPanel: View {
    @EnvironmentObject private var appState: AppState

    @State private var tab = "memory"
    @State private var query = "Hermes Cael"
    @State private var memoryFiles: [WorkspaceMemoryFile] = []
    @State private var memoryMatches: [WorkspaceMemorySearchMatch] = []
    @State private var knowledgePages: [WorkspaceKnowledgePage] = []
    @State private var knowledgeMatches: [WorkspaceKnowledgeSearchMatch] = []
    @State private var selectedTitle = ""
    @State private var selectedPath = ""
    @State private var selectedContent = ""
    @State private var secondBrainSources: [WorkspaceSecondBrainSource] = []
    @State private var secondBrainSourceID = ""
    @State private var secondBrainFolder = ""
    @State private var secondBrainEntries: [WorkspaceSecondBrainEntry] = []
    @State private var secondBrainHash = ""
    @State private var secondBrainDispatchOperation = "ingest"
    @State private var secondBrainDispatchResponse: WorkspaceSecondBrainDispatchResponse?
    @State private var statusMessage: String?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var isDispatchingSecondBrainWorkflow = false

    private var activeSecondBrainSource: WorkspaceSecondBrainSource? {
        secondBrainSources.first { $0.id == secondBrainSourceID }
    }

    var body: some View {
        HermesSurfacePanel(
            title: "Memory / Knowledge Files",
            subtitle: "Native file-backed memory, wiki, and second-brain actions through the shared Workspace API."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Picker("Source", selection: $tab) {
                        Text("Memory").tag("memory")
                        Text("Knowledge").tag("knowledge")
                        Text("Second Brain").tag("second")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)

                    Button("Refresh") {
                        Task { await refreshActiveTab() }
                    }
                    .disabled(isLoading)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let statusMessage {
                    MirrorRow(title: "Status", detail: statusMessage, tint: statusMessage.lowercased().contains("error") ? .orange : .blue)
                }

                switch tab {
                case "knowledge":
                    knowledgeBody
                case "second":
                    secondBrainBody
                default:
                    memoryBody
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await refreshActiveTab()
        }
        .onChange(of: tab) { _, _ in
            Task { await refreshActiveTab() }
        }
    }

    private var memoryBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchRow(placeholder: "Search memory files")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(memoryFiles.prefix(8)) { file in
                    Button {
                        Task { await readMemory(file.path, title: file.name) }
                    } label: {
                        MirrorRow(title: file.name, detail: file.path, badge: formatBytes(file.size), tint: .blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !memoryMatches.isEmpty {
                resultRows(memoryMatches.map { ($0.path, "Line \($0.line)", $0.text) }) { path in
                    Task { await readMemory(path, title: path) }
                }
            }
            previewEditor(readOnly: true)
        }
    }

    private var knowledgeBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchRow(placeholder: "Search knowledge wiki")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(knowledgePages.prefix(8)) { page in
                    Button {
                        Task { await readKnowledge(page.path, title: page.title) }
                    } label: {
                        MirrorRow(title: page.title, detail: page.summary ?? page.path, badge: page.status ?? "wiki", tint: .purple)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !knowledgeMatches.isEmpty {
                resultRows(knowledgeMatches.map { ($0.path, $0.title, $0.text) }) { path in
                    Task { await readKnowledge(path, title: path) }
                }
            }
            previewEditor(readOnly: true)
        }
    }

    private var secondBrainBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Second Brain Source", selection: $secondBrainSourceID) {
                    ForEach(secondBrainSources) { source in
                        Text("\(source.label) (\(source.status))").tag(source.id)
                    }
                }
                .frame(maxWidth: 420)

                Button("Up") {
                    secondBrainFolder = parentPath(secondBrainFolder)
                    Task { await listSecondBrainEntries() }
                }
                .disabled(secondBrainFolder.isEmpty)

                Text("/\(secondBrainFolder)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let activeSecondBrainSource {
                MirrorRow(
                    title: activeSecondBrainSource.category.capitalized,
                    detail: activeSecondBrainSource.description,
                    badge: activeSecondBrainSource.writable ? "Writable" : "Read-only",
                    tint: activeSecondBrainSource.writable ? .green : .secondary
                )

                secondBrainDispatchControls(activeSecondBrainSource)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(secondBrainEntries.prefix(12)) { entry in
                    Button {
                        if entry.type == "folder" {
                            secondBrainFolder = entry.path
                            Task { await listSecondBrainEntries() }
                        } else {
                            Task { await readSecondBrain(entry.path) }
                        }
                    } label: {
                        MirrorRow(
                            title: entry.name,
                            detail: entry.ref,
                            badge: entry.type == "folder" ? "Folder" : formatBytes(entry.size ?? 0),
                            tint: entry.type == "folder" ? .cyan : .blue
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            previewEditor(readOnly: activeSecondBrainSource?.writable != true) {
                Task { await saveSecondBrain() }
            }
        }
        .onChange(of: secondBrainSourceID) { _, _ in
            secondBrainFolder = ""
            Task { await listSecondBrainEntries() }
        }
    }

    private func secondBrainDispatchControls(_ source: WorkspaceSecondBrainSource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Picker("Workflow", selection: $secondBrainDispatchOperation) {
                    Text("Ingest").tag("ingest")
                    Text("Update").tag("update")
                    Text("Reclass").tag("reclass")
                    Text("Reingest").tag("reingest")
                    Text("Rank").tag("rank")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Button {
                    Task { await dispatchSecondBrainWorkflow() }
                } label: {
                    Label(isDispatchingSecondBrainWorkflow ? "Dispatching" : "Dispatch Workflow", systemImage: "paperplane")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDispatchingSecondBrainWorkflow || source.status != "available")

                if isDispatchingSecondBrainWorkflow {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(selectedPath.isEmpty ? "Dispatches a source-level workflow through the server-side second-brain registry." : "Dispatch target: \(selectedPath)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let response = secondBrainDispatchResponse {
                MirrorRow(
                    title: response.status ?? "dispatch",
                    detail: secondBrainDispatchDetail(response),
                    badge: response.n8n?.configured == true ? "n8n" : "Dry run",
                    tint: response.ok ? .green : .orange
                )
            }
        }
    }

    private func searchRow(placeholder: String) -> some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await runSearch() }
                }
            Button("Search") {
                Task { await runSearch() }
            }
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func resultRows(_ rows: [(String, String, String)], onSelect: @escaping (String) -> Task<Void, Never>) -> some View {
        MirrorListCard(title: "Search Results", emptyText: "No search results.") {
            ForEach(Array(rows.prefix(8)), id: \.0) { row in
                Button {
                    _ = onSelect(row.0)
                } label: {
                    MirrorRow(title: row.1, detail: "\(row.0)\n\(preview(row.2, maxLength: 180))", tint: .green)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func previewEditor(readOnly: Bool, saveAction: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !selectedTitle.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTitle)
                            .font(.headline)
                        Text(selectedPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let saveAction, !readOnly {
                        Button(isSaving ? "Saving..." : "Save") {
                            saveAction()
                        }
                        .disabled(isSaving || secondBrainHash.isEmpty)
                    }
                }
                TextEditor(text: $selectedContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 260)
                    .disabled(readOnly)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )
            }
        }
    }

    private func refreshActiveTab() async {
        switch tab {
        case "knowledge":
            await loadKnowledgePages()
        case "second":
            await loadSecondBrainSources()
        default:
            await loadMemoryFiles()
        }
    }

    private func loadMemoryFiles() async {
        guard let connection = appState.activeConnection else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            memoryFiles = try await appState.caelWorkspaceAPIService.listMemoryFiles(connection: connection).files
            statusMessage = "Loaded \(memoryFiles.count) memory files."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func readMemory(_ path: String, title: String) async {
        guard let connection = appState.activeConnection else { return }
        do {
            let response = try await appState.caelWorkspaceAPIService.readMemoryFile(connection: connection, path: path)
            selectedTitle = title
            selectedPath = response.path ?? path
            selectedContent = response.content ?? ""
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func loadKnowledgePages() async {
        guard let connection = appState.activeConnection else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await appState.caelWorkspaceAPIService.listKnowledgePages(connection: connection)
            knowledgePages = response.pages
            if let root = response.knowledgeRoot?.nilIfBlank {
                statusMessage = "Loaded \(knowledgePages.count) knowledge pages from \(root)."
            } else {
                statusMessage = "Loaded \(knowledgePages.count) knowledge pages."
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func readKnowledge(_ path: String, title: String) async {
        guard let connection = appState.activeConnection else { return }
        do {
            let response = try await appState.caelWorkspaceAPIService.readKnowledgePage(connection: connection, path: path)
            selectedTitle = response.page?.title ?? title
            selectedPath = response.page?.path ?? path
            selectedContent = response.content ?? ""
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func runSearch() async {
        guard let connection = appState.activeConnection else { return }
        do {
            if tab == "knowledge" {
                knowledgeMatches = try await appState.caelWorkspaceAPIService.searchKnowledgePages(connection: connection, query: query).results
                statusMessage = "Found \(knowledgeMatches.count) knowledge matches."
            } else {
                memoryMatches = try await appState.caelWorkspaceAPIService.searchMemoryFiles(connection: connection, query: query).results
                statusMessage = "Found \(memoryMatches.count) memory matches."
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func loadSecondBrainSources() async {
        guard let connection = appState.activeConnection else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await appState.caelWorkspaceAPIService.listSecondBrainSources(connection: connection)
            secondBrainSources = response.sources ?? []
            if secondBrainSourceID.isEmpty {
                secondBrainSourceID = secondBrainSources.first(where: { $0.status == "available" })?.id ?? secondBrainSources.first?.id ?? ""
            }
            await listSecondBrainEntries()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func listSecondBrainEntries() async {
        guard let connection = appState.activeConnection, !secondBrainSourceID.isEmpty else { return }
        do {
            let response = try await appState.caelWorkspaceAPIService.listSecondBrainEntries(
                connection: connection,
                source: secondBrainSourceID,
                path: secondBrainFolder
            )
            secondBrainEntries = response.entries ?? []
            statusMessage = "Loaded \(secondBrainEntries.count) second-brain entries."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func readSecondBrain(_ path: String) async {
        guard let connection = appState.activeConnection, !secondBrainSourceID.isEmpty else { return }
        do {
            let response = try await appState.caelWorkspaceAPIService.readSecondBrainFile(
                connection: connection,
                source: secondBrainSourceID,
                path: path
            )
            selectedTitle = path
            selectedPath = response.path ?? path
            selectedContent = response.content ?? ""
            secondBrainHash = response.hash ?? ""
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func dispatchSecondBrainWorkflow() async {
        guard let connection = appState.activeConnection, !secondBrainSourceID.isEmpty else { return }
        isDispatchingSecondBrainWorkflow = true
        defer { isDispatchingSecondBrainWorkflow = false }
        do {
            let trimmedPath = selectedPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let hash = trimmedPath.isEmpty ? nil : secondBrainHash.nilIfBlank
            let response = try await appState.caelWorkspaceAPIService.dispatchSecondBrainWorkflow(
                connection: connection,
                source: secondBrainSourceID,
                path: trimmedPath.nilIfBlank,
                operation: secondBrainDispatchOperation,
                hash: hash
            )
            secondBrainDispatchResponse = response
            statusMessage = "Second-brain \(response.status ?? "dispatch") accepted for \(secondBrainDispatchOperation)."
        } catch {
            secondBrainDispatchResponse = nil
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func saveSecondBrain() async {
        guard let connection = appState.activeConnection, !secondBrainSourceID.isEmpty, !selectedPath.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await appState.caelWorkspaceAPIService.writeSecondBrainFile(
                connection: connection,
                source: secondBrainSourceID,
                path: selectedPath,
                content: selectedContent,
                expectedHash: secondBrainHash
            )
            secondBrainHash = response.hash ?? secondBrainHash
            statusMessage = "Saved second-brain file with hash guard."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func secondBrainDispatchDetail(_ response: WorkspaceSecondBrainDispatchResponse) -> String {
        let endpoint = response.n8n?.endpointLabel ?? "not configured"
        let idempotencyKey = response.idempotencyKey ?? "no idempotency key returned"
        return "Operation: \(response.operation ?? secondBrainDispatchOperation). Endpoint: \(endpoint). Idempotency: \(idempotencyKey)."
    }

    private func parentPath(_ value: String) -> String {
        guard let index = value.lastIndex(of: "/") else { return "" }
        return String(value[..<index])
    }

    private func formatBytes(_ size: Int) -> String {
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / (1024 * 1024))
    }

    private func preview(_ value: String, maxLength: Int) -> String {
        let normalized = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= maxLength { return normalized }
        let index = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return String(normalized[..<index]) + "..."
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
