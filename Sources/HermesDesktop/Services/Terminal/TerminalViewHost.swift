import AppKit
import Foundation
@preconcurrency import SwiftTerm

@MainActor
final class TerminalViewHost: NSObject, LocalProcessTerminalViewDelegate {
    private weak var session: TerminalSession?
    private let hostView = TerminalHostView()
    private var startedLaunchToken: UUID?

    override init() {
        super.init()
        hostView.terminalView.processDelegate = self
    }

    func bind(session: TerminalSession) {
        self.session = session
    }

    func mount(in container: TerminalMountContainerView, session: TerminalSession, isActive: Bool) {
        self.session = session
        container.mount(hostView)
        setActive(isActive)
        startIfNeeded(for: session)
    }

    func unmount(from container: TerminalMountContainerView) {
        container.unmountHostedView()
    }

    nonisolated func terminate() {
        performSelector(onMainThread: #selector(terminateOnMainThread), with: nil, waitUntilDone: false)
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.session?.updateTitle(title)
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor [weak self] in
            self?.session?.currentDirectory = directory
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            self?.session?.markExited(exitCode)
        }
    }

    private func startIfNeeded(for session: TerminalSession) {
        let launchToken = session.launchToken
        guard startedLaunchToken != launchToken else { return }
        startedLaunchToken = launchToken
        session.markStarted()

        let environment = [
            "TERM=xterm-256color",
            "COLORTERM=truecolor"
        ]

        hostView.terminalView.startProcess(
            executable: session.executablePath,
            args: session.terminalArguments,
            environment: environment,
            execName: session.usesMosh ? "mosh" : "ssh"
        )
    }

    private func setActive(_ isActive: Bool) {
        hostView.isHidden = !isActive
        if !isActive {
            hostView.window?.makeFirstResponder(nil)
        }
    }

    @MainActor
    @objc
    private func terminateOnMainThread() {
        hostView.terminalView.terminate()
    }
}

final class TerminalMountContainerView: NSView {
    private weak var hostedView: NSView?
    private var hostedConstraints: [NSLayoutConstraint] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func mount(_ view: NSView) {
        if hostedView === view, view.superview === self {
            return
        }

        unmountHostedView()
        if let previousContainer = view.superview as? TerminalMountContainerView,
           previousContainer !== self {
            previousContainer.releaseHostedViewReference(ifMatching: view)
        }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        hostedView = view
        hostedConstraints = [
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(hostedConstraints)
    }

    func unmountHostedView() {
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedConstraints.removeAll(keepingCapacity: false)
        if hostedView?.superview === self {
            hostedView?.removeFromSuperview()
        }
        hostedView = nil
    }

    private func releaseHostedViewReference(ifMatching view: NSView) {
        guard hostedView === view else { return }
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedConstraints.removeAll(keepingCapacity: false)
        hostedView = nil
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
