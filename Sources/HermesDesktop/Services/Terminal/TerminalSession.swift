import Foundation

@MainActor
final class TerminalSession: ObservableObject, @unchecked Sendable {
    let connection: ConnectionProfile
    let sshArguments: [String]
    private let viewHost = TerminalViewHost()

    @Published var terminalTitle: String
    @Published var currentDirectory: String?
    @Published var exitCode: Int32?
    @Published var didStart = false
    @Published private(set) var launchToken = UUID()
    @Published private(set) var isRunning = false

    init(connection: ConnectionProfile, sshTransport: SSHTransport) {
        self.connection = connection
        self.sshArguments = sshTransport.shellArguments(for: connection)
        self.terminalTitle = connection.label
        viewHost.bind(session: self)
    }

    deinit {
        viewHost.terminate()
    }

    func markStarted() {
        didStart = true
        isRunning = true
        exitCode = nil
    }

    func updateTitle(_ title: String) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        terminalTitle = title
    }

    func markExited(_ code: Int32?) {
        isRunning = false
        exitCode = code
    }

    func requestReconnect() {
        currentDirectory = nil
        exitCode = nil
        launchToken = UUID()
    }

    func mount(in container: TerminalMountContainerView, isActive: Bool) {
        viewHost.mount(in: container, session: self, isActive: isActive)
    }

    func unmount(from container: TerminalMountContainerView) {
        viewHost.unmount(from: container)
    }

    func stop() {
        viewHost.terminate()
        isRunning = false
        currentDirectory = nil
    }
}
