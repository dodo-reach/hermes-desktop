import Foundation

@MainActor
final class TerminalWorkspaceStore: ObservableObject {
    @Published private(set) var tabs: [TerminalTabModel] = []
    @Published var selectedTabID: UUID?

    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    var selectedTab: TerminalTabModel? {
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    var hasTabs: Bool {
        !tabs.isEmpty
    }

    func selectTab(_ tabID: UUID?) {
        selectedTabID = tabID
    }

    func ensureInitialTab(for connection: ConnectionProfile) {
        if let existingTab = existingTab(for: connection.workspaceScopeFingerprint) {
            selectTab(existingTab.id)
        } else {
            addTab(for: connection)
        }
    }

    @discardableResult
    func addTab(for connection: ConnectionProfile) -> TerminalTabModel {
        let session = TerminalSession(connection: connection, sshTransport: sshTransport)
        let tab = TerminalTabModel(
            title: connection.label,
            connectionID: connection.id,
            hostConnectionFingerprint: connection.hostConnectionFingerprint,
            workspaceScopeFingerprint: connection.workspaceScopeFingerprint,
            session: session
        )
        tabs.append(tab)
        selectTab(tab.id)
        return tab
    }

    func closeTab(_ tab: TerminalTabModel) {
        if selectedTabID == tab.id {
            selectTab(tabs.last(where: { $0.id != tab.id })?.id)
        }
        tabs.removeAll(where: { $0.id == tab.id })
        tab.session.stop()
    }

    func closeAllTabs() {
        for tab in tabs {
            tab.session.stop()
        }
        tabs = []
        selectTab(nil)
    }

    func closeTabs(forConnectionID connectionID: UUID) {
        let removedTabs = tabs.filter { $0.connectionID == connectionID }
        let removedTabIDs = Set(removedTabs.map(\.id))

        if let selectedTabID, removedTabIDs.contains(selectedTabID) {
            selectTab(tabs.last(where: { !removedTabIDs.contains($0.id) })?.id)
        }

        tabs.removeAll(where: { $0.connectionID == connectionID })

        for tab in removedTabs {
            tab.session.stop()
        }
    }

    private func existingTab(for workspaceScopeFingerprint: String) -> TerminalTabModel? {
        tabs.last(where: { $0.workspaceScopeFingerprint == workspaceScopeFingerprint })
    }
}
