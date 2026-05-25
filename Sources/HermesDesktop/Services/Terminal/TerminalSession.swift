import Foundation

@MainActor
final class TerminalSession: ObservableObject, @unchecked Sendable {
    enum Backend: Equatable {
        case nativeSSH
        case workspacePTY(sessionId: String? = nil)

        var attachedWorkspaceSessionId: String? {
            guard case let .workspacePTY(sessionId) = self else { return nil }
            return sessionId
        }
    }

    let connection: ConnectionProfile
    let sshArguments: [String]
    let startupInput: String?
    let workflowLaunchDiagnosticsContext: WorkflowLaunchDiagnosticsContext?
    let backend: Backend
    private let workflowLaunchDiagnostics: WorkflowLaunchDiagnostics
    private let viewHost = TerminalViewHost()
    private let workspaceViewHost = WorkspaceTerminalViewHost()

    @Published var terminalTitle: String
    @Published var currentDirectory: String?
    @Published var exitCode: Int32?
    @Published var didStart = false
    @Published private(set) var launchToken = UUID()
    @Published private(set) var isRunning = false

    init(
        connection: ConnectionProfile,
        sshTransport: SSHTransport,
        startupCommandLine: String? = nil,
        startupInput: String? = nil,
        backend: Backend = .nativeSSH,
        workflowLaunchDiagnostics: WorkflowLaunchDiagnostics,
        workflowLaunchDiagnosticsContext: WorkflowLaunchDiagnosticsContext? = nil
    ) {
        self.connection = connection
        self.startupInput = startupInput
        self.backend = backend
        self.workflowLaunchDiagnostics = workflowLaunchDiagnostics
        self.workflowLaunchDiagnosticsContext = workflowLaunchDiagnosticsContext
        self.sshArguments = sshTransport.shellArguments(
            for: connection,
            startupCommandLine: startupCommandLine
        )
        self.terminalTitle = backend.isWorkspacePTY
            ? "Shared PTY · \(connection.resolvedHermesProfileName)"
            : "\(connection.label) · \(connection.resolvedHermesProfileName)"
        viewHost.setEventHandlers(
            onProcessStart: { [weak self] in
                self?.markStarted()
            },
            onTitleChange: { [weak self] title in
                self?.updateTitle(title)
            },
            onDirectoryChange: { [weak self] directory in
                self?.currentDirectory = directory
            },
            onProcessExit: { [weak self] exitCode in
                self?.markExited(exitCode)
            }
        )
        workspaceViewHost.setEventHandlers(
            onProcessStart: { [weak self] in
                self?.markStarted()
            },
            onTitleChange: { [weak self] title in
                self?.updateTitle(title)
            },
            onDirectoryChange: { [weak self] directory in
                self?.currentDirectory = directory
            },
            onProcessExit: { [weak self] exitCode in
                self?.markExited(exitCode)
            }
        )
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
        if let workflowLaunchDiagnosticsContext {
            Task {
                await workflowLaunchDiagnostics.recordTerminalProcessExited(
                    workflowLaunchDiagnosticsContext,
                    exitCode: code
                )
            }
        }
    }

    func requestReconnect() {
        currentDirectory = nil
        exitCode = nil
        launchToken = UUID()
    }

    func mount(in container: TerminalMountContainerView, appearance: TerminalThemeAppearance, isActive: Bool) {
        switch backend {
        case .nativeSSH:
            viewHost.mount(
                in: container,
                request: TerminalLaunchRequest(
                    sshArguments: sshArguments,
                    launchToken: launchToken,
                    initialInput: startupInput,
                    workflowLaunchDiagnostics: workflowLaunchDiagnostics,
                    workflowLaunchDiagnosticsContext: workflowLaunchDiagnosticsContext
                ),
                appearance: appearance,
                isActive: isActive
            )
        case .workspacePTY:
            workspaceViewHost.mount(
                in: container,
                request: WorkspaceTerminalLaunchRequest(
                    baseURL: connection.resolvedCaelWorkspaceBaseURL,
                    launchToken: launchToken,
                    attachedSessionId: backend.attachedWorkspaceSessionId
                ),
                appearance: appearance,
                isActive: isActive
            )
        }
    }

    func unmount(from container: TerminalMountContainerView) {
        switch backend {
        case .nativeSSH:
            viewHost.unmount(from: container)
        case .workspacePTY:
            workspaceViewHost.unmount(from: container)
        }
    }

    func stop() {
        viewHost.terminate()
        workspaceViewHost.terminate()
        isRunning = false
        currentDirectory = nil
    }

    var backendLabel: String {
        switch backend {
        case .nativeSSH:
            return "Native SSH"
        case .workspacePTY(let sessionId):
            return sessionId == nil ? "Shared PTY" : "Attached PTY"
        }
    }

    var isWorkspacePTY: Bool {
        backend.isWorkspacePTY
    }
}


private extension TerminalSession.Backend {
    var isWorkspacePTY: Bool {
        if case .workspacePTY = self { return true }
        return false
    }
}
