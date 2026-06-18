#if canImport(UIKit)
@preconcurrency import Citadel
import Crypto
import Foundation
import NIOCore
@preconcurrency import NIOSSH
import OSLog
import Security
import SwiftUI
import UIKit

@MainActor
final class HermesPhoneStore: ObservableObject {
    enum CompanionScope: Hashable {
        case gateway
        case profiles
        case kanban
        case config
        case environment
    }

    @Published var selectedRootTab: HermesPhoneRootTab = .sessions
    @Published var sessionNavigationPath: [HermesPhoneSessionRoute] = []
    @Published var connections: [ConnectionProfile] = []
    @Published var activeConnectionID: UUID?
    @Published var activeHostFingerprint: String?
    @Published var activeProfileNameByHost: [String: String] = [:]
    @Published var overview: RemoteDiscovery?
    @Published var sessions: [SessionSummary] = []
    @Published var sessionsLoadState: SessionListLoadState = .idle
    @Published var hasMoreSessions = false
    @Published var totalSessionsCount = 0
    @Published var cronJobs: [CronJob] = []
    @Published var directoryListing: RemoteDirectoryListing?
    @Published var activeDirectoryPath: String = "~/.hermes"
    @Published var skills: [SkillSummary] = []
    @Published var selectedSkillDetail: SkillDetail?
    @Published var skillsError: String?
    @Published var isLoadingOverview = false
    @Published var isLoadingSessions = false
    @Published var isLoadingCronJobs = false
    @Published var isLoadingFiles = false
    @Published var isLoadingSkills = false
    @Published var isLoadingSkillDetail = false
    @Published var isBusy = false
    @Published var activeCronOperation: CronOperationState?
    @Published var alertMessage: String?
    @Published var hostKeyPrompt: HostKeyTrustPrompt?
    @Published var fileEditor: RemoteFileDraft?
    @Published var gatewaySnapshot: GatewaySnapshot?
    @Published var profileSnapshot: ProfileManagementSnapshot?
    @Published var kanbanSnapshot: KanbanMobileSnapshot?
    @Published var configSnapshot: ConfigSnapshot?
    @Published var environmentSnapshot: EnvironmentSnapshot?
    @Published private(set) var loadingCompanionScopes: Set<CompanionScope> = []
    @Published private(set) var workspaceFileBookmarks: [WorkspaceFileBookmark] = []

    let terminalWorkspace = HermesTerminalWorkspaceStore()

    private let secretsStore = ConnectionSecretsStore()
    private let sshTransport = SSHTransport()
    private lazy var remoteHermesService = RemoteHermesService(sshTransport: sshTransport)
    private lazy var sessionBrowserService = SessionBrowserService(sshTransport: sshTransport)
    private lazy var cronBrowserService = CronBrowserService(sshTransport: sshTransport)
    private lazy var fileEditorService = FileEditorService(sshTransport: sshTransport)
    private lazy var skillBrowserService = SkillBrowserService(sshTransport: sshTransport)
    private lazy var mobileCompanionService = MobileCompanionService(sshTransport: sshTransport)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let sessionPageSize = 20
    private var currentSessionsLoadID: UUID?
    private var sessionOffset = 0
    private var sessionSearchQuery = ""
    private var transcriptCache: [String: [SessionMessage]] = [:]
    private var transcriptRequests: [String: (id: UUID, task: Task<[SessionMessage], Error>)] = [:]
    private var sessionCacheByWorkspace: [String: [SessionSummary]] = [:]
    private var transcriptSnapshotCacheByWorkspace: [String: [String: [SessionMessage]]] = [:]
    private var transcriptPrefetchTask: Task<Void, Never>?
    private var hiddenProfilesByHost: [String: Set<String>] = [:]
    private var selectedKanbanBoardByWorkspace: [String: String] = [:]
    private var companionRequestIDs: [CompanionScope: UUID] = [:]
    private var overviewLoadingWorkspaceFingerprint: String?
    private var skillsLoadingWorkspaceFingerprint: String?

    init() {
        terminalWorkspace.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.persistConnections()
            }
        }
        loadPersistedConnections()
        markSessionsPendingLoadIfNeeded()
    }

    var activeConnection: ConnectionProfile? {
        guard let activeHostFingerprint else { return nil }
        return connectionForHost(fingerprint: activeHostFingerprint)
    }

    var activeHostConnections: [ConnectionProfile] {
        connectionsForActiveHost
    }

    var activeWorkspaceScopeFingerprint: String? {
        activeConnection?.workspaceScopeFingerprint
    }

    var terminalConnection: ConnectionProfile? {
        activeConnection?.updated()
    }

    func isLoadingCompanion(_ scope: CompanionScope) -> Bool {
        loadingCompanionScopes.contains(scope)
    }

    var activeTerminalHostFingerprint: String? {
        terminalConnection?.hostConnectionFingerprint
    }

    var availableProfiles: [RemoteHermesProfile] {
        var profiles = overview?.availableProfiles ?? []

        let localProfiles = (activeHostConnections + [activeConnection].compactMap { $0 }).map {
            RemoteHermesProfile(
                name: $0.resolvedHermesProfileName,
                path: $0.remoteHermesHomePath,
                isDefault: $0.usesDefaultHermesProfile,
                exists: true
            )
        }

        for localProfile in localProfiles where !profiles.contains(where: { $0.name == localProfile.name }) {
            profiles.append(localProfile)
        }

        let hidden = activeHostFingerprint.flatMap { hiddenProfilesByHost[$0] } ?? []
        return profiles.filter { !hidden.contains($0.name) }.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var untrackedProfiles: [RemoteHermesProfile] {
        guard let host = activeHostFingerprint else { return [] }
        let hidden = hiddenProfilesByHost[host] ?? []
        return (overview?.availableProfiles ?? []).filter { hidden.contains($0.name) }
    }

    var selectedKanbanBoard: String {
        guard let workspace = activeWorkspaceScopeFingerprint else { return "default" }
        return selectedKanbanBoardByWorkspace[workspace] ?? "default"
    }

    private var connectionsForActiveHost: [ConnectionProfile] {
        guard let activeHostFingerprint else { return [] }
        return connections
            .filter { $0.hostConnectionFingerprint == activeHostFingerprint }
            .sorted { lhs, rhs in
                if lhs.usesDefaultHermesProfile != rhs.usesDefaultHermesProfile {
                    return lhs.usesDefaultHermesProfile
                }
                return lhs.resolvedHermesProfileName.localizedCaseInsensitiveCompare(rhs.resolvedHermesProfileName) == .orderedAscending
            }
    }

    var canonicalFileReferences: [WorkspaceFileReference] {
        guard let activeConnection else { return [] }
        return RemoteTrackedFile.allCases.map { trackedFile in
            WorkspaceFileReference.canonical(
                trackedFile,
                remotePath: trackedFile.resolvedRemotePath(using: overview?.paths) ??
                    activeConnection.remotePath(for: trackedFile)
            )
        }
    }

    var bookmarkedWorkspaceFileReferences: [WorkspaceFileReference] {
        guard let activeConnection else { return [] }
        return workspaceFileBookmarks
            .filter { $0.workspaceScopeFingerprint == activeConnection.workspaceScopeFingerprint }
            .sorted { lhs, rhs in
                lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
            .map(WorkspaceFileReference.bookmark)
    }

    var bookmarkedWorkspaceFileGroups: [WorkspaceFileBookmarkGroup] {
        WorkspaceFileBookmarkGroup.groups(for: bookmarkedWorkspaceFileReferences)
    }

    func credential(for connection: ConnectionProfile) throws -> SSHCredentialRecord {
        guard let credential = try secretsStore.load(for: connection.id) else {
            throw HermesPhoneStoreError.missingCredential
        }
        return credential
    }

    func saveConnection(
        profile: ConnectionProfile,
        credential: SSHCredentialRecord,
        makeActive: Bool
    ) {
        var updatedConnections = connections
        let normalized = profile.updated()

        if let index = updatedConnections.firstIndex(where: { $0.id == normalized.id }) {
            updatedConnections[index] = normalized
        } else {
            updatedConnections.append(normalized)
        }

        updatedConnections.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        connections = updatedConnections
        if makeActive {
            let selectedProfileName = activeHostFingerprint.flatMap { activeProfileNameByHost[$0] }
            selectProfileConnection(normalized)
            if let selectedProfileName, normalized.usesDefaultHermesProfile {
                activeProfileNameByHost[normalized.hostConnectionFingerprint] = selectedProfileName
            }
            markSessionsPendingLoadIfNeeded()
        } else if normalized.hostConnectionFingerprint == activeHostFingerprint,
                  normalized.resolvedHermesProfileName == activeProfileNameByHost[normalized.hostConnectionFingerprint] {
            activeConnectionID = normalized.id
        }

        do {
            try secretsStore.save(credential, for: normalized.id)
            persistConnections()
        } catch {
            present(error)
        }
    }

    func removeConnection(_ profile: ConnectionProfile) {
        connections.removeAll { $0.id == profile.id }
        secretsStore.delete(for: profile.id)
        terminalWorkspace.closeSessions(forConnectionID: profile.id)
        if activeConnectionID == profile.id || activeHostFingerprint == profile.hostConnectionFingerprint {
            overview = nil
            resetCompanionState()
            markSessionsPendingLoadIfNeeded()
            cronJobs = []
            skills = []
            selectedSkillDetail = nil
            skillsError = nil
            directoryListing = nil
            fileEditor = nil
            activeProfileNameByHost[profile.hostConnectionFingerprint] = nil
            if connections.contains(where: { $0.hostConnectionFingerprint == profile.hostConnectionFingerprint }) {
                let replacement = connections
                    .filter { $0.hostConnectionFingerprint == profile.hostConnectionFingerprint }
                    .sorted { $0.resolvedHermesProfileName.localizedCaseInsensitiveCompare($1.resolvedHermesProfileName) == .orderedAscending }
                    .first
                if let replacement {
                    selectProfileConnection(replacement)
                    activeDirectoryPath = replacement.remoteHermesHomePath
                }
            } else if let first = connections.first {
                selectProfileConnection(first)
                activeDirectoryPath = first.remoteHermesHomePath
            } else {
                activeConnectionID = nil
                activeHostFingerprint = nil
            }
        }
        persistConnections()
    }

    func activateConnection(_ profile: ConnectionProfile) {
        selectProfileConnection(profile)
        markSessionsPendingLoadIfNeeded()
        cronJobs = []
        skills = []
        selectedSkillDetail = nil
        skillsError = nil
        directoryListing = nil
        fileEditor = nil
        activeDirectoryPath = profile.remoteHermesHomePath
        overview = nil
        resetCompanionState()
        persistConnections()
    }

    func activateHost(_ hostFingerprint: String) {
        guard let connection = connectionForHost(fingerprint: hostFingerprint) else { return }
        activateConnection(connection)
    }

    func configuredProfileConnectionForActiveHost(named profileName: String) -> ConnectionProfile? {
        guard let activeHostFingerprint else { return nil }
        return profileConnection(forHost: activeHostFingerprint, profileName: profileName)
    }

    func switchHermesProfile(to profileName: String) async {
        guard let activeHostFingerprint else { return }
        let previousWorkspaceFingerprint = activeWorkspaceScopeFingerprint
        guard fileEditor == nil else {
            present(SSHTransportError.invalidConnection("Close the open file before switching Hermes profiles."))
            return
        }
        guard let profileConnection = profileConnection(forHost: activeHostFingerprint, profileName: profileName) else {
            present(SSHTransportError.invalidConnection("Choose a saved host before switching profiles."))
            return
        }

        selectProfileConnection(profileConnection)
        if previousWorkspaceFingerprint != profileConnection.workspaceScopeFingerprint {
            markSessionsPendingLoadIfNeeded()
            cronJobs = []
            skills = []
            selectedSkillDetail = nil
            skillsError = nil
            directoryListing = nil
            fileEditor = nil
            activeDirectoryPath = profileConnection.remoteHermesHomePath
            overview = nil
            resetCompanionState()
            persistConnections()
        }
        await refreshOverview()
    }

    func testConnection(profile: ConnectionProfile, credential: SSHCredentialRecord) async -> String? {
        do {
            try validateDraft(profile: profile, credential: credential)
            try secretsStore.save(credential, for: profile.id)
            let discovery = try await remoteHermesService.discover(connection: profile.updated())
            if activeConnectionID == profile.id || activeConnectionID == nil {
                overview = discovery
                activeDirectoryPath = discovery.hermesHome
            }
            return "Connected to \(profile.displayDestination)."
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return nil
        } catch {
            present(error)
            return error.localizedDescription
        }
    }

    func refreshOverview() async {
        guard let connection = activeConnection else { return }
        let requestedFingerprint = connection.workspaceScopeFingerprint
        guard overviewLoadingWorkspaceFingerprint != requestedFingerprint else { return }
        overviewLoadingWorkspaceFingerprint = requestedFingerprint
        isLoadingOverview = true
        defer {
            if overviewLoadingWorkspaceFingerprint == requestedFingerprint {
                overviewLoadingWorkspaceFingerprint = nil
                isLoadingOverview = false
            }
        }

        do {
            let discovery = try await remoteHermesService.discover(connection: connection)
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            overview = discovery
            activeDirectoryPath = overview?.hermesHome ?? connection.remoteHermesHomePath
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return
        } catch {
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            if overview == nil {
                present(error)
            }
        }
    }

    func loadSessions(query: String = "") async {
        await loadSessionsPage(query: query, reset: true)
    }

    func loadMoreSessions() async {
        await loadSessionsPage(query: sessionSearchQuery, reset: false)
    }

    private func loadSessionsPage(query: String, reset: Bool) async {
        guard let connection = activeConnection else {
            sessions = []
            sessionsLoadState = .idle
            hasMoreSessions = false
            totalSessionsCount = 0
            sessionOffset = 0
            sessionSearchQuery = ""
            currentSessionsLoadID = nil
            isLoadingSessions = false
            return
        }
        guard reset || hasMoreSessions else { return }
        let requestedFingerprint = connection.workspaceScopeFingerprint
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        currentSessionsLoadID = requestID
        sessionSearchQuery = normalizedQuery
        sessionsLoadState = .loading
        isLoadingSessions = true
        defer {
            if currentSessionsLoadID == requestID {
                currentSessionsLoadID = nil
                isLoadingSessions = false
            }
        }

        do {
            let page = try await sessionBrowserService.listSessions(
                connection: connection,
                offset: reset ? 0 : sessionOffset,
                limit: sessionPageSize,
                query: normalizedQuery
            )
            guard currentSessionsLoadID == requestID,
                  activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            let incoming = deduplicatedSessionLineage(page.items)
            if reset {
                sessions = mergeSessionPage(
                    previous: sessions,
                    incoming: incoming,
                    keepIDs: []
                )
                sessionOffset = page.items.count
            } else {
                sessions = deduplicatedSessionLineage(sessions + incoming)
                sessionOffset += page.items.count
            }
            totalSessionsCount = page.totalCount
            hasMoreSessions = sessionOffset < totalSessionsCount
            cacheSessionsForActiveWorkspace(sessions)
            scheduleRecentTranscriptPrefetch()
            sessionsLoadState = .loaded
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            guard currentSessionsLoadID == requestID,
                  activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            sessionsLoadState = sessions.isEmpty ? .pending : .loaded
        } catch {
            guard currentSessionsLoadID == requestID,
                  activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            sessionsLoadState = .failed
            present(error)
        }
    }

    func cachedTranscript(for sessionID: String) -> [SessionMessage]? {
        guard let connection = activeConnection else { return nil }
        let cacheKey = transcriptCacheKey(connection: connection, sessionID: sessionID)
        if let transcript = transcriptCache[cacheKey] {
            return transcript
        }
        guard let snapshot = transcriptSnapshotCacheByWorkspace[connection.workspaceScopeFingerprint]?[sessionID] else {
            return nil
        }
        transcriptCache[cacheKey] = snapshot
        return snapshot
    }

    func transcript(for sessionID: String) async throws -> [SessionMessage] {
        guard let connection = activeConnection else { return [] }
        let cacheKey = transcriptCacheKey(connection: connection, sessionID: sessionID)
        if let request = transcriptRequests[cacheKey] {
            return try await request.task.value
        }

        let requestID = UUID()
        let request = Task {
            try await sessionBrowserService.loadTranscript(
                connection: connection,
                sessionID: sessionID
            )
        }
        transcriptRequests[cacheKey] = (requestID, request)

        do {
            let transcript = try await request.value
            if transcriptRequests[cacheKey]?.id == requestID {
                transcriptRequests[cacheKey] = nil
            }
            transcriptCache[cacheKey] = transcript
            cacheTranscriptSnapshot(transcript, sessionID: sessionID, connection: connection)
            return transcript
        } catch {
            if transcriptRequests[cacheKey]?.id == requestID {
                transcriptRequests[cacheKey] = nil
            }
            throw error
        }
    }

    private func mergeSessionPage(
        previous: [SessionSummary],
        incoming: [SessionSummary],
        keepIDs: Set<String>
    ) -> [SessionSummary] {
        guard !keepIDs.isEmpty else { return incoming }

        let incomingIDs = Set(incoming.map(\.id))
        let incomingLineageIDs = Set(incoming.map(\.lineageMatchID))
        let survivors = previous.filter { session in
            !incomingIDs.contains(session.id) &&
                !incomingLineageIDs.contains(session.lineageMatchID) &&
                (keepIDs.contains(session.id) ||
                    keepIDs.contains(session.durableSessionID) ||
                    keepIDs.contains(session.lineageMatchID))
        }

        return survivors.isEmpty ? incoming : survivors + incoming
    }

    private func deduplicatedSessionLineage(_ items: [SessionSummary]) -> [SessionSummary] {
        var seen = Set<String>()
        return items.filter { session in
            let key = session.lineageMatchID
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    func ensureTerminalConnected() {
        guard let connection = terminalConnection else { return }
        terminalWorkspace.ensureSingleSession(for: connection)
        selectedRootTab = .terminal
    }

    func openNewTerminalSession() {
        openMonoTerminalSession()
    }

    func openMonoTerminalSession() {
        guard let connection = terminalConnection else { return }
        terminalWorkspace.ensureSingleSession(for: connection)
        selectedRootTab = .terminal
    }

    func loadCronJobs() async {
        guard let connection = activeConnection else { return }
        isLoadingCronJobs = true
        defer { isLoadingCronJobs = false }

        do {
            cronJobs = try await cronBrowserService.listJobs(connection: connection)
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return
        } catch {
            present(error)
        }
    }

    func loadSkills() async {
        guard let connection = activeConnection else { return }
        let requestedFingerprint = connection.workspaceScopeFingerprint
        guard skillsLoadingWorkspaceFingerprint != requestedFingerprint else { return }
        skillsLoadingWorkspaceFingerprint = requestedFingerprint
        isLoadingSkills = true
        skillsError = nil
        defer {
            if skillsLoadingWorkspaceFingerprint == requestedFingerprint {
                skillsLoadingWorkspaceFingerprint = nil
                isLoadingSkills = false
            }
        }

        do {
            let loadedSkills = try await skillBrowserService.listSkills(connection: connection)
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            skills = loadedSkills
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return
        } catch {
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            skillsError = error.localizedDescription
        }
    }

    func loadSkillDetail(summary: SkillSummary) async {
        guard let connection = activeConnection else { return }
        let requestedFingerprint = connection.workspaceScopeFingerprint
        isLoadingSkillDetail = true
        skillsError = nil
        defer { isLoadingSkillDetail = false }

        do {
            let detail = try await skillBrowserService.loadSkillDetail(
                connection: connection,
                locator: summary.locator
            )
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            selectedSkillDetail = detail
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return
        } catch {
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            skillsError = error.localizedDescription
        }
    }

    func operateCron(
        _ job: CronJob,
        kind: CronOperationKind,
        operation: @escaping (CronBrowserService, ConnectionProfile, String) async throws -> Void
    ) async {
        guard let connection = activeConnection else { return }
        guard activeCronOperation?.jobID != job.id else { return }
        isBusy = true
        activeCronOperation = CronOperationState(jobID: job.id, kind: kind)
        defer {
            isBusy = false
            activeCronOperation = nil
        }

        do {
            try await operation(cronBrowserService, connection, job.id)
            cronJobs = try await cronBrowserService.listJobs(connection: connection)
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return
        } catch {
            present(error)
        }
    }

    func browseDirectory(path: String? = nil) async {
        guard let connection = activeConnection else { return }
        let requestedFingerprint = connection.workspaceScopeFingerprint
        directoryListing = nil
        isLoadingFiles = true
        defer { isLoadingFiles = false }

        do {
            let resolvedPath = (path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? path!
                : (overview?.hermesHome ?? connection.remoteHermesHomePath)
            let listing = try await fileEditorService.listDirectory(
                remotePath: resolvedPath,
                hermesHome: connection.remoteHermesHomePath,
                connection: connection
            )
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            directoryListing = listing
            activeDirectoryPath = listing.displayPath
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return
        } catch {
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            present(error)
        }
    }

    func openCanonicalFile(_ reference: WorkspaceFileReference) async {
        await openRemoteFile(remotePath: reference.remotePath, title: reference.title)
    }

    func openWorkspaceFileReference(_ reference: WorkspaceFileReference) async {
        if reference.opensDirectory {
            await browseDirectory(path: reference.remotePath)
        } else {
            await openRemoteFile(remotePath: reference.remotePath, title: reference.title)
        }
    }

    func openDirectoryEntry(_ entry: RemoteDirectoryEntry) async {
        switch entry.kind {
        case .directory:
            await browseDirectory(path: entry.path)
        case .file, .symlink:
            await openRemoteFile(remotePath: entry.displayPath, title: entry.name)
        case .other:
            break
        }
    }

    @discardableResult
    func addWorkspaceFileBookmark(
        remotePath: String,
        title: String? = nil,
        targetKind: WorkspaceFileBookmark.TargetKind,
        selectAfterAdd: Bool = false
    ) -> WorkspaceFileBookmark? {
        guard let activeConnection else { return nil }
        let normalizedRemotePath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRemotePath.isEmpty else { return nil }

        if let index = workspaceFileBookmarks.firstIndex(where: {
            $0.workspaceScopeFingerprint == activeConnection.workspaceScopeFingerprint &&
                $0.remotePath == normalizedRemotePath
        }) {
            var bookmark = workspaceFileBookmarks[index]
            bookmark.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? bookmark.title
            bookmark.targetKind = targetKind
            bookmark.updatedAt = Date()
            workspaceFileBookmarks[index] = bookmark
            persistConnections()
            if selectAfterAdd {
                Task { await openWorkspaceFileReference(.bookmark(bookmark)) }
            }
            return bookmark
        }

        let bookmark = WorkspaceFileBookmark(
            workspaceScopeFingerprint: activeConnection.workspaceScopeFingerprint,
            remotePath: normalizedRemotePath,
            title: title,
            targetKind: targetKind
        )
        workspaceFileBookmarks.append(bookmark)
        persistConnections()
        if selectAfterAdd {
            Task { await openWorkspaceFileReference(.bookmark(bookmark)) }
        }
        return bookmark
    }

    func removeWorkspaceFileBookmark(id: UUID) {
        workspaceFileBookmarks.removeAll { $0.id == id }
        persistConnections()
    }

    func removeWorkspaceFileBookmark(remotePath: String) {
        guard let activeConnection else { return }
        let normalizedRemotePath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaceFileBookmarks.removeAll {
            $0.workspaceScopeFingerprint == activeConnection.workspaceScopeFingerprint &&
                $0.remotePath == normalizedRemotePath
        }
        persistConnections()
    }

    func isWorkspaceFileBookmarked(remotePath: String) -> Bool {
        guard let activeConnection else { return false }
        let normalizedRemotePath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return workspaceFileBookmarks.contains {
            $0.workspaceScopeFingerprint == activeConnection.workspaceScopeFingerprint &&
                $0.remotePath == normalizedRemotePath
        }
    }

    func openRemoteFile(remotePath: String, title: String? = nil) async {
        guard let connection = activeConnection else { return }
        let requestedFingerprint = connection.workspaceScopeFingerprint
        isBusy = true
        defer { isBusy = false }

        do {
            let snapshot = try await fileEditorService.read(remotePath: remotePath, connection: connection)
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            fileEditor = RemoteFileDraft(
                path: remotePath,
                title: title ?? WorkspaceFileBookmark.displayTitle(for: remotePath),
                content: snapshot.content,
                contentHash: snapshot.contentHash
            )
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return
        } catch {
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            present(error)
        }
    }

    func saveOpenFile(content: String) async -> Bool {
        guard let connection = activeConnection, let fileEditor else { return false }
        isBusy = true
        defer { isBusy = false }

        do {
            let saveResult = try await fileEditorService.write(
                remotePath: fileEditor.path,
                content: content,
                expectedContentHash: fileEditor.contentHash,
                connection: connection
            )
            self.fileEditor = RemoteFileDraft(
                path: fileEditor.path,
                title: fileEditor.title,
                content: content,
                contentHash: saveResult.contentHash
            )
            return true
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return false
        } catch {
            present(error)
            return false
        }
    }

    func refreshGateway() async {
        if let value: GatewaySnapshot = await performCompanionLoad(scope: .gateway, { service, connection in
            try await service.gatewaySnapshot(connection: connection)
        }) {
            gatewaySnapshot = value
        }
    }

    func performGatewayAction(_ action: GatewayLifecycleAction) async {
        if let value: GatewaySnapshot = await performCompanionLoad(scope: .gateway, { service, connection in
            try await service.gatewayAction(action, connection: connection)
        }) {
            gatewaySnapshot = value
        }
    }

    func refreshProfiles() async {
        if let value: ProfileManagementSnapshot = await performCompanionLoad(scope: .profiles, { service, connection in
            try await service.profileSnapshot(connection: connection)
        }) {
            profileSnapshot = value
        }
    }

    func refreshConfig() async {
        if let value: ConfigSnapshot = await performCompanionLoad(scope: .config, { service, connection in
            try await service.configSnapshot(connection: connection)
        }) {
            configSnapshot = value
        }
    }

    func refreshEnvironment() async {
        if let value: EnvironmentSnapshot = await performCompanionLoad(scope: .environment, { service, connection in
            try await service.environmentSnapshot(connection: connection)
        }) {
            environmentSnapshot = value
        }
    }

    func refreshKanban() async {
        let board = selectedKanbanBoard
        if let value: KanbanMobileSnapshot = await performCompanionLoad(scope: .kanban, { service, connection in
            try await service.kanbanSnapshot(board: board, connection: connection)
        }) {
            kanbanSnapshot = value
        }
    }

    func selectKanbanBoard(_ slug: String) async {
        guard let workspace = activeWorkspaceScopeFingerprint else { return }
        selectedKanbanBoardByWorkspace[workspace] = slug
        persistConnections()
        await refreshKanban()
    }

    func updateKanbanTask(
        _ task: KanbanMobileTask,
        status: String? = nil,
        assignee: String? = nil,
        comment: String? = nil
    ) async {
        let board = selectedKanbanBoard
        if let value: KanbanMobileSnapshot = await performCompanionLoad(scope: .kanban, { service, connection in
            try await service.updateKanbanTask(
                id: task.id,
                status: status,
                assignee: assignee,
                priority: nil,
                comment: comment,
                board: board,
                connection: connection
            )
        }) {
            kanbanSnapshot = value
        }
    }

    func stopTrackingProfile(_ name: String) {
        guard let host = activeHostFingerprint,
              name != activeConnection?.resolvedHermesProfileName else { return }
        hiddenProfilesByHost[host, default: []].insert(name)
        persistConnections()
        objectWillChange.send()
    }

    func restoreTrackingProfile(_ name: String) {
        guard let host = activeHostFingerprint else { return }
        hiddenProfilesByHost[host]?.remove(name)
        persistConnections()
        objectWillChange.send()
    }

    func deleteRemoteProfile(named name: String) async {
        guard let connection = activeConnection,
              name != "default",
              name != connection.resolvedHermesProfileName,
              let flag = profileSnapshot?.noninteractiveDeleteFlag else {
            present(MobileCompanionError.unsafeOperation("Switch away from the named profile and verify that the installed Hermes CLI exposes a noninteractive deletion flag."))
            return
        }
        if let value: ProfileManagementSnapshot = await performCompanionLoad(scope: .profiles, { service, connection in
            try await service.deleteProfile(named: name, confirmationFlag: flag, connection: connection)
        }) {
            profileSnapshot = value
            hiddenProfilesByHost[connection.hostConnectionFingerprint]?.remove(name)
            await refreshOverview()
            persistConnections()
        }
    }

    func saveConfig(_ fields: [ConfigField]) async -> Bool {
        guard let snapshot = configSnapshot else { return false }
        var succeeded = false
        if let value: ConfigSnapshot = await performCompanionLoad(scope: .config, { service, connection in
            try await service.saveConfig(fields: fields, expectedHash: snapshot.contentHash, connection: connection)
        }) {
            configSnapshot = value
            succeeded = true
        }
        return succeeded
    }

    func updateEnvironment(name: String, value: String?, clear: Bool) async -> Bool {
        var succeeded = false
        if let snapshot: EnvironmentSnapshot = await performCompanionLoad(scope: .environment, { service, connection in
            try await service.updateEnvironment(name: name, value: value, clear: clear, connection: connection)
        }) {
            environmentSnapshot = snapshot
            succeeded = true
        }
        return succeeded
    }

    private func beginCompanionRequest(scope: CompanionScope) -> UUID {
        let id = UUID()
        companionRequestIDs[scope] = id
        loadingCompanionScopes.insert(scope)
        return id
    }

    private func acceptsCompanionResponse(
        requestID: UUID,
        companionScope: CompanionScope,
        workspaceScope: String
    ) -> Bool {
        companionRequestIDs[companionScope] == requestID &&
            activeWorkspaceScopeFingerprint == workspaceScope
    }

    private func performCompanionLoad<Response>(
        scope companionScope: CompanionScope,
        _ operation: (MobileCompanionService, ConnectionProfile) async throws -> Response
    ) async -> Response? {
        guard let connection = activeConnection else { return nil }
        let requestID = beginCompanionRequest(scope: companionScope)
        let workspaceScope = connection.workspaceScopeFingerprint
        defer {
            if companionRequestIDs[companionScope] == requestID {
                companionRequestIDs[companionScope] = nil
                loadingCompanionScopes.remove(companionScope)
            }
        }
        do {
            let response = try await operation(mobileCompanionService, connection)
            guard acceptsCompanionResponse(
                requestID: requestID,
                companionScope: companionScope,
                workspaceScope: workspaceScope
            ) else { return nil }
            return response
        } catch where AsyncOperationErrorPolicy.isCancellation(error) {
            return nil
        } catch {
            guard acceptsCompanionResponse(
                requestID: requestID,
                companionScope: companionScope,
                workspaceScope: workspaceScope
            ) else { return nil }
            present(error)
            return nil
        }
    }

    private func resetCompanionState() {
        companionRequestIDs.removeAll()
        loadingCompanionScopes.removeAll()
        gatewaySnapshot = nil
        profileSnapshot = nil
        kanbanSnapshot = nil
        configSnapshot = nil
        environmentSnapshot = nil
    }

    func dismissAlert() {
        alertMessage = nil
    }

    func dismissHostKeyPrompt() {
        hostKeyPrompt = nil
    }

    func acceptHostKeyPrompt() {
        guard let challenge = hostKeyPrompt?.challenge else { return }
        do {
            try HostKeyTrustStore().save(TrustedHostKeyRecord(challenge: challenge))
            hostKeyPrompt = nil
            alertMessage = "Trusted \(challenge.displayDestination). Retry the connection to continue."
        } catch {
            present(error)
        }
    }

    private func validateDraft(profile: ConnectionProfile, credential: SSHCredentialRecord) throws {
        guard let validationError = profile.updated().validationError else {
            switch profile.authKind {
            case .password:
                let password = credential.password ?? ""
                guard !password.isEmpty else {
                    throw HermesPhoneStoreError.missingCredential
                }
            case .privateKey:
                let key = credential.privateKey ?? ""
                guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw HermesPhoneStoreError.missingCredential
                }
            }
            return
        }

        throw SSHTransportError.invalidConnection(validationError)
    }

    private func persistConnections() {
        do {
            let envelope = PersistenceEnvelope(
                activeConnectionID: activeConnectionID,
                activeHostFingerprint: activeHostFingerprint,
                activeProfileNameByHost: activeProfileNameByHost,
                connections: connections,
                terminalWorkspace: terminalWorkspace.snapshot(),
                workspaceFileBookmarks: workspaceFileBookmarks,
                sessionCacheByWorkspace: sessionCacheByWorkspace,
                transcriptSnapshotCacheByWorkspace: transcriptSnapshotCacheByWorkspace,
                hiddenProfilesByHost: hiddenProfilesByHost.mapValues { Array($0).sorted() },
                selectedKanbanBoardByWorkspace: selectedKanbanBoardByWorkspace
            )
            let data = try encoder.encode(envelope)
            let url = try persistenceURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            present(error)
        }
    }

    private func loadPersistedConnections() {
        do {
            let url = try persistenceURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            let envelope = try decoder.decode(PersistenceEnvelope.self, from: data)
            connections = envelope.connections
            activeConnectionID = envelope.activeConnectionID ?? connections.first?.id
            activeHostFingerprint = envelope.activeHostFingerprint ??
                connections.first(where: { $0.id == activeConnectionID })?.hostConnectionFingerprint ??
                connections.first?.hostConnectionFingerprint
            activeProfileNameByHost = envelope.activeProfileNameByHost
            if let activeConnection = connections.first(where: { $0.id == activeConnectionID }) {
                activeProfileNameByHost[activeConnection.hostConnectionFingerprint] = activeConnection.resolvedHermesProfileName
            }
            activeConnectionID = activeConnection?.id
            terminalWorkspace.restore(from: envelope.terminalWorkspace, availableConnections: connections)
            workspaceFileBookmarks = envelope.workspaceFileBookmarks
            sessionCacheByWorkspace = envelope.sessionCacheByWorkspace
            transcriptSnapshotCacheByWorkspace = envelope.transcriptSnapshotCacheByWorkspace
            hiddenProfilesByHost = envelope.hiddenProfilesByHost.mapValues(Set.init)
            selectedKanbanBoardByWorkspace = envelope.selectedKanbanBoardByWorkspace
            restoreCachedSessionsForActiveConnection()
        } catch {
            present(error)
        }
    }

    private func markSessionsPendingLoadIfNeeded() {
        restoreCachedSessionsForActiveConnection()
        currentSessionsLoadID = nil
        isLoadingSessions = false
        guard activeConnection != nil else {
            sessionsLoadState = .idle
            hasMoreSessions = false
            totalSessionsCount = 0
            sessionOffset = 0
            sessionSearchQuery = ""
            return
        }
        sessionsLoadState = sessions.isEmpty ? .pending : .loaded
    }

    private func restoreCachedSessionsForActiveConnection() {
        guard let key = activeWorkspaceScopeFingerprint else {
            sessions = []
            hasMoreSessions = false
            totalSessionsCount = 0
            sessionOffset = 0
            sessionSearchQuery = ""
            transcriptPrefetchTask?.cancel()
            return
        }
        sessions = sessionCacheByWorkspace[key] ?? []
        hasMoreSessions = false
        totalSessionsCount = sessions.count
        sessionOffset = sessions.count
        hydrateTranscriptSnapshotCacheForActiveConnection()
        scheduleRecentTranscriptPrefetch()
    }

    private func cacheSessionsForActiveWorkspace(_ sessions: [SessionSummary]) {
        guard let key = activeWorkspaceScopeFingerprint else { return }
        sessionCacheByWorkspace[key] = Array(sessions.prefix(100))
        persistConnections()
    }

    private func scheduleRecentTranscriptPrefetch() {
        transcriptPrefetchTask?.cancel()
        guard let connection = activeConnection else { return }
        let candidates = sessions
            .prefix(4)
            .filter { session in
                transcriptCache[transcriptCacheKey(connection: connection, sessionID: session.id)] == nil
            }
        guard !candidates.isEmpty else { return }

        let workspaceFingerprint = connection.workspaceScopeFingerprint
        transcriptPrefetchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            for session in candidates {
                guard !Task.isCancelled else { return }
                await self?.prefetchTranscript(
                    sessionID: session.id,
                    workspaceFingerprint: workspaceFingerprint
                )
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func prefetchTranscript(sessionID: String, workspaceFingerprint: String) async {
        guard let connection = activeConnection,
              connection.workspaceScopeFingerprint == workspaceFingerprint else { return }
        let key = transcriptCacheKey(connection: connection, sessionID: sessionID)
        guard transcriptCache[key] == nil else { return }

        do {
            let transcript = try await transcript(for: sessionID)
            guard activeConnection?.workspaceScopeFingerprint == workspaceFingerprint else { return }
            transcriptCache[key] = transcript
        } catch {
            // Best-effort cache warm; foreground transcript loads still surface errors.
        }
    }

    private func hydrateTranscriptSnapshotCacheForActiveConnection() {
        guard let connection = activeConnection,
              let workspaceCache = transcriptSnapshotCacheByWorkspace[connection.workspaceScopeFingerprint] else { return }
        for (sessionID, transcript) in workspaceCache {
            transcriptCache[transcriptCacheKey(connection: connection, sessionID: sessionID)] = transcript
        }
    }

    private func cacheTranscriptSnapshot(
        _ transcript: [SessionMessage],
        sessionID: String,
        connection: ConnectionProfile
    ) {
        guard !transcript.isEmpty else { return }
        let workspaceFingerprint = connection.workspaceScopeFingerprint
        var workspaceCache = transcriptSnapshotCacheByWorkspace[workspaceFingerprint] ?? [:]
        workspaceCache[sessionID] = Array(transcript.suffix(120))

        let preferredSessionIDs = Set(sessions.prefix(6).map(\.id)).union([sessionID])
        if workspaceCache.count > 6 {
            for cachedSessionID in workspaceCache.keys where !preferredSessionIDs.contains(cachedSessionID) {
                workspaceCache[cachedSessionID] = nil
            }
        }
        if workspaceCache.count > 6 {
            let removableSessionIDs = workspaceCache.keys
                .filter { $0 != sessionID }
                .sorted()
            for cachedSessionID in removableSessionIDs.prefix(workspaceCache.count - 6) {
                workspaceCache[cachedSessionID] = nil
            }
        }

        transcriptSnapshotCacheByWorkspace[workspaceFingerprint] = workspaceCache
        persistConnections()
    }

    private func selectProfileConnection(_ connection: ConnectionProfile) {
        let previousWorkspaceScope = activeWorkspaceScopeFingerprint
        activeHostFingerprint = connection.hostConnectionFingerprint
        activeProfileNameByHost[connection.hostConnectionFingerprint] = connection.resolvedHermesProfileName
        activeConnectionID = connection.id
        if let previousWorkspaceScope,
           previousWorkspaceScope != connection.workspaceScopeFingerprint {
            resetCompanionState()
        }
    }

    private func transcriptCacheKey(connection: ConnectionProfile, sessionID: String) -> String {
        "\(connection.workspaceScopeFingerprint)|\(sessionID)"
    }

    private func connectionForHost(fingerprint: String) -> ConnectionProfile? {
        if let selectedProfileName = activeProfileNameByHost[fingerprint],
           let selectedConnection = profileConnection(forHost: fingerprint, profileName: selectedProfileName) {
            return selectedConnection
        }

        let hostConnections = sortedConnections(forHost: fingerprint)
        guard !hostConnections.isEmpty else { return nil }

        if let legacyActiveConnection = connections.first(where: { $0.id == activeConnectionID }),
           legacyActiveConnection.hostConnectionFingerprint == fingerprint {
            return legacyActiveConnection
        }

        return hostConnections.first(where: \.usesDefaultHermesProfile) ?? hostConnections[0]
    }

    private func profileConnection(forHost fingerprint: String, profileName: String) -> ConnectionProfile? {
        let trimmedProfileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfileName.isEmpty else { return nil }

        let hostConnections = sortedConnections(forHost: fingerprint)
        if let configuredCustomConnection = hostConnections.first(where: {
            $0.usesCustomHermesHome && $0.resolvedHermesProfileName == trimmedProfileName
        }) {
            return configuredCustomConnection
        }

        guard let baseConnection = hostConnections.first(where: \.usesDefaultHermesProfile) ?? hostConnections.first else {
            return nil
        }
        return baseConnection.applyingHermesProfile(named: trimmedProfileName)
    }

    private func sortedConnections(forHost fingerprint: String) -> [ConnectionProfile] {
        connections
            .filter { $0.hostConnectionFingerprint == fingerprint }
            .sorted { lhs, rhs in
                if lhs.usesDefaultHermesProfile != rhs.usesDefaultHermesProfile {
                    return lhs.usesDefaultHermesProfile
                }
                return lhs.resolvedHermesProfileName.localizedCaseInsensitiveCompare(rhs.resolvedHermesProfileName) == .orderedAscending
            }
    }

    private func persistenceURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("HermesPhone", isDirectory: true)
            .appendingPathComponent("connections.json")
    }

    private func present(_ error: Error) {
        guard !AsyncOperationErrorPolicy.isCancellation(error) else { return }

        if let hostKeyError = error as? HostKeyValidationError {
            alertMessage = nil
            switch hostKeyError {
            case .unknownHost(let challenge):
                hostKeyPrompt = HostKeyTrustPrompt(challenge: challenge, expectedRecord: nil)
            case .hostKeyMismatch(let expected, let presented):
                hostKeyPrompt = HostKeyTrustPrompt(challenge: presented, expectedRecord: expected)
            case .storeFailure(let message):
                hostKeyPrompt = nil
                alertMessage = message
            }
            return
        }

        alertMessage = error.localizedDescription
    }
}

struct RemoteFileDraft: Identifiable, Equatable {
    let path: String
    let title: String
    let content: String
    let contentHash: String

    var id: String { path }
}

final class SSHTransport: @unchecked Sendable {
    private static let logger = Logger(subsystem: "HermesPhoneKit", category: "SSHTransport")

    private struct CollectedCommandOutput {
        var stdout = ByteBuffer()
        var stderr = ByteBuffer()
        var failure: Error?
    }

    private final class CommandOutputCapture: @unchecked Sendable {
        var value: CollectedCommandOutput?
    }

    func execute(
        on connection: ConnectionProfile,
        remoteCommand: String,
        standardInput: Data? = nil,
        allocateTTY: Bool
    ) async throws -> SSHCommandResult {
        let operationID = String(UUID().uuidString.prefix(8))
        let credentialStore = ConnectionSecretsStore()
        guard let credential = try credentialStore.load(for: connection.id) else {
            throw HermesPhoneStoreError.missingCredential
        }

        Self.logger.info("SSH operation \(operationID, privacy: .public) connecting")
        let client = try await makeClient(connection: connection, credential: credential)
        Self.logger.info("SSH operation \(operationID, privacy: .public) authenticated")
        defer {
            Task {
                try? await client.close()
            }
        }

        let completionToken = RemoteCommandCompletion.makeToken()
        let wrapped = makeWrappedCommand(
            for: connection,
            remoteCommand: remoteCommand,
            standardInputByteCount: standardInput?.count,
            completionToken: completionToken
        )

        let collected: CollectedCommandOutput

        do {
            collected = try await withTaskCancellationHandler {
                if let standardInput {
                    return try await executeWithStandardInput(
                        client: client,
                        command: wrapped,
                        standardInput: standardInput
                    )
                }
                return try await executeWithoutStandardInput(
                    client: client,
                    command: wrapped
                )
            } onCancel: {
                Task { try? await client.close() }
            }
        } catch is CancellationError {
            Self.logger.info("SSH operation \(operationID, privacy: .public) cancelled")
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                Self.logger.info("SSH operation \(operationID, privacy: .public) closed while cancelling")
                throw CancellationError()
            }
            Self.logger.error("SSH operation \(operationID, privacy: .public) failed before completion: \(SSHCommandStreamTermination.diagnosticName(for: error), privacy: .public)")
            throw mapConnectionError(error, connection: connection)
        }

        let stdout = String(buffer: collected.stdout)
        let rawStderr = String(buffer: collected.stderr)
        guard let completion = RemoteCommandCompletion.parse(
            stderr: rawStderr,
            token: completionToken
        ) else {
            if let failure = collected.failure {
                Self.logger.error("SSH operation \(operationID, privacy: .public) ended without its completion marker: \(SSHCommandStreamTermination.diagnosticName(for: failure), privacy: .public)")
                throw mapConnectionError(failure, connection: connection)
            }
            Self.logger.error("SSH operation \(operationID, privacy: .public) ended without its completion marker or an underlying error")
            throw SSHTransportError.remoteFailure(
                "The SSH command on \(connection.displayDestination) ended before confirming completion. The remote connection may have closed or the command may have been interrupted."
            )
        }

        Self.logger.info("SSH operation \(operationID, privacy: .public) completed with exit code \(completion.exitCode)")

        return SSHCommandResult(
            stdout: stdout,
            stderr: completion.stderr,
            exitCode: completion.exitCode
        )
    }

    func executeJSON<Response: Decodable>(
        on connection: ConnectionProfile,
        pythonScript: String,
        responseType: Response.Type
    ) async throws -> Response {
        let result = try await execute(
            on: connection,
            remoteCommand: "python3 -",
            standardInput: Data(pythonScript.utf8),
            allocateTTY: false
        )

        try validateSuccessfulExit(result, for: connection)

        return try RemoteJSONResponseDecoder.decode(
            Response.self,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }

    func executeJSONLines<Response: Decodable>(
        on connection: ConnectionProfile,
        pythonScript: String,
        responseType: Response.Type,
        onLine: @escaping @Sendable (Response) async throws -> Void
    ) async throws {
        let result = try await execute(
            on: connection,
            remoteCommand: "python3 -",
            standardInput: Data(pythonScript.utf8),
            allocateTTY: false
        )
        try validateSuccessfulExit(result, for: connection)

        let decoder = JSONDecoder()
        for rawLine in result.stdout.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else {
                throw SSHTransportError.invalidResponse("Remote stream line was not valid UTF-8.")
            }
            do {
                try await onLine(decoder.decode(Response.self, from: data))
            } catch let transportError as SSHTransportError {
                throw transportError
            } catch {
                throw SSHTransportError.invalidResponse(
                    "Failed to decode remote JSON stream line: \(error.localizedDescription)\n\nline:\n\(shortenedOutputPreview(line, limit: 2000))"
                )
            }
        }
    }

    private func formattedInvalidJSONResponse(
        stdout: String,
        stderr: String,
        decodingError: Error
    ) -> String {
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if looksLikeNonJSONShellOutput(trimmedStdout) {
            let guidance = "Remote command returned non-JSON output. This usually means a shell startup file or Hermes startup command printed text during a non-interactive SSH command. Keep startup files quiet for non-interactive SSH sessions and retry."
            let preview = shortenedOutputPreview(trimmedStdout)
            if preview.isEmpty {
                return guidance
            }
            return "\(guidance)\n\nPreview:\n\(preview)"
        }

        var message = "Failed to decode remote JSON: \(decodingErrorDescription(decodingError))"
        if !trimmedStdout.isEmpty {
            message += "\n\nstdout:\n\(shortenedOutputPreview(trimmedStdout, limit: 2000))"
        }
        if !trimmedStderr.isEmpty {
            message += "\n\nstderr:\n\(shortenedOutputPreview(trimmedStderr, limit: 2000))"
        }
        return message
    }

    private func decodingErrorDescription(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            let path: String
            switch decodingError {
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context), .dataCorrupted(let context):
                path = context.codingPath.map(\.stringValue).joined(separator: ".")
            @unknown default:
                path = ""
            }
            let base = error.localizedDescription
            return path.isEmpty ? base : "\(base) at \(path)"
        }
        return error.localizedDescription
    }

    private func looksLikeNonJSONShellOutput(_ output: String) -> Bool {
        guard let firstCharacter = output.first else { return false }
        if firstCharacter == "{" || firstCharacter == "[" {
            return false
        }

        let lowered = output.lowercased()
        return output.contains("{") ||
            output.contains("[") ||
            lowered.contains("welcome") ||
            lowered.contains("last login")
    }

    private func shortenedOutputPreview(_ output: String, limit: Int = 240) -> String {
        guard output.count > limit else { return output }
        let endIndex = output.index(output.startIndex, offsetBy: limit)
        return String(output[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    func shellBootstrapSequence(
        for connection: ConnectionProfile,
        startupCommandLine: String? = nil
    ) -> String {
        connection.remoteShellBootstrapCommand(startupCommandLine: startupCommandLine)
    }

    func validateSuccessfulExit(_ result: SSHCommandResult, for connection: ConnectionProfile? = nil) throws {
        guard result.exitCode == 0 else {
            throw SSHTransportError.remoteFailure(
                describeRemoteFailure(
                    stdout: result.stdout,
                    stderr: result.stderr,
                    exitCode: result.exitCode,
                    connection: connection
                )
            )
        }
    }

    func describeRemoteFailure(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        connection: ConnectionProfile?
    ) -> String {
        let rawMessage = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        let lowered = rawMessage.lowercased()
        if lowered.contains("permission denied") {
            return "SSH authentication failed. Verify the selected user and credentials."
        }
        if lowered.contains("host key verification failed") {
            return "SSH host key verification failed."
        }
        if lowered.contains("python3: command not found") {
            return "SSH succeeded, but python3 is not available on the remote host."
        }
        if !rawMessage.isEmpty {
            return rawMessage
        }
        return "SSH command failed with exit code \(exitCode)."
    }

    func makeClient(connection: ConnectionProfile, credential: SSHCredentialRecord) async throws -> SSHClient {
        let authMethod = try connection.authenticationMethod(using: credential)
        let settings = SSHClientSettings(
            host: connection.effectiveTarget,
            port: connection.resolvedPort ?? 22,
            authenticationMethod: { authMethod },
            hostKeyValidator: .custom(
                ConnectionHostKeyValidator(
                    connection: connection,
                    trustStore: HostKeyTrustStore()
                )
            )
        )

        do {
            return try await SSHClient.connect(to: settings)
        } catch {
            throw mapConnectionError(error, connection: connection)
        }
    }

    func makeWrappedCommand(
        for connection: ConnectionProfile,
        remoteCommand: String,
        standardInputByteCount: Int?,
        completionToken: String
    ) -> String {
        RemoteCommandCompletion.wrappedCommand(
            environmentExports: connection.remoteServiceEnvironmentExports,
            remoteCommand: remoteCommand,
            standardInputByteCount: standardInputByteCount,
            token: completionToken
        )
    }

    private func mapConnectionError(_ error: Error, connection: ConnectionProfile) -> Error {
        if error is CancellationError {
            return CancellationError()
        }
        if let hostKeyError = error as? HostKeyValidationError {
            return hostKeyError
        }

        if let channelError = error as? ChannelError {
            switch channelError {
            case .inputClosed, .eof, .alreadyClosed:
                return SSHTransportError.remoteFailure(
                    "The SSH command channel on \(connection.displayDestination) closed before Hermes could confirm the result. Retry the operation."
                )
            case .ioOnClosedChannel, .outputClosed:
                return SSHTransportError.remoteFailure(
                    "The SSH command channel on \(connection.displayDestination) became unavailable before Hermes could confirm the result. Retry the operation."
                )
            default:
                break
            }
        }

        if let sshError = error as? SSHClientError {
            switch sshError {
            case .allAuthenticationOptionsFailed:
                return SSHTransportError.invalidConnection(authFailureMessage(for: connection))
            case .unsupportedPasswordAuthentication:
                return SSHTransportError.invalidConnection(
                    "The SSH server does not accept password authentication for \(connection.displayDestination). Use Private Key instead."
                )
            case .unsupportedPrivateKeyAuthentication:
                return SSHTransportError.invalidConnection(
                    "The SSH server does not accept public key authentication for \(connection.displayDestination). Use Password instead."
                )
            case .unsupportedHostBasedAuthentication, .channelCreationFailed:
                break
            }
        }

        if let sshProtocolError = error as? NIOSSHError {
            switch sshProtocolError.type {
            case .tcpShutdown, .creatingChannelAfterClosure:
                return SSHTransportError.remoteFailure(
                    "The SSH connection to \(connection.displayDestination) closed while preparing the command. Retry the operation."
                )
            case .channelSetupRejected:
                return SSHTransportError.remoteFailure(
                    "The SSH server on \(connection.displayDestination) rejected the command channel. Retry the operation."
                )
            case .keyExchangeNegotiationFailure:
                return SSHTransportError.invalidConnection(
                    "Hermes and \(connection.displayDestination) could not agree on secure SSH algorithms."
                )
            default:
                return SSHTransportError.launchFailure(
                    "SSH protocol error on \(connection.displayDestination): \(String(describing: sshProtocolError))"
                )
            }
        }

        let message = error.localizedDescription
        let reflectedType = String(reflecting: type(of: error))
        if reflectedType.contains("ClientHandshakeHandler.Disconnected")
            || message.localizedCaseInsensitiveContains("disconnected")
        {
            return SSHTransportError.remoteFailure(
                "The SSH connection to \(connection.displayDestination) was closed during handshake."
            )
        }
        if message.localizedCaseInsensitiveContains("password") {
            return SSHTransportError.invalidConnection("SSH authentication failed for \(connection.displayDestination).")
        }
        if message.localizedCaseInsensitiveContains("publickey") {
            return SSHTransportError.invalidConnection("SSH private key authentication failed for \(connection.displayDestination).")
        }
        if message.localizedCaseInsensitiveContains("timed out") {
            return SSHTransportError.remoteFailure("The SSH connection to \(connection.displayDestination) timed out.")
        }
        return SSHTransportError.launchFailure(message)
    }

    private func authFailureMessage(for connection: ConnectionProfile) -> String {
        switch connection.authKind {
        case .password:
            return "SSH authentication failed for \(connection.displayDestination). The server rejected the provided username/password."
        case .privateKey:
            return "SSH authentication failed for \(connection.displayDestination). The server rejected the provided username/private key."
        }
    }

    private func executeWithoutStandardInput(
        client: SSHClient,
        command: String
    ) async throws -> CollectedCommandOutput {
        let streams = try await client.executeCommandPair(command)
        async let stdoutResult = collectBuffer(from: streams.stdout)
        async let stderrResult = collectBuffer(from: streams.stderr)
        let (collectedStdout, collectedStderr) = await (stdoutResult, stderrResult)

        return CollectedCommandOutput(
            stdout: collectedStdout.buffer,
            stderr: collectedStderr.buffer,
            failure: collectedStdout.failure ?? collectedStderr.failure
        )
    }

    private func executeWithStandardInput(
        client: SSHClient,
        command: String,
        standardInput: Data
    ) async throws -> CollectedCommandOutput {
        let capture = CommandOutputCapture()

        do {
            try await client.withExec(command) { [self] inbound, writer in
                let outputTask = Task { await collectOutput(from: inbound) }
                var input = ByteBuffer()
                input.writeBytes(standardInput)
                do {
                    try await writer.write(input)
                    capture.value = await outputTask.value
                } catch {
                    var output = await outputTask.value
                    if output.failure == nil {
                        output.failure = error
                    }
                    capture.value = output
                    throw error
                }
            }
        } catch {
            guard var output = capture.value else {
                throw error
            }
            if output.failure == nil {
                output.failure = error
            }
            capture.value = output
        }

        guard let output = capture.value else {
            throw SSHTransportError.remoteFailure(
                "The SSH command channel closed before its output could be collected."
            )
        }
        return output
    }

    private func collectOutput(from stream: TTYOutput) async -> CollectedCommandOutput {
        var output = CollectedCommandOutput()
        do {
            for try await chunk in stream {
                switch chunk {
                case .stdout(let buffer):
                    output.stdout.writeImmutableBuffer(buffer)
                case .stderr(let buffer):
                    output.stderr.writeImmutableBuffer(buffer)
                }
            }
        } catch let failure as SSHClient.CommandFailed {
            output.failure = failure
        } catch {
            if !SSHCommandStreamTermination.isExpectedAfterRemoteCompletion(error) {
                output.failure = error
            }
        }
        return output
    }

    private func collectBuffer(
        from stream: AsyncThrowingStream<ByteBuffer, Error>
    ) async -> (buffer: ByteBuffer, failure: Error?) {
        var buffer = ByteBuffer()
        do {
            for try await chunk in stream {
                buffer.writeImmutableBuffer(chunk)
            }
            return (buffer, nil)
        } catch let failure as SSHClient.CommandFailed {
            return (buffer, failure)
        } catch {
            return (
                buffer,
                SSHCommandStreamTermination.isExpectedAfterRemoteCompletion(error) ? nil : error
            )
        }
    }
}

#endif
