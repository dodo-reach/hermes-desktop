import Combine
import Foundation

@MainActor
final class ConnectionStore: ObservableObject {
    @Published private(set) var connections: [ConnectionProfile] = []
    @Published private(set) var persistenceError: String?
    @Published var lastConnectionID: UUID? {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published var terminalTheme: TerminalThemePreference = .defaultValue {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published var terminalFontSize: Double = TerminalFontPreference.defaultSize {
        didSet {
            let clampedFontSize = TerminalFontPreference.clamped(terminalFontSize)
            if terminalFontSize != clampedFontSize {
                terminalFontSize = clampedFontSize
                return
            }
            persistPreferencesIfNeeded()
        }
    }
    @Published var appAppearance: AppAppearancePreference = .system {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published var automaticallyChecksForUpdates = true {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published var backgroundImagePath: String? = nil {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published var lastAutomaticUpdateCheckAt: Date? {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published private(set) var workspaceFileBookmarks: [WorkspaceFileBookmark] = [] {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published private(set) var pinnedSessions: [PinnedSession] = [] {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published private(set) var workflows: [WorkflowPreset] = [] {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published private(set) var hiddenHermesProfiles: [HiddenHermesProfilePreference] = [] {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published private(set) var sidebarSectionOrder: [AppSection] = AppSection.customizableSidebarSections {
        didSet {
            persistPreferencesIfNeeded()
        }
    }
    @Published private(set) var hiddenSidebarSections: [AppSection] = [] {
        didSet {
            persistPreferencesIfNeeded()
        }
    }

    private let paths: AppPaths
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let privateFileAttributes: [FileAttributeKey: Any] = [
        .posixPermissions: NSNumber(value: Int16(0o600))
    ]
    private var isHydratingFromDisk = false

    init(paths: AppPaths) {
        self.paths = paths
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func upsert(_ connection: ConnectionProfile) {
        let normalized = connection.updated()
        if let index = connections.firstIndex(where: { $0.id == normalized.id }) {
            connections[index] = normalized
        } else {
            connections.append(normalized)
        }
        connections.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        saveConnections()
    }

    func delete(_ connection: ConnectionProfile) {
        connections.removeAll(where: { $0.id == connection.id })
        if lastConnectionID == connection.id {
            lastConnectionID = nil
        }
        saveConnections()
    }

    func bookmarks(for workspaceScopeFingerprint: String) -> [WorkspaceFileBookmark] {
        workspaceFileBookmarks
            .filter { $0.workspaceScopeFingerprint == workspaceScopeFingerprint }
            .sorted { lhs, rhs in
                lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    @discardableResult
    func upsertWorkspaceFileBookmark(
        remotePath: String,
        title: String? = nil,
        workspaceScopeFingerprint: String
    ) -> WorkspaceFileBookmark? {
        let normalizedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return nil }

        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        if let index = workspaceFileBookmarks.firstIndex(where: {
            $0.workspaceScopeFingerprint == workspaceScopeFingerprint &&
                $0.remotePath == normalizedPath
        }) {
            var bookmark = workspaceFileBookmarks[index]
            bookmark.title = normalizedTitle ?? bookmark.title
            bookmark.updatedAt = Date()
            workspaceFileBookmarks[index] = bookmark
            return bookmark
        }

        let bookmark = WorkspaceFileBookmark(
            workspaceScopeFingerprint: workspaceScopeFingerprint,
            remotePath: normalizedPath,
            title: normalizedTitle
        )
        workspaceFileBookmarks.append(bookmark)
        return bookmark
    }

    func removeWorkspaceFileBookmark(id: UUID) {
        workspaceFileBookmarks.removeAll { $0.id == id }
    }

    func pinnedSessions(for workspaceScopeFingerprint: String) -> [PinnedSession] {
        pinnedSessions
            .filter { $0.workspaceScopeFingerprint == workspaceScopeFingerprint }
            .sorted { lhs, rhs in
                lhs.createdAt > rhs.createdAt
            }
    }

    func isSessionPinned(id: String, workspaceScopeFingerprint: String) -> Bool {
        pinnedSessions.contains {
            $0.workspaceScopeFingerprint == workspaceScopeFingerprint &&
                $0.id == id
        }
    }

    func upsertPinnedSession(_ session: SessionSummary, workspaceScopeFingerprint: String) {
        if let index = pinnedSessions.firstIndex(where: {
            $0.workspaceScopeFingerprint == workspaceScopeFingerprint &&
                $0.id == session.id
        }) {
            var pinnedSession = pinnedSessions[index]
            pinnedSession.title = session.title
            pinnedSession.model = session.model
            pinnedSession.startedAt = session.startedAt
            pinnedSession.lastActive = session.lastActive
            pinnedSession.messageCount = session.messageCount
            pinnedSession.preview = session.preview
            pinnedSession.updatedAt = Date()
            pinnedSessions[index] = pinnedSession
            return
        }

        pinnedSessions.append(
            PinnedSession(
                session: session,
                workspaceScopeFingerprint: workspaceScopeFingerprint
            )
        )
    }

    func removePinnedSession(id: String, workspaceScopeFingerprint: String) {
        pinnedSessions.removeAll {
            $0.workspaceScopeFingerprint == workspaceScopeFingerprint &&
                $0.id == id
        }
    }

    func workflows(for workspaceScopeFingerprint: String) -> [WorkflowPreset] {
        workflows
            .filter { $0.workspaceScopeFingerprint == workspaceScopeFingerprint }
            .sorted { lhs, rhs in
                let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }

                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func upsertWorkflow(_ workflow: WorkflowPreset) {
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
            workflows[index] = workflow
        } else {
            workflows.append(workflow)
        }
    }

    func removeWorkflow(id: UUID) {
        workflows.removeAll { $0.id == id }
    }

    func isHermesProfileHidden(name: String, hostConnectionFingerprint: String) -> Bool {
        hiddenHermesProfiles.contains {
            $0.hostConnectionFingerprint == hostConnectionFingerprint &&
                $0.profileName == name
        }
    }

    func hideHermesProfile(name: String, hostConnectionFingerprint: String) {
        let preference = HiddenHermesProfilePreference(
            hostConnectionFingerprint: hostConnectionFingerprint,
            profileName: name
        )
        guard !hiddenHermesProfiles.contains(preference) else { return }
        hiddenHermesProfiles.append(preference)
    }

    func showHermesProfile(name: String, hostConnectionFingerprint: String) {
        hiddenHermesProfiles.removeAll {
            $0.hostConnectionFingerprint == hostConnectionFingerprint &&
                $0.profileName == name
        }
    }

    var visibleSidebarSections: [AppSection] {
        sidebarSectionOrder.filter { !hiddenSidebarSections.contains($0) }
    }

    func isSidebarSectionVisible(_ section: AppSection) -> Bool {
        !hiddenSidebarSections.contains(section)
    }

    func setSidebarSection(_ section: AppSection, isVisible: Bool) {
        guard AppSection.customizableSidebarSections.contains(section) else { return }
        if isVisible {
            hiddenSidebarSections = normalizedHiddenSidebarSections(
                hiddenSidebarSections.filter { $0 != section }
            )
        } else if !hiddenSidebarSections.contains(section) {
            hiddenSidebarSections = normalizedHiddenSidebarSections(hiddenSidebarSections + [section])
        }
    }

    func moveSidebarSection(_ section: AppSection, direction: SidebarSectionMoveDirection) {
        var updatedOrder = normalizedSidebarOrder(sidebarSectionOrder)
        guard let index = updatedOrder.firstIndex(of: section) else { return }
        let destinationIndex: Int
        switch direction {
        case .up:
            destinationIndex = max(updatedOrder.startIndex, index - 1)
        case .down:
            destinationIndex = min(updatedOrder.index(before: updatedOrder.endIndex), index + 1)
        }
        guard destinationIndex != index else { return }
        updatedOrder.swapAt(index, destinationIndex)
        sidebarSectionOrder = updatedOrder
    }

    private func load() {
        isHydratingFromDisk = true
        defer { isHydratingFromDisk = false }
        loadConnections()
        loadPreferences()
    }

    private func saveConnections() {
        do {
            paths.ensureApplicationSupportDirectory()
            let data = try encoder.encode(connections)
            try data.write(to: paths.connectionsURL, options: [.atomic])
            try fileManagerSetPrivatePermissions(at: paths.connectionsURL)
        } catch {
            reportPersistenceError(
                "Unable to save saved hosts to \(paths.connectionsURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
        savePreferences()
    }

    private func savePreferences() {
        let preferences = AppPreferences(
            lastConnectionID: lastConnectionID,
            terminalTheme: terminalTheme,
            terminalFontSize: terminalFontSize,
            appAppearance: appAppearance,
            automaticallyChecksForUpdates: automaticallyChecksForUpdates,
            lastAutomaticUpdateCheckAt: lastAutomaticUpdateCheckAt,
            backgroundImagePath: backgroundImagePath,
            workspaceFileBookmarks: workspaceFileBookmarks,
            pinnedSessions: pinnedSessions,
            workflows: workflows,
            hiddenHermesProfiles: hiddenHermesProfiles,
            sidebarSectionOrder: sidebarSectionOrder,
            hiddenSidebarSections: hiddenSidebarSections
        )

        do {
            paths.ensureApplicationSupportDirectory()
            let data = try encoder.encode(preferences)
            try data.write(to: paths.preferencesURL, options: [.atomic])
            try fileManagerSetPrivatePermissions(at: paths.preferencesURL)
        } catch {
            reportPersistenceError(
                "Unable to save app preferences to \(paths.preferencesURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func loadConnections() {
        do {
            let data = try Data(contentsOf: paths.connectionsURL)
            connections = try decoder.decode([ConnectionProfile].self, from: data)
            try? fileManagerSetPrivatePermissions(at: paths.connectionsURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            connections = []
        } catch {
            connections = []
            reportPersistenceError(
                "Unable to load saved hosts from \(paths.connectionsURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func loadPreferences() {
        do {
            let data = try Data(contentsOf: paths.preferencesURL)
            let decoded = try decoder.decode(AppPreferences.self, from: data)
            applyPreferences(decoded)
            try? fileManagerSetPrivatePermissions(at: paths.preferencesURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            applyDefaultPreferences()
        } catch {
            applyDefaultPreferences()
            reportPersistenceError(
                "Unable to load app preferences from \(paths.preferencesURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func persistPreferencesIfNeeded() {
        guard !isHydratingFromDisk else { return }
        savePreferences()
    }

    private func applyDefaultPreferences() {
        applyPreferences(
            AppPreferences(
                lastConnectionID: nil,
                terminalTheme: .defaultValue,
                terminalFontSize: TerminalFontPreference.defaultSize,
                appAppearance: .system,
                automaticallyChecksForUpdates: true,
                lastAutomaticUpdateCheckAt: nil,
                backgroundImagePath: nil,
                workspaceFileBookmarks: [],
                pinnedSessions: [],
                workflows: [],
                hiddenHermesProfiles: [],
                sidebarSectionOrder: AppSection.customizableSidebarSections,
                hiddenSidebarSections: []
            )
        )
    }

    private func applyPreferences(_ preferences: AppPreferences) {
        lastConnectionID = preferences.lastConnectionID
        terminalTheme = preferences.terminalTheme ?? .defaultValue
        terminalFontSize = TerminalFontPreference.clamped(preferences.terminalFontSize ?? TerminalFontPreference.defaultSize)
        appAppearance = preferences.appAppearance ?? .system
        automaticallyChecksForUpdates = preferences.automaticallyChecksForUpdates ?? true
        lastAutomaticUpdateCheckAt = preferences.lastAutomaticUpdateCheckAt
        backgroundImagePath = preferences.backgroundImagePath
        workspaceFileBookmarks = preferences.workspaceFileBookmarks ?? []
        pinnedSessions = preferences.pinnedSessions ?? []
        workflows = preferences.workflows ?? []
        hiddenHermesProfiles = preferences.hiddenHermesProfiles ?? []
        sidebarSectionOrder = normalizedSidebarOrder(preferences.sidebarSectionOrder ?? AppSection.customizableSidebarSections)
        hiddenSidebarSections = normalizedHiddenSidebarSections(preferences.hiddenSidebarSections ?? [])
    }

    private func reportPersistenceError(_ message: String) {
        persistenceError = message
    }

    private func fileManagerSetPrivatePermissions(at url: URL) throws {
        try paths.fileManager.setAttributes(privateFileAttributes, ofItemAtPath: url.path)
    }
}

private struct AppPreferences: Codable {
    var lastConnectionID: UUID?
    var terminalTheme: TerminalThemePreference?
    var terminalFontSize: Double?
    var appAppearance: AppAppearancePreference?
    var automaticallyChecksForUpdates: Bool?
    var lastAutomaticUpdateCheckAt: Date?
    var backgroundImagePath: String?
    var workspaceFileBookmarks: [WorkspaceFileBookmark]?
    var pinnedSessions: [PinnedSession]?
    var workflows: [WorkflowPreset]?
    var hiddenHermesProfiles: [HiddenHermesProfilePreference]?
    var sidebarSectionOrder: [AppSection]?
    var hiddenSidebarSections: [AppSection]?
}

enum SidebarSectionMoveDirection {
    case up
    case down
}

private func normalizedSidebarOrder(_ sections: [AppSection]) -> [AppSection] {
    var normalized = [AppSection]()
    for section in sections where AppSection.customizableSidebarSections.contains(section) && !normalized.contains(section) {
        normalized.append(section)
    }
    for section in AppSection.customizableSidebarSections where !normalized.contains(section) {
        normalized.append(section)
    }
    return normalized
}

private func normalizedHiddenSidebarSections(_ sections: [AppSection]) -> [AppSection] {
    var normalized = [AppSection]()
    for section in sections where AppSection.customizableSidebarSections.contains(section) && !normalized.contains(section) {
        normalized.append(section)
    }
    return normalized
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
