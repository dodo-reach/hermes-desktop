import Combine
import Foundation
import SwiftUI

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
    @Published var sessions: [SessionSummary] = []
    @Published var sessionMessages: [SessionMessage] = []
    @Published var sessionsError: String?
    @Published var isLoadingSessions = false
    @Published var isRefreshingSessions = false
    @Published var isDeletingSession = false
    @Published var hasMoreSessions = false
    @Published var totalSessionsCount = 0
    @Published private(set) var sessionSearchQuery = ""
    @Published var usageSummary: UsageSummary?
    @Published var usageError: String?
    @Published var isLoadingUsage = false
    @Published var isRefreshingUsage = false
    @Published var selectedSkillID: String?
    @Published var skills: [SkillSummary] = []
    @Published var selectedSkillDetail: SkillDetail?
    @Published var skillsError: String?
    @Published var isLoadingSkills = false
    @Published var isRefreshingSkills = false
    @Published var isLoadingSkillDetail = false
    @Published var cronJobs: [CronJob] = []
    @Published var selectedCronJobID: String?
    @Published var cronJobsError: String?
    @Published var isLoadingCronJobs = false
    @Published var isRefreshingCronJobs = false
    @Published var isOperatingOnCronJob = false
    @Published var operatingCronJobID: String?
    @Published var isSavingCronJobDraft = false
    @Published var selectedTrackedFile: RemoteTrackedFile = .memory
    @Published var memoryDocument = FileEditorDocument(trackedFile: .memory)
    @Published var userDocument = FileEditorDocument(trackedFile: .user)
    @Published var soulDocument = FileEditorDocument(trackedFile: .soul)
    @Published var pendingSectionSelection: AppSection?
    @Published var showDiscardChangesAlert = false

    let connectionStore: ConnectionStore
    let sshTransport: SSHTransport
    let remoteHermesService: RemoteHermesService
    let fileEditorService: FileEditorService
    let sessionBrowserService: SessionBrowserService
    let usageBrowserService: UsageBrowserService
    let skillBrowserService: SkillBrowserService
    let cronBrowserService: CronBrowserService
    let terminalWorkspace: TerminalWorkspaceStore

    private let sessionPageSize = 50
    private var sessionOffset = 0
    private var statusTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let paths = AppPaths()
        let connectionStore = ConnectionStore(paths: paths)
        let sshTransport = SSHTransport(paths: paths)

        self.connectionStore = connectionStore
        self.sshTransport = sshTransport
        self.remoteHermesService = RemoteHermesService(sshTransport: sshTransport)
        self.fileEditorService = FileEditorService(sshTransport: sshTransport)
        self.sessionBrowserService = SessionBrowserService(sshTransport: sshTransport)
        self.usageBrowserService = UsageBrowserService(sshTransport: sshTransport)
        self.skillBrowserService = SkillBrowserService(sshTransport: sshTransport)
        self.cronBrowserService = CronBrowserService(sshTransport: sshTransport)
        self.terminalWorkspace = TerminalWorkspaceStore(sshTransport: sshTransport)

        connectionStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
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

    var hasUnsavedFileChanges: Bool {
        memoryDocument.isDirty || userDocument.isDirty || soulDocument.isDirty
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

    func discardChangesAndContinue() {
        memoryDocument.discardChanges()
        userDocument.discardChanges()
        soulDocument.discardChanges()
        if let pendingSectionSelection {
            selectedSection = pendingSectionSelection
            handleSectionEntry(pendingSectionSelection)
        }
        pendingSectionSelection = nil
    }

    func stayOnCurrentSection() {
        pendingSectionSelection = nil
    }

    func connect(to profile: ConnectionProfile) {
        let isSwitchingConnection = activeConnectionID != profile.id

        if isSwitchingConnection {
            resetWorkspaceStateForConnectionChange()
        }

        activeConnectionID = profile.id
        connectionStore.lastConnectionID = profile.id
        var updatedProfile = profile
        updatedProfile.lastConnectedAt = Date()
        connectionStore.upsert(updatedProfile)
        selectedSection = .overview
        setStatusMessage("Connecting to \(profile.label)…")

        Task {
            await prepareWorkspaceForActiveConnection()
        }
    }

    func reconnectActiveConnection() {
        Task {
            guard activeConnection != nil else { return }
            setStatusMessage("Reconnecting…")
            await prepareWorkspaceForActiveConnection()
        }
    }

    func testConnection(_ profile: ConnectionProfile) {
        Task {
            do {
                isBusy = true
                setStatusMessage("Testing \(profile.label)…")

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

                isBusy = false
                let home = response.remoteHome.trimmingCharacters(in: .whitespacesAndNewlines)
                setStatusMessage("SSH and python3 OK for \(profile.label)")
                let messageLines = [
                    "SSH and python3 are available for this Hermes host.",
                    home.isEmpty ? nil : "Remote HOME: \(home)"
                ].compactMap { $0 }
                activeAlert = AppAlert(
                    title: "Connection OK",
                    message: messageLines.joined(separator: "\n")
                )
            } catch {
                isBusy = false
                activeAlert = AppAlert(
                    title: "Connection failed",
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
            overview = try await remoteHermesService.discover(connection: profile)
            isBusy = false
            if manual {
                isRefreshingOverview = false
            }
        } catch {
            isBusy = false
            if manual {
                isRefreshingOverview = false
            }
            overview = nil
            overviewError = error.localizedDescription
            setStatusMessage("Unable to refresh remote discovery")
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

    func refreshSkills() async {
        guard !isLoadingSkills, !isRefreshingSkills else { return }
        isRefreshingSkills = true
        await loadSkills(reset: true)
        isRefreshingSkills = false
    }

    func refreshCronJobs() async {
        guard !isLoadingCronJobs, !isRefreshingCronJobs else { return }
        isRefreshingCronJobs = true
        await loadCronJobs()
        isRefreshingCronJobs = false
    }

    func loadTrackedFile(_ trackedFile: RemoteTrackedFile, forceReload: Bool = false) async {
        guard let profile = activeConnection else { return }
        var document = document(for: trackedFile)

        if document.hasLoaded && !forceReload {
            return
        }

        document.isLoading = true
        document.errorMessage = nil
        setDocument(document)

        do {
            let snapshot = try await fileEditorService.read(file: trackedFile, connection: profile)
            document.content = snapshot.content
            document.originalContent = snapshot.content
            document.remoteContentHash = snapshot.contentHash
            document.lastSavedAt = nil
            document.errorMessage = nil
            document.isLoading = false
            document.hasLoaded = true
            setDocument(document)
        } catch {
            document.isLoading = false
            document.errorMessage = error.localizedDescription
            setDocument(document)
        }
    }

    func saveTrackedFile(_ trackedFile: RemoteTrackedFile) async {
        guard let profile = activeConnection else { return }
        var document = document(for: trackedFile)
        document.isLoading = true
        document.errorMessage = nil
        setDocument(document)

        do {
            let saveResult = try await fileEditorService.write(
                file: trackedFile,
                content: document.content,
                expectedContentHash: document.remoteContentHash,
                connection: profile
            )
            document.originalContent = document.content
            document.remoteContentHash = saveResult.contentHash
            document.lastSavedAt = Date()
            document.hasLoaded = true
            document.isLoading = false
            setDocument(document)
            setStatusMessage("\(trackedFile.fileName) saved")
        } catch {
            document.isLoading = false
            document.errorMessage = error.localizedDescription
            setDocument(document)
            setStatusMessage(error.localizedDescription)
        }
    }

    func updateDocument(_ trackedFile: RemoteTrackedFile, content: String) {
        var document = document(for: trackedFile)
        document.content = content
        setDocument(document)
    }

    func loadSessions(reset: Bool = false, query: String? = nil) async {
        guard let profile = activeConnection else { return }
        if isLoadingSessions { return }

        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? sessionSearchQuery
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
                let preferredSessionID: String?
                if let previousSelectedSessionID,
                   sessions.contains(where: { $0.id == previousSelectedSessionID }) {
                    preferredSessionID = previousSelectedSessionID
                } else {
                    preferredSessionID = sessions.first?.id
                }

                if let preferredSessionID {
                    await loadSessionDetail(sessionID: preferredSessionID)
                } else {
                    selectedSessionID = nil
                    sessionMessages = []
                }
            }
        } catch {
            isLoadingSessions = false
            sessionsError = error.localizedDescription
            setStatusMessage("Unable to load sessions")
        }
    }

    func loadSessionDetail(sessionID: String) async {
        guard let profile = activeConnection else { return }
        selectedSessionID = sessionID
        sessionsError = nil

        do {
            sessionMessages = try await sessionBrowserService.loadTranscript(
                connection: profile,
                sessionID: sessionID
            )
        } catch {
            sessionMessages = []
            sessionsError = error.localizedDescription
            setStatusMessage("Unable to load session transcript")
        }
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

            await loadSessions(reset: true)
            await loadUsage(forceRefresh: true)
            isDeletingSession = false
            setStatusMessage("Session deleted locally and on the remote Hermes host")
        } catch {
            isDeletingSession = false
            sessionsError = error.localizedDescription
            setStatusMessage("Unable to delete session")
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
            usageSummary = try await usageBrowserService.loadUsage(
                connection: profile,
                hintedSessionStore: overview?.sessionStore
            )
            isLoadingUsage = false
        } catch {
            isLoadingUsage = false
            usageSummary = nil
            usageError = error.localizedDescription
            setStatusMessage("Unable to load usage")
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
            skills = items
            isLoadingSkills = false

            if reset {
                let preferredSkillID: String?
                if let previousSelectedSkillID,
                   items.contains(where: { $0.id == previousSelectedSkillID }) {
                    preferredSkillID = previousSelectedSkillID
                } else {
                    preferredSkillID = items.first?.id
                }

                if let preferredSkillID {
                    await loadSkillDetail(relativePath: preferredSkillID)
                } else {
                    selectedSkillID = nil
                    selectedSkillDetail = nil
                    isLoadingSkillDetail = false
                }
            }
        } catch {
            isLoadingSkills = false
            skillsError = error.localizedDescription
            setStatusMessage("Unable to load skills")
        }
    }

    func loadSkillDetail(relativePath: String) async {
        guard let profile = activeConnection else { return }
        selectedSkillID = relativePath
        selectedSkillDetail = nil
        skillsError = nil
        isLoadingSkillDetail = true

        do {
            let detail = try await skillBrowserService.loadSkillDetail(
                connection: profile,
                relativePath: relativePath
            )

            guard selectedSkillID == relativePath else { return }
            selectedSkillDetail = detail
            isLoadingSkillDetail = false
        } catch {
            guard selectedSkillID == relativePath else { return }
            selectedSkillDetail = nil
            isLoadingSkillDetail = false
            skillsError = error.localizedDescription
            setStatusMessage("Unable to load skill detail")
        }
    }

    func loadCronJobs() async {
        guard let profile = activeConnection else { return }
        if isLoadingCronJobs { return }

        let previousSelectedCronJobID = selectedCronJobID
        isLoadingCronJobs = true
        cronJobsError = nil

        do {
            let jobs = try await cronBrowserService.listJobs(connection: profile)
            cronJobs = jobs
            isLoadingCronJobs = false

            if let previousSelectedCronJobID,
               jobs.contains(where: { $0.id == previousSelectedCronJobID }) {
                selectedCronJobID = previousSelectedCronJobID
            } else {
                selectedCronJobID = jobs.first?.id
            }
        } catch {
            isLoadingCronJobs = false
            cronJobsError = error.localizedDescription
            setStatusMessage("Unable to load cron jobs")
        }
    }

    func pauseCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await cronBrowserService.pauseJob(connection: profile, jobID: job.id)
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage("\(job.resolvedName) paused")
        } catch {
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage("Unable to pause cron job")
        }
    }

    func createCronJob(_ draft: CronJobDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingCronJobDraft, !isOperatingOnCronJob else { return false }

        if let validationError = draft.validationError {
            cronJobsError = validationError
            setStatusMessage(validationError)
            return false
        }

        isSavingCronJobDraft = true
        cronJobsError = nil
        setStatusMessage("Creating cron job…")

        do {
            let jobID = try await cronBrowserService.createJob(connection: profile, draft: draft)
            await loadCronJobs()
            selectedCronJobID = jobID
            isSavingCronJobDraft = false
            setStatusMessage("\(draft.normalizedName) created")
            return true
        } catch {
            isSavingCronJobDraft = false
            cronJobsError = error.localizedDescription
            setStatusMessage("Unable to create cron job")
            return false
        }
    }

    func updateCronJob(_ job: CronJob, draft: CronJobDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingCronJobDraft, !isOperatingOnCronJob else { return false }

        if let validationError = draft.validationError {
            cronJobsError = validationError
            setStatusMessage(validationError)
            return false
        }

        isSavingCronJobDraft = true
        cronJobsError = nil
        setStatusMessage("Updating \(job.resolvedName)…")

        do {
            try await cronBrowserService.updateJob(connection: profile, jobID: job.id, draft: draft)
            await loadCronJobs()
            selectedCronJobID = job.id
            isSavingCronJobDraft = false
            setStatusMessage("\(draft.normalizedName) updated")
            return true
        } catch {
            isSavingCronJobDraft = false
            cronJobsError = error.localizedDescription
            setStatusMessage("Unable to update cron job")
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
            try await cronBrowserService.resumeJob(connection: profile, jobID: job.id)
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage("\(job.resolvedName) resumed")
        } catch {
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage("Unable to resume cron job")
        }
    }

    func deleteCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await cronBrowserService.removeJob(connection: profile, jobID: job.id)
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage("\(job.resolvedName) removed")
        } catch {
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage("Unable to remove cron job")
        }
    }

    func runCronJobNow(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil
        setStatusMessage("Triggering \(job.resolvedName)…")

        do {
            try await cronBrowserService.runJobNow(connection: profile, jobID: job.id)
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage("Run requested for \(job.resolvedName)")
        } catch {
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage("Unable to run cron job")
        }
    }

    func deleteConnection(_ profile: ConnectionProfile) {
        connectionStore.delete(profile)
        if activeConnectionID == profile.id {
            activeConnectionID = nil
            resetWorkspaceStateForConnectionChange()
            selectedSection = .connections
        }
    }

    func ensureTerminalSession() {
        guard let profile = activeConnection else { return }
        terminalWorkspace.ensureInitialTab(for: profile)
    }

    private func handleSectionEntry(_ section: AppSection) {
        switch section {
        case .overview:
            Task { await refreshOverview() }
        case .files:
            Task { await ensureInitialFileLoads() }
        case .sessions:
            Task { await loadSessions(reset: true) }
        case .cronjobs:
            Task { await loadCronJobs() }
        case .usage:
            Task { await loadUsage(forceRefresh: true) }
        case .skills:
            Task { await loadSkills(reset: true) }
        case .terminal:
            ensureTerminalSession()
        case .connections:
            break
        }
    }

    private func ensureInitialFileLoads() async {
        await loadTrackedFile(.user, forceReload: true)
        await loadTrackedFile(.memory, forceReload: true)
        await loadTrackedFile(.soul, forceReload: true)
    }

    private func document(for trackedFile: RemoteTrackedFile) -> FileEditorDocument {
        switch trackedFile {
        case .user:
            return userDocument
        case .memory:
            return memoryDocument
        case .soul:
            return soulDocument
        }
    }

    private func setDocument(_ document: FileEditorDocument) {
        switch document.trackedFile {
        case .user:
            userDocument = document
        case .memory:
            memoryDocument = document
        case .soul:
            soulDocument = document
        }
    }

    private func prepareWorkspaceForActiveConnection() async {
        guard activeConnection != nil else { return }
        await refreshOverview()

        guard overviewError == nil else {
            isRefreshingOverview = false
            sessions = []
            sessionMessages = []
            sessionsError = nil
            isLoadingSessions = false
            isRefreshingSessions = false
            usageSummary = nil
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
            cronJobs = []
            selectedCronJobID = nil
            cronJobsError = nil
            isLoadingCronJobs = false
            isRefreshingCronJobs = false
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            isSavingCronJobDraft = false
            resetDocuments()
            return
        }

        await ensureInitialFileLoads()
        await loadSessions(reset: true)
    }

    private func resetWorkspaceStateForConnectionChange() {
        overview = nil
        overviewError = nil
        isRefreshingOverview = false
        sessions = []
        sessionMessages = []
        sessionsError = nil
        isLoadingSessions = false
        isRefreshingSessions = false
        isDeletingSession = false
        hasMoreSessions = false
        totalSessionsCount = 0
        selectedSessionID = nil
        sessionOffset = 0
        sessionSearchQuery = ""
        usageSummary = nil
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
        cronJobs = []
        selectedCronJobID = nil
        cronJobsError = nil
        isLoadingCronJobs = false
        isRefreshingCronJobs = false
        isOperatingOnCronJob = false
        operatingCronJobID = nil
        isSavingCronJobDraft = false
        resetDocuments()
        terminalWorkspace.closeAllTabs()
    }

    private func resetDocuments() {
        memoryDocument = FileEditorDocument(trackedFile: .memory)
        userDocument = FileEditorDocument(trackedFile: .user)
        soulDocument = FileEditorDocument(trackedFile: .soul)
        selectedTrackedFile = .memory
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
