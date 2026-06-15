#if canImport(UIKit)
@preconcurrency import Citadel
import Crypto
import Foundation
import NIOCore
@preconcurrency import NIOSSH
import Security
import SwiftUI
import UIKit

@MainActor
final class HermesPhoneStore: ObservableObject {
    @Published var selectedRootTab: HermesPhoneRootTab = .chat
    @Published var chatNavigationPath: [HermesPhoneChatRoute] = []
    @Published var connections: [ConnectionProfile] = []
    @Published var activeConnectionID: UUID?
    @Published var activeHostFingerprint: String?
    @Published var activeProfileNameByHost: [String: String] = [:]
    @Published var overview: RemoteDiscovery?
    @Published var sessions: [SessionSummary] = []
    @Published var sessionsLoadState: SessionListLoadState = .idle
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
    @Published private(set) var workspaceFileBookmarks: [WorkspaceFileBookmark] = []

    let terminalWorkspace = HermesTerminalWorkspaceStore()
    lazy var nativeChatStore = HermesNativeChatStore(phoneStore: self, sshTransport: sshTransport)

    private let secretsStore = ConnectionSecretsStore()
    private let sshTransport = SSHTransport()
    private lazy var remoteHermesService = RemoteHermesService(sshTransport: sshTransport)
    private lazy var sessionBrowserService = SessionBrowserService(sshTransport: sshTransport)
    private lazy var cronBrowserService = CronBrowserService(sshTransport: sshTransport)
    private lazy var fileEditorService = FileEditorService(sshTransport: sshTransport)
    private lazy var skillBrowserService = SkillBrowserService(sshTransport: sshTransport)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var currentSessionsLoadID: UUID?
    private var transcriptCache: [String: [SessionMessage]] = [:]
    private var sessionCacheByWorkspace: [String: [SessionSummary]] = [:]
    private var transcriptSnapshotCacheByWorkspace: [String: [String: [SessionMessage]]] = [:]
    private var transcriptPrefetchTask: Task<Void, Never>?

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

        return profiles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
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
            persistConnections()
        }
        await nativeChatStore.syncWithActiveConnection()
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
        } catch {
            present(error)
            return error.localizedDescription
        }
    }

    func refreshOverview() async {
        guard let connection = activeConnection else { return }
        let requestedFingerprint = connection.workspaceScopeFingerprint
        isLoadingOverview = true
        defer { isLoadingOverview = false }

        do {
            let discovery = try await remoteHermesService.discover(connection: connection)
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            overview = discovery
            activeDirectoryPath = overview?.hermesHome ?? connection.remoteHermesHomePath
        } catch {
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            present(error)
        }
    }

    func loadSessions(query: String = "") async {
        guard let connection = activeConnection else {
            sessions = []
            sessionsLoadState = .idle
            currentSessionsLoadID = nil
            isLoadingSessions = false
            return
        }
        let requestedFingerprint = connection.workspaceScopeFingerprint
        let requestID = UUID()
        currentSessionsLoadID = requestID
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
                offset: 0,
                limit: 100,
                query: query
            )
            guard currentSessionsLoadID == requestID,
                  activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            let incoming = deduplicatedSessionLineage(page.items)
            sessions = mergeSessionPage(
                previous: sessions,
                incoming: incoming,
                keepIDs: nativeChatStore.activeLineageSessionIDs
            )
            cacheSessionsForActiveWorkspace(sessions)
            scheduleRecentTranscriptPrefetch()
            sessionsLoadState = .loaded
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
        let transcript = try await sessionBrowserService.loadTranscript(connection: connection, sessionID: sessionID)
        transcriptCache[transcriptCacheKey(connection: connection, sessionID: sessionID)] = transcript
        cacheTranscriptSnapshot(transcript, sessionID: sessionID, connection: connection)
        return transcript
    }

    func resumeSessionInTerminal(_ session: SessionSummary) {
        guard let connection = activeConnection else {
            present(HermesPhoneStoreError.missingTerminalConnection)
            return
        }
        let invocation = HermesSessionResumeInvocation(sessionID: session.id, connection: connection)
        terminalWorkspace.replaceWithSingleSession(
            for: connection,
            startupCommandLine: invocation.startupCommandLine,
            titleHint: session.resolvedTitle
        )
        selectedRootTab = .terminal
    }

    func continueSessionInChat(_ session: SessionSummary) {
        selectedRootTab = .chat
        chatNavigationPath = [.conversation]
        if nativeChatStore.isActiveConversation(session), nativeChatStore.hasConversationContent {
            return
        }
        guard !nativeChatStore.isWorking else {
            alertMessage = "Hermes is still working in the current chat. Stop it before continuing another conversation."
            return
        }
        Task { @MainActor in
            await nativeChatStore.queueResumeSessionReplacingActiveConversation(session)
        }
    }

    func openNewChat() {
        selectedRootTab = .chat
        chatNavigationPath = [.conversation]
        guard !nativeChatStore.isWorking else {
            alertMessage = "Hermes is still working in the current chat. Stop it before starting a new one."
            return
        }
        nativeChatStore.prepareInstantNewChat()
    }

    func reopenActiveConversation() {
        selectedRootTab = .chat
        chatNavigationPath = [.conversation]
    }

    func openNotificationRoute(_ route: HermesPhoneNotificationRoute) {
        selectedRootTab = .chat

        if let routeWorkspace = route.workspaceFingerprint,
           routeWorkspace != activeWorkspaceScopeFingerprint {
            chatNavigationPath = []
            alertMessage = "This notification belongs to a different Hermes profile. Switch to that profile to reopen the chat."
            return
        }

        if nativeChatStore.hasRestorableConversation {
            chatNavigationPath = [.conversation]
            return
        }

        guard let sessionID = route.sessionID else {
            chatNavigationPath = [.conversation]
            return
        }

        if let session = notificationSession(matching: sessionID) {
            continueSessionInChat(session)
            return
        }

        chatNavigationPath = []
        Task { @MainActor in
            await loadSessions()
            if let session = notificationSession(matching: sessionID) {
                continueSessionInChat(session)
            }
        }
    }

    private func notificationSession(matching sessionID: String) -> SessionSummary? {
        sessions.first { session in
            session.matchesSessionIdentity(sessionID)
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

    func openNativeChat() {
        openNewChat()
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
        } catch {
            present(error)
        }
    }

    func loadSkills() async {
        guard let connection = activeConnection else { return }
        let requestedFingerprint = connection.workspaceScopeFingerprint
        isLoadingSkills = true
        skillsError = nil
        defer { isLoadingSkills = false }

        do {
            let loadedSkills = try await skillBrowserService.listSkills(connection: connection)
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            skills = loadedSkills
        } catch {
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            skillsError = error.localizedDescription
            present(error)
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
        } catch {
            guard activeConnection?.workspaceScopeFingerprint == requestedFingerprint else { return }
            skillsError = error.localizedDescription
            present(error)
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
        } catch {
            present(error)
            return false
        }
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
                transcriptSnapshotCacheByWorkspace: transcriptSnapshotCacheByWorkspace
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
            return
        }
        sessionsLoadState = sessions.isEmpty ? .pending : .loaded
    }

    private func restoreCachedSessionsForActiveConnection() {
        guard let key = activeWorkspaceScopeFingerprint else {
            sessions = []
            transcriptPrefetchTask?.cancel()
            return
        }
        sessions = sessionCacheByWorkspace[key] ?? []
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
            let transcript = try await sessionBrowserService.loadTranscript(connection: connection, sessionID: sessionID)
            guard activeConnection?.workspaceScopeFingerprint == workspaceFingerprint else { return }
            transcriptCache[key] = transcript
            cacheTranscriptSnapshot(transcript, sessionID: sessionID, connection: connection)
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
        activeHostFingerprint = connection.hostConnectionFingerprint
        activeProfileNameByHost[connection.hostConnectionFingerprint] = connection.resolvedHermesProfileName
        activeConnectionID = connection.id
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
    func execute(
        on connection: ConnectionProfile,
        remoteCommand: String,
        standardInput: Data? = nil,
        allocateTTY: Bool
    ) async throws -> SSHCommandResult {
        let credentialStore = ConnectionSecretsStore()
        guard let credential = try credentialStore.load(for: connection.id) else {
            throw HermesPhoneStoreError.missingCredential
        }

        let client = try await makeClient(connection: connection, credential: credential)
        defer {
            Task {
                try? await client.close()
            }
        }

        let wrapped = makeWrappedCommand(
            for: connection,
            remoteCommand: remoteCommand,
            standardInput: standardInput
        )

        var stdout = ByteBuffer()
        var stderr = ByteBuffer()
        var exitCode: Int32 = 0

        do {
            let streams = try await client.executeCommandPair(wrapped)
            async let stdoutResult = collectBuffer(from: streams.stdout)
            async let stderrResult = collectBuffer(from: streams.stderr)
            let (collectedStdout, collectedStderr) = await (stdoutResult, stderrResult)
            stdout = collectedStdout.buffer
            stderr = collectedStderr.buffer
            exitCode = collectedStdout.exitCode ?? collectedStderr.exitCode ?? 0

            if let failure = collectedStdout.failure ?? collectedStderr.failure {
                throw failure
            }
        } catch let failure as SSHClient.CommandFailed {
            exitCode = Int32(failure.exitCode)
        } catch {
            throw mapConnectionError(error, connection: connection)
        }

        return SSHCommandResult(
            stdout: String(buffer: stdout),
            stderr: String(buffer: stderr),
            exitCode: exitCode
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

        guard let data = result.stdout.data(using: .utf8) else {
            throw SSHTransportError.invalidResponse("Remote output was not valid UTF-8.")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SSHTransportError.invalidResponse(
                formattedInvalidJSONResponse(
                    stdout: result.stdout,
                    stderr: result.stderr,
                    decodingError: error
                )
            )
        }
    }

    func executeJSONLines<Response: Decodable>(
        on connection: ConnectionProfile,
        pythonScript: String,
        responseType: Response.Type,
        onLine: @escaping @Sendable (Response) async throws -> Void
    ) async throws {
        let credentialStore = ConnectionSecretsStore()
        guard let credential = try credentialStore.load(for: connection.id) else {
            throw HermesPhoneStoreError.missingCredential
        }

        let client = try await makeClient(connection: connection, credential: credential)
        defer {
            Task { try? await client.close() }
        }

        let wrapped = makeWrappedCommand(
            for: connection,
            remoteCommand: "python3 -",
            standardInput: Data(pythonScript.utf8)
        )
        let decoder = JSONDecoder()
        var stdoutRemainder = ""
        var stderr = ByteBuffer()
        var exitCode: Int32 = 0

        func consumeStdout(_ chunk: ByteBuffer) async throws {
            guard let text = chunk.getString(at: chunk.readerIndex, length: chunk.readableBytes), !text.isEmpty else {
                return
            }
            stdoutRemainder.append(text)
            while let newlineRange = stdoutRemainder.range(of: "\n") {
                let line = String(stdoutRemainder[..<newlineRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                stdoutRemainder.removeSubrange(stdoutRemainder.startIndex ... newlineRange.lowerBound)
                guard !line.isEmpty else { continue }
                guard let data = line.data(using: .utf8) else {
                    throw SSHTransportError.invalidResponse("Remote stream line was not valid UTF-8.")
                }
                do {
                    try await onLine(decoder.decode(Response.self, from: data))
                } catch let transportError as SSHTransportError {
                    throw transportError
                } catch {
                    throw SSHTransportError.invalidResponse("Failed to decode remote JSON stream line: \(error.localizedDescription)\n\nline:\n\(shortenedOutputPreview(line, limit: 2000))")
                }
            }
        }

        do {
            let streams = try await client.executeCommandPair(wrapped)
            async let stderrResult = collectBuffer(from: streams.stderr)
            do {
                for try await chunk in streams.stdout {
                    try await consumeStdout(chunk)
                }
                let line = stdoutRemainder.trimmingCharacters(in: .whitespacesAndNewlines)
                stdoutRemainder.removeAll(keepingCapacity: false)
                if !line.isEmpty {
                    guard let data = line.data(using: .utf8) else {
                        throw SSHTransportError.invalidResponse("Remote stream line was not valid UTF-8.")
                    }
                    try await onLine(try decoder.decode(Response.self, from: data))
                }
            } catch let failure as SSHClient.CommandFailed {
                exitCode = Int32(failure.exitCode)
            }
            let collectedStderr = await stderrResult
            stderr = collectedStderr.buffer
            exitCode = exitCode == 0 ? (collectedStderr.exitCode ?? 0) : exitCode
            if let failure = collectedStderr.failure {
                throw failure
            }
        } catch let failure as SSHClient.CommandFailed {
            exitCode = Int32(failure.exitCode)
        } catch {
            throw mapConnectionError(error, connection: connection)
        }

        try validateSuccessfulExit(
            SSHCommandResult(stdout: "", stderr: String(buffer: stderr), exitCode: exitCode),
            for: connection
        )
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
        standardInput: Data?
    ) -> String {
        var commandBody = remoteCommand
        if let standardInput, let inputText = String(data: standardInput, encoding: .utf8) {
            let marker = "__HERMES_STDIN__"
            commandBody = "\(remoteCommand) <<'\(marker)'\n\(inputText)\n\(marker)"
        }

        let fullBody = "\(connection.remoteServiceEnvironmentExports); \(commandBody)"
        return "/bin/sh -lc \(fullBody.shellQuotedForTerminalCommand)"
    }

    private func mapConnectionError(_ error: Error, connection: ConnectionProfile) -> Error {
        if let hostKeyError = error as? HostKeyValidationError {
            return hostKeyError
        }

        if let channelError = error as? ChannelError {
            switch channelError {
            case .inputClosed, .eof, .alreadyClosed:
                return SSHTransportError.remoteFailure(
                    "The SSH connection to \(connection.displayDestination) was closed by the remote host."
                )
            case .ioOnClosedChannel, .outputClosed:
                return SSHTransportError.remoteFailure(
                    "The SSH connection to \(connection.displayDestination) closed unexpectedly."
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

    private func collectBuffer(
        from stream: AsyncThrowingStream<ByteBuffer, Error>
    ) async -> (buffer: ByteBuffer, exitCode: Int32?, failure: Error?) {
        var buffer = ByteBuffer()
        do {
            for try await chunk in stream {
                buffer.writeImmutableBuffer(chunk)
            }
            return (buffer, nil, nil)
        } catch let failure as SSHClient.CommandFailed {
            return (buffer, Int32(failure.exitCode), nil)
        } catch {
            if isExpectedCommandStreamTermination(error) {
                return (buffer, nil, nil)
            }
            return (buffer, nil, error)
        }
    }

    private func isExpectedCommandStreamTermination(_ error: Error) -> Bool {
        if let channelError = error as? ChannelError {
            switch channelError {
            case .inputClosed, .eof, .alreadyClosed, .ioOnClosedChannel:
                return true
            default:
                return false
            }
        }

        let reflectedType = String(reflecting: type(of: error))
        return reflectedType.contains("ClientHandshakeHandler.Disconnected")
    }
}

#endif
