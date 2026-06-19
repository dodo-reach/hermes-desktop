#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit

struct KanbanScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTask: KanbanMobileTask?

    var body: some View {
        List {
            workspaceSection
            kanbanContent
        }
        .navigationTitle("Kanban")
        .sheet(item: $selectedTask) { task in
            NavigationStack {
                KanbanTaskSheet(task: task)
                    .environmentObject(store)
            }
            .hermesKeyboardDismissal()
        }
        .task(id: "\(store.activeWorkspaceScopeFingerprint ?? "")|\(scenePhase)") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.refreshKanban()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .refreshable { await store.refreshKanban() }
    }

    private var workspaceSection: some View {
        Section {
            ActiveWorkspaceStrip(compact: true)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var kanbanContent: some View {
        if let snapshot = store.kanbanSnapshot {
            boardPicker(snapshot)
            warningSection(snapshot.warning)
            taskSections(snapshot)
        } else if store.isLoadingCompanion(.kanban) {
            Section {
                ProgressView("Loading Kanban…")
                    .frame(maxWidth: .infinity)
            }
        } else {
            Section {
                ContentUnavailableView(
                    "Kanban Unavailable",
                    systemImage: "rectangle.3.group",
                    description: Text("Pull to refresh after selecting a host.")
                )
            }
        }
    }

    @ViewBuilder
    private func boardPicker(_ snapshot: KanbanMobileSnapshot) -> some View {
        if snapshot.boards.count > 1 {
            Section {
                Picker("Board", selection: selectedBoardBinding) {
                    ForEach(snapshot.boards) { board in
                        Text(board.name).tag(board.slug)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func warningSection(_ warning: String?) -> some View {
        if let warning {
            Section {
                Text(warning).foregroundStyle(.secondary)
            }
        }
    }

    private func taskSections(_ snapshot: KanbanMobileSnapshot) -> some View {
        ForEach(groupedStatuses, id: \.self) { status in
            let tasks = snapshot.tasks.filter { $0.status == status }
            Section(status.replacingOccurrences(of: "_", with: " ").capitalized) {
                ForEach(tasks) { task in
                    Button {
                        selectedTask = task
                    } label: {
                        KanbanTaskRow(task: task)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedBoardBinding: Binding<String> {
        Binding(
            get: { store.selectedKanbanBoard },
            set: { value in
                Task { await store.selectKanbanBoard(value) }
            }
        )
    }

    private var groupedStatuses: [String] {
        let preferred = ["triage", "todo", "ready", "running", "blocked", "done", "archived"]
        let present = Set(store.kanbanSnapshot?.tasks.map(\.status) ?? [])
        return preferred.filter(present.contains) + present.filter { !preferred.contains($0) }.sorted()
    }
}

private struct KanbanTaskRow: View {
    let task: KanbanMobileTask

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(task.title).font(.headline).foregroundStyle(.primary)
            if let body = task.body, !body.isEmpty {
                Text(body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 6) {
                if let assignee = task.assignee { DetailBadge(title: assignee, tint: .blue) }
                DetailBadge(title: "P\(task.priority)", tint: .orange)
                if task.commentCount > 0 { DetailBadge(title: "\(task.commentCount) comments", tint: .secondary) }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct KanbanTaskSheet: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @Environment(\.dismiss) private var dismiss
    let task: KanbanMobileTask
    @State private var comment = ""
    @State private var assignee = ""

    var body: some View {
        List {
            Section {
                Text(task.title).font(.title3.weight(.semibold))
                if let body = task.body { Text(body).textSelection(.enabled) }
                LabeledContent("Status", value: task.status.capitalized)
                LabeledContent("Assignee", value: task.assignee ?? "Unassigned")
                LabeledContent("Priority", value: "\(task.priority)")
            }
            if !task.comments.isEmpty {
                Section("Comments") {
                    ForEach(task.comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(comment.author ?? "Comment").font(.caption.weight(.semibold))
                            Text(comment.body).textSelection(.enabled)
                        }
                    }
                }
            }
            Section("Safe Actions") {
                if task.status == "blocked" {
                    Button("Unblock") {
                        Task { await store.updateKanbanTask(task, status: "ready"); dismiss() }
                    }
                } else if !["done", "archived"].contains(task.status) {
                    Button("Block", role: .destructive) {
                        Task { await store.updateKanbanTask(task, status: "blocked"); dismiss() }
                    }
                    Button("Complete") {
                        Task { await store.updateKanbanTask(task, status: "done"); dismiss() }
                    }
                }

                TextField("Assignee (blank clears)", text: $assignee)
                    .textInputAutocapitalization(.never)
                Button("Update Assignee") {
                    Task { await store.updateKanbanTask(task, assignee: assignee); dismiss() }
                }

                TextField("Add comment", text: $comment, axis: .vertical)
                Button("Add Comment") {
                    let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    Task { await store.updateKanbanTask(task, comment: text); dismiss() }
                }
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { assignee = task.assignee ?? "" }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

struct HermesSettingsScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ActiveWorkspaceStrip(compact: true)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Connection") {
                NavigationLink {
                    ConnectionsScreen()
                } label: {
                    Label("Hosts", systemImage: "network")
                }
            }

            Section("Agents") {
                NavigationLink {
                    AgentManagementScreen()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Manage Agents")
                            Text("\(store.agentSummaries.count) on this host")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.2")
                    }
                }
            }

            Section("Current Agent") {
                ManagedAgentSummaryRow()

                NavigationLink {
                    GatewayManagerScreen()
                } label: {
                    Label("Gateway & Channels", systemImage: "antenna.radiowaves.left.and.right")
                }
                NavigationLink {
                    ConfigEditorScreen()
                } label: {
                    Label("Agent Settings", systemImage: "switch.2")
                }
                NavigationLink {
                    EnvironmentEditorScreen()
                } label: {
                    Label("Keys & Integrations", systemImage: "key")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task(id: store.activeWorkspaceScopeFingerprint) {
            await store.refreshOverview()
            await store.refreshProfiles()
            await store.refreshGateway()
        }
        .refreshable {
            await store.refreshOverview()
            await store.refreshProfiles()
            await store.refreshGateway()
        }
    }
}

private struct ManagedAgentSummaryRow: View {
    @EnvironmentObject private var store: HermesPhoneStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent?.name ?? store.activeConnection?.resolvedHermesProfileName ?? "No agent")
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let agent {
                Circle()
                    .fill(agent.gatewayRunning ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 9, height: 9)
                    .accessibilityLabel(agent.gatewayRunning ? "Gateway running" : "Gateway stopped")
            }
        }
        .padding(.vertical, 3)
    }

    private var agent: HermesAgentSummary? {
        let name = store.activeConnection?.resolvedHermesProfileName
        return store.agentSummaries.first { $0.name == name }
    }

    private var summary: String {
        guard let agent else { return "Select a host and agent" }
        if let model = agent.model, !model.isEmpty {
            return agent.provider.map { "\(model) · \($0)" } ?? model
        }
        return agent.description?.nilIfBlank ?? "Ready to configure"
    }
}

private struct GatewayManagerScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @State private var pendingAction: GatewayLifecycleAction?

    var body: some View {
        List {
            if let snapshot = store.gatewaySnapshot {
                Section("Gateway") {
                    LabeledContent("Profile", value: snapshot.profileName)
                    LabeledContent("State", value: gatewayState(snapshot))
                    if let processID = snapshot.processID {
                        LabeledContent("Process", value: "\(processID)")
                    }
                    LabeledContent("Manager", value: snapshot.manager ?? "Not detected")
                    if let status = snapshot.serviceStatus { Text(status).font(.caption.monospaced()).textSelection(.enabled) }
                    if let error = snapshot.lastError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }

                Section("Lifecycle") {
                    ForEach(GatewayLifecycleAction.allCases) { action in
                        Button(action.title, role: action.isDestructive ? .destructive : nil) {
                            pendingAction = action
                        }
                        .disabled(!snapshot.lifecycleAvailable || store.isLoadingCompanion(.gateway))
                    }
                    if !snapshot.lifecycleAvailable {
                        Text("This CLI version is monitoring-only because lifecycle commands could not be verified.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Channels") {
                    if snapshot.channels.isEmpty {
                        Text("No configured channels were discovered. Secret values are never returned to the phone.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.channels) { channel in
                        NavigationLink {
                            GatewayChannelDetailScreen(channelID: channel.id)
                        } label: {
                            GatewayChannelRow(channel: channel)
                        }
                    }
                }
            } else {
                ProgressView("Checking gateway…").frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Gateway")
        .task(id: store.activeWorkspaceScopeFingerprint) {
            await store.refreshGateway()
        }
        .refreshable { await store.refreshGateway() }
        .confirmationDialog(
            pendingAction.map { "\($0.title) gateway?" } ?? "Gateway action",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
        ) {
            if let action = pendingAction {
                Button(action.title, role: action.isDestructive ? .destructive : nil) {
                    pendingAction = nil
                    Task { await store.performGatewayAction(action) }
                }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text("Hermes CLI will perform the profile-scoped action. The phone never calls the host supervisor directly.")
        }
    }

    private func gatewayState(_ snapshot: GatewaySnapshot) -> String {
        if let state = snapshot.state?.replacingOccurrences(of: "_", with: " "), !state.isEmpty {
            return state.capitalized
        }
        return snapshot.running.map { $0 ? "Running" : "Stopped" } ?? "Unknown"
    }
}

private struct GatewayChannelDetailScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    let channelID: String
    @State private var values: [String: String] = [:]
    @State private var clearKeys: Set<String> = []
    @State private var enabled = false
    @State private var showsAdvanced = false
    @State private var restartPrompt = false

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $enabled)
                if let description = channel.description?.nilIfBlank {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Status", value: channelStateTitle)
            }

            Section("Credentials") {
                ForEach(visibleCredentials) { credential in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(credential.prompt)
                                .font(.subheadline.weight(.semibold))
                            if credential.required {
                                Text("Required")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            if credential.isSet && !clearKeys.contains(credential.key) {
                                Label("Set", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        if credential.isPassword {
                            SecureField(
                                credential.isSet ? "New value (keeps current if blank)" : "Value",
                                text: valueBinding(for: credential.key)
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        } else {
                            TextField(
                                credential.isSet ? "New value (keeps current if blank)" : "Value",
                                text: valueBinding(for: credential.key)
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        }
                        if let description = credential.description?.nilIfBlank {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if credential.isSet {
                            Button(
                                clearKeys.contains(credential.key) ? "Keep Existing Value" : "Clear Existing Value",
                                role: clearKeys.contains(credential.key) ? nil : .destructive
                            ) {
                                if clearKeys.contains(credential.key) {
                                    clearKeys.remove(credential.key)
                                } else {
                                    clearKeys.insert(credential.key)
                                    values[credential.key] = ""
                                }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if channel.credentials.contains(where: \.isAdvanced) {
                    Toggle("Show advanced fields", isOn: $showsAdvanced)
                }
                if channel.credentials.isEmpty {
                    Text("This channel has no editable credential metadata in the installed Hermes version.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Save Channel") {
                    Task {
                        let submittedValues = values.filter {
                            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                !clearKeys.contains($0.key)
                        }
                        if await store.updateGatewayChannel(
                            id: channel.id,
                            enabled: enabled,
                            values: submittedValues,
                            clearKeys: Array(clearKeys)
                        ) {
                            values = [:]
                            clearKeys = []
                            restartPrompt = true
                        }
                    }
                }
                .disabled(store.isLoadingCompanion(.gateway))
            } footer: {
                Text("Secret values are sent directly over SSH and written to this agent’s .env. They are never read back, cached, or displayed by HermesPhone.")
            }
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: channelID) {
            enabled = channel.enabled
        }
        .alert("Channel saved", isPresented: $restartPrompt) {
            Button("Restart gateway now") {
                Task { await store.performGatewayAction(.restart) }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The running gateway must restart before channel changes take effect.")
        }
    }

    private var channel: GatewayChannel {
        store.gatewaySnapshot?.channels.first { $0.id == channelID } ??
            GatewayChannel(
                id: channelID,
                name: channelID.replacingOccurrences(of: "_", with: " ").capitalized,
                description: nil,
                enabled: false,
                configured: false,
                state: "unknown",
                errorMessage: nil,
                updatedAt: nil,
                credentials: []
            )
    }

    private var visibleCredentials: [GatewayChannelCredential] {
        channel.credentials.filter { showsAdvanced || !$0.isAdvanced || $0.isSet }
    }

    private var channelStateTitle: String {
        channel.state.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func valueBinding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: {
                values[key] = $0
                if !$0.isEmpty {
                    clearKeys.remove(key)
                }
            }
        )
    }
}

private struct GatewayChannelRow: View {
    let channel: GatewayChannel

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(channel.name)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(channel.errorMessage == nil ? .secondary : Color.red)
                if let error = channel.errorMessage?.nilIfBlank {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: statusIconName)
                .foregroundStyle(statusColor)
        }
    }

    private var statusText: String {
        switch channel.state {
        case "connected": "Connected"
        case "pending_restart": "Configured · restart required"
        case "gateway_stopped": "Configured · gateway stopped"
        case "startup_failed": "Startup failed"
        case "not_configured": "Setup required"
        case "disabled": "Disabled"
        default:
            channel.configured ? channel.state.replacingOccurrences(of: "_", with: " ").capitalized : "Setup required"
        }
    }

    private var statusIconName: String {
        switch channel.state {
        case "connected": "checkmark.circle.fill"
        case "startup_failed": "exclamationmark.triangle.fill"
        case "pending_restart": "arrow.clockwise.circle"
        case "gateway_stopped": "stop.circle"
        case "disabled": "pause.circle"
        default: channel.configured ? "checkmark.circle" : "plus.circle"
        }
    }

    private var statusColor: Color {
        switch channel.state {
        case "connected": .green
        case "startup_failed": .red
        case "pending_restart": .orange
        default: .secondary
        }
    }
}

private enum AgentManagementSheet: Identifiable {
    case create
    case rename(HermesAgentSummary)
    case describe(HermesAgentSummary)
    case soul(HermesAgentSummary)
    case delete(HermesAgentSummary)

    var id: String {
        switch self {
        case .create: "create"
        case .rename(let agent): "rename:\(agent.name)"
        case .describe(let agent): "describe:\(agent.name)"
        case .soul(let agent): "soul:\(agent.name)"
        case .delete(let agent): "delete:\(agent.name)"
        }
    }
}

private struct AgentManagementScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @State private var presentedSheet: AgentManagementSheet?

    var body: some View {
        List {
            Section {
                Text("Agents are isolated Hermes profiles. Each has its own model, identity, keys, skills, conversations, channels, and gateway.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("On This Host") {
                ForEach(store.agentSummaries) { agent in
                    NavigationLink {
                        AgentDetailScreen(agentName: agent.name)
                    } label: {
                        AgentSummaryRow(agent: agent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !agent.isDefault && !agent.isActive && store.profileSnapshot?.canDelete != false {
                            Button("Delete", role: .destructive) {
                                presentedSheet = .delete(agent)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Edit Description") { presentedSheet = .describe(agent) }
                        if !agent.isDefault && store.profileSnapshot?.canRename != false {
                            Button("Rename") { presentedSheet = .rename(agent) }
                        }
                        if !agent.isActive {
                            Button("Use Agent") {
                                Task { await store.switchHermesProfile(to: agent.name) }
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    presentedSheet = .create
                } label: {
                    Label("Create Agent", systemImage: "plus")
                }
                .disabled(store.profileSnapshot?.canCreate == false)
            }
        }
        .navigationTitle("Agents")
        .task(id: store.activeWorkspaceScopeFingerprint) {
            await store.refreshProfiles()
        }
        .refreshable { await store.refreshProfiles() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentedSheet = .create
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(store.activeConnection == nil || store.profileSnapshot?.canCreate == false)
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .create:
                AgentCreateSheet()
                    .environmentObject(store)
            case .rename(let agent):
                AgentRenameSheet(agent: agent)
                    .environmentObject(store)
            case .describe(let agent):
                AgentDescriptionSheet(agent: agent)
                    .environmentObject(store)
            case .soul(let agent):
                AgentSoulSheet(agent: agent)
                    .environmentObject(store)
            case .delete(let agent):
                AgentDeleteSheet(agent: agent)
                    .environmentObject(store)
            }
        }
    }
}

private struct AgentSummaryRow: View {
    let agent: HermesAgentSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: agent.isDefault ? "brain" : "brain.head.profile")
                .foregroundStyle(agent.isActive ? Color.accentColor : Color.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(agent.name)
                        .font(.headline)
                    if agent.isActive {
                        Text("Current")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                if let description = agent.description?.nilIfBlank {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let model = agent.model?.nilIfBlank {
                        Label(model, systemImage: "sparkles")
                    }
                    Label("\(agent.skillCount)", systemImage: "puzzlepiece.extension")
                    Label(
                        agent.gatewayRunning ? "On" : "Off",
                        systemImage: agent.gatewayRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
                    )
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AgentDetailScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @State private var managedAgentName: String
    @State private var presentedSheet: AgentManagementSheet?

    init(agentName: String) {
        _managedAgentName = State(initialValue: agentName)
    }

    var body: some View {
        List {
            Section {
                AgentSummaryRow(agent: agent)
                if !agent.isActive {
                    ProgressView("Switching to \(agent.name)…")
                }
            }

            Section("Identity") {
                Button("Edit Description") { presentedSheet = .describe(agent) }
                Button("Edit SOUL.md") { presentedSheet = .soul(agent) }
                    .disabled(!agent.isActive)
                if !agent.isDefault && store.profileSnapshot?.canRename != false {
                    Button("Rename Agent") { presentedSheet = .rename(agent) }
                }
            }

            Section("Configuration") {
                NavigationLink {
                    ConfigEditorScreen()
                } label: {
                    Label("Behavior & Model", systemImage: "switch.2")
                }
                .disabled(!agent.isActive)
                NavigationLink {
                    EnvironmentEditorScreen()
                } label: {
                    Label("Keys & Integrations", systemImage: "key")
                }
                .disabled(!agent.isActive)
                NavigationLink {
                    GatewayManagerScreen()
                } label: {
                    Label("Gateway & Channels", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(!agent.isActive)
                NavigationLink {
                    SkillsScreen()
                } label: {
                    Label("Skills", systemImage: "book.closed")
                }
                .disabled(!agent.isActive)
            }

            Section {
                Text("Changes on this screen apply only to \(agent.name). Other agents on this host remain isolated.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: managedAgentName) {
            if store.activeConnection?.resolvedHermesProfileName != managedAgentName {
                await store.switchHermesProfile(to: managedAgentName)
            }
            await store.refreshProfiles()
            await store.refreshGateway()
        }
        .onChange(of: store.activeConnection?.resolvedHermesProfileName) { previousName, activeName in
            guard let activeName, previousName == managedAgentName else { return }
            managedAgentName = activeName
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .rename(let agent):
                AgentRenameSheet(agent: agent).environmentObject(store)
            case .describe(let agent):
                AgentDescriptionSheet(agent: agent).environmentObject(store)
            case .soul(let agent):
                AgentSoulSheet(agent: agent).environmentObject(store)
            case .create:
                AgentCreateSheet().environmentObject(store)
            case .delete(let agent):
                AgentDeleteSheet(agent: agent).environmentObject(store)
            }
        }
    }

    private var agent: HermesAgentSummary {
        store.agentSummaries.first { $0.name == managedAgentName } ??
            HermesAgentSummary(
                name: managedAgentName,
                path: "",
                isDefault: managedAgentName == "default",
                isActive: store.activeConnection?.resolvedHermesProfileName == managedAgentName,
                gatewayRunning: false,
                model: nil,
                provider: nil,
                hasEnvironment: false,
                skillCount: 0,
                description: nil,
                descriptionIsAutomatic: false,
                soul: nil
            )
    }
}

private struct AgentCreateSheet: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var mode: AgentCreationMode = .cloneCurrent

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("What is this agent good at?", text: $description, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                Section("Starting Point") {
                    Picker("Create", selection: $mode) {
                        ForEach(AgentCreationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text(mode == .cloneCurrent
                         ? "Copies the current agent’s configuration, keys, identity, and skills into an isolated profile."
                         : "Creates a clean profile with Hermes’ bundled skills and default identity.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await store.createRemoteProfile(
                                named: normalizedName,
                                description: description,
                                mode: mode
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isValidName || store.isLoadingCompanion(.profiles))
                }
            }
        }
        .hermesKeyboardDismissal()
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isValidName: Bool {
        normalizedName.range(of: #"^[a-z0-9][a-z0-9_-]{0,63}$"#, options: .regularExpression) != nil &&
            normalizedName != "default"
    }
}

private struct AgentRenameSheet: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @Environment(\.dismiss) private var dismiss
    let agent: HermesAgentSummary
    @State private var name: String

    init(agent: HermesAgentSummary) {
        self.agent = agent
        _name = State(initialValue: agent.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Agent name", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Renaming also updates the profile alias and stops its gateway before moving the profile.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Rename Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        Task {
                            if await store.renameRemoteProfile(named: agent.name, to: normalizedName) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isValidName || normalizedName == agent.name || store.isLoadingCompanion(.profiles))
                }
            }
        }
        .hermesKeyboardDismissal()
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isValidName: Bool {
        normalizedName.range(of: #"^[a-z0-9][a-z0-9_-]{0,63}$"#, options: .regularExpression) != nil &&
            normalizedName != "default"
    }
}

private struct AgentDescriptionSheet: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @Environment(\.dismiss) private var dismiss
    let agent: HermesAgentSummary
    @State private var description: String

    init(agent: HermesAgentSummary) {
        self.agent = agent
        _description = State(initialValue: agent.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What is this agent good at?", text: $description, axis: .vertical)
                    .lineLimit(3 ... 8)
                Text("Hermes uses this description when routing Kanban work between agents.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Agent Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await store.updateRemoteProfileDescription(
                                named: agent.name,
                                description: description
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(store.isLoadingCompanion(.profiles))
                }
            }
        }
        .hermesKeyboardDismissal()
    }
}

private struct AgentSoulSheet: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @Environment(\.dismiss) private var dismiss
    let agent: HermesAgentSummary
    @State private var content: String

    init(agent: HermesAgentSummary) {
        self.agent = agent
        _content = State(initialValue: agent.soul ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("SOUL.md defines this agent’s voice, temperament, and enduring identity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
            .navigationTitle("SOUL.md")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await store.updateRemoteProfileSoul(named: agent.name, content: content) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(store.isLoadingCompanion(.profiles))
                }
            }
        }
        .hermesKeyboardDismissal()
    }
}

private struct AgentDeleteSheet: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @Environment(\.dismiss) private var dismiss
    let agent: HermesAgentSummary
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently removes \(agent.name)’s config, keys, memories, sessions, skills, cron jobs, alias, and managed gateway service.")
                    TextField("Type \(agent.name)", text: $confirmation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("Delete \(agent.name)", role: .destructive) {
                        dismiss()
                        Task { await store.deleteRemoteProfile(named: agent.name) }
                    }
                    .disabled(confirmation != agent.name)
                }
            }
            .navigationTitle("Delete Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .hermesKeyboardDismissal()
    }
}

private struct ConfigEditorScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @State private var fields: [ConfigField] = []
    @State private var query = ""
    @State private var restartPrompt = false

    var body: some View {
        List {
            Section {
                Label {
                    Text("These settings shape how Hermes thinks, delegates, remembers, speaks, and runs tools. They are grouped by intent so you can change one part without wading through the whole config file.")
                } icon: {
                    Image(systemName: "switch.2")
                        .foregroundStyle(.tint)
                }
                .font(.subheadline)
            }

            if isSearching {
                searchResults
            } else {
                categorySections
            }

            saveSection
        }
        .navigationTitle("Agent Settings")
        .searchable(text: $query, prompt: "Search settings and descriptions")
        .task(id: store.activeWorkspaceScopeFingerprint) {
            await store.refreshConfig()
        }
        .task(id: store.configSnapshot?.contentHash) {
            fields = store.configSnapshot?.fields ?? []
        }
        .refreshable { await store.refreshConfig() }
        .alert("Config saved", isPresented: $restartPrompt) {
            Button("Restart gateway now", role: .destructive) {
                Task { await store.performGatewayAction(.restart) }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The save was atomic. Restart only if the changed fields affect the running gateway.")
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var orderedCategories: [String] {
        let available = Set(fields.map(\.category))
        let preferred = store.configSnapshot?.categoryOrder ?? []
        return preferred.filter(available.contains) + available.filter { !preferred.contains($0) }.sorted()
    }

    private var categorySections: some View {
        ForEach(ConfigCategoryGroup.allCases) { group in
            let categories = orderedCategories.filter {
                ConfigCategoryPresentation(category: $0).group == group
            }
            if !categories.isEmpty {
                Section {
                    ForEach(categories, id: \.self) { category in
                        NavigationLink {
                            ConfigCategoryScreen(category: category, fields: $fields)
                        } label: {
                            ConfigCategoryRow(
                                presentation: ConfigCategoryPresentation(category: category),
                                count: fields.lazy.filter { $0.category == category }.count
                            )
                        }
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if let footer = group.footer {
                        Text(footer)
                    }
                }
            }
        }
    }

    private var searchResults: some View {
        Section("Results") {
            if matchingFieldIndices.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(matchingFieldIndices, id: \.self) { index in
                    NavigationLink {
                        ConfigSingleFieldScreen(field: $fields[index])
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fields[index].title)
                            Text(ConfigCategoryPresentation(category: fields[index].category).title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let description = fields[index].description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }

    private var saveSection: some View {
        Section("Applying Changes") {
            Text("New CLI chats use saved settings on their next session. Gateway conversations use them for new sessions; restart the gateway only when you need its running process to reload immediately.")
            Button("Save Config") {
                Task {
                    if await store.saveConfig(fields) {
                        restartPrompt = true
                    }
                }
            }
            .disabled(store.isLoadingCompanion(.config) || fields.isEmpty)
        }
    }

    private var matchingFieldIndices: [Int] {
        fields.indices.filter { index in
            matches(fields[index])
        }
    }

    private func matches(_ field: ConfigField) -> Bool {
        query.isEmpty ||
            field.path.localizedCaseInsensitiveContains(query) ||
            field.title.localizedCaseInsensitiveContains(query) ||
            field.category.localizedCaseInsensitiveContains(query) ||
            (field.description?.localizedCaseInsensitiveContains(query) ?? false)
    }
}

private enum ConfigCategoryGroup: String, CaseIterable, Identifiable {
    case essentials
    case capabilities
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .essentials: "Everyday Behavior"
        case .capabilities: "Capabilities"
        case .advanced: "Advanced"
        }
    }

    var footer: String? {
        switch self {
        case .essentials:
            "The settings most likely to change how Hermes behaves in normal conversations."
        case .capabilities:
            "Specialized systems that are useful when you have configured the corresponding providers or workflows."
        case .advanced:
            "Operational tuning. Leave these at their defaults unless you know why you need them."
        }
    }
}

private struct ConfigCategoryPresentation {
    let category: String

    var title: String {
        switch category {
        case "general": "Model & Defaults"
        case "agent": "Agent Behavior"
        case "delegation": "Delegation"
        case "memory": "Memory"
        case "compression": "Context & Compression"
        case "security": "Safety & Approvals"
        case "voice": "Voice"
        case "tts": "Text to Speech"
        case "stt": "Speech to Text"
        case "terminal": "Terminal Execution"
        case "browser": "Browser"
        case "discord": "Gateway Conversations"
        case "auxiliary": "Auxiliary Models"
        case "kanban": "Kanban"
        case "display": "CLI & Dashboard Display"
        case "logging": "Logging"
        default:
            category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var subtitle: String {
        switch category {
        case "general": "Default model, timezone, toolsets, and global choices"
        case "agent": "Turn limits, timeouts, goals, and core behavior"
        case "delegation": "How Hermes creates and coordinates subagents"
        case "memory": "Persistent memory provider and context injection"
        case "compression": "How long conversations are condensed"
        case "security": "Dangerous-command approval and privacy boundaries"
        case "voice", "tts", "stt": "Speech input, output, and voice behavior"
        case "terminal": "Where commands run and how shells behave"
        case "browser": "Browser engine and web automation behavior"
        case "discord": "Shared-chat and gateway conversation behavior"
        case "auxiliary": "Models used for vision, summaries, and helper tasks"
        case "kanban": "Dispatcher and autonomous task behavior"
        case "display": "Visual preferences for terminal-facing surfaces"
        case "logging": "Diagnostic detail and log retention"
        default: "Less frequently changed Hermes settings"
        }
    }

    var systemImage: String {
        switch category {
        case "general": "sparkles"
        case "agent": "brain.head.profile"
        case "delegation": "person.3.sequence"
        case "memory": "memorychip"
        case "compression": "arrow.down.right.and.arrow.up.left"
        case "security": "checkmark.shield"
        case "voice", "tts", "stt": "waveform"
        case "terminal": "terminal"
        case "browser": "globe"
        case "discord": "bubble.left.and.bubble.right"
        case "auxiliary": "square.stack.3d.up"
        case "kanban": "rectangle.3.group"
        case "display": "paintpalette"
        case "logging": "doc.text.magnifyingglass"
        default: "slider.horizontal.3"
        }
    }

    var group: ConfigCategoryGroup {
        switch category {
        case "general", "agent", "delegation", "memory", "compression", "security":
            .essentials
        case "voice", "tts", "stt", "browser", "auxiliary", "kanban", "discord":
            .capabilities
        default:
            .advanced
        }
    }
}

private struct ConfigCategoryRow: View {
    let presentation: ConfigCategoryPresentation
    let count: Int

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(presentation.title)
                    Spacer()
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(presentation.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: presentation.systemImage)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 3)
    }
}

private struct ConfigCategoryScreen: View {
    let category: String
    @Binding var fields: [ConfigField]

    var body: some View {
        List {
            Section {
                Text(presentation.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(matchingIndices, id: \.self) { index in
                    ConfigFieldEditor(field: $fields[index])
                }
            }

            Section {
                Button("Restore This Section to Defaults") {
                    for index in matchingIndices {
                        guard let defaultValue = fields[index].defaultValue else { continue }
                        fields[index] = fields[index].replacingValue(defaultValue)
                    }
                }
            } footer: {
                Text("Restoring only changes the draft. Use Save Config on the previous screen to write it to the host.")
            }
        }
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var presentation: ConfigCategoryPresentation {
        ConfigCategoryPresentation(category: category)
    }

    private var matchingIndices: [Int] {
        fields.indices.filter { fields[$0].category == category }
    }
}

private struct ConfigSingleFieldScreen: View {
    @Binding var field: ConfigField

    var body: some View {
        Form {
            Section {
                ConfigFieldEditor(field: $field)
            }
        }
        .navigationTitle(field.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConfigFieldEditor: View {
    @Binding var field: ConfigField

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.title)
                .font(.subheadline.weight(.semibold))
            if let description = field.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            editor
            Text(field.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var editor: some View {
        switch field.kind {
        case "bool":
            Toggle("Enabled", isOn: Binding(get: { field.value.boolValue ?? false }, set: { replace(.bool($0)) }))
        case "number":
            TextField("Number", value: Binding(get: { field.value.numberValue }, set: { value in
                if let value { replace(.number(value)) }
            }), format: .number)
                .keyboardType(.decimalPad)
        case "list", "object":
            NavigationLink {
                StructuredConfigValueEditor(field: $field)
            } label: {
                HStack {
                    Text(field.kind == "list" ? "Edit List" : "Edit Structured Value")
                    Spacer()
                    Text(structuredSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        default:
            if !field.enumValues.isEmpty {
                Picker("Value", selection: Binding(get: { field.value.stringValue ?? "" }, set: { replace(.string($0)) })) {
                    ForEach(field.enumValues, id: \.self) { Text($0).tag($0) }
                }
            } else {
                TextField("Value", text: Binding(get: { field.value.stringValue ?? "" }, set: { replace(.string($0)) }))
            }
        }
    }

    private func replace(_ value: JSONValue) {
        field = field.replacingValue(value)
    }

    private var structuredSummary: String {
        switch field.value {
        case .array(let values): "\(values.count) items"
        case .object(let values): "\(values.count) keys"
        default: "JSON"
        }
    }
}

private struct StructuredConfigValueEditor: View {
    @Binding var field: ConfigField
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var validationMessage: String?

    init(field: Binding<ConfigField>) {
        _field = field
        _draft = State(initialValue: field.wrappedValue.value.displayString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit this value as JSON. It is validated before the draft setting is replaced.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle(field.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") { apply() }
            }
        }
    }

    private func apply() {
        guard let data = draft.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            validationMessage = "Enter valid JSON before applying."
            return
        }
        field = field.replacingValue(value)
        dismiss()
    }
}

private struct EnvironmentEditorScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @State private var selected: EnvironmentVariableStatus?
    @State private var query = ""
    @State private var showsAdvanced = false
    @State private var filter: EnvironmentFilter = .configured

    var body: some View {
        List {
            Section {
                Text("Keys unlock model providers, tools, skills, and gateway integrations. Existing secret values stay on the host; HermesPhone only knows whether each one is configured.")
                    .font(.subheadline)
            }

            Section {
                Picker("Show", selection: $filter) {
                    ForEach(EnvironmentFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show advanced variables", isOn: $showsAdvanced)
            }

            ForEach(groupedSections) { group in
                Section {
                    ForEach(group.variables) { variable in
                        Button {
                            selected = variable
                        } label: {
                            EnvironmentVariableRow(variable: variable)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label(group.title, systemImage: group.systemImage)
                } footer: {
                    if let footer = group.footer {
                        Text(footer)
                    }
                }
            }

            if groupedSections.isEmpty {
                ContentUnavailableView(
                    "No Matching Keys",
                    systemImage: "key.slash",
                    description: Text(filter == .configured ? "Switch to All to browse keys you can configure." : "Try another search.")
                )
            }

            Section {
                Text("Existing values are never fetched, displayed, logged, cached, or persisted. Blank input keeps the current value; Clear is explicit.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("A running CLI may use /reload. A running gateway generally needs an explicit restart.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Keys & Integrations")
        .searchable(text: $query, prompt: "Search providers, tools, and keys")
        .task(id: store.activeWorkspaceScopeFingerprint) {
            await store.refreshEnvironment()
        }
        .refreshable { await store.refreshEnvironment() }
        .sheet(item: $selected) { variable in
            EnvironmentValueSheet(variable: variable)
                .environmentObject(store)
        }
    }

    private var filteredVariables: [EnvironmentVariableStatus] {
        (store.environmentSnapshot?.variables ?? []).filter { variable in
            let passesConfigured = filter == .all || variable.isSet
            let passesAdvanced = showsAdvanced || !variable.isAdvanced || variable.isSet
            let passesSearch = query.isEmpty ||
                variable.name.localizedCaseInsensitiveContains(query) ||
                variable.category.localizedCaseInsensitiveContains(query) ||
                (variable.description?.localizedCaseInsensitiveContains(query) ?? false) ||
                variable.tools.contains { $0.localizedCaseInsensitiveContains(query) }
            return passesConfigured && passesAdvanced && passesSearch
        }
    }

    private var groupedSections: [EnvironmentVariableGroup] {
        Dictionary(grouping: filteredVariables, by: EnvironmentVariableGroup.groupingKey)
            .map { EnvironmentVariableGroup(key: $0.key, variables: $0.value) }
            .sorted()
    }
}

private enum EnvironmentFilter: String, CaseIterable, Identifiable {
    case configured
    case all

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct EnvironmentVariableGroup: Identifiable, Comparable {
    let key: String
    let variables: [EnvironmentVariableStatus]

    var id: String { key }

    init(key: String, variables: [EnvironmentVariableStatus]) {
        self.key = key
        self.variables = variables.sorted {
            if $0.isSet != $1.isSet { return $0.isSet }
            return $0.name < $1.name
        }
    }

    static func groupingKey(_ variable: EnvironmentVariableStatus) -> String {
        if variable.category == "provider" {
            return "provider:\(providerName(for: variable.name))"
        }
        return variable.category
    }

    var title: String {
        if key.hasPrefix("provider:") {
            return String(key.dropFirst("provider:".count))
        }
        return switch key {
        case "tool": "Tools"
        case "skill": "Skill Integrations"
        case "messaging": "Gateway Channels"
        case "setting": "Runtime Settings"
        default: key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var systemImage: String {
        if key.hasPrefix("provider:") { return "sparkles" }
        return switch key {
        case "tool": "wrench.and.screwdriver"
        case "skill": "puzzlepiece.extension"
        case "messaging": "bubble.left.and.bubble.right"
        case "setting": "gearshape.2"
        default: "key"
        }
    }

    var footer: String? {
        key == "messaging" ? "Gateway credentials normally need a gateway restart after replacement." : nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let lhsRank = rank(lhs.key)
        let rhsRank = rank(rhs.key)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.title < rhs.title
    }

    private static func rank(_ key: String) -> Int {
        if key.hasPrefix("provider:") { return 0 }
        return switch key {
        case "tool": 1
        case "skill": 2
        case "messaging": 3
        case "setting": 4
        default: 5
        }
    }

    private static func providerName(for name: String) -> String {
        let prefixes: [(String, String)] = [
            ("NOUS_", "Nous Portal"),
            ("ANTHROPIC_", "Anthropic"),
            ("OPENAI_", "OpenAI"),
            ("OPENROUTER_", "OpenRouter"),
            ("GOOGLE_", "Gemini"),
            ("GEMINI_", "Gemini"),
            ("GLM_", "GLM / Z.AI"),
            ("ZAI_", "GLM / Z.AI"),
            ("Z_AI_", "GLM / Z.AI"),
            ("KIMI_", "Kimi / Moonshot"),
            ("MINIMAX_CN_", "MiniMax China"),
            ("MINIMAX_", "MiniMax"),
            ("DEEPSEEK_", "DeepSeek"),
            ("DASHSCOPE_", "DashScope / Qwen"),
            ("HERMES_QWEN_", "DashScope / Qwen"),
            ("HF_", "Hugging Face"),
            ("OPENCODE_", "OpenCode"),
            ("XAI_", "xAI"),
            ("NVIDIA_", "NVIDIA NIM"),
            ("OLLAMA_", "Ollama"),
            ("AWS_", "AWS Bedrock"),
            ("AZURE_", "Azure"),
        ]
        return prefixes.first(where: { name.hasPrefix($0.0) })?.1 ?? "Other Providers"
    }
}

private struct EnvironmentVariableRow: View {
    let variable: EnvironmentVariableStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(variable.name).font(.body.monospaced())
                if let description = variable.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: variable.isSet ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(variable.isSet ? Color.green : Color.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct EnvironmentValueSheet: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @Environment(\.dismiss) private var dismiss
    let variable: EnvironmentVariableStatus
    @State private var value = ""
    @State private var restartPrompt = false

    var body: some View {
        NavigationStack {
            Form {
                SecureField("New value (blank keeps existing)", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let description = variable.description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Save") {
                    Task {
                        if value.isEmpty { dismiss(); return }
                        if await store.updateEnvironment(name: variable.name, value: value, clear: false) {
                            value = ""
                            restartPrompt = true
                        }
                    }
                }
                Button("Clear", role: .destructive) {
                    Task {
                        if await store.updateEnvironment(name: variable.name, value: nil, clear: true) { dismiss() }
                    }
                }
            }
            .navigationTitle(variable.name)
            .toolbar { Button("Cancel") { dismiss() } }
            .alert("Environment updated", isPresented: $restartPrompt) {
                Button("Restart gateway now", role: .destructive) {
                    dismiss()
                    Task { await store.performGatewayAction(.restart) }
                }
                Button("Later", role: .cancel) { dismiss() }
            } message: {
                Text("The .env file was updated atomically with mode 0600.")
            }
            .hermesKeyboardDismissal()
        }
    }
}

private extension ConfigField {
    func replacingValue(_ value: JSONValue) -> ConfigField {
        ConfigField(
            path: path,
            title: title,
            category: category,
            description: description,
            kind: kind,
            enumValues: enumValues,
            value: value,
            defaultValue: defaultValue
        )
    }
}
#endif
