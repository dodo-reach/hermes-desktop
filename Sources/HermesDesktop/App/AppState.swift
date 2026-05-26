import Combine
import Foundation
import SwiftUI

private enum PendingSectionEntryAction {
    case openNewConnectionEditor
    case prepareNewSessionComposer
    case openNewTerminalTab(ConnectionProfile)
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSection: AppSection = .connections
    @Published var activeAlert: AppAlert?
    @Published var isBusy = false
    @Published var statusMessage: String?
    @Published var overview: RemoteDiscovery?
    @Published var overviewError: String?
    @Published var isRefreshingOverview = false
    @Published var activeConnectionID: UUID?
    @Published var selectedSessionID: String?
    @Published var selectedSessionDetailMode: SessionDetailMode = .transcript
    @Published private(set) var sessionTUITerminal: SessionTUITerminal?
    @Published var sessions: [SessionSummary] = []
    @Published var sessionMessages: [SessionMessage] = []
    @Published var sessionMessageDisplays: [SessionMessageDisplay] = []
    @Published var sessionsError: String?
    @Published var isLoadingSessions = false
    @Published var isRefreshingSessions = false
    @Published var isDeletingSession = false
    @Published var isSendingSessionMessage = false
    @Published var sessionConversationError: String?
    @Published var pendingSessionTurn: PendingSessionTurn?
    @Published var liveSessionMessageDisplays: [SessionMessageDisplay] = []
    @Published var liveToolActivityCards: [HermesToolActivityCard] = []
    @Published var sessionPromptCards: [HermesPromptCard] = []
    @Published var sessionCompactionNotice: SessionCompactionNotice?
    @Published var workspaceSessionActiveRun: WorkspaceSessionActiveRun?
    @Published private(set) var nativeChatBootstrapStatus: HermesChatBootstrapStatus?
    @Published var hasMoreSessions = false
    @Published var totalSessionsCount = 0
    @Published private(set) var sessionSearchQuery = ""
    @Published private(set) var sessionPinStateVersion = 0
    @Published var selectedWorkflowID: UUID?
    @Published var workflows: [WorkflowPreset] = []
    @Published var usageSummary: UsageSummary?
    @Published var usageProfileBreakdown: UsageProfileBreakdown?
    @Published var usageError: String?
    @Published var isLoadingUsage = false
    @Published var isRefreshingUsage = false
    @Published var caelWorkspaceStatus: CaelWorkspaceStatus?
    @Published var caelIntegrationStatus: CaelIntegrationStatus?
    @Published var caelProviderUsageLimits: CaelProviderUsageLimits?
    @Published var caelN8nGovernance: CaelN8nGovernanceStatus?
    @Published var caelN8nGovernanceError: String?
    @Published var caelCommandCenterSummary: CaelCommandCenterSummary?
    @Published var caelCommandCenterSections: CaelCommandCenterSectionsSnapshot?
    @Published var caelCommandCenterWarnings: [String] = []
    @Published var caelCommandCenterCacheNotice: String?
    @Published var caelWorkspaceError: String?
    @Published var caelProviderUsageError: String?
    @Published var isLoadingCaelWorkspace = false
    @Published var isRefreshingCaelWorkspace = false
    @Published var isLoadingCaelProviderUsage = false
    @Published var isRefreshingCaelProviderUsage = false
    @Published var selectedSkillID: String?
    @Published var skills: [SkillSummary] = []
    @Published var selectedSkillDetail: SkillDetail?
    @Published var skillsError: String?
    @Published var isLoadingSkills = false
    @Published var isRefreshingSkills = false
    @Published var isLoadingSkillDetail = false
    @Published var isSavingSkillDraft = false
    @Published var cronJobs: [CronJob] = []
    @Published var selectedCronJobID: String?
    @Published var cronJobsError: String?
    @Published var isLoadingCronJobs = false
    @Published var isRefreshingCronJobs = false
    @Published var isOperatingOnCronJob = false
    @Published var operatingCronJobID: String?
    @Published var isSavingCronJobDraft = false
    @Published var kanbanBoards: [KanbanProject] = []
    @Published var selectedKanbanBoardSlug = KanbanProject.defaultSlug
    @Published var remoteCurrentKanbanBoardSlug: String?
    @Published var supportsKanbanBoardManagement = false
    @Published var kanbanBoard: KanbanBoard?
    @Published var selectedKanbanTaskID: String?
    @Published var selectedKanbanTaskDetail: KanbanTaskDetail?
    @Published var kanbanError: String?
    @Published var isLoadingKanbanBoards = false
    @Published var isLoadingKanbanBoard = false
    @Published var isRefreshingKanbanBoard = false
    @Published var isLoadingKanbanTaskDetail = false
    @Published var isOperatingOnKanbanTask = false
    @Published var operatingKanbanTaskID: String?
    @Published var isSavingKanbanTaskDraft = false
    @Published var isSavingKanbanBoardDraft = false
    @Published var isOperatingOnKanbanBoard = false
    @Published var isDispatchingKanban = false
    @Published var includeArchivedKanbanTasks = false
    @Published var selectedWorkspaceFileID: String = RemoteTrackedFile.memory.workspaceFileID
    @Published var workspaceFileDocuments: [String: FileEditorDocument] = [:]
    @Published var workspaceFileBrowserListing: RemoteDirectoryListing?
    @Published var workspaceFileBrowserError: String?
    @Published var workspaceFileBrowserNotice: String?
    @Published var isLoadingWorkspaceFileBrowser = false
    @Published var workspacePreviewFile: WorkspacePreviewFile?
    @Published var workspacePreviewError: String?
    @Published var isLoadingWorkspacePreview = false
    @Published var isUploadingWorkspaceFile = false
    @Published var toolArtifacts: [ToolArtifactSummary] = []
    @Published var selectedToolArtifactID: String?
    @Published var selectedToolArtifactDetail: ToolArtifactDetail?
    @Published var toolArtifactsError: String?
    @Published var isLoadingToolArtifacts = false
    @Published var isLoadingToolArtifactDetail = false
    @Published var pendingSectionSelection: AppSection?
    @Published var showDiscardChangesAlert = false
    @Published var pendingNewConnectionEditorRequestID: UUID?
    @Published var searchFocusRequestID: UUID?
    @Published var availableUpdate: AvailableUpdate?
    @Published var isCheckingForUpdates = false

    let connectionStore: ConnectionStore
    let sshTransport: SSHTransport
    let remoteHermesService: RemoteHermesService
    let fileEditorService: FileEditorService
    let sessionBrowserService: SessionBrowserService
    let hermesChatService: HermesChatService
    let usageBrowserService: UsageBrowserService
    let caelWorkspaceAPIService: CaelWorkspaceAPIService
    let caelCommandCenterSnapshotStore: CaelCommandCenterSnapshotStore
    let skillBrowserService: SkillBrowserService
    let cronBrowserService: CronBrowserService
    let kanbanBrowserService: KanbanBrowserService
    let updateCheckService: UpdateCheckService
    let terminalWorkspace: TerminalWorkspaceStore
    let workflowLaunchDiagnostics: WorkflowLaunchDiagnostics

    private let sessionPageSize = 50
    private let approvalNeededMessage = "Hermes requested command approval, but this chat turn cannot collect manual approvals. Retry this turn with Auto-approve enabled, or resume the session in Terminal to review the command yourself."
    private var sessionOffset = 0
    private var pendingSessionReloadQuery: String?
    private var pendingSectionEntryAction: PendingSectionEntryAction?
    private var isNewSessionComposerActive = false
    private var sessionScrollOffsets: [String: CGFloat] = [:]
    private var sessionMessageSignature = SessionMessageSignature(messages: [])
    private var connectionTestRequestID: UUID?
    private var hasPerformedAutomaticUpdateCheck = false
    private let automaticUpdateCheckInterval: TimeInterval = 24 * 60 * 60
    private var statusTask: Task<Void, Never>?
    private var sessionTranscriptPollingTask: Task<Void, Never>?
    private var acceptedWorkspaceSessionMonitorTask: Task<Void, Never>?
    private var acceptedWorkspaceChatEventsTask: Task<Void, Never>?
    private var gatewayChatService: HermesGatewayChatService?
    private var gatewayEventsTask: Task<Void, Never>?
    private var nativeChatStatusWorkspaceScopeFingerprint: String?
    private var gatewayWorkspaceScopeFingerprint: String?
    private var gatewaySessionID: String?
    private var activeGatewayAssistantMessageID: String?
    private var hasAcceptedNativeTurnInFlight = false
    private var activeNativeTurnResult: Bool?
    private var activeNativeTurnCompletion: CheckedContinuation<Bool, Never>?
    private var cancellables = Set<AnyCancellable>()

    convenience init(updateCheckService: UpdateCheckService = UpdateCheckService()) {
        self.init(paths: AppPaths(), updateCheckService: updateCheckService)
    }

    init(paths: AppPaths, updateCheckService: UpdateCheckService = UpdateCheckService()) {
        let connectionStore = ConnectionStore(paths: paths)
        let sshTransport = SSHTransport(paths: paths)
        let workflowLaunchLogURL = paths.applicationSupportURL
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("workflow-launch-latest.log")
        let workflowLaunchDiagnostics = WorkflowLaunchDiagnostics(logFileURL: workflowLaunchLogURL)

        self.connectionStore = connectionStore
        self.sshTransport = sshTransport
        self.remoteHermesService = RemoteHermesService(sshTransport: sshTransport)
        self.fileEditorService = FileEditorService(sshTransport: sshTransport)
        self.sessionBrowserService = SessionBrowserService(sshTransport: sshTransport)
        self.hermesChatService = HermesChatService(sshTransport: sshTransport)
        self.usageBrowserService = UsageBrowserService(sshTransport: sshTransport)
        self.caelWorkspaceAPIService = CaelWorkspaceAPIService(sshTransport: sshTransport)
        self.caelCommandCenterSnapshotStore = CaelCommandCenterSnapshotStore(paths: paths)
        self.skillBrowserService = SkillBrowserService(sshTransport: sshTransport)
        self.cronBrowserService = CronBrowserService(sshTransport: sshTransport)
        self.kanbanBrowserService = KanbanBrowserService(sshTransport: sshTransport)
        self.updateCheckService = updateCheckService
        self.workflowLaunchDiagnostics = workflowLaunchDiagnostics
        self.terminalWorkspace = TerminalWorkspaceStore(
            sshTransport: sshTransport,
            workflowLaunchDiagnostics: workflowLaunchDiagnostics
        )

        connectionStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        connectionStore.$persistenceError
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.activeAlert = AppAlert(
                    title: L10n.string("Local storage error"),
                    message: message
                )
                self?.setStatusMessage(L10n.string("Local storage error"))
            }
            .store(in: &cancellables)

        self.activeConnectionID = connectionStore.lastConnectionID

        if activeConnectionID != nil {
            selectedSection = .overview
        }
    }

    var activeConnection: ConnectionProfile? {
        guard let activeConnectionID else { return nil }
        return connectionStore.connections.first(where: { $0.id == activeConnectionID })
    }

    var canUseNativeChat: Bool {
        nativeChatBootstrapStatus?.canUseNativeChat == true
    }

    var selectedKanbanBoard: KanbanProject? {
        kanbanBoards.first(where: { $0.slug == selectedKanbanBoardSlug })
    }

    var isWorkspaceKanbanBoardSelected: Bool {
        selectedKanbanBoardSlug == KanbanProject.workspaceTasksSlug
    }

    var canonicalWorkspaceFileReferences: [WorkspaceFileReference] {
        guard let activeConnection else { return [] }

        return RemoteTrackedFile.allCases.map { trackedFile in
            WorkspaceFileReference.canonical(
                trackedFile,
                remotePath: resolvedRemotePath(for: trackedFile, connection: activeConnection)
            )
        }
    }

    var bookmarkedWorkspaceFileReferences: [WorkspaceFileReference] {
        guard let activeConnection else { return [] }

        return connectionStore
            .bookmarks(for: activeConnection.workspaceScopeFingerprint)
            .map(WorkspaceFileReference.bookmark)
    }

    var bookmarkedWorkspaceFileGroups: [WorkspaceFileBookmarkGroup] {
        WorkspaceFileBookmarkGroup.groups(for: bookmarkedWorkspaceFileReferences)
    }

    var workspaceFileReferences: [WorkspaceFileReference] {
        canonicalWorkspaceFileReferences + bookmarkedWorkspaceFileReferences
    }

    var pinnedSessionSummaries: [SessionSummary] {
        guard let activeConnection else { return [] }

        return connectionStore
            .pinnedSessions(for: activeConnection.workspaceScopeFingerprint)
            .map { pinnedSession in
                sessions.first(where: { $0.id == pinnedSession.id }) ?? pinnedSession.summary
            }
    }

    var unpinnedSessions: [SessionSummary] {
        guard let activeConnection else { return sessions }
        let pinnedIDs = Set(
            connectionStore
                .pinnedSessions(for: activeConnection.workspaceScopeFingerprint)
                .map(\.id)
        )
        return sessions.filter { !pinnedIDs.contains($0.id) }
    }

    var selectedWorkspaceFileReference: WorkspaceFileReference? {
        workspaceFileReferences.first { $0.id == selectedWorkspaceFileID } ??
            workspaceFileReferences.first
    }

    var workspaceFileBrowserDefaultPath: String {
        overview?.hermesHome ?? activeConnection?.remoteHermesHomePath ?? "~"
    }

    var hasUnsavedFileChanges: Bool {
        workspaceFileDocuments.values.contains { $0.isDirty }
    }

    var canRefreshCurrentSection: Bool {
        guard activeConnection != nil else { return false }
        if selectedSection.isCommandCenterMirrorSection {
            return !isLoadingCaelWorkspace && !isRefreshingCaelWorkspace
        }

        switch selectedSection {
        case .overview:
            return !isLoadingCaelWorkspace && !isRefreshingCaelWorkspace
        case .sessions:
            return !isLoadingSessions && !isRefreshingSessions
        case .workflows:
            return !isLoadingSkills && !isRefreshingSkills
        case .cronjobs:
            return !isLoadingCronJobs && !isRefreshingCronJobs
        case .kanban:
            return !isLoadingKanbanBoards && !isLoadingKanbanBoard && !isRefreshingKanbanBoard
        case .usage:
            return !isLoadingUsage && !isRefreshingUsage && !isLoadingCaelProviderUsage && !isRefreshingCaelProviderUsage
        case .skills:
            return !isLoadingSkills && !isRefreshingSkills
        case .connections, .files, .mail, .contacts, .calendar, .missionControl, .operations, .swarm, .memory, .integrations, .mcp, .profiles, .terminal:
            return false
        }
    }

    var canSaveCurrentWorkspaceFile: Bool {
        guard selectedSection == .files else { return false }
        guard let document = workspaceFileDocuments[selectedWorkspaceFileID] else { return false }
        return document.hasLoaded && document.isDirty && !document.isLoading
    }

    var canFocusSearchCurrentSection: Bool {
        guard activeConnection != nil else { return false }

        switch selectedSection {
        case .sessions, .workflows, .cronjobs, .kanban, .skills:
            return true
        case .connections, .overview, .files, .mail, .contacts, .calendar, .missionControl, .operations, .swarm, .usage, .memory, .integrations, .mcp, .profiles, .terminal:
            return false
        }
    }

    func isSectionAvailable(_ section: AppSection) -> Bool {
        section == .connections || activeConnection != nil
    }

    func requestSectionSelection(_ section: AppSection) {
        guard selectedSection != section else { return }
        guard section != .files || activeConnection != nil else {
            selectedSection = .connections
            return
        }

        if hasUnsavedFileChanges && selectedSection == .files {
            pendingSectionSelection = section
            showDiscardChangesAlert = true
            return
        }

        selectedSection = section
        handleSectionEntry(section)
    }

    func requestNewConnectionEditorFromCommand() {
        pendingSectionEntryAction = .openNewConnectionEditor
        requestSectionSelection(.connections)
        guard selectedSection == .connections else { return }
        pendingNewConnectionEditorRequestID = UUID()
        pendingSectionEntryAction = nil
    }

    func consumeNewConnectionEditorRequest(_ requestID: UUID) {
        guard pendingNewConnectionEditorRequestID == requestID else { return }
        pendingNewConnectionEditorRequestID = nil
    }

    func requestNewSessionFromCommand() {
        guard activeConnection != nil else { return }
        pendingSectionEntryAction = .prepareNewSessionComposer
        isNewSessionComposerActive = true
        requestSectionSelection(.sessions)
        guard selectedSection == .sessions else { return }
        startNewSessionChat()
        pendingSectionEntryAction = nil
    }

    func openNewTerminalTabFromCommand() {
        guard let profile = activeConnection else { return }
        let updatedProfile = profile.updated()

        if hasUnsavedFileChanges && selectedSection == .files {
            pendingSectionEntryAction = .openNewTerminalTab(updatedProfile)
            requestSectionSelection(.terminal)
            return
        }

        openNewTerminalTab(for: updatedProfile)
    }

    func requestSearchFocusFromCommand() {
        guard canFocusSearchCurrentSection else { return }
        searchFocusRequestID = UUID()
    }

    func refreshCurrentSectionFromCommand() async {
        guard canRefreshCurrentSection else { return }
        if selectedSection.isCommandCenterMirrorSection {
            await refreshCaelWorkspace()
            return
        }

        switch selectedSection {
        case .overview:
            await refreshCaelWorkspace()
        case .sessions:
            await refreshSessions(query: sessionSearchQuery)
        case .workflows:
            await refreshWorkflows()
        case .cronjobs:
            await refreshCronJobs()
        case .kanban:
            await refreshKanbanBoard()
        case .usage:
            await refreshUsage()
            await refreshCaelProviderUsage()
        case .skills:
            await refreshSkills()
        case .connections, .files, .mail, .contacts, .calendar, .missionControl, .operations, .swarm, .memory, .integrations, .mcp, .profiles, .terminal:
            break
        }
    }

    func checkForUpdatesAtLaunch() async {
        guard connectionStore.automaticallyChecksForUpdates else { return }
        guard !hasPerformedAutomaticUpdateCheck else { return }
        guard shouldRunAutomaticUpdateCheck() else { return }
        hasPerformedAutomaticUpdateCheck = true
        let didCompleteCheck = await checkForUpdates(presentsCurrentResult: false)
        if didCompleteCheck {
            connectionStore.lastAutomaticUpdateCheckAt = Date()
        }
    }

    func checkForUpdatesFromCommand() async {
        _ = await checkForUpdates(presentsCurrentResult: true)
    }

    func dismissAvailableUpdate() {
        availableUpdate = nil
    }

    func noteOpenedRelease(for update: AvailableUpdate) {
        dismissAvailableUpdate()
        setStatusMessage(L10n.string("Opening Hermes Desktop %@ release…", update.latestVersion))
    }

    func updateAutomaticUpdateChecks(_ enabled: Bool) {
        connectionStore.automaticallyChecksForUpdates = enabled
    }

    func discardChangesAndContinue() {
        for fileID in Array(workspaceFileDocuments.keys) {
            var document = workspaceFileDocuments[fileID]
            document?.discardChanges()
            workspaceFileDocuments[fileID] = document
        }
        if let pendingSectionSelection {
            switch pendingSectionEntryAction {
            case .openNewConnectionEditor where pendingSectionSelection == .connections:
                pendingNewConnectionEditorRequestID = UUID()
                selectedSection = pendingSectionSelection
                handleSectionEntry(pendingSectionSelection)
            case .prepareNewSessionComposer where pendingSectionSelection == .sessions:
                selectedSection = pendingSectionSelection
                startNewSessionChat()
                handleSectionEntry(pendingSectionSelection)
            case .openNewTerminalTab(let profile) where pendingSectionSelection == .terminal:
                openNewTerminalTab(for: profile)
            default:
                selectedSection = pendingSectionSelection
                handleSectionEntry(pendingSectionSelection)
            }
        }
        pendingSectionSelection = nil
        pendingSectionEntryAction = nil
    }

    func stayOnCurrentSection() {
        pendingSectionSelection = nil
        pendingSectionEntryAction = nil
        isNewSessionComposerActive = false
    }

    func connect(to profile: ConnectionProfile) {
        let isSwitchingConnection = activeConnection?.workspaceScopeFingerprint != profile.workspaceScopeFingerprint
        let isSwitchingCaelWorkspace = activeConnection?.commandCenterClientFingerprint != profile.commandCenterClientFingerprint

        if isSwitchingConnection {
            resetWorkspaceStateForConnectionChange()
        } else if isSwitchingCaelWorkspace {
            resetCaelWorkspaceState()
        }

        activeConnectionID = profile.id
        connectionStore.lastConnectionID = profile.id
        var updatedProfile = profile
        updatedProfile.lastConnectedAt = Date()
        connectionStore.upsert(updatedProfile)
        selectedSection = .overview
        setStatusMessage(L10n.string("Connecting to %@…", profile.label))

        Task {
            await prepareWorkspaceForActiveConnection()
        }
    }

    func saveConnection(_ profile: ConnectionProfile) {
        let normalized = profile.updated()
        let previous = connectionStore.connections.first(where: { $0.id == normalized.id })
        let isActiveConnection = activeConnectionID == normalized.id
        let isChangingWorkspaceScope = previous?.workspaceScopeFingerprint != normalized.workspaceScopeFingerprint
        let isChangingCaelWorkspaceScope = previous?.commandCenterClientFingerprint != normalized.commandCenterClientFingerprint

        if isActiveConnection && isChangingWorkspaceScope && hasUnsavedFileChanges {
            activeAlert = AppAlert(
                title: L10n.string("Unsaved file edits"),
                message: L10n.string("Save or discard Workspace Files edits before switching the Hermes profile for the active host.")
            )
            return
        }

        connectionStore.upsert(normalized)

        guard isActiveConnection else { return }
        if isChangingWorkspaceScope {
            resetWorkspaceStateForConnectionChange()
            selectedSection = .overview
            setStatusMessage(L10n.string("Refreshing %@…", normalized.label))

            Task {
                await prepareWorkspaceForActiveConnection()
            }
        } else if isChangingCaelWorkspaceScope {
            resetCaelWorkspaceState()
            setStatusMessage(L10n.string("Refreshing Cael Workspace for %@…", normalized.label))

            Task {
                await loadCaelWorkspace(forceRefresh: true)
                await loadCaelProviderUsage(forceRefresh: true)
            }
        }
    }

    func switchHermesProfile(to profileName: String) async {
        guard let activeConnection else { return }
        guard activeConnection.resolvedHermesProfileName != profileName else { return }

        if hasUnsavedFileChanges {
            activeAlert = AppAlert(
                title: L10n.string("Unsaved file edits"),
                message: L10n.string("Save or discard Workspace Files edits before switching Hermes profiles.")
            )
            return
        }

        let updatedConnection = activeConnection.applyingHermesProfile(named: profileName)
        let shouldCarryTerminalWorkspace = selectedSection == .terminal || terminalWorkspace.hasTabs

        if shouldCarryTerminalWorkspace {
            terminalWorkspace.ensureInitialTab(for: updatedConnection)
        }

        connectionStore.upsert(updatedConnection)
        await reloadWorkspaceScope(
            section: selectedSection,
            statusMessage: L10n.string("Switching to %@…", profileName)
        )
    }

    func testConnection(_ profile: ConnectionProfile) {
        let requestID = UUID()
        connectionTestRequestID = requestID

        Task {
            do {
                isBusy = true
                setStatusMessage(L10n.string("Testing %@…", profile.label))

                let script = try RemotePythonScript.wrap(
                    ConnectionTestRequest(),
                    body: """
                    import json
                    import pathlib
                    import sys

                    print(json.dumps({
                        "ok": True,
                        "remote_home": str(pathlib.Path.home()),
                        "python_executable": sys.executable,
                    }, ensure_ascii=False))
                    """
                )

                let response = try await sshTransport.executeJSON(
                    on: profile,
                    pythonScript: script,
                    responseType: ConnectionTestResponse.self
                )

                guard connectionTestRequestID == requestID else { return }
                isBusy = false
                let home = response.remoteHome.trimmingCharacters(in: .whitespacesAndNewlines)
                setStatusMessage(L10n.string("SSH and python3 OK for %@", profile.label))
                let messageLines = [
                    L10n.string("SSH and python3 are available for this Hermes host."),
                    home.isEmpty ? nil : L10n.string("Remote HOME: %@", home)
                ].compactMap { $0 }
                activeAlert = AppAlert(
                    title: L10n.string("Connection OK"),
                    message: messageLines.joined(separator: "\n")
                )
            } catch {
                guard connectionTestRequestID == requestID else { return }
                isBusy = false
                activeAlert = AppAlert(
                    title: L10n.string("Connection failed"),
                    message: error.localizedDescription
                )
            }
        }
    }

    func refreshOverview(manual: Bool = false) async {
        guard let profile = activeConnection else { return }
        if manual {
            guard !isRefreshingOverview, !isBusy else { return }
            isRefreshingOverview = true
        }

        do {
            isBusy = true
            overviewError = nil
            let discovery = try await remoteHermesService.discover(connection: profile)
            guard isActiveWorkspace(profile) else { return }
            overview = discovery
            _ = await refreshNativeChatBootstrapStatus(for: profile, force: manual)
            isBusy = false
            if manual {
                isRefreshingOverview = false
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isBusy = false
            if manual {
                isRefreshingOverview = false
            }
            overview = nil
            overviewError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to refresh remote discovery"))
        }
    }

    func refreshSessions(query: String? = nil) async {
        guard !isLoadingSessions, !isRefreshingSessions else { return }
        isRefreshingSessions = true
        await loadSessions(reset: true, query: query)
        isRefreshingSessions = false
    }

    func refreshUsage() async {
        guard !isLoadingUsage, !isRefreshingUsage else { return }
        isRefreshingUsage = true
        await loadUsage(forceRefresh: true)
        isRefreshingUsage = false
    }

    func refreshCaelWorkspace() async {
        guard !isLoadingCaelWorkspace, !isRefreshingCaelWorkspace else { return }
        isRefreshingCaelWorkspace = true
        await loadCaelWorkspace(forceRefresh: true)
        isRefreshingCaelWorkspace = false
    }

    func refreshCaelProviderUsage() async {
        guard !isLoadingCaelProviderUsage, !isRefreshingCaelProviderUsage else { return }
        isRefreshingCaelProviderUsage = true
        await loadCaelProviderUsage(forceRefresh: true)
        isRefreshingCaelProviderUsage = false
    }

    func refreshSkills() async {
        guard !isLoadingSkills, !isRefreshingSkills else { return }
        isRefreshingSkills = true
        await loadSkills(reset: true)
        isRefreshingSkills = false
    }

    func refreshWorkflows() async {
        loadWorkflows(reset: true)
        await loadSkills(reset: false)
        loadWorkflows(reset: true)
    }

    func refreshCronJobs() async {
        guard !isLoadingCronJobs, !isRefreshingCronJobs else { return }
        isRefreshingCronJobs = true
        await loadCronJobs()
        isRefreshingCronJobs = false
    }

    func refreshKanbanBoard(includeArchived: Bool? = nil) async {
        guard !isLoadingKanbanBoard, !isRefreshingKanbanBoard else { return }
        isRefreshingKanbanBoard = true
        await loadKanbanBoards()
        await loadKanbanBoard(includeArchived: includeArchived)
        isRefreshingKanbanBoard = false
    }

    func workspaceFileDocument(for fileID: String) -> FileEditorDocument? {
        workspaceFileDocuments[fileID]
    }

    func selectWorkspaceFile(_ fileID: String) {
        guard workspaceFileReferences.contains(where: { $0.id == fileID }) else { return }
        selectedWorkspaceFileID = fileID
    }

    func loadSelectedWorkspaceFile(forceReload: Bool = false) async {
        guard let reference = selectedWorkspaceFileReference else { return }
        selectedWorkspaceFileID = reference.id
        await loadWorkspaceFile(reference, forceReload: forceReload)
    }

    func loadWorkspaceFile(_ reference: WorkspaceFileReference, forceReload: Bool = false) async {
        guard let profile = activeConnection else { return }
        var document = document(for: reference)

        if document.hasLoaded && !forceReload {
            setDocument(document)
            return
        }

        document.isLoading = true
        document.errorMessage = nil
        setDocument(document)

        do {
            let snapshot = try await caelWorkspaceAPIService.readWorkspaceFile(
                connection: profile,
                path: reference.remotePath
            )
            guard isActiveWorkspace(profile) else { return }
            document.content = snapshot.content
            document.originalContent = snapshot.content
            document.remoteContentHash = snapshot.contentHash
            document.lastSavedAt = nil
            document.errorMessage = nil
            document.isLoading = false
            document.hasLoaded = true
            setDocument(document)
        } catch {
            guard isActiveWorkspace(profile) else { return }
            document.isLoading = false
            document.errorMessage = error.localizedDescription
            setDocument(document)
        }
    }

    func saveSelectedWorkspaceFile() async {
        await saveWorkspaceFile(fileID: selectedWorkspaceFileID)
    }

    func saveWorkspaceFile(fileID: String) async {
        guard let profile = activeConnection else { return }
        guard let reference = workspaceFileReferences.first(where: { $0.id == fileID }) else { return }
        var document = document(for: reference)
        guard document.hasLoaded, document.remoteContentHash != nil else {
            document.errorMessage = L10n.string("Reload the file before saving.")
            setDocument(document)
            setStatusMessage(document.errorMessage)
            return
        }

        document.isLoading = true
        document.errorMessage = nil
        setDocument(document)

        do {
            let saveResult = try await caelWorkspaceAPIService.writeWorkspaceFile(
                connection: profile,
                path: reference.remotePath,
                content: document.content,
                expectedContentHash: document.remoteContentHash
            )
            guard isActiveWorkspace(profile) else { return }
            document.originalContent = document.content
            document.remoteContentHash = saveResult.contentHash
            document.lastSavedAt = Date()
            document.hasLoaded = true
            document.isLoading = false
            setDocument(document)
            setStatusMessage(L10n.string("%@ saved", reference.title))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            document.isLoading = false
            document.errorMessage = error.localizedDescription
            setDocument(document)
            setStatusMessage(error.localizedDescription)
        }
    }

    func updateWorkspaceFile(_ fileID: String, content: String) {
        guard let reference = workspaceFileReferences.first(where: { $0.id == fileID }) else { return }
        var document = document(for: reference)
        document.content = content
        setDocument(document)
    }

    func discardWorkspaceFile(_ fileID: String) {
        var document = workspaceFileDocuments[fileID]
        document?.discardChanges()
        workspaceFileDocuments[fileID] = document
    }

    @discardableResult
    func addWorkspaceFileBookmark(
        remotePath: String,
        title: String? = nil,
        selectAfterAdd: Bool = true
    ) -> WorkspaceFileBookmark? {
        guard let activeConnection else { return nil }
        guard let bookmark = connectionStore.upsertWorkspaceFileBookmark(
            remotePath: remotePath,
            title: title,
            workspaceScopeFingerprint: activeConnection.workspaceScopeFingerprint
        ) else {
            return nil
        }

        let reference = WorkspaceFileReference.bookmark(bookmark)
        if selectAfterAdd {
            selectedWorkspaceFileID = reference.id
            workspaceFileDocuments[reference.id] = workspaceFileDocuments[reference.id] ??
                FileEditorDocument(fileID: reference.id, title: reference.title, remotePath: reference.remotePath)
        }
        setStatusMessage(L10n.string("%@ added to Workspace Files", reference.title))
        return bookmark
    }

    func removeWorkspaceFileBookmark(id: UUID) {
        connectionStore.removeWorkspaceFileBookmark(id: id)
        workspaceFileDocuments.removeValue(forKey: "bookmark:\(id.uuidString)")

        if selectedWorkspaceFileID == "bookmark:\(id.uuidString)" {
            selectedWorkspaceFileID = RemoteTrackedFile.memory.workspaceFileID
        }

        setStatusMessage(L10n.string("Bookmark removed"))
    }

    func isSessionPinned(_ sessionID: String) -> Bool {
        guard let activeConnection else { return false }
        return connectionStore.isSessionPinned(
            id: sessionID,
            workspaceScopeFingerprint: activeConnection.workspaceScopeFingerprint
        )
    }

    func pinSession(_ session: SessionSummary) {
        guard let activeConnection else { return }
        connectionStore.upsertPinnedSession(
            session,
            workspaceScopeFingerprint: activeConnection.workspaceScopeFingerprint
        )
        sessionPinStateVersion &+= 1
    }

    func unpinSession(_ session: SessionSummary) {
        guard let activeConnection else { return }
        connectionStore.removePinnedSession(
            id: session.id,
            workspaceScopeFingerprint: activeConnection.workspaceScopeFingerprint
        )
        sessionPinStateVersion &+= 1
    }

    func toggleSessionPin(_ session: SessionSummary) {
        if isSessionPinned(session.id) {
            unpinSession(session)
        } else {
            pinSession(session)
        }
    }

    func sessionSummary(for sessionID: String) -> SessionSummary? {
        sessions.first(where: { $0.id == sessionID }) ??
            pinnedSessionSummaries.first(where: { $0.id == sessionID })
    }

    func browseWorkspaceDirectory(path: String? = nil) async {
        guard let profile = activeConnection else { return }
        let trimmedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let browsePath = trimmedPath?.isEmpty == false ? trimmedPath! : workspaceFileBrowserDefaultPath

        isLoadingWorkspaceFileBrowser = true
        workspaceFileBrowserError = nil

        do {
            let listing = try await caelWorkspaceAPIService.listWorkspaceFiles(
                connection: profile,
                path: browsePath,
                maxDepth: 0,
                maxEntries: 500
            )
            guard isActiveWorkspace(profile) else { return }
            workspaceFileBrowserListing = listing
            isLoadingWorkspaceFileBrowser = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingWorkspaceFileBrowser = false
            workspaceFileBrowserError = error.localizedDescription
            workspaceFileBrowserNotice = nil
            setStatusMessage(L10n.string("Unable to browse remote files"))
        }
    }

    func createWorkspaceDirectory(path: String) async {
        guard let profile = activeConnection else { return }
        let targetPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetPath.isEmpty else { return }

        do {
            _ = try await caelWorkspaceAPIService.makeWorkspaceDirectory(connection: profile, path: targetPath)
            guard isActiveWorkspace(profile) else { return }
            workspaceFileBrowserNotice = L10n.string("Folder created")
            setStatusMessage(L10n.string("Folder created"))
            await browseWorkspaceDirectory(path: workspaceFileBrowserListing?.displayPath ?? workspaceFileBrowserDefaultPath)
        } catch {
            guard isActiveWorkspace(profile) else { return }
            workspaceFileBrowserError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create folder"))
        }
    }

    func renameWorkspacePath(from sourcePath: String, to destinationPath: String) async {
        guard let profile = activeConnection else { return }
        let source = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !destination.isEmpty, source != destination else { return }

        do {
            _ = try await caelWorkspaceAPIService.renameWorkspacePath(connection: profile, from: source, to: destination)
            guard isActiveWorkspace(profile) else { return }
            workspaceFileBrowserNotice = L10n.string("Renamed to %@", destination)
            setStatusMessage(L10n.string("File renamed"))
            await browseWorkspaceDirectory(path: workspaceFileBrowserListing?.displayPath ?? workspaceFileBrowserDefaultPath)
        } catch {
            guard isActiveWorkspace(profile) else { return }
            workspaceFileBrowserError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to rename path"))
        }
    }

    func deleteWorkspacePath(path: String) async {
        guard let profile = activeConnection else { return }
        let targetPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetPath.isEmpty else { return }

        do {
            try await caelWorkspaceAPIService.deleteWorkspacePath(connection: profile, path: targetPath)
            guard isActiveWorkspace(profile) else { return }
            workspaceFileBrowserNotice = L10n.string("Deleted %@", targetPath)
            setStatusMessage(L10n.string("Path deleted"))
            await browseWorkspaceDirectory(path: workspaceFileBrowserListing?.displayPath ?? workspaceFileBrowserDefaultPath)
        } catch {
            guard isActiveWorkspace(profile) else { return }
            workspaceFileBrowserError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to delete path"))
        }
    }

    func uploadWorkspaceFile(localFileURL: URL, to targetPath: String) async {
        guard let profile = activeConnection else { return }
        let target = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }

        isUploadingWorkspaceFile = true
        workspaceFileBrowserError = nil
        workspaceFileBrowserNotice = nil

        do {
            let didAccess = localFileURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    localFileURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: localFileURL)
            guard data.count <= WorkspaceFileLimits.maxDesktopUploadBytes else {
                throw SSHTransportError.invalidResponse(
                    L10n.string(
                        "Desktop uploads are limited to %@.",
                        WorkspaceFileLimits.decimalMegabytes(for: Int64(WorkspaceFileLimits.maxDesktopUploadBytes))
                    )
                )
            }

            let result = try await caelWorkspaceAPIService.uploadWorkspaceFile(
                connection: profile,
                targetPath: target,
                fileName: localFileURL.lastPathComponent,
                contentBase64: data.base64EncodedString()
            )
            guard isActiveWorkspace(profile) else { return }
            isUploadingWorkspaceFile = false
            let uploadedPath = result.path ?? localFileURL.lastPathComponent
            let sizeText = result.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            workspaceFileBrowserNotice = sizeText.map { L10n.string("Uploaded %@ (%@)", uploadedPath, $0) } ??
                L10n.string("Uploaded %@", uploadedPath)
            setStatusMessage(L10n.string("%@ uploaded", uploadedPath))
            await browseWorkspaceDirectory(path: workspaceFileBrowserListing?.displayPath ?? workspaceFileBrowserDefaultPath)
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isUploadingWorkspaceFile = false
            workspaceFileBrowserError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to upload file"))
        }
    }

    func previewWorkspacePath(_ path: String) async {
        guard let profile = activeConnection else { return }
        let targetPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetPath.isEmpty else { return }

        isLoadingWorkspacePreview = true
        workspacePreviewError = nil
        workspacePreviewFile = nil

        do {
            let preview = try await caelWorkspaceAPIService.loadPreviewFile(connection: profile, path: targetPath)
            guard isActiveWorkspace(profile) else { return }
            workspacePreviewFile = preview
            isLoadingWorkspacePreview = false
            setStatusMessage(L10n.string("Preview loaded"))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingWorkspacePreview = false
            workspacePreviewError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to preview file"))
        }
    }

    func loadToolArtifacts(resetSelection: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingToolArtifacts { return }

        isLoadingToolArtifacts = true
        toolArtifactsError = nil

        do {
            let artifacts = try await caelWorkspaceAPIService.loadToolArtifacts(connection: profile, limit: 100)
            guard isActiveWorkspace(profile) else { return }
            toolArtifacts = artifacts
            if resetSelection || selectedToolArtifactID == nil || !artifacts.contains(where: { $0.id == selectedToolArtifactID }) {
                selectedToolArtifactID = artifacts.first?.id
                selectedToolArtifactDetail = nil
            }
            isLoadingToolArtifacts = false
            if let selectedToolArtifactID {
                await loadToolArtifactDetail(id: selectedToolArtifactID)
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingToolArtifacts = false
            toolArtifactsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load artifacts"))
        }
    }

    func selectToolArtifact(_ artifactID: String) async {
        selectedToolArtifactID = artifactID
        await loadToolArtifactDetail(id: artifactID)
    }

    func loadToolArtifactDetail(id artifactID: String) async {
        guard let profile = activeConnection else { return }
        if isLoadingToolArtifactDetail { return }

        isLoadingToolArtifactDetail = true
        toolArtifactsError = nil

        do {
            let detail = try await caelWorkspaceAPIService.loadToolArtifact(connection: profile, id: artifactID)
            guard isActiveWorkspace(profile) else { return }
            selectedToolArtifactDetail = detail
            isLoadingToolArtifactDetail = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingToolArtifactDetail = false
            toolArtifactsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load artifact detail"))
        }
    }

    func loadSessions(
        reset: Bool = false,
        query: String? = nil,
        preferredSessionID: String? = nil,
        allowsFallbackSelection: Bool = true,
        updatesSelection: Bool = true
    ) async {
        guard let profile = activeConnection else { return }

        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? sessionSearchQuery
        if isLoadingSessions {
            if reset, query != nil {
                sessionSearchQuery = normalizedQuery
                pendingSessionReloadQuery = normalizedQuery
            }
            return
        }

        let previousSelectedSessionID = selectedSessionID

        isLoadingSessions = true
        sessionsError = nil

        if reset, query != nil {
            sessionSearchQuery = normalizedQuery
        }

        do {
            let page = try await sessionBrowserService.listSessions(
                connection: profile,
                offset: reset ? 0 : sessionOffset,
                limit: sessionPageSize,
                query: normalizedQuery
            )
            guard isActiveWorkspace(profile) else { return }

            if reset {
                sessions = page.items
                sessionOffset = page.items.count
            } else {
                sessions.append(contentsOf: page.items)
                sessionOffset += page.items.count
            }

            totalSessionsCount = page.totalCount
            hasMoreSessions = sessionOffset < totalSessionsCount
            isLoadingSessions = false

            if reset {
                let resolvedPreferredSessionID: String?
                if let explicitPreferredSessionID = preferredSessionID,
                   sessions.contains(where: { $0.id == explicitPreferredSessionID }) ||
                    isSessionPinned(explicitPreferredSessionID) {
                    resolvedPreferredSessionID = explicitPreferredSessionID
                } else if isNewSessionComposerActive {
                    resolvedPreferredSessionID = nil
                } else if let previousSelectedSessionID,
                   sessions.contains(where: { $0.id == previousSelectedSessionID }) ||
                    isSessionPinned(previousSelectedSessionID) {
                    resolvedPreferredSessionID = previousSelectedSessionID
                } else if !allowsFallbackSelection {
                    resolvedPreferredSessionID = nil
                } else {
                    resolvedPreferredSessionID = normalizedQuery.isEmpty
                        ? pinnedSessionSummaries.first?.id ?? sessions.first?.id
                        : sessions.first?.id
                }

                if updatesSelection {
                    if let resolvedPreferredSessionID {
                        await loadSessionDetail(sessionID: resolvedPreferredSessionID)
                    } else {
                        selectedSessionID = nil
                        clearSessionMessages()
                    }
                }
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingSessions = false
            sessionsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load sessions"))
        }

        guard let queuedQuery = pendingSessionReloadQuery else { return }
        pendingSessionReloadQuery = nil
        guard queuedQuery != normalizedQuery else { return }
        await loadSessions(reset: true, query: queuedQuery)
    }

    func loadSessionDetail(sessionID: String) async {
        guard let profile = activeConnection else { return }
        if selectedSessionID != sessionID {
            if shouldPreserveLiveTranscriptDuringSessionTransition {
                clearPersistedSessionMessages()
            } else {
                clearSessionMessages()
            }
        }
        if let knownSessionCompactionNotice = knownSessionCompactionNotice(for: sessionID) {
            self.sessionCompactionNotice = knownSessionCompactionNotice
        } else if sessionCompactionNotice?.sourceSessionID != sessionID {
            self.sessionCompactionNotice = nil
        }
        clearSessionScrollOffset(for: sessionID)
        isNewSessionComposerActive = false
        selectedSessionID = sessionID
        sessionsError = nil
        sessionConversationError = nil
        workspaceSessionActiveRun = nil

        do {
            let messages = try await sessionBrowserService.loadTranscript(
                connection: profile,
                sessionID: sessionID
            )
            guard isActiveWorkspace(profile), selectedSessionID == sessionID else { return }
            await setSessionMessages(messages, for: profile, sessionID: sessionID)
        } catch {
            guard isActiveWorkspace(profile), selectedSessionID == sessionID else { return }
            clearSessionMessages()
            sessionsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load session transcript"))
        }
    }

    func prepareNewSessionComposer() {
        startNewSessionChat()
    }

    func startNewSessionChat() {
        isNewSessionComposerActive = true
        selectedSessionID = nil
        clearSessionMessages()
        sessionCompactionNotice = nil
        sessionsError = nil
        sessionConversationError = nil
        workspaceSessionActiveRun = nil
        selectedSessionDetailMode = .chat
        stopSessionTUI()
    }

    func setSessionDetailMode(_ mode: SessionDetailMode) {
        let previousMode = selectedSessionDetailMode
        selectedSessionDetailMode = mode

        switch mode {
        case .transcript:
            if previousMode == .chat {
                Task { [weak self] in
                    await self?.refreshSessionsAfterChat()
                }
            }
        case .chat:
            stopSessionTUI()
        }
    }

    func startSelectedSessionChat() {
        selectedSessionDetailMode = .chat
        stopSessionTUI()
    }

    func refreshSessionsAfterChat() async {
        await refreshSessions(query: sessionSearchQuery)
        if let selectedSessionID {
            await loadSessionDetail(sessionID: selectedSessionID)
        }
    }

    private func startSessionTUIIfNeededForCurrentSelection() {
        guard let profile = activeConnection else {
            sessionsError = L10n.string("Select a connection before starting Chat.")
            setStatusMessage(L10n.string("No active connection"))
            return
        }

        let sessionID = selectedSessionID
        if sessionTUITerminal?.matches(sessionID: sessionID, connection: profile) == true {
            return
        }

        guard sessionTUITerminal == nil else { return }
        startSessionTUI(sessionID: sessionID, replacesExisting: false)
    }

    private func startSessionTUI(sessionID: String?, replacesExisting: Bool) {
        guard let profile = activeConnection else {
            sessionsError = L10n.string("Select a connection before starting Chat.")
            setStatusMessage(L10n.string("No active connection"))
            return
        }

        let updatedProfile = profile.updated()
        if let sessionTUITerminal,
           sessionTUITerminal.matches(sessionID: sessionID, connection: updatedProfile),
           sessionTUITerminal.terminalSession.isRunning {
            return
        }

        if replacesExisting {
            stopSessionTUI()
        } else if sessionTUITerminal != nil {
            return
        }

        sessionTUITerminal = SessionTUITerminal(
            sessionID: sessionID,
            connection: updatedProfile,
            sshTransport: sshTransport,
            workflowLaunchDiagnostics: workflowLaunchDiagnostics
        )
        sessionConversationError = nil
        sessionsError = nil
        setStatusMessage(
            sessionID == nil
                ? L10n.string("Starting Hermes TUI…")
                : L10n.string("Resuming session in Hermes TUI…")
        )
    }

    private func stopSessionTUI() {
        sessionTUITerminal?.stop()
        sessionTUITerminal = nil
    }

    func savedSessionScrollOffset(for sessionID: String) -> CGFloat? {
        sessionScrollOffsets[sessionID]
    }

    func saveSessionScrollOffset(_ offset: CGFloat?, for sessionID: String) {
        guard let offset else {
            sessionScrollOffsets.removeValue(forKey: sessionID)
            return
        }

        sessionScrollOffsets[sessionID] = offset
    }

    private func clearSessionScrollOffset(for sessionID: String) {
        sessionScrollOffsets.removeValue(forKey: sessionID)
    }

    func startNewSession(with prompt: String, autoApproveCommands: Bool) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSendingSessionMessage else { return false }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return false }

        // Normal desktop composer sends use the same Workspace API as the web
        // app so both clients share the server-owned run ledger.

        isSendingSessionMessage = true
        pendingSessionTurn = PendingSessionTurn(
            sessionID: nil,
            prompt: trimmedPrompt,
            autoApproveCommands: autoApproveCommands
        )
        sessionConversationError = nil
        sessionsError = nil

        appendPendingUserLiveMessage(prompt: trimmedPrompt)

        do {
            let createdSession = try await caelWorkspaceAPIService.createWorkspaceChatSession(
                connection: profile,
                label: String(trimmedPrompt.prefix(80))
            )
            let serverSessionID = (createdSession.sessionKey ?? createdSession.friendlyId ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !serverSessionID.isEmpty else {
                throw SSHTransportError.invalidResponse("Workspace API did not return a session key for the new chat session.")
            }
            let sendResponse = try await caelWorkspaceAPIService.sendWorkspaceSessionMessage(
                connection: profile,
                sessionKey: serverSessionID,
                message: trimmedPrompt,
                autoApproveCommands: autoApproveCommands
            )
            guard isActiveWorkspace(profile) else { return false }

            let responseSessionID = sendResponse.sessionKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let createdSessionID = responseSessionID.isEmpty ? serverSessionID : responseSessionID
            isSendingSessionMessage = false
            pendingSessionTurn = nil
            markAcceptedWorkspaceRun(sendResponse, sessionID: createdSessionID)
            sessionSearchQuery = ""
            selectedSessionDetailMode = .chat
            isNewSessionComposerActive = false
            selectedSessionID = createdSessionID
            upsertAcceptedWorkspaceSessionSummary(
                sessionID: createdSessionID,
                prompt: trimmedPrompt,
                messageCount: max(sessionMessages.count + liveSessionMessageDisplays.count, 1)
            )
            scheduleAcceptedWorkspaceSessionRefresh(sessionID: createdSessionID, connection: profile)
            await loadSessions(
                reset: true,
                query: "",
                preferredSessionID: createdSessionID,
                allowsFallbackSelection: false,
                updatesSelection: false
            )
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSendingSessionMessage = false
            pendingSessionTurn = nil
            let message = error.localizedDescription
            sessionConversationError = message
            setStatusMessage(sessionStatusMessage(forConversationError: message, fallback: "Unable to start Hermes session"))
            return false
        }
    }

    private func likelyNewSessionID(
        afterStartingWith prompt: String,
        excluding existingSessionIDs: Set<String>
    ) -> String? {
        let newSessions = sessions.filter { !existingSessionIDs.contains($0.id) }
        guard !newSessions.isEmpty else { return nil }

        let normalizedPrompt = Self.normalizedSessionSelectionText(prompt)
        guard !normalizedPrompt.isEmpty else {
            return newSessions.first?.id
        }

        return newSessions.first { summary in
            Self.sessionSummary(summary, matchesNewSessionPrompt: normalizedPrompt)
        }?.id ?? newSessions.first?.id
    }

    private var knownSessionSummariesForCompaction: [SessionSummary] {
        uniqueSessionSummaries(sessions + pinnedSessionSummaries)
    }

    private func compactedSessionID(
        from sourceSessionID: String,
        preferredTargetSessionID: String? = nil,
        candidates: [SessionSummary]? = nil
    ) -> String? {
        let childSessions = (candidates ?? knownSessionSummariesForCompaction)
            .filter { $0.parentSessionID == sourceSessionID }

        guard !childSessions.isEmpty else { return nil }

        if let preferredTargetSessionID,
           childSessions.contains(where: { $0.id == preferredTargetSessionID }) {
            return preferredTargetSessionID
        }

        return childSessions.first?.id
    }

    private func knownSessionCompactionNotice(for sourceSessionID: String) -> SessionCompactionNotice? {
        guard let targetSessionID = compactedSessionID(from: sourceSessionID) else {
            return nil
        }

        return SessionCompactionNotice(
            sourceSessionID: sourceSessionID,
            targetSessionID: targetSessionID
        )
    }

    private func confirmSessionCompaction(
        from sourceSessionID: String,
        preferredTargetSessionID: String?,
        profile: ConnectionProfile
    ) async -> SessionCompactionNotice? {
        if let targetSessionID = compactedSessionID(
            from: sourceSessionID,
            preferredTargetSessionID: preferredTargetSessionID
        ) {
            return SessionCompactionNotice(
                sourceSessionID: sourceSessionID,
                targetSessionID: targetSessionID
            )
        }

        do {
            let recentSessions = try await sessionBrowserService.listSessions(
                connection: profile,
                offset: 0,
                limit: max(sessionPageSize, 100),
                query: ""
            ).items

            guard isActiveWorkspace(profile),
                  let targetSessionID = compactedSessionID(
                    from: sourceSessionID,
                    preferredTargetSessionID: preferredTargetSessionID,
                    candidates: recentSessions
                  ) else {
                return nil
            }

            return SessionCompactionNotice(
                sourceSessionID: sourceSessionID,
                targetSessionID: targetSessionID
            )
        } catch {
            return nil
        }
    }

    private func resolvedCompletedNativeTurnSessionID(
        sourceSessionID: String?,
        prompt: String,
        excluding existingVisibleSessionIDs: Set<String>,
        compactedSessionID: String?
    ) -> String? {
        if compactedSessionID != nil {
            return sourceSessionID ?? compactedSessionID
        }

        if let explicitTargetSessionID = gatewaySessionID,
           explicitTargetSessionID != sourceSessionID,
           resolvedKnownSessionID(explicitTargetSessionID) != nil {
            return explicitTargetSessionID
        }

        for candidateSessionID in [gatewaySessionID, sourceSessionID] {
            if let candidateSessionID,
               resolvedKnownSessionID(candidateSessionID) != nil {
                return candidateSessionID
            }
        }

        return likelyNewSessionID(
            afterStartingWith: prompt,
            excluding: existingVisibleSessionIDs
        ) ?? sessions.first?.id
    }

    private func resolvedKnownSessionID(_ sessionID: String) -> String? {
        if sessions.contains(where: { $0.id == sessionID }) || isSessionPinned(sessionID) {
            return sessionID
        }
        return nil
    }

    private func uniqueSessionSummaries(_ sessions: [SessionSummary]) -> [SessionSummary] {
        var seen = Set<String>()

        return sessions.filter { summary in
            seen.insert(summary.id).inserted
        }
    }

    nonisolated private static func sessionSummary(
        _ summary: SessionSummary,
        matchesNewSessionPrompt normalizedPrompt: String
    ) -> Bool {
        [summary.title, summary.preview].contains { candidate in
            let normalizedCandidate = normalizedSessionSelectionText(candidate ?? "")
            guard !normalizedCandidate.isEmpty else { return false }

            return normalizedPrompt.hasPrefix(normalizedCandidate) ||
                normalizedCandidate.hasPrefix(normalizedPrompt) ||
                normalizedCandidate.contains(normalizedPrompt)
        }
    }

    nonisolated private static func normalizedSessionSelectionText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func sendMessageToSelectedSession(_ prompt: String, autoApproveCommands: Bool) async -> Bool {
        guard let profile = activeConnection,
              let selectedSessionID else {
            return false
        }
        guard !isSendingSessionMessage else { return false }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return false }

        if let compactionNotice = knownSessionCompactionNotice(for: selectedSessionID) ??
            (sessionCompactionNotice?.sourceSessionID == selectedSessionID ? sessionCompactionNotice : nil) {
            sessionCompactionNotice = compactionNotice
            let message = L10n.string("This conversation was compacted and is now closed. Open the new session from the history list to continue.")
            sessionConversationError = message
            setStatusMessage(L10n.string("Conversation compacted. Open the new session from history to continue."))
            return false
        }

        // Normal desktop composer sends use the same Workspace API as the web
        // app so focus loss and active-run recovery behave identically.

        isSendingSessionMessage = true
        pendingSessionTurn = PendingSessionTurn(
            sessionID: selectedSessionID,
            prompt: trimmedPrompt,
            autoApproveCommands: autoApproveCommands
        )
        sessionConversationError = nil
        sessionsError = nil
        appendPendingUserLiveMessage(prompt: trimmedPrompt)

        do {
            let sendResponse = try await caelWorkspaceAPIService.sendWorkspaceSessionMessage(
                connection: profile,
                sessionKey: selectedSessionID,
                message: trimmedPrompt,
                autoApproveCommands: autoApproveCommands
            )
            guard isActiveWorkspace(profile) else { return false }

            isSendingSessionMessage = false
            pendingSessionTurn = nil
            markAcceptedWorkspaceRun(sendResponse, sessionID: selectedSessionID)
            scheduleAcceptedWorkspaceSessionRefresh(sessionID: selectedSessionID, connection: profile)
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSendingSessionMessage = false
            pendingSessionTurn = nil
            let message = error.localizedDescription
            sessionConversationError = message
            setStatusMessage(sessionStatusMessage(forConversationError: message, fallback: "Unable to send prompt to Hermes"))
            return false
        }
    }

    func respondToSessionPrompt(_ card: HermesPromptCard, response: HermesPromptResponse) async {
        guard let gatewayChatService else { return }

        let method: String
        var params: [String: JSONValue] = [
            "request_id": .string(card.requestID)
        ]

        if let sessionID = card.sessionID ?? gatewaySessionID ?? selectedSessionID {
            params["session_id"] = .string(sessionID)
        }

        switch response {
        case .approval(let approved):
            method = "approval.respond"
            params["choice"] = .string(approved ? "approve" : "deny")
        case .text(let value):
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch card.kind {
            case .clarify:
                method = "clarify.respond"
                params["answer"] = .string(trimmedValue)
            case .sudo:
                method = "sudo.respond"
                params["password"] = .string(trimmedValue)
            case .secret:
                method = "secret.respond"
                params["value"] = .string(trimmedValue)
            case .approval:
                return
            }
        }

        do {
            _ = try await gatewayChatService.request(method: method, params: params, timeout: 45)
            sessionPromptCards.removeAll { $0.id == card.id }
        } catch {
            let message = error.localizedDescription
            sessionConversationError = message
            setStatusMessage(sessionStatusMessage(forConversationError: message, fallback: "Unable to answer native chat prompt"))
            completeActiveNativeTurn(success: false)
        }
    }

    private func startNativeSessionTurn(
        prompt: String,
        sessionID: String?,
        autoApproveCommands: Bool,
        existingVisibleSessionIDs: Set<String> = []
    ) async -> Bool {
        guard let profile = activeConnection else { return false }

        isSendingSessionMessage = true
        sessionConversationError = nil
        sessionsError = nil
        sessionCompactionNotice = nil
        clearNativeTurnUIState()
        prepareActiveNativeTurnWait()
        pendingSessionTurn = PendingSessionTurn(
            sessionID: sessionID,
            prompt: prompt,
            autoApproveCommands: autoApproveCommands
        )
        appendPendingUserLiveMessage(prompt: prompt)

        do {
            let gatewayChatService = try await ensureGatewayChatService(for: profile)
            let resolvedSessionID = try await prepareGatewaySession(
                using: gatewayChatService,
                sessionID: sessionID
            )

            let submitResult = try await gatewayChatService.request(
                method: "prompt.submit",
                params: [
                    "session_id": .string(resolvedSessionID),
                    "text": .string(prompt)
                ],
                timeout: 120
            )
            applyGatewaySessionResult(submitResult, preferredSessionID: resolvedSessionID)

            isSendingSessionMessage = false
            pendingSessionTurn = nil
            hasAcceptedNativeTurnInFlight = true
            Task {
                await finishAcceptedNativeSessionTurn(
                    profile: profile,
                    sessionID: sessionID,
                    resolvedSessionID: resolvedSessionID,
                    prompt: prompt,
                    existingVisibleSessionIDs: existingVisibleSessionIDs,
                    gatewayChatService: gatewayChatService
                )
            }
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            hasAcceptedNativeTurnInFlight = false
            isSendingSessionMessage = false
            pendingSessionTurn = nil
            clearNativeTurnUIState()
            let message = error.localizedDescription
            sessionConversationError = message
            setStatusMessage(sessionStatusMessage(forConversationError: message, fallback: "Unable to send prompt to Hermes"))
            completeActiveNativeTurn(success: false)
            return false
        }
    }

    private func finishAcceptedNativeSessionTurn(
        profile: ConnectionProfile,
        sessionID: String?,
        resolvedSessionID: String,
        prompt: String,
        existingVisibleSessionIDs: Set<String>,
        gatewayChatService: HermesGatewayChatService
    ) async {
        let didComplete = await waitForActiveNativeTurnCompletion()
        hasAcceptedNativeTurnInFlight = false
        guard isActiveWorkspace(profile) else { return }

        if didComplete {
            stopSessionTranscriptPolling()
            isSendingSessionMessage = false
            pendingSessionTurn = nil
            let sourceSessionID = sessionID ?? resolvedSessionID
            var hydratedSessionIDs = Set<String>()

            let provisionalSessionID = gatewaySessionID ?? sourceSessionID
            if await hydrateSessionHistoryFromGateway(
                sessionID: provisionalSessionID,
                using: gatewayChatService,
                profile: profile,
                updatesSelection: provisionalSessionID == sourceSessionID
            ) {
                if provisionalSessionID == sourceSessionID {
                    hydratedSessionIDs.insert(provisionalSessionID)
                }
            }

            let refreshQuery = sessionID == nil ? "" : sessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            sessionSearchQuery = refreshQuery
            await loadSessions(
                reset: true,
                query: refreshQuery,
                allowsFallbackSelection: false,
                updatesSelection: false
            )

            let confirmedCompactionNotice = await confirmSessionCompaction(
                from: sourceSessionID,
                preferredTargetSessionID: gatewaySessionID,
                profile: profile
            )
            let resolvedCompactedSessionID = confirmedCompactionNotice?.targetSessionID
            if let confirmedCompactionNotice {
                registerSessionCompaction(confirmedCompactionNotice)
            }

            let canonicalSessionID = resolvedCompletedNativeTurnSessionID(
                sourceSessionID: sourceSessionID,
                prompt: prompt,
                excluding: existingVisibleSessionIDs,
                compactedSessionID: resolvedCompactedSessionID
            )

            if let canonicalSessionID {
                let didHydrateCanonicalSession: Bool
                if hydratedSessionIDs.contains(canonicalSessionID) {
                    didHydrateCanonicalSession = true
                } else {
                    didHydrateCanonicalSession = await hydrateSessionHistoryFromGateway(
                        sessionID: canonicalSessionID,
                        using: gatewayChatService,
                        profile: profile
                    )
                }

                if !didHydrateCanonicalSession &&
                    (
                        resolvedCompactedSessionID != nil ||
                        selectedSessionID != canonicalSessionID ||
                        sessionMessageDisplays.isEmpty
                    ) {
                    await loadSessionDetail(sessionID: canonicalSessionID)
                }
            } else if hydratedSessionIDs.isEmpty {
                clearNativeTurnUIState()
            }
            return
        }

        isSendingSessionMessage = false
        pendingSessionTurn = nil
        clearNativeTurnUIState()
        let message = sessionConversationError ?? "Native chat did not complete successfully."
        sessionConversationError = message
        setStatusMessage(sessionStatusMessage(forConversationError: message, fallback: "Unable to send prompt to Hermes"))
    }

    func deleteSession(_ session: SessionSummary) async {
        guard let profile = activeConnection else { return }
        if isDeletingSession { return }

        isDeletingSession = true
        sessionsError = nil

        do {
            try await sessionBrowserService.deleteSession(
                connection: profile,
                sessionID: session.id,
                hintedSessionStore: overview?.sessionStore
            )
            guard isActiveWorkspace(profile) else { return }

            await loadSessions(reset: true)
            await loadUsage(forceRefresh: true)
            isDeletingSession = false
            setStatusMessage(L10n.string("Session deleted locally and on the remote Hermes host"))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isDeletingSession = false
            sessionsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to delete session"))
        }
    }

    func loadUsage(forceRefresh: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingUsage { return }
        if !forceRefresh {
            if usageSummary != nil || usageError != nil {
                return
            }
        }

        isLoadingUsage = true
        usageError = nil

        do {
            let summary = try await usageBrowserService.loadUsage(
                connection: profile,
                hintedSessionStore: overview?.sessionStore
            )
            guard isActiveWorkspace(profile) else { return }

            let profileBreakdown: UsageProfileBreakdown?
            if let overview,
               overview.availableProfiles.count > 1 {
                profileBreakdown = await loadUsageProfileBreakdown(
                    using: profile,
                    activeSummary: summary,
                    discoveredProfiles: overview.availableProfiles
                )
            } else {
                profileBreakdown = nil
            }
            guard isActiveWorkspace(profile) else { return }

            usageSummary = summary
            usageProfileBreakdown = profileBreakdown
            isLoadingUsage = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingUsage = false
            usageSummary = nil
            usageProfileBreakdown = nil
            usageError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load usage"))
        }
    }

    func loadCaelWorkspace(forceRefresh: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingCaelWorkspace { return }
        if !forceRefresh,
           caelWorkspaceStatus != nil,
           caelIntegrationStatus != nil,
           (caelN8nGovernance != nil || caelN8nGovernanceError != nil),
           caelCommandCenterSummary != nil,
           caelCommandCenterSections != nil {
            return
        }

        if caelCommandCenterSummary == nil, caelCommandCenterSections == nil {
            _ = applyCachedCommandCenterSnapshot(
                for: profile,
                reason: "Refreshing the live Workspace in the background."
            )
        }

        isLoadingCaelWorkspace = true
        caelWorkspaceError = nil

        do {
            let loadedStatus = try await caelWorkspaceAPIService.loadStatus(connection: profile)
            let loadedIntegrations = try await caelWorkspaceAPIService.loadIntegrations(connection: profile)
            let loadedGovernance: CaelN8nGovernanceStatus?
            let loadedGovernanceError: String?
            do {
                loadedGovernance = try await caelWorkspaceAPIService.loadN8nGovernance(connection: profile)
                loadedGovernanceError = nil
            } catch {
                loadedGovernance = nil
                loadedGovernanceError = error.localizedDescription
            }
            let loadedCommandCenter = try? await caelWorkspaceAPIService.loadCommandCenterSummary(connection: profile)
            let loadedSections = await caelWorkspaceAPIService.loadCommandCenterSections(connection: profile)
            guard isActiveCaelWorkspace(profile) else { return }

            caelWorkspaceStatus = loadedStatus
            caelIntegrationStatus = loadedIntegrations
            caelN8nGovernance = loadedGovernance
            caelN8nGovernanceError = loadedGovernanceError
            caelCommandCenterSummary = loadedCommandCenter?.data
            caelCommandCenterSections = loadedSections
            caelCommandCenterWarnings = loadedCommandCenter?.warnings ?? []
            caelCommandCenterCacheNotice = nil
            try? caelCommandCenterSnapshotStore.save(
                summaryEnvelope: loadedCommandCenter,
                sections: loadedSections,
                for: profile
            )
            isLoadingCaelWorkspace = false
        } catch {
            guard isActiveCaelWorkspace(profile) else { return }
            if caelCommandCenterSummary == nil, caelCommandCenterSections == nil {
                _ = applyCachedCommandCenterSnapshot(
                    for: profile,
                    reason: "The live Workspace fetch failed: \(error.localizedDescription)"
                )
            }
            isLoadingCaelWorkspace = false
            caelWorkspaceError = error.localizedDescription
            setStatusMessage("Unable to load Cael workspace status")
        }
    }

    func loadCaelProviderUsage(forceRefresh: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingCaelProviderUsage { return }
        if !forceRefresh, caelProviderUsageLimits != nil {
            return
        }

        isLoadingCaelProviderUsage = true
        caelProviderUsageError = nil

        do {
            let limits = try await caelWorkspaceAPIService.loadProviderUsage(
                connection: profile,
                force: forceRefresh
            )
            guard isActiveCaelWorkspace(profile) else { return }

            caelProviderUsageLimits = limits
            isLoadingCaelProviderUsage = false
        } catch {
            guard isActiveCaelWorkspace(profile) else { return }
            isLoadingCaelProviderUsage = false
            caelProviderUsageLimits = nil
            caelProviderUsageError = error.localizedDescription
            setStatusMessage("Unable to load provider usage limits")
        }
    }

    func loadSkills(reset: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingSkills { return }

        let previousSelectedSkillID = selectedSkillID

        isLoadingSkills = true
        skillsError = nil

        do {
            let items = try await skillBrowserService.listSkills(connection: profile)
            guard isActiveWorkspace(profile) else { return }
            skills = items.sorted { lhs, rhs in
                let comparison = lhs.slug.localizedCaseInsensitiveCompare(rhs.slug)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }

                return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
            }
            isLoadingSkills = false

            if reset {
                let preferredSkillID: String?
                if let previousSelectedSkillID,
                   items.contains(where: { $0.id == previousSelectedSkillID }) {
                    preferredSkillID = previousSelectedSkillID
                } else {
                    preferredSkillID = items.first?.id
                }

                if let preferredSkill = items.first(where: { $0.id == preferredSkillID }) {
                    await loadSkillDetail(summary: preferredSkill)
                } else if let firstSkill = items.first {
                    await loadSkillDetail(summary: firstSkill)
                } else {
                    selectedSkillID = nil
                    selectedSkillDetail = nil
                    isLoadingSkillDetail = false
                }
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingSkills = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load skills"))
        }
    }

    func loadWorkflows(reset: Bool = false) {
        guard let profile = activeConnection else {
            workflows = []
            selectedWorkflowID = nil
            return
        }

        let previousSelectedWorkflowID = selectedWorkflowID
        workflows = connectionStore.workflows(for: profile.workspaceScopeFingerprint)

        guard reset else { return }

        if let previousSelectedWorkflowID,
           workflows.contains(where: { $0.id == previousSelectedWorkflowID }) {
            selectedWorkflowID = previousSelectedWorkflowID
        } else {
            selectedWorkflowID = workflows.first?.id
        }
    }

    func createWorkflow(_ draft: WorkflowDraft) -> Bool {
        guard let profile = activeConnection else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            setStatusMessage(localizedError)
            activeAlert = AppAlert(
                title: L10n.string("Unable to save workflow"),
                message: localizedError
            )
            return false
        }

        let workflow = WorkflowPreset(
            workspaceScopeFingerprint: profile.workspaceScopeFingerprint,
            name: draft.normalizedName,
            prompt: draft.normalizedPrompt,
            assignedSkills: draft.normalizedSelectedSkills
        )

        connectionStore.upsertWorkflow(workflow)
        loadWorkflows(reset: true)
        selectedWorkflowID = workflow.id
        setStatusMessage(L10n.string("%@ created", workflow.name))
        return true
    }

    func updateWorkflow(_ workflow: WorkflowPreset, draft: WorkflowDraft) -> Bool {
        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            setStatusMessage(localizedError)
            activeAlert = AppAlert(
                title: L10n.string("Unable to save workflow"),
                message: localizedError
            )
            return false
        }

        let updatedWorkflow = workflow.updated(
            name: draft.normalizedName,
            prompt: draft.normalizedPrompt,
            assignedSkills: draft.normalizedSelectedSkills
        )

        connectionStore.upsertWorkflow(updatedWorkflow)
        loadWorkflows(reset: true)
        selectedWorkflowID = updatedWorkflow.id
        setStatusMessage(L10n.string("%@ updated", updatedWorkflow.name))
        return true
    }

    func deleteWorkflow(_ workflow: WorkflowPreset) {
        connectionStore.removeWorkflow(id: workflow.id)
        loadWorkflows(reset: true)
        setStatusMessage(L10n.string("%@ removed", workflow.name))
    }

    func workflow(id: UUID?) -> WorkflowPreset? {
        guard let id else { return nil }
        return workflows.first(where: { $0.id == id })
    }

    func runWorkflow(_ workflow: WorkflowPreset) async {
        await runWorkflow(workflow, destination: .terminal)
    }

    func runWorkflow(_ workflow: WorkflowPreset, destination: WorkflowRunDestination) async {
        guard let profile = activeConnection else {
            activeAlert = AppAlert(
                title: L10n.string("No active connection"),
                message: L10n.string("Select a connection before running a workflow.")
            )
            setStatusMessage(L10n.string("No active connection"))
            return
        }

        if skills.isEmpty && !isLoadingSkills {
            await loadSkills(reset: false)
        }

        let skillsByRelativePath = Dictionary(uniqueKeysWithValues: skills.map { ($0.relativePath, $0) })
        let missingSkills = workflow.assignedSkills.filter { skillsByRelativePath[$0.relativePath] == nil }

        guard missingSkills.isEmpty else {
            let message: String
            if let skillsError,
               skills.isEmpty {
                message = skillsError
            } else {
                message = L10n.string(
                    "This workflow references skills that are not available on the active host/profile: %@",
                    missingSkills.map(\.relativePath).joined(separator: ", ")
                )
            }

            activeAlert = AppAlert(
                title: L10n.string("Workflow cannot run"),
                message: message
            )
            setStatusMessage(L10n.string("Workflow cannot run"))
            return
        }

        switch destination {
        case .terminal:
            await runWorkflowInTerminal(workflow, connection: profile)
        case .chat:
            await runWorkflowInChat(workflow, connection: profile)
        }
    }

    private func runWorkflowInTerminal(_ workflow: WorkflowPreset, connection profile: ConnectionProfile) async {
        let invocation = WorkflowLaunchInvocation(workflow: workflow, connection: profile)
        let workflowLaunchDiagnosticsContext = WorkflowLaunchDiagnosticsContext(
            workflow: workflow,
            invocation: invocation,
            connection: profile
        )
        await workflowLaunchDiagnostics.recordWorkflowRunRequested(workflowLaunchDiagnosticsContext)
        terminalWorkspace.addCommandTab(
            for: profile.updated(),
            commandLine: invocation.startupCommandLine,
            initialInput: invocation.initialInput,
            workflowLaunchDiagnosticsContext: workflowLaunchDiagnosticsContext
        )
        selectedSection = .terminal
        handleSectionEntry(.terminal)
        setStatusMessage(L10n.string("Opening %@ in Terminal…", workflow.name))
    }

    private func runWorkflowInChat(_ workflow: WorkflowPreset, connection profile: ConnectionProfile) async {
        let invocation = WorkflowChatLaunchInvocation(workflow: workflow, connection: profile)
        let terminalInvocation = WorkflowLaunchInvocation(workflow: workflow, connection: profile)
        let workflowLaunchDiagnosticsContext = WorkflowLaunchDiagnosticsContext(
            workflow: workflow,
            invocation: terminalInvocation,
            connection: profile
        )
        await workflowLaunchDiagnostics.recordWorkflowRunRequested(workflowLaunchDiagnosticsContext)

        stopSessionTUI()
        isNewSessionComposerActive = true
        selectedSessionID = nil
        clearSessionMessages()
        sessionCompactionNotice = nil
        sessionsError = nil
        sessionConversationError = nil
        selectedSessionDetailMode = .chat
        selectedSection = .sessions

        if await preferredChatTransport(for: profile) == .native {
            setStatusMessage(L10n.string("Running %@ in native Chat…", workflow.name))
            _ = await startNativeSessionTurn(
                prompt: invocation.initialInput,
                sessionID: nil,
                autoApproveCommands: false
            )
            return
        }

        sessionTUITerminal = SessionTUITerminal(
            sessionID: nil,
            connection: profile.updated(),
            sshTransport: sshTransport,
            workflowLaunchDiagnostics: workflowLaunchDiagnostics,
            startupInput: invocation.initialInput,
            workflowLaunchDiagnosticsContext: workflowLaunchDiagnosticsContext
        )
        setStatusMessage(L10n.string("Opening %@ in Chat TUI fallback…", workflow.name))
    }

    func loadSkillDetail(summary: SkillSummary) async {
        guard let profile = activeConnection else { return }
        let skillID = summary.id
        selectedSkillID = skillID
        selectedSkillDetail = nil
        skillsError = nil
        isLoadingSkillDetail = true

        do {
            let detail = try await skillBrowserService.loadSkillDetail(
                connection: profile,
                locator: summary.locator
            )

            guard isActiveWorkspace(profile), selectedSkillID == skillID else { return }
            selectedSkillDetail = detail
            isLoadingSkillDetail = false
        } catch {
            guard isActiveWorkspace(profile), selectedSkillID == skillID else { return }
            selectedSkillDetail = nil
            isLoadingSkillDetail = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load skill detail"))
        }
    }

    func createSkill(_ draft: SkillDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingSkillDraft else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            skillsError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingSkillDraft = true
        skillsError = nil
        setStatusMessage(L10n.string("Creating skill…"))

        do {
            let detail = try await skillBrowserService.createSkill(
                connection: profile,
                draft: draft
            )
            guard isActiveWorkspace(profile) else { return false }
            await loadSkills(reset: true)
            selectedSkillID = detail.id
            selectedSkillDetail = detail
            isSavingSkillDraft = false
            setStatusMessage(L10n.string("%@ created", draft.normalizedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingSkillDraft = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create skill"))
            return false
        }
    }

    func updateSkill(
        _ detail: SkillDetail,
        markdownContent: String,
        ensureReferencesFolder: Bool,
        ensureScriptsFolder: Bool,
        ensureTemplatesFolder: Bool
    ) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingSkillDraft else { return false }

        let normalizedContent = markdownContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContent.isEmpty else {
            let message = L10n.string("SKILL.md content cannot be empty.")
            skillsError = message
            setStatusMessage(message)
            return false
        }

        isSavingSkillDraft = true
        skillsError = nil
        setStatusMessage(L10n.string("Updating %@…", detail.resolvedName))

        do {
            let updatedDetail = try await skillBrowserService.updateSkill(
                connection: profile,
                locator: detail.locator,
                markdownContent: normalizedContent + "\n",
                expectedContentHash: detail.contentHash,
                ensureReferencesFolder: ensureReferencesFolder,
                ensureScriptsFolder: ensureScriptsFolder,
                ensureTemplatesFolder: ensureTemplatesFolder
            )
            guard isActiveWorkspace(profile) else { return false }
            await loadSkills(reset: true)
            selectedSkillID = updatedDetail.id
            selectedSkillDetail = updatedDetail
            isSavingSkillDraft = false
            setStatusMessage(L10n.string("%@ updated", updatedDetail.resolvedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingSkillDraft = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to update skill"))
            return false
        }
    }

    func loadCronJobs() async {
        guard let profile = activeConnection else { return }
        if isLoadingCronJobs { return }

        let previousSelectedCronJobID = selectedCronJobID
        isLoadingCronJobs = true
        cronJobsError = nil

        do {
            let jobs = try await caelWorkspaceAPIService.loadWorkspaceCronJobs(connection: profile)
            guard isActiveWorkspace(profile) else { return }
            cronJobs = jobs
            isLoadingCronJobs = false

            if let previousSelectedCronJobID,
               jobs.contains(where: { $0.id == previousSelectedCronJobID }) {
                selectedCronJobID = previousSelectedCronJobID
            } else {
                selectedCronJobID = jobs.first?.id
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingCronJobs = false
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load cron jobs"))
        }
    }

    func pauseCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await caelWorkspaceAPIService.pauseWorkspaceCronJob(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("%@ paused", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to pause cron job"))
        }
    }

    func createCronJob(_ draft: CronJobDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingCronJobDraft, !isOperatingOnCronJob else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            cronJobsError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingCronJobDraft = true
        cronJobsError = nil
        setStatusMessage(L10n.string("Creating cron job…"))

        do {
            let result: CronJobMutationResult
            if draft.noAgent {
                let jobID = try await cronBrowserService.createJob(connection: profile, draft: draft)
                result = CronJobMutationResult(jobID: jobID, job: nil)
            } else {
                result = try await caelWorkspaceAPIService.createWorkspaceCronJob(connection: profile, draft: draft)
            }
            guard isActiveWorkspace(profile) else { return false }
            await loadCronJobs()
            selectedCronJobID = result.jobID ?? result.job?.id
            isSavingCronJobDraft = false
            setStatusMessage(L10n.string("%@ created", draft.normalizedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingCronJobDraft = false
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create cron job"))
            return false
        }
    }

    func updateCronJob(_ job: CronJob, draft: CronJobDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingCronJobDraft, !isOperatingOnCronJob else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            cronJobsError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingCronJobDraft = true
        cronJobsError = nil
        setStatusMessage(L10n.string("Updating %@…", job.resolvedName))

        do {
            if draft.noAgent || job.noAgent {
                try await cronBrowserService.updateJob(connection: profile, jobID: job.id, draft: draft)
            } else {
                _ = try await caelWorkspaceAPIService.updateWorkspaceCronJob(connection: profile, jobID: job.id, draft: draft)
            }
            guard isActiveWorkspace(profile) else { return false }
            await loadCronJobs()
            selectedCronJobID = job.id
            isSavingCronJobDraft = false
            setStatusMessage(L10n.string("%@ updated", draft.normalizedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingCronJobDraft = false
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to update cron job"))
            return false
        }
    }

    func resumeCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await caelWorkspaceAPIService.resumeWorkspaceCronJob(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("%@ resumed", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to resume cron job"))
        }
    }

    func deleteCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await caelWorkspaceAPIService.deleteWorkspaceCronJob(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("%@ removed", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to remove cron job"))
        }
    }

    func runCronJobNow(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil
        setStatusMessage(L10n.string("Triggering %@…", job.resolvedName))

        do {
            try await caelWorkspaceAPIService.triggerWorkspaceCronJob(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("Run requested for %@", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to run cron job"))
        }
    }

    func loadKanbanBoards() async {
        guard let profile = activeConnection else { return }
        if isLoadingKanbanBoards { return }

        isLoadingKanbanBoards = true
        kanbanError = nil

        do {
            let response = try await kanbanBrowserService.loadBoards(connection: profile)
            guard isActiveWorkspace(profile) else { return }

            let remoteBoards = response.boards.isEmpty
                ? [KanbanProject(slug: KanbanProject.defaultSlug)]
                : response.boards
            kanbanBoards = [KanbanProject.workspaceTasks] + remoteBoards
            remoteCurrentKanbanBoardSlug = response.current
            supportsKanbanBoardManagement = response.supportsBoardManagement

            if !kanbanBoards.contains(where: { $0.slug == selectedKanbanBoardSlug }) {
                selectedKanbanBoardSlug = KanbanProject.workspaceTasksSlug
            } else if selectedKanbanBoardSlug == KanbanProject.defaultSlug {
                selectedKanbanBoardSlug = KanbanProject.workspaceTasksSlug
            }

            isLoadingKanbanBoards = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingKanbanBoards = false
            kanbanBoards = kanbanBoards.isEmpty ? [KanbanProject.workspaceTasks, KanbanProject(slug: KanbanProject.defaultSlug)] : kanbanBoards
            if !kanbanBoards.contains(where: { $0.slug == selectedKanbanBoardSlug }) {
                selectedKanbanBoardSlug = KanbanProject.workspaceTasksSlug
            }
            remoteCurrentKanbanBoardSlug = nil
            supportsKanbanBoardManagement = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load Kanban boards"))
        }
    }

    func selectKanbanBoard(_ slug: String) async {
        let normalizedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSlug.isEmpty else { return }
        guard selectedKanbanBoardSlug != normalizedSlug else { return }
        guard kanbanBoards.isEmpty || kanbanBoards.contains(where: { $0.slug == normalizedSlug }) else { return }

        selectedKanbanBoardSlug = normalizedSlug
        selectedKanbanTaskID = nil
        selectedKanbanTaskDetail = nil
        kanbanBoard = nil
        await loadKanbanBoard()
    }

    func loadKanbanBoard(includeArchived: Bool? = nil) async {
        guard let profile = activeConnection else { return }
        if isLoadingKanbanBoard { return }

        if let includeArchived {
            includeArchivedKanbanTasks = includeArchived
        }

        if kanbanBoards.isEmpty, !isLoadingKanbanBoards {
            await loadKanbanBoards()
        }

        let boardSlug = selectedKanbanBoardSlug
        let previousSelectedTaskID = selectedKanbanTaskID
        isLoadingKanbanBoard = true
        kanbanError = nil

        do {
            let board: KanbanBoard
            if boardSlug == KanbanProject.workspaceTasksSlug {
                let tasks = try await caelWorkspaceAPIService.loadWorkspaceTasks(
                    connection: profile,
                    includeDone: includeArchivedKanbanTasks
                )
                board = .workspaceTasks(tasks, includeDone: includeArchivedKanbanTasks)
            } else {
                board = try await kanbanBrowserService.loadBoard(
                    connection: profile,
                    boardSlug: boardSlug,
                    includeArchived: includeArchivedKanbanTasks
                )
            }
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            kanbanBoard = board
            isLoadingKanbanBoard = false

            let nextSelectedTaskID: String?
            if let previousSelectedTaskID,
               board.tasks.contains(where: { $0.id == previousSelectedTaskID }) {
                nextSelectedTaskID = previousSelectedTaskID
            } else {
                nextSelectedTaskID = board.tasks.first?.id
            }

            selectedKanbanTaskID = nextSelectedTaskID
            if let nextSelectedTaskID {
                await loadKanbanTaskDetail(taskID: nextSelectedTaskID)
            } else {
                selectedKanbanTaskDetail = nil
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingKanbanBoard = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load Kanban board"))
        }
    }

    func loadKanbanTaskDetail(taskID: String) async {
        guard let profile = activeConnection else { return }
        let boardSlug = selectedKanbanBoardSlug

        selectedKanbanTaskID = taskID
        isLoadingKanbanTaskDetail = true
        kanbanError = nil

        if boardSlug == KanbanProject.workspaceTasksSlug {
            selectedKanbanTaskDetail = nil
            isLoadingKanbanTaskDetail = false
            return
        }

        do {
            let detail = try await kanbanBrowserService.loadTaskDetail(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID
            )
            guard isActiveWorkspace(profile),
                  selectedKanbanBoardSlug == boardSlug,
                  selectedKanbanTaskID == taskID else { return }
            selectedKanbanTaskDetail = detail
            isLoadingKanbanTaskDetail = false
        } catch {
            guard isActiveWorkspace(profile),
                  selectedKanbanBoardSlug == boardSlug,
                  selectedKanbanTaskID == taskID else { return }
            selectedKanbanTaskDetail = nil
            isLoadingKanbanTaskDetail = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load Kanban task"))
        }
    }

    func createKanbanBoard(_ draft: KanbanBoardDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingKanbanBoardDraft, !isOperatingOnKanbanBoard else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            kanbanError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingKanbanBoardDraft = true
        kanbanError = nil
        setStatusMessage(L10n.string("Creating Kanban board..."))

        do {
            let board = try await kanbanBrowserService.createBoard(connection: profile, draft: draft)
            guard isActiveWorkspace(profile) else { return false }
            await loadKanbanBoards()
            selectedKanbanBoardSlug = board.slug
            selectedKanbanTaskID = nil
            selectedKanbanTaskDetail = nil
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            isSavingKanbanBoardDraft = false
            setStatusMessage(L10n.string("%@ created", board.resolvedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingKanbanBoardDraft = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create Kanban board"))
            return false
        }
    }

    func archiveKanbanBoard(_ board: KanbanProject) async {
        guard let profile = activeConnection else { return }
        guard !board.isDefault, !isOperatingOnKanbanBoard else { return }

        isOperatingOnKanbanBoard = true
        kanbanError = nil
        setStatusMessage(L10n.string("Archiving %@...", board.resolvedName))

        do {
            try await kanbanBrowserService.archiveBoard(connection: profile, slug: board.slug)
            guard isActiveWorkspace(profile) else { return }
            if selectedKanbanBoardSlug == board.slug {
                selectedKanbanBoardSlug = KanbanProject.defaultSlug
                selectedKanbanTaskID = nil
                selectedKanbanTaskDetail = nil
                kanbanBoard = nil
            }
            await loadKanbanBoards()
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            isOperatingOnKanbanBoard = false
            setStatusMessage(L10n.string("%@ archived", board.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnKanbanBoard = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to archive Kanban board"))
        }
    }

    func createKanbanTask(_ draft: KanbanTaskDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingKanbanTaskDraft, !isOperatingOnKanbanTask else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            kanbanError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingKanbanTaskDraft = true
        kanbanError = nil
        setStatusMessage(L10n.string("Creating Kanban task..."))

        do {
            let boardSlug = selectedKanbanBoardSlug
            let taskID: String
            if boardSlug == KanbanProject.workspaceTasksSlug {
                taskID = try await caelWorkspaceAPIService.createWorkspaceTask(
                    connection: profile,
                    draft: draft
                ).id
            } else {
                taskID = try await kanbanBrowserService.createTask(connection: profile, boardSlug: boardSlug, draft: draft)
            }
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            selectedKanbanTaskID = taskID
            if boardSlug == KanbanProject.workspaceTasksSlug {
                selectedKanbanTaskDetail = nil
            } else {
                await loadKanbanTaskDetail(taskID: taskID)
            }
            isSavingKanbanTaskDraft = false
            setStatusMessage(L10n.string("Kanban task created"))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingKanbanTaskDraft = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create Kanban task"))
            return false
        }
    }

    func moveWorkspaceKanbanTask(taskID: String, to status: KanbanTaskStatus) async {
        guard let profile = activeConnection else { return }
        guard isWorkspaceKanbanBoardSelected, !isOperatingOnKanbanTask else { return }

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            try await caelWorkspaceAPIService.moveWorkspaceTask(
                connection: profile,
                taskID: taskID,
                column: WorkspaceTaskColumn.fromKanbanStatus(status)
            )
            guard isActiveWorkspace(profile), isWorkspaceKanbanBoardSelected else { return }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            selectedKanbanTaskID = taskID
            selectedKanbanTaskDetail = nil
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Workspace task moved"))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to move Workspace task"))
        }
    }

    func deleteWorkspaceKanbanTask(taskID: String) async {
        guard let profile = activeConnection else { return }
        guard isWorkspaceKanbanBoardSelected, !isOperatingOnKanbanTask else { return }

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            try await caelWorkspaceAPIService.deleteWorkspaceTask(connection: profile, taskID: taskID)
            guard isActiveWorkspace(profile), isWorkspaceKanbanBoardSelected else { return }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            if selectedKanbanTaskID == taskID {
                selectedKanbanTaskID = kanbanBoard?.tasks.first?.id
            }
            selectedKanbanTaskDetail = nil
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Workspace task deleted"))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to delete Workspace task"))
        }
    }

    func updateWorkspaceKanbanTask(taskID: String, draft: KanbanTaskDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard isWorkspaceKanbanBoardSelected, !isOperatingOnKanbanTask else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            kanbanError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            try await caelWorkspaceAPIService.updateWorkspaceTask(
                connection: profile,
                taskID: taskID,
                title: draft.normalizedTitle,
                description: draft.normalizedBody ?? "",
                priority: WorkspaceTaskPriority.fromKanbanPriority(draft.priority),
                assignee: draft.normalizedAssignee,
                tags: draft.skills
            )
            guard isActiveWorkspace(profile), isWorkspaceKanbanBoardSelected else { return false }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            selectedKanbanTaskID = taskID
            selectedKanbanTaskDetail = nil
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Workspace task updated"))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to update Workspace task"))
            return false
        }
    }


    func launchWorkspaceKanbanTaskSession(taskID: String) async {
        guard let profile = activeConnection else { return }
        guard isWorkspaceKanbanBoardSelected, !isOperatingOnKanbanTask else { return }

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil
        setStatusMessage(L10n.string("Launching Workspace task session..."))

        do {
            let launch = try await caelWorkspaceAPIService.launchWorkspaceTaskSession(connection: profile, taskID: taskID)
            let sessionID = launch.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !sessionID.isEmpty else {
                throw SSHTransportError.invalidResponse("Workspace API did not return a task session id.")
            }
            _ = try await caelWorkspaceAPIService.linkWorkspaceTaskSession(connection: profile, taskID: taskID, sessionID: sessionID)
            guard isActiveWorkspace(profile), isWorkspaceKanbanBoardSelected else { return }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            selectedKanbanTaskID = taskID
            selectedKanbanTaskDetail = nil
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            await openWorkspaceTaskSession(sessionID: sessionID)
            setStatusMessage(L10n.string("Workspace task session launched"))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to launch Workspace task session"))
        }
    }

    func linkWorkspaceKanbanTaskSession(taskID: String, sessionID: String?) async {
        guard let profile = activeConnection else { return }
        guard isWorkspaceKanbanBoardSelected, !isOperatingOnKanbanTask else { return }
        let trimmedSessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedSessionID = trimmedSessionID.isEmpty ? nil : trimmedSessionID

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            _ = try await caelWorkspaceAPIService.linkWorkspaceTaskSession(
                connection: profile,
                taskID: taskID,
                sessionID: normalizedSessionID
            )
            guard isActiveWorkspace(profile), isWorkspaceKanbanBoardSelected else { return }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            selectedKanbanTaskID = taskID
            selectedKanbanTaskDetail = nil
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(normalizedSessionID == nil ? L10n.string("Workspace task session link cleared") : L10n.string("Workspace task session linked"))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to link Workspace task session"))
        }
    }

    func openWorkspaceTaskSession(sessionID: String) async {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else { return }

        stopSessionTUI()
        isNewSessionComposerActive = false
        selectedSessionDetailMode = .chat
        selectedSection = .sessions
        await loadSessions(
            reset: true,
            query: "",
            preferredSessionID: normalizedSessionID,
            allowsFallbackSelection: false,
            updatesSelection: false
        )
        await loadSessionDetail(sessionID: normalizedSessionID)
    }

    func addKanbanComment(taskID: String, body: String) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isOperatingOnKanbanTask else { return false }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            let boardSlug = selectedKanbanBoardSlug
            try await kanbanBrowserService.addComment(connection: profile, boardSlug: boardSlug, taskID: taskID, body: trimmed)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            await reloadKanbanAfterOperation(taskID: taskID, boardSlug: boardSlug)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Comment added"))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to add Kanban comment"))
            return false
        }
    }

    func updateKanbanTaskFields(
        taskID: String,
        body: String,
        tenant: String,
        priority: Int,
        skills: [String]
    ) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task details updated",
            failureMessage: "Unable to update Kanban task details"
        ) { profile, boardSlug in
            try await kanbanBrowserService.updateTaskFields(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                body: body,
                tenant: tenant,
                priority: priority,
                skills: skills
            )
        }
    }

    func setKanbanTaskParents(taskID: String, parentIDs: [String]) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task parents updated",
            failureMessage: "Unable to update Kanban task parents"
        ) { profile, boardSlug in
            try await kanbanBrowserService.setTaskParents(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                parentIDs: parentIDs
            )
        }
    }

    func setKanbanTaskChildren(taskID: String, childIDs: [String]) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task children updated",
            failureMessage: "Unable to update Kanban task children"
        ) { profile, boardSlug in
            try await kanbanBrowserService.setTaskChildren(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                childIDs: childIDs
            )
        }
    }

    func assignKanbanTask(taskID: String, assignee: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task assigned",
            failureMessage: "Unable to assign Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.assignTask(connection: profile, boardSlug: boardSlug, taskID: taskID, assignee: assignee)
        }
    }

    func specifyKanbanTask(taskID: String) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task specified",
            failureMessage: "Unable to specify Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.specifyTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
        }
    }

    func blockKanbanTask(taskID: String, reason: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task blocked",
            failureMessage: "Unable to block Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.blockTask(connection: profile, boardSlug: boardSlug, taskID: taskID, reason: reason)
        }
    }

    func unblockKanbanTask(taskID: String) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task unblocked",
            failureMessage: "Unable to unblock Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.unblockTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
        }
    }

    func completeKanbanTask(taskID: String, result: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task completed",
            failureMessage: "Unable to complete Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.completeTask(connection: profile, boardSlug: boardSlug, taskID: taskID, result: result)
        }
    }

    func reclaimKanbanTask(taskID: String, reason: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task reclaimed",
            failureMessage: "Unable to reclaim Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.reclaimTask(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                reason: reason
            )
        }
    }

    func reassignKanbanTask(taskID: String, assignee: String?, reclaimFirst: Bool, reason: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task reassigned",
            failureMessage: "Unable to reassign Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.reassignTask(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                assignee: assignee,
                reclaimFirst: reclaimFirst,
                reason: reason
            )
        }
    }

    func editKanbanTaskResult(taskID: String, result: String, summary: String?, metadataJSON: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task result edited",
            failureMessage: "Unable to edit Kanban task result"
        ) { profile, boardSlug in
            try await kanbanBrowserService.editCompletedTaskResult(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                result: result,
                summary: summary,
                metadataJSON: metadataJSON
            )
        }
    }

    func archiveKanbanTask(taskID: String) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task archived",
            failureMessage: "Unable to archive Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.archiveTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
        }
    }

    func deleteKanbanTask(taskID: String) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnKanbanTask else { return }

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            let boardSlug = selectedKanbanBoardSlug
            try await kanbanBrowserService.deleteTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            if selectedKanbanTaskID == nil {
                selectedKanbanTaskDetail = nil
            }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Kanban task deleted"))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to delete Kanban task"))
        }
    }

    func dispatchKanbanNow() async {
        guard let profile = activeConnection else { return }
        guard !isDispatchingKanban else { return }

        isDispatchingKanban = true
        kanbanError = nil
        setStatusMessage(L10n.string("Nudging Kanban dispatcher..."))

        do {
            let boardSlug = selectedKanbanBoardSlug
            let result = try await kanbanBrowserService.dispatchNow(connection: profile, boardSlug: boardSlug)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            isDispatchingKanban = false

            if let result {
                setStatusMessage(
                    L10n.string(
                        "Kanban dispatch: %@ spawned, %@ promoted",
                        "\(result.spawned.count)",
                        "\(result.promoted)"
                    )
                )
            } else {
                setStatusMessage(L10n.string("Kanban dispatcher nudged"))
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isDispatchingKanban = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to nudge Kanban dispatcher"))
        }
    }

    func setKanbanHomeSubscription(
        taskID: String,
        homeChannel: KanbanHomeChannel,
        subscribed: Bool
    ) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isOperatingOnKanbanTask else { return false }

        let boardSlug = selectedKanbanBoardSlug
        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            try await kanbanBrowserService.setHomeSubscription(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                homeChannel: homeChannel,
                subscribed: subscribed
            )
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            await loadKanbanTaskDetail(taskID: taskID)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(subscribed ? L10n.string("Home channel subscribed") : L10n.string("Home channel unsubscribed"))
            return true
        } catch {
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to update Kanban home channel"))
            return false
        }
    }

    func deleteConnection(_ profile: ConnectionProfile) {
        connectionStore.delete(profile)
        terminalWorkspace.closeTabs(forConnectionID: profile.id)
        if activeConnectionID == profile.id {
            activeConnectionID = nil
            resetWorkspaceStateForConnectionChange(closeTerminalTabs: false)
            selectedSection = .connections
        }
    }

    func ensureTerminalSession() {
        guard let profile = activeConnection else { return }
        terminalWorkspace.ensureInitialTab(for: profile)
    }

    private func openNewTerminalTab(for profile: ConnectionProfile) {
        terminalWorkspace.addTab(for: profile)
        selectedSection = .terminal
        handleSectionEntry(.terminal)
        setStatusMessage(L10n.string("New Terminal tab opened"))
    }

    func resumeSessionInTerminal(_ session: SessionSummary) {
        guard let profile = activeConnection else {
            sessionsError = L10n.string("Select a connection before resuming a session in Terminal.")
            setStatusMessage(L10n.string("No active connection"))
            return
        }

        let invocation = HermesSessionResumeInvocation(sessionID: session.id, connection: profile)
        terminalWorkspace.addCommandTab(
            for: profile.updated(),
            commandLine: invocation.startupCommandLine
        )
        selectedSection = .terminal
        handleSectionEntry(.terminal)
        setStatusMessage(L10n.string("Opening %@ in Terminal…", session.resolvedTitle))
    }

    private func operateOnKanbanTask(
        taskID: String,
        successMessage: String,
        failureMessage: String,
        operation: (ConnectionProfile, String) async throws -> Void
    ) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnKanbanTask else { return }

        let boardSlug = selectedKanbanBoardSlug
        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            try await operation(profile, boardSlug)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            await reloadKanbanAfterOperation(taskID: taskID, boardSlug: boardSlug)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string(successMessage))
        } catch {
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string(failureMessage))
        }
    }

    private func reloadKanbanAfterOperation(taskID: String, boardSlug: String) async {
        await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
        guard selectedKanbanBoardSlug == boardSlug else { return }
        if kanbanBoard?.tasks.contains(where: { $0.id == taskID }) == true {
            selectedKanbanTaskID = taskID
            await loadKanbanTaskDetail(taskID: taskID)
        }
    }

    private func handleSectionEntry(_ section: AppSection) {
        if section.isCommandCenterMirrorSection {
            Task { await loadCaelWorkspace() }
            return
        }

        switch section {
        case .overview:
            Task { await loadCaelWorkspace() }
        case .files:
            Task { await ensureInitialFileLoads() }
        case .sessions:
            Task { await loadSessions(reset: true) }
        case .workflows:
            Task {
                loadWorkflows(reset: true)
                await loadSkills(reset: false)
                loadWorkflows(reset: true)
            }
        case .cronjobs:
            Task { await loadCronJobs() }
        case .kanban:
            Task { await loadKanbanBoard() }
        case .usage:
            Task {
                await loadUsage(forceRefresh: true)
                await loadCaelProviderUsage(forceRefresh: true)
            }
        case .skills:
            Task { await loadSkills(reset: true) }
        case .terminal:
            ensureTerminalSession()
        case .connections, .mail, .contacts, .calendar, .missionControl, .operations, .swarm, .memory, .integrations, .mcp, .profiles:
            break
        }
    }

    @discardableResult
    private func checkForUpdates(presentsCurrentResult: Bool) async -> Bool {
        guard !isCheckingForUpdates else { return false }

        isCheckingForUpdates = true
        if presentsCurrentResult {
            setStatusMessage(L10n.string("Checking for Hermes Desktop updates…"))
        }

        do {
            let update = try await updateCheckService.checkForUpdate()
            isCheckingForUpdates = false

            if let update {
                availableUpdate = update
                setStatusMessage(L10n.string("Hermes Desktop update available: %@", update.latestVersion))
            } else if presentsCurrentResult {
                activeAlert = AppAlert(
                    title: L10n.string("Hermes Desktop is up to date"),
                    message: L10n.string(
                        "You are running Hermes Desktop %@, which matches the latest Hermes Desktop release.",
                        UpdateCheckService.bundleShortVersion()
                    )
                )
                setStatusMessage(nil)
            }
            return true
        } catch {
            isCheckingForUpdates = false
            if presentsCurrentResult {
                activeAlert = AppAlert(
                    title: L10n.string("Unable to check for updates"),
                    message: error.localizedDescription
                )
                setStatusMessage(nil)
            }
            return false
        }
    }

    private func shouldRunAutomaticUpdateCheck(now: Date = Date()) -> Bool {
        guard let lastAutomaticUpdateCheckAt = connectionStore.lastAutomaticUpdateCheckAt else {
            return true
        }

        return now.timeIntervalSince(lastAutomaticUpdateCheckAt) >= automaticUpdateCheckInterval
    }

    private func ensureInitialFileLoads() async {
        await loadSelectedWorkspaceFile()
    }

    private func document(for reference: WorkspaceFileReference) -> FileEditorDocument {
        var document = workspaceFileDocuments[reference.id] ??
            FileEditorDocument(fileID: reference.id, title: reference.title, remotePath: reference.remotePath)
        document.title = reference.title
        document.remotePath = reference.remotePath
        return document
    }

    private func resolvedRemotePath(for trackedFile: RemoteTrackedFile, connection: ConnectionProfile) -> String {
        trackedFile.resolvedRemotePath(using: overview?.paths) ?? connection.remotePath(for: trackedFile)
    }

    private func isActiveWorkspace(_ profile: ConnectionProfile) -> Bool {
        activeConnection?.workspaceScopeFingerprint == profile.workspaceScopeFingerprint
    }

    private func isActiveCaelWorkspace(_ profile: ConnectionProfile) -> Bool {
        activeConnection?.commandCenterClientFingerprint == profile.commandCenterClientFingerprint
    }

    private func setDocument(_ document: FileEditorDocument) {
        workspaceFileDocuments[document.fileID] = document
    }

    private func reloadWorkspaceScope(section: AppSection, statusMessage: String) async {
        resetWorkspaceStateForConnectionChange(closeTerminalTabs: false)
        selectedSection = section
        setStatusMessage(statusMessage)
        await prepareWorkspaceForActiveConnection()
        await reloadSectionAfterScopeChange(section)
    }

    private func reloadSectionAfterScopeChange(_ section: AppSection) async {
        if section.isCommandCenterMirrorSection {
            await loadCaelWorkspace()
            return
        }

        switch section {
        case .connections, .overview:
            break
        case .files:
            await ensureInitialFileLoads()
        case .sessions:
            await loadSessions(reset: true)
        case .workflows:
            loadWorkflows(reset: true)
            await loadSkills(reset: false)
            loadWorkflows(reset: true)
        case .cronjobs:
            await loadCronJobs()
        case .kanban:
            await loadKanbanBoard()
        case .usage:
            await loadUsage(forceRefresh: true)
        case .skills:
            await loadSkills(reset: true)
        case .terminal:
            ensureTerminalSession()
        case .mail, .contacts, .calendar, .missionControl, .operations, .swarm, .memory, .integrations, .mcp, .profiles:
            break
        }
    }

    private func clearSessionMessages() {
        acceptedWorkspaceChatEventsTask?.cancel()
        acceptedWorkspaceChatEventsTask = nil
        guard !sessionMessages.isEmpty ||
                !sessionMessageDisplays.isEmpty ||
                !liveSessionMessageDisplays.isEmpty ||
                !liveToolActivityCards.isEmpty ||
                !sessionPromptCards.isEmpty else {
            return
        }
        sessionMessages = []
        sessionMessageDisplays = []
        sessionMessageSignature = SessionMessageSignature(messages: [])
        clearNativeTurnUIState()
    }

    private func clearPersistedSessionMessages() {
        guard !sessionMessages.isEmpty || !sessionMessageDisplays.isEmpty else { return }
        sessionMessages = []
        sessionMessageDisplays = []
        sessionMessageSignature = SessionMessageSignature(messages: [])
    }

    private var shouldPreserveLiveTranscriptDuringSessionTransition: Bool {
        pendingSessionTurn != nil && (
            !liveSessionMessageDisplays.isEmpty ||
                !liveToolActivityCards.isEmpty ||
                !sessionPromptCards.isEmpty
        )
    }

    private func sessionStatusMessage(forConversationError message: String, fallback: String) -> String {
        if message.contains(approvalNeededMessage) {
            return L10n.string("Approval needed")
        }
        return L10n.string(fallback)
    }

    private func setSessionMessages(
        _ messages: [SessionMessage],
        for profile: ConnectionProfile? = nil,
        sessionID: String? = nil
    ) async {
        let signature = await Task.detached(priority: .userInitiated) {
            SessionMessageSignature(messages: messages)
        }.value

        if let profile {
            guard isActiveWorkspace(profile) else { return }
        }
        if let sessionID {
            guard selectedSessionID == sessionID else { return }
        }
        guard signature != sessionMessageSignature else { return }

        let displays = await Task.detached(priority: .userInitiated) {
            Self.makeSessionMessageDisplays(from: messages)
        }.value

        if let profile {
            guard isActiveWorkspace(profile) else { return }
        }
        if let sessionID {
            guard selectedSessionID == sessionID else { return }
        }
        applySessionMessages(messages, displays: displays, signature: signature)
    }

    private func hydrateSessionHistoryFromGateway(
        sessionID: String,
        using gatewayChatService: HermesGatewayChatService,
        profile: ConnectionProfile,
        updatesSelection: Bool = true
    ) async -> Bool {
        do {
            guard let messages = try await gatewaySessionHistory(
                sessionID: sessionID,
                using: gatewayChatService
            ), !messages.isEmpty else {
                return false
            }

            guard isActiveWorkspace(profile) else { return false }

            guard updatesSelection else { return true }

            isNewSessionComposerActive = false
            selectedSessionID = sessionID
            sessionsError = nil
            sessionConversationError = nil
            clearSessionScrollOffset(for: sessionID)
            await setSessionMessages(messages, for: profile, sessionID: sessionID)
            return true
        } catch {
            return false
        }
    }

    private func applySessionMessages(
        _ messages: [SessionMessage],
        displays: [SessionMessageDisplay],
        signature: SessionMessageSignature
    ) {
        guard signature != sessionMessageSignature else { return }
        sessionMessages = messages
        sessionMessageDisplays = displays
        sessionMessageSignature = signature
        clearNativeTurnUIState()
    }

    nonisolated private static func makeSessionMessageDisplays(
        from messages: [SessionMessage]
    ) -> [SessionMessageDisplay] {
        messages.map(SessionMessageDisplay.init)
    }

    private func gatewaySessionHistory(
        sessionID: String,
        using gatewayChatService: HermesGatewayChatService
    ) async throws -> [SessionMessage]? {
        let result = try await gatewayChatService.request(
            method: "session.history",
            params: [
                "session_id": .string(sessionID),
                "id": .string(sessionID)
            ],
            timeout: 60
        )
        let messages = HermesGatewayHistoryDecoder.sessionMessages(from: result)
        return messages.isEmpty ? nil : messages
    }

    private func preferredChatTransport(for connection: ConnectionProfile) async -> HermesChatTransportMode {
        let status = await refreshNativeChatBootstrapStatus(for: connection)
        return status.preferredTransportMode
    }

    @discardableResult
    private func refreshNativeChatBootstrapStatus(
        for connection: ConnectionProfile,
        force: Bool = false
    ) async -> HermesChatBootstrapStatus {
        let workspaceScopeFingerprint = connection.workspaceScopeFingerprint

        if !force,
           nativeChatStatusWorkspaceScopeFingerprint == workspaceScopeFingerprint,
           let nativeChatBootstrapStatus {
            return nativeChatBootstrapStatus
        }

        let status = await sshTransport.probeNativeChatAvailability(on: connection)
        guard isActiveWorkspace(connection) else { return status }
        nativeChatStatusWorkspaceScopeFingerprint = workspaceScopeFingerprint
        nativeChatBootstrapStatus = status
        return status
    }

    private func ensureGatewayChatService(
        for connection: ConnectionProfile
    ) async throws -> HermesGatewayChatService {
        let workspaceScopeFingerprint = connection.workspaceScopeFingerprint
        let status = await refreshNativeChatBootstrapStatus(for: connection)
        guard status.canUseNativeChat else {
            throw HermesGatewayError.remote(
                1,
                status.fallbackReason ?? "Native chat is unavailable for this host."
            )
        }

        if let gatewayChatService,
           gatewayWorkspaceScopeFingerprint == workspaceScopeFingerprint {
            return gatewayChatService
        }

        await closeGatewayChatSession(clearBootstrapStatus: false)

        let gatewayChatService = HermesGatewayChatService(
            connection: connection,
            sshTransport: sshTransport
        )
        self.gatewayChatService = gatewayChatService
        gatewayWorkspaceScopeFingerprint = workspaceScopeFingerprint
        gatewayEventsTask = Task { [weak self] in
            guard let self else { return }
            for await event in gatewayChatService.events {
                await MainActor.run {
                    self.applyGatewayEvent(event, workspaceScopeFingerprint: workspaceScopeFingerprint)
                }
            }
        }

        do {
            try await gatewayChatService.start()
            return gatewayChatService
        } catch {
            await closeGatewayChatSession(clearBootstrapStatus: false)
            var degradedStatus = status
            degradedStatus.canUseNativeChat = false
            degradedStatus.fallbackReason = error.localizedDescription
            nativeChatBootstrapStatus = degradedStatus
            throw error
        }
    }

    private func closeGatewayChatSession(clearBootstrapStatus: Bool) async {
        gatewayEventsTask?.cancel()
        gatewayEventsTask = nil

        if let gatewayChatService {
            await gatewayChatService.close()
        }

        self.gatewayChatService = nil
        gatewayWorkspaceScopeFingerprint = nil
        gatewaySessionID = nil
        activeGatewayAssistantMessageID = nil
        clearNativeTurnUIState()
        hasAcceptedNativeTurnInFlight = false
        completeActiveNativeTurn(success: false)
        activeNativeTurnResult = nil
        activeNativeTurnCompletion = nil

        if clearBootstrapStatus {
            nativeChatBootstrapStatus = nil
            nativeChatStatusWorkspaceScopeFingerprint = nil
        }
    }

    private func prepareGatewaySession(
        using gatewayChatService: HermesGatewayChatService,
        sessionID: String?
    ) async throws -> String {
        if let sessionID,
           sessionID == gatewaySessionID {
            return sessionID
        }

        if let sessionID {
            let result = try await gatewayChatService.request(
                method: "session.resume",
                params: [
                    "session_id": .string(sessionID),
                    "id": .string(sessionID)
                ],
                timeout: 60
            )
            applyGatewaySessionResult(result, preferredSessionID: sessionID)
            return gatewaySessionID ?? sessionID
        }

        let result = try await gatewayChatService.request(
            method: "session.create",
            params: [
                "client": .string("HermesDesktop"),
                "source": .string("macos"),
                "ui": .string("native")
            ],
            timeout: 60
        )
        applyGatewaySessionResult(result, preferredSessionID: nil)
        if let gatewaySessionID {
            return gatewaySessionID
        }
        throw HermesGatewayError.invalidFrame("session.create did not return a session identifier")
    }

    private func prepareActiveNativeTurnWait() {
        hasAcceptedNativeTurnInFlight = false
        activeNativeTurnResult = nil
        activeNativeTurnCompletion = nil
    }

    private func scheduleAcceptedWorkspaceSessionRefresh(sessionID: String, connection: ConnectionProfile) {
        let workspaceScopeFingerprint = connection.workspaceScopeFingerprint
        acceptedWorkspaceSessionMonitorTask?.cancel()
        acceptedWorkspaceChatEventsTask?.cancel()
        acceptedWorkspaceChatEventsTask = Task { [weak self] in
            var sawTerminalEvent = false
            while !Task.isCancelled, !sawTerminalEvent {
                sawTerminalEvent = await self?.tailAcceptedWorkspaceChatEvents(
                    sessionID: sessionID,
                    workspaceScopeFingerprint: workspaceScopeFingerprint,
                    timeoutSeconds: 8
                ) ?? false
                if sawTerminalEvent { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        acceptedWorkspaceSessionMonitorTask = Task { [weak self] in
            let startedAt = Date()
            var sawActiveRun = false
            var emptyRunChecks = 0

            for delay in [1.2, 3, 5, 8, 13] as [Double] {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }

                let run = await self?.refreshAcceptedWorkspaceSession(
                    sessionID: sessionID,
                    workspaceScopeFingerprint: workspaceScopeFingerprint
                )
                if let run {
                    sawActiveRun = true
                    emptyRunChecks = 0
                    if Self.isTerminalWorkspaceRunStatus(run.status) { return }
                } else {
                    emptyRunChecks += 1
                    if sawActiveRun { return }
                }
            }

            while !Task.isCancelled, Date().timeIntervalSince(startedAt) < 10 * 60 {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }

                let run = await self?.refreshAcceptedWorkspaceSession(
                    sessionID: sessionID,
                    workspaceScopeFingerprint: workspaceScopeFingerprint
                )
                if let run {
                    sawActiveRun = true
                    emptyRunChecks = 0
                    if Self.isTerminalWorkspaceRunStatus(run.status) { return }
                } else {
                    emptyRunChecks += 1
                    if sawActiveRun || emptyRunChecks >= 2 { return }
                }
            }
        }
    }

    @discardableResult
    private func refreshAcceptedWorkspaceSession(sessionID: String, workspaceScopeFingerprint: String) async -> WorkspaceSessionActiveRun? {
        guard let profile = activeConnection,
              profile.workspaceScopeFingerprint == workspaceScopeFingerprint else { return nil }
        var activeRun: WorkspaceSessionActiveRun?
        if selectedSessionID == sessionID {
            activeRun = await refreshWorkspaceSessionActiveRun(sessionID: sessionID, connection: profile)
            let loadedWorkspaceHistory = await hydrateWorkspaceSessionHistory(sessionID: sessionID, connection: profile)
            if !loadedWorkspaceHistory {
                await loadSessionDetail(sessionID: sessionID)
            }
        }
        await loadSessions(
            reset: true,
            query: sessionSearchQuery,
            preferredSessionID: sessionID,
            allowsFallbackSelection: false,
            updatesSelection: false
        )
        return activeRun
    }

    nonisolated private static func isTerminalWorkspaceRunStatus(_ status: String) -> Bool {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "complete", "completed", "succeeded", "success", "done", "failed", "failure", "error", "cancelled", "canceled":
            return true
        default:
            return false
        }
    }

    private func upsertAcceptedWorkspaceSessionSummary(sessionID: String, prompt: String, messageCount: Int) {
        let now = SessionTimestamp.unixSeconds(Date().timeIntervalSince1970)
        let title = String(prompt.prefix(80))
        let summary = SessionSummary(
            id: sessionID,
            title: title,
            model: nil,
            startedAt: now,
            lastActive: now,
            messageCount: messageCount,
            preview: prompt
        )
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index] = summary
        } else {
            sessions.insert(summary, at: 0)
            totalSessionsCount = max(totalSessionsCount, sessions.count)
        }
    }

    private func markAcceptedWorkspaceRun(_ response: WorkspaceSessionSendResponse, sessionID: String) {
        guard let runID = response.runId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !runID.isEmpty else {
            return
        }
        let now = Date().timeIntervalSince1970 * 1000
        workspaceSessionActiveRun = WorkspaceSessionActiveRun(
            runId: runID,
            sessionKey: sessionID,
            friendlyId: sessionID,
            status: "accepted",
            createdAt: now,
            updatedAt: now,
            lastEventAt: now,
            assistantText: "",
            thinkingText: "",
            toolCalls: [],
            lifecycleEvents: [],
            errorMessage: nil
        )
    }

    @discardableResult
    private func refreshWorkspaceSessionActiveRun(sessionID: String, connection: ConnectionProfile) async -> WorkspaceSessionActiveRun? {
        do {
            let response = try await caelWorkspaceAPIService.loadWorkspaceSessionActiveRun(
                connection: connection,
                sessionKey: sessionID
            )
            guard isActiveWorkspace(connection), selectedSessionID == sessionID else { return nil }
            workspaceSessionActiveRun = response.run
            return response.run
        } catch {
            return nil
        }
    }

    @discardableResult
    private func tailAcceptedWorkspaceChatEvents(
        sessionID: String,
        workspaceScopeFingerprint: String,
        timeoutSeconds: Int
    ) async -> Bool {
        guard let profile = activeConnection,
              profile.workspaceScopeFingerprint == workspaceScopeFingerprint,
              selectedSessionID == sessionID else { return true }

        do {
            let response = try await caelWorkspaceAPIService.tailWorkspaceChatEvents(
                connection: profile,
                sessionKey: sessionID,
                timeoutSeconds: timeoutSeconds
            )
            guard isActiveWorkspace(profile), selectedSessionID == sessionID else { return true }
            var terminalEvent = false
            for event in response.events {
                terminalEvent = applyWorkspaceChatEvent(event, sessionID: sessionID) || terminalEvent
            }
            return terminalEvent
        } catch {
            return false
        }
    }

    @discardableResult
    private func applyWorkspaceChatEvent(_ event: WorkspaceChatEvent, sessionID: String) -> Bool {
        if let eventSessionID = gatewayValue(in: event.data, keys: ["sessionKey"]),
           eventSessionID != sessionID {
            return false
        }

        switch event.event {
        case "connected", "heartbeat", "started", "user_message":
            return false
        case "message":
            startLiveAssistantMessage(with: workspaceAssistantMessagePayload(from: event.data))
            return false
        case "chunk":
            if event.data["fullReplace"]?.boolValue == true {
                replaceLiveAssistantText(from: event.data)
            } else {
                appendLiveAssistantDelta(from: event.data)
            }
            return false
        case "thinking":
            if let thinking = gatewayValue(in: event.data, keys: ["text", "delta", "content"]) {
                appendLiveSystemMessage(thinking)
            }
            return false
        case "tool", "artifact":
            let state = gatewayValue(in: event.data, keys: ["phase", "state", "status"])?.lowercased() ?? ""
            updateToolActivityCard(for: event.data, defaultRunning: state != "complete" && state != "completed")
            return false
        case "done":
            completeLiveAssistantMessage(from: event.data)
            return true
        case "error":
            let message = gatewayValue(in: event.data, keys: ["message", "error"]) ?? "Workspace chat event stream reported an error."
            appendLiveSystemMessage(message)
            sessionConversationError = message
            return true
        default:
            return false
        }
    }

    private func workspaceAssistantMessagePayload(from payload: [String: JSONValue]) -> [String: JSONValue] {
        guard let message = payload["message"]?.objectValue else { return payload }
        return [
            "id": message["id"] ?? .string(UUID().uuidString),
            "text": .string("")
        ]
    }

    private func hydrateWorkspaceSessionHistory(sessionID: String, connection: ConnectionProfile) async -> Bool {
        do {
            let response = try await caelWorkspaceAPIService.loadWorkspaceSessionHistory(
                connection: connection,
                sessionKey: sessionID
            )
            guard isActiveWorkspace(connection), selectedSessionID == sessionID else { return false }
            guard !response.messages.isEmpty else { return false }
            await setSessionMessages(response.messages, for: connection, sessionID: sessionID)
            if let last = response.messages.last {
                upsertAcceptedWorkspaceSessionSummary(
                    sessionID: sessionID,
                    prompt: last.content ?? sessionID,
                    messageCount: response.messages.count
                )
            }
            return true
        } catch {
            return false
        }
    }

    private func waitForActiveNativeTurnCompletion() async -> Bool {
        if let activeNativeTurnResult {
            return activeNativeTurnResult
        }

        return await withCheckedContinuation { continuation in
            activeNativeTurnCompletion = continuation
        }
    }

    private func completeActiveNativeTurn(success: Bool) {
        activeNativeTurnResult = success
        guard let activeNativeTurnCompletion else { return }
        self.activeNativeTurnCompletion = nil
        activeNativeTurnCompletion.resume(returning: success)
    }

    private func clearNativeTurnUIState() {
        activeGatewayAssistantMessageID = nil
        liveSessionMessageDisplays = []
        liveToolActivityCards = []
        sessionPromptCards = []
    }

    private func applyGatewayEvent(
        _ event: HermesGatewayEvent,
        workspaceScopeFingerprint: String
    ) {
        guard activeConnection?.workspaceScopeFingerprint == workspaceScopeFingerprint else {
            return
        }

        registerGatewaySessionID(from: event)

        switch event.type {
        case "session.info":
            break
        case "message.start":
            startLiveAssistantMessage(with: event.payload)
        case "message.delta":
            appendLiveAssistantDelta(from: event.payload)
        case "message.complete":
            completeLiveAssistantMessage(from: event.payload)
            completeActiveNativeTurn(success: true)
        case "tool.start":
            updateToolActivityCard(for: event.payload, defaultRunning: true)
        case "tool.progress":
            updateToolActivityCard(for: event.payload, defaultRunning: true)
        case "tool.complete":
            updateToolActivityCard(for: event.payload, defaultRunning: false)
        case "approval.request":
            upsertPromptCard(kind: .approval, payload: event.payload, fallbackSessionID: event.sessionID)
        case "clarify.request":
            upsertPromptCard(kind: .clarify, payload: event.payload, fallbackSessionID: event.sessionID)
        case "sudo.request":
            upsertPromptCard(kind: .sudo, payload: event.payload, fallbackSessionID: event.sessionID)
        case "secret.request":
            upsertPromptCard(kind: .secret, payload: event.payload, fallbackSessionID: event.sessionID)
        case "error":
            let message = gatewayValue(in: event.payload, keys: ["message", "error"]) ?? "Unknown gateway error"
            if isSendingSessionMessage || hasAcceptedNativeTurnInFlight {
                appendLiveSystemMessage(message)
            }
            sessionConversationError = message
            completeActiveNativeTurn(success: false)
        case "gateway.closed":
            if isSendingSessionMessage || hasAcceptedNativeTurnInFlight {
                let message = gatewayValue(in: event.payload, keys: ["error"]) ?? "Native chat disconnected."
                appendLiveSystemMessage(message)
                sessionConversationError = message
                completeActiveNativeTurn(success: false)
            }
        default:
            break
        }
    }

    private func applyGatewaySessionResult(
        _ result: JSONValue?,
        preferredSessionID: String?
    ) {
        guard let object = result?.objectValue else {
            if let preferredSessionID {
                gatewaySessionID = preferredSessionID
            }
            return
        }

        if let sessionID = gatewayValue(in: object, keys: ["session_id", "id"]) ?? preferredSessionID {
            gatewaySessionID = sessionID
        }
    }

    private func registerGatewaySessionID(from event: HermesGatewayEvent) {
        let candidateSessionID: String?
        if event.type == "session.info" {
            candidateSessionID = event.sessionID ?? gatewayValue(in: event.payload, keys: ["session_id", "id"])
        } else {
            candidateSessionID = event.sessionID ?? gatewayValue(in: event.payload, keys: ["session_id"])
        }

        guard let candidateSessionID, !candidateSessionID.isEmpty else { return }
        gatewaySessionID = candidateSessionID
    }

    private func registerSessionCompaction(_ notice: SessionCompactionNotice) {
        guard notice.sourceSessionID != notice.targetSessionID else { return }
        guard sessionCompactionNotice != notice else { return }

        sessionCompactionNotice = notice
        setStatusMessage(L10n.string("Conversation compacted. Open the new session from history to continue."))
    }

    private func startLiveAssistantMessage(with payload: [String: JSONValue]) {
        let initialText = gatewayValue(in: payload, keys: ["text", "delta", "content"]) ?? ""
        let messageID = gatewayValue(in: payload, keys: ["message_id", "id"]) ?? UUID().uuidString
        activeGatewayAssistantMessageID = messageID
        liveSessionMessageDisplays.append(
            SessionMessageDisplay(
                id: messageID,
                role: .assistant,
                content: initialText,
                isStreaming: true
            )
        )
    }

    private func appendLiveAssistantDelta(from payload: [String: JSONValue]) {
        let delta = gatewayValue(in: payload, keys: ["text", "delta", "content"]) ?? ""
        guard !delta.isEmpty else { return }

        if activeGatewayAssistantMessageID == nil {
            startLiveAssistantMessage(with: payload)
            return
        }

        guard let messageID = activeGatewayAssistantMessageID,
              let index = liveSessionMessageDisplays.lastIndex(where: { $0.id == messageID }) else {
            return
        }

        let existing = liveSessionMessageDisplays[index]
        liveSessionMessageDisplays[index] = SessionMessageDisplay(
            id: existing.id,
            role: existing.role,
            content: (existing.content ?? "") + delta,
            timestampText: existing.timestampText,
            metadataItems: existing.metadataItems,
            toolSummary: existing.toolSummary,
            isStreaming: true
        )
    }

    private func replaceLiveAssistantText(from payload: [String: JSONValue]) {
        let text = gatewayValue(in: payload, keys: ["text", "content"]) ?? ""
        guard !text.isEmpty else { return }

        if activeGatewayAssistantMessageID == nil {
            startLiveAssistantMessage(with: payload)
            return
        }

        guard let messageID = activeGatewayAssistantMessageID,
              let index = liveSessionMessageDisplays.lastIndex(where: { $0.id == messageID }) else {
            return
        }

        let existing = liveSessionMessageDisplays[index]
        liveSessionMessageDisplays[index] = SessionMessageDisplay(
            id: existing.id,
            role: existing.role,
            content: text,
            timestampText: existing.timestampText,
            metadataItems: existing.metadataItems,
            toolSummary: existing.toolSummary,
            isStreaming: true
        )
    }

    private func completeLiveAssistantMessage(from payload: [String: JSONValue]) {
        if activeGatewayAssistantMessageID == nil {
            startLiveAssistantMessage(with: payload)
        }

        if let messageID = activeGatewayAssistantMessageID,
           let index = liveSessionMessageDisplays.lastIndex(where: { $0.id == messageID }) {
            let existing = liveSessionMessageDisplays[index]
            let text = gatewayValue(in: payload, keys: ["text", "content"]) ?? existing.content
            liveSessionMessageDisplays[index] = SessionMessageDisplay(
                id: existing.id,
                role: existing.role,
                content: text,
                timestampText: existing.timestampText,
                metadataItems: existing.metadataItems,
                toolSummary: existing.toolSummary,
                isStreaming: false
            )
        }

        activeGatewayAssistantMessageID = nil
    }

    private func appendPendingUserLiveMessage(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        liveSessionMessageDisplays.append(
            SessionMessageDisplay(
                id: "live-user-\(UUID().uuidString)",
                role: .user,
                content: trimmedPrompt
            )
        )
    }

    private func appendLiveSystemMessage(_ message: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        if let lastMessage = liveSessionMessageDisplays.last,
           lastMessage.role == .system,
           lastMessage.content == trimmedMessage {
            return
        }

        liveSessionMessageDisplays.append(
            SessionMessageDisplay(
                id: "live-system-\(UUID().uuidString)",
                role: .system,
                content: trimmedMessage
            )
        )
    }

    private func updateToolActivityCard(
        for payload: [String: JSONValue],
        defaultRunning: Bool
    ) {
        let toolID = gatewayValue(in: payload, keys: ["tool_call_id", "id", "tool_id", "name"]) ?? UUID().uuidString
        let title = gatewayValue(in: payload, keys: ["title", "name", "tool"]) ?? "Tool activity"
        let status = gatewayValue(in: payload, keys: ["status", "message", "state"]) ?? (defaultRunning ? "Running" : "Complete")
        let detail = gatewayValue(in: payload, keys: ["detail", "summary", "output"])
        let isRunning = payload["running"]?.boolValue ?? defaultRunning
        let updatedAt = Date()

        if let index = liveToolActivityCards.firstIndex(where: { $0.id == toolID }) {
            liveToolActivityCards[index].title = title
            liveToolActivityCards[index].status = status
            liveToolActivityCards[index].detail = detail
            liveToolActivityCards[index].isRunning = isRunning
            liveToolActivityCards[index].updatedAt = updatedAt
        } else {
            liveToolActivityCards.append(
                HermesToolActivityCard(
                    id: toolID,
                    title: title,
                    status: status,
                    detail: detail,
                    isRunning: isRunning,
                    updatedAt: updatedAt
                )
            )
        }

        if liveToolActivityCards.count > 12 {
            liveToolActivityCards.removeFirst(liveToolActivityCards.count - 12)
        }
    }

    private func upsertPromptCard(
        kind: HermesPromptKind,
        payload: [String: JSONValue],
        fallbackSessionID: String?
    ) {
        let requestID = gatewayValue(in: payload, keys: ["request_id", "id", "approval_id"]) ?? UUID().uuidString
        let title = gatewayValue(in: payload, keys: ["title", "prompt", "kind"]) ?? kind.rawValue.capitalized
        let message = gatewayValue(in: payload, keys: ["message", "text", "body"]) ?? ""
        let sessionID = gatewayValue(in: payload, keys: ["session_id"]) ?? fallbackSessionID
        let choices = payload["choices"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let placeholder = gatewayValue(in: payload, keys: ["placeholder", "hint"])
        let toolName = gatewayValue(in: payload, keys: ["tool_name", "tool", "name"])
        let actionText = gatewayDisplayValue(
            in: payload,
            keys: ["action", "summary", "operation", "reason", "description"],
            maximumLength: 220
        )
        let previewText = gatewayDisplayValue(
            in: payload,
            keys: ["preview", "command_preview", "command", "argv", "input"],
            maximumLength: 600
        )

        let card = HermesPromptCard(
            id: "\(kind.rawValue)-\(requestID)",
            sessionID: sessionID,
            requestID: requestID,
            kind: kind,
            title: title,
            message: message,
            choices: choices,
            placeholder: placeholder,
            toolName: toolName,
            actionText: actionText,
            previewText: previewText == actionText ? nil : previewText
        )

        if let index = sessionPromptCards.firstIndex(where: { $0.id == card.id }) {
            sessionPromptCards[index] = card
        } else {
            sessionPromptCards.append(card)
        }
    }

    private func gatewayValue(
        in payload: [String: JSONValue],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = payload[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func gatewayDisplayValue(
        in payload: [String: JSONValue],
        keys: [String],
        maximumLength: Int
    ) -> String? {
        for key in keys {
            guard let value = payload[key] else { continue }
            let text = value.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if text.count <= maximumLength {
                return text
            }

            let endIndex = text.index(text.startIndex, offsetBy: maximumLength)
            return text[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }

        return nil
    }

    private func startSessionTranscriptPolling(sessionID: String, connection: ConnectionProfile) {
        stopSessionTranscriptPolling()
        let workspaceScopeFingerprint = connection.workspaceScopeFingerprint

        sessionTranscriptPollingTask = Task { [sessionBrowserService] in
            while !Task.isCancelled {
                do {
                    let messages = try await sessionBrowserService.loadTranscript(
                        connection: connection,
                        sessionID: sessionID
                    )

                    let signature = await Task.detached(priority: .utility) {
                        SessionMessageSignature(messages: messages)
                    }.value

                    let shouldBuildDisplays = await MainActor.run { [weak self] in
                        guard let self,
                              self.activeConnection?.workspaceScopeFingerprint == workspaceScopeFingerprint,
                              self.isSendingSessionMessage,
                              self.selectedSessionID == sessionID else {
                            return false
                        }
                        return signature != self.sessionMessageSignature
                    }

                    guard shouldBuildDisplays else {
                        try? await Task.sleep(for: .seconds(2))
                        continue
                    }

                    let displays = await Task.detached(priority: .utility) {
                        Self.makeSessionMessageDisplays(from: messages)
                    }.value

                    await MainActor.run { [weak self] in
                        guard let self,
                              self.activeConnection?.workspaceScopeFingerprint == workspaceScopeFingerprint,
                              self.isSendingSessionMessage,
                              self.selectedSessionID == sessionID else {
                            return
                        }
                        self.applySessionMessages(messages, displays: displays, signature: signature)
                    }
                } catch {
                    // Keep polling best-effort; a transient SSH/store read failure
                    // should not end the in-flight chat turn.
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopSessionTranscriptPolling() {
        sessionTranscriptPollingTask?.cancel()
        sessionTranscriptPollingTask = nil
    }

    private func loadUsageProfileBreakdown(
        using connection: ConnectionProfile,
        activeSummary: UsageSummary,
        discoveredProfiles: [RemoteHermesProfile]
    ) async -> UsageProfileBreakdown {
        var slices: [UsageProfileSlice] = []
        let activeProfileName = connection.resolvedHermesProfileName

        for discoveredProfile in discoveredProfiles {
            if discoveredProfile.name == activeProfileName {
                slices.append(
                    usageProfileSlice(
                        for: discoveredProfile,
                        summary: activeSummary,
                        activeProfileName: activeProfileName
                    )
                )
                continue
            }

            let scopedConnection = connection.applyingHermesProfile(named: discoveredProfile.name)

            do {
                let summary = try await usageBrowserService.loadUsage(
                    connection: scopedConnection,
                    hintedSessionStore: nil
                )

                slices.append(
                    usageProfileSlice(
                        for: discoveredProfile,
                        summary: summary,
                        activeProfileName: activeProfileName
                    )
                )
            } catch {
                slices.append(
                    UsageProfileSlice(
                        profileName: discoveredProfile.name,
                        hermesHomePath: discoveredProfile.path,
                        state: .unavailable,
                        sessionCount: 0,
                        inputTokens: 0,
                        outputTokens: 0,
                        cacheReadTokens: 0,
                        cacheWriteTokens: 0,
                        reasoningTokens: 0,
                        databasePath: nil,
                        message: error.localizedDescription,
                        isActiveProfile: discoveredProfile.name == activeProfileName
                    )
                )
            }
        }

        return UsageProfileBreakdown(profiles: slices)
    }

    private func usageProfileSlice(
        for discoveredProfile: RemoteHermesProfile,
        summary: UsageSummary,
        activeProfileName: String
    ) -> UsageProfileSlice {
        UsageProfileSlice(
            profileName: discoveredProfile.name,
            hermesHomePath: discoveredProfile.path,
            state: summary.state,
            sessionCount: summary.sessionCount,
            inputTokens: summary.inputTokens,
            outputTokens: summary.outputTokens,
            cacheReadTokens: summary.cacheReadTokens,
            cacheWriteTokens: summary.cacheWriteTokens,
            reasoningTokens: summary.reasoningTokens,
            databasePath: summary.databasePath,
            message: summary.message,
            isActiveProfile: discoveredProfile.name == activeProfileName
        )
    }

    private func prepareWorkspaceForActiveConnection() async {
        guard let profile = activeConnection else { return }
        await refreshOverview()
        guard isActiveWorkspace(profile) else { return }

        guard overviewError == nil else {
            isRefreshingOverview = false
            sessions = []
            clearSessionMessages()
            sessionsError = nil
            isLoadingSessions = false
            isRefreshingSessions = false
            pendingSessionReloadQuery = nil
            isSendingSessionMessage = false
            sessionConversationError = nil
            pendingSessionTurn = nil
            hasAcceptedNativeTurnInFlight = false
            sessionCompactionNotice = nil
            selectedSessionDetailMode = .transcript
            stopSessionTUI()
            clearNativeTurnUIState()
            nativeChatBootstrapStatus = nil
            nativeChatStatusWorkspaceScopeFingerprint = nil
            stopSessionTranscriptPolling()
            Task { [weak self] in
                await self?.closeGatewayChatSession(clearBootstrapStatus: true)
            }
            workflows = []
            selectedWorkflowID = nil
            usageSummary = nil
            usageProfileBreakdown = nil
            usageError = nil
            isLoadingUsage = false
            isRefreshingUsage = false
            skills = []
            selectedSkillID = nil
            selectedSkillDetail = nil
            skillsError = nil
            isLoadingSkills = false
            isRefreshingSkills = false
            isLoadingSkillDetail = false
            isSavingSkillDraft = false
            cronJobs = []
            selectedCronJobID = nil
            cronJobsError = nil
            isLoadingCronJobs = false
            isRefreshingCronJobs = false
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            isSavingCronJobDraft = false
            kanbanBoards = []
            selectedKanbanBoardSlug = KanbanProject.defaultSlug
            remoteCurrentKanbanBoardSlug = nil
            supportsKanbanBoardManagement = false
            kanbanBoard = nil
            selectedKanbanTaskID = nil
            selectedKanbanTaskDetail = nil
            kanbanError = nil
            isLoadingKanbanBoards = false
            isLoadingKanbanBoard = false
            isRefreshingKanbanBoard = false
            isLoadingKanbanTaskDetail = false
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            isSavingKanbanTaskDraft = false
            isSavingKanbanBoardDraft = false
            isOperatingOnKanbanBoard = false
            isDispatchingKanban = false
            includeArchivedKanbanTasks = false
            resetDocuments()
            return
        }

        await ensureInitialFileLoads()
        await loadSessions(reset: true)
    }


    @discardableResult
    private func applyCachedCommandCenterSnapshot(for profile: ConnectionProfile, reason: String) -> Bool {
        guard let cached = caelCommandCenterSnapshotStore.load(for: profile) else { return false }
        caelCommandCenterSummary = cached.summaryEnvelope?.data
        caelCommandCenterSections = cached.sections
        let cachedAt = cached.cachedAt.formatted(date: .abbreviated, time: .shortened)
        let notice = "Showing last-known command center snapshot from \(cachedAt). \(reason)"
        var warnings = cached.summaryEnvelope?.warnings ?? []
        warnings.insert(notice, at: 0)
        caelCommandCenterWarnings = warnings
        caelCommandCenterCacheNotice = notice
        return true
    }

    private func resetCaelWorkspaceState() {
        caelWorkspaceStatus = nil
        caelIntegrationStatus = nil
        caelProviderUsageLimits = nil
        caelN8nGovernance = nil
        caelN8nGovernanceError = nil
        caelCommandCenterSummary = nil
        caelCommandCenterSections = nil
        caelCommandCenterWarnings = []
        caelCommandCenterCacheNotice = nil
        caelWorkspaceError = nil
        caelProviderUsageError = nil
        isLoadingCaelWorkspace = false
        isRefreshingCaelWorkspace = false
        isLoadingCaelProviderUsage = false
        isRefreshingCaelProviderUsage = false
    }

    private func resetWorkspaceStateForConnectionChange(closeTerminalTabs: Bool = true) {
        isBusy = false
        connectionTestRequestID = nil
        overview = nil
        overviewError = nil
        isRefreshingOverview = false
        sessions = []
        clearSessionMessages()
        sessionsError = nil
        isLoadingSessions = false
        isRefreshingSessions = false
        isDeletingSession = false
        isSendingSessionMessage = false
        sessionConversationError = nil
        pendingSessionTurn = nil
        hasAcceptedNativeTurnInFlight = false
        sessionCompactionNotice = nil
        selectedSessionDetailMode = .transcript
        stopSessionTUI()
        clearNativeTurnUIState()
        nativeChatBootstrapStatus = nil
        nativeChatStatusWorkspaceScopeFingerprint = nil
        stopSessionTranscriptPolling()
        Task { [weak self] in
            await self?.closeGatewayChatSession(clearBootstrapStatus: true)
        }
        hasMoreSessions = false
        totalSessionsCount = 0
        selectedSessionID = nil
        isNewSessionComposerActive = false
        sessionOffset = 0
        pendingSessionReloadQuery = nil
        pendingSectionEntryAction = nil
        sessionSearchQuery = ""
        workflows = []
        selectedWorkflowID = nil
        usageSummary = nil
        usageProfileBreakdown = nil
        usageError = nil
        isLoadingUsage = false
        isRefreshingUsage = false
        resetCaelWorkspaceState()
        skills = []
        selectedSkillID = nil
        selectedSkillDetail = nil
        skillsError = nil
        isLoadingSkills = false
        isRefreshingSkills = false
        isLoadingSkillDetail = false
        isSavingSkillDraft = false
        cronJobs = []
        selectedCronJobID = nil
        cronJobsError = nil
        isLoadingCronJobs = false
        isRefreshingCronJobs = false
        isOperatingOnCronJob = false
        operatingCronJobID = nil
        isSavingCronJobDraft = false
        kanbanBoards = []
        selectedKanbanBoardSlug = KanbanProject.defaultSlug
        remoteCurrentKanbanBoardSlug = nil
        supportsKanbanBoardManagement = false
        kanbanBoard = nil
        selectedKanbanTaskID = nil
        selectedKanbanTaskDetail = nil
        kanbanError = nil
        isLoadingKanbanBoards = false
        isLoadingKanbanBoard = false
        isRefreshingKanbanBoard = false
        isLoadingKanbanTaskDetail = false
        isOperatingOnKanbanTask = false
        operatingKanbanTaskID = nil
        isSavingKanbanTaskDraft = false
        isSavingKanbanBoardDraft = false
        isOperatingOnKanbanBoard = false
        isDispatchingKanban = false
        includeArchivedKanbanTasks = false
        resetDocuments()
        if closeTerminalTabs {
            terminalWorkspace.closeAllTabs()
        }
    }

    private func resetDocuments() {
        workspaceFileDocuments = [:]
        workspaceFileBrowserListing = nil
        workspaceFileBrowserError = nil
        workspaceFileBrowserNotice = nil
        isLoadingWorkspaceFileBrowser = false
        workspacePreviewFile = nil
        workspacePreviewError = nil
        isLoadingWorkspacePreview = false
        isUploadingWorkspaceFile = false
        selectedWorkspaceFileID = RemoteTrackedFile.memory.workspaceFileID
    }

    private func setStatusMessage(_ message: String?) {
        statusTask?.cancel()
        statusMessage = message

        guard let message else { return }

        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.statusMessage == message else { return }
                self.statusMessage = nil
            }
        }
    }
}

private struct SessionMessageSignature: Equatable, Sendable {
    let count: Int
    let digest: Int

    init(messages: [SessionMessage]) {
        var hasher = Hasher()
        hasher.combine(messages.count)

        for message in messages {
            hasher.combine(message.id)
            hasher.combine(message.role)
            hasher.combine(message.content)
            hasher.combine(message.timestamp)
            hasher.combine(message.metadata)
        }

        count = messages.count
        digest = hasher.finalize()
    }
}

private struct ConnectionTestRequest: Encodable {}

private struct ConnectionTestResponse: Decodable {
    let ok: Bool
    let remoteHome: String
    let pythonExecutable: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case remoteHome = "remote_home"
        case pythonExecutable = "python_executable"
    }
}
