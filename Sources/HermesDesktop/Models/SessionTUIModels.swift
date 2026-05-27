import Foundation

enum SessionDetailMode: String, CaseIterable, Equatable, Sendable {
    case chat
}

@MainActor
final class SessionTUITerminal: ObservableObject, Identifiable {
    let id = UUID()
    let sessionID: String?
    let connectionWorkspaceFingerprint: String
    let invocation: HermesTUIInvocation
    let terminalSession: TerminalSession

    init(
        sessionID: String?,
        connection: ConnectionProfile,
        sshTransport: SSHTransport,
        workflowLaunchDiagnostics: WorkflowLaunchDiagnostics,
        startupInput: String? = nil,
        workflowLaunchDiagnosticsContext: WorkflowLaunchDiagnosticsContext? = nil
    ) {
        self.sessionID = sessionID
        self.connectionWorkspaceFingerprint = connection.workspaceScopeFingerprint
        self.invocation = HermesTUIInvocation(sessionID: sessionID, connection: connection)
        self.terminalSession = TerminalSession(
            connection: connection,
            sshTransport: sshTransport,
            startupCommandLine: invocation.startupCommandLine,
            startupInput: startupInput,
            workflowLaunchDiagnostics: workflowLaunchDiagnostics,
            workflowLaunchDiagnosticsContext: workflowLaunchDiagnosticsContext
        )
    }

    var targetLabel: String {
        sessionID.map { "Session \(Self.shortSessionID($0))" } ?? "New Chat"
    }

    func matches(sessionID: String?, connection: ConnectionProfile) -> Bool {
        self.sessionID == sessionID &&
            connectionWorkspaceFingerprint == connection.workspaceScopeFingerprint
    }

    func stop() {
        terminalSession.stop()
    }

    private static func shortSessionID(_ sessionID: String) -> String {
        if sessionID.count <= 10 {
            return sessionID
        }
        return String(sessionID.prefix(10))
    }
}
