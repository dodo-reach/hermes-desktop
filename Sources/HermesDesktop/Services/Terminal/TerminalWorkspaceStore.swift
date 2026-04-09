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

    func ensureInitialTab(for connection: ConnectionProfile) {
        if tabs.isEmpty {
            addTab(for: connection)
        } else if let selectedTab, selectedTab.connectionID != connection.id {
            addTab(for: connection)
        }
    }

    func addTab(for connection: ConnectionProfile) {
        let session = TerminalSession(connection: connection, sshTransport: sshTransport)
        let tab = TerminalTabModel(
            title: connection.label,
            connectionID: connection.id,
            session: session
        )
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func closeTab(_ tab: TerminalTabModel) {
        tab.session.stop()
        tabs.removeAll(where: { $0.id == tab.id })
        if selectedTabID == tab.id {
            selectedTabID = tabs.last?.id
        }
    }

    func closeAllTabs() {
        for tab in tabs {
            tab.session.stop()
        }
        tabs = []
        selectedTabID = nil
    }
}
