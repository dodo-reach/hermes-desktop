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
    @Published var activeConnectionID: UUID?
    @Published var selectedSessionID: String?
    @Published var sessions: [SessionSummary] = []
    @Published var sessionMessages: [SessionMessage] = []
    @Published var sessionsError: String?
    @Published var isLoadingSessions = false
    @Published var hasMoreSessions = false
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

    func refreshOverview() async {
        guard let profile = activeConnection else { return }

        do {
            isBusy = true
            overviewError = nil
            overview = try await remoteHermesService.discover(connection: profile)
            isBusy = false
        } catch {
            isBusy = false
            overview = nil
            overviewError = error.localizedDescription
            setStatusMessage("Unable to refresh remote discovery")
        }
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
            let content = try await fileEditorService.read(file: trackedFile, connection: profile)
            document.content = content
            document.originalContent = content
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
            try await fileEditorService.write(
                file: trackedFile,
                content: document.content,
                connection: profile
            )
            document.originalContent = document.content
            document.lastSavedAt = Date()
            document.hasLoaded = true
            document.isLoading = false
            setDocument(document)
            setStatusMessage("\(trackedFile.fileName) saved")
        } catch {
            document.isLoading = false
            document.errorMessage = error.localizedDescription
            setDocument(document)
            setStatusMessage("Unable to save \(trackedFile.fileName)")
        }
    }

    func updateDocument(_ trackedFile: RemoteTrackedFile, content: String) {
        var document = document(for: trackedFile)
        document.content = content
        setDocument(document)
    }

    func loadSessions(reset: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingSessions { return }

        if reset {
            sessionOffset = 0
            sessions = []
            hasMoreSessions = false
            selectedSessionID = nil
            sessionMessages = []
        }

        isLoadingSessions = true
        sessionsError = nil

        do {
            let page = try await sessionBrowserService.listSessions(
                connection: profile,
                offset: sessionOffset,
                limit: sessionPageSize
            )

            if reset {
                sessions = page.items
            } else {
                sessions.append(contentsOf: page.items)
            }

            hasMoreSessions = page.items.count == sessionPageSize
            sessionOffset += page.items.count
            isLoadingSessions = false

            if reset, let first = sessions.first {
                await loadSessionDetail(sessionID: first.id)
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
            Task { await loadSessions(reset: sessions.isEmpty) }
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
            sessions = []
            sessionMessages = []
            resetDocuments()
            return
        }

        await ensureInitialFileLoads()
        await loadSessions(reset: true)
    }

    private func resetWorkspaceStateForConnectionChange() {
        overview = nil
        overviewError = nil
        sessions = []
        sessionMessages = []
        sessionsError = nil
        isLoadingSessions = false
        hasMoreSessions = false
        selectedSessionID = nil
        sessionOffset = 0
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
