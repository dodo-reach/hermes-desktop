import AppKit
@preconcurrency import SwiftTerm
import SwiftUI

struct SwiftTermTerminalView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> TerminalHostView {
        let hostView = TerminalHostView()
        hostView.terminalView.processDelegate = context.coordinator
        context.coordinator.attach(to: hostView.terminalView)
        context.coordinator.startIfNeeded()
        hostView.isHidden = !isActive
        return hostView
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        context.coordinator.session = session
        context.coordinator.attach(to: nsView.terminalView)
        context.coordinator.startIfNeeded()
        nsView.isHidden = !isActive

        if !isActive {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    static func dismantleNSView(_ nsView: TerminalHostView, coordinator: Coordinator) {
        coordinator.terminateProcess()
        nsView.terminalView.processDelegate = nil
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var session: TerminalSession
        private weak var terminalView: LocalProcessTerminalView?
        private var startedLaunchToken: UUID?

        init(session: TerminalSession) {
            self.session = session
        }

        func attach(to terminalView: LocalProcessTerminalView) {
            self.terminalView = terminalView
        }

        func startIfNeeded() {
            guard let terminalView else { return }
            let launchToken = session.launchToken
            guard startedLaunchToken != launchToken else { return }
            startedLaunchToken = launchToken
            session.markStarted()

            let environment = [
                "TERM=xterm-256color",
                "COLORTERM=truecolor"
            ]

            let sshArguments = session.sshArguments
            Task { @MainActor [weak terminalView] in
                terminalView?.startProcess(
                    executable: "/usr/bin/ssh",
                    args: sshArguments,
                    environment: environment,
                    execName: "ssh"
                )
            }
        }

        func terminateProcess() {
            performSelector(onMainThread: #selector(terminateOnMainThread), with: nil, waitUntilDone: false)
        }

        @MainActor
        @objc
        private func terminateOnMainThread() {
            terminalView?.terminate()
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            DispatchQueue.main.async { [session] in
                session.updateTitle(title)
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            DispatchQueue.main.async { [session] in
                session.currentDirectory = directory
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [session] in
                session.markExited(exitCode)
            }
        }
    }
}

final class TerminalHostView: NSView {
    let terminalView = LocalProcessTerminalView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
