import AppKit
import Foundation
@preconcurrency import SwiftTerm

@MainActor
final class TerminalViewHost: NSObject, LocalProcessTerminalViewDelegate {
    private let hostView = TerminalHostView()
    private var startedLaunchToken: UUID?
    private var scheduledLaunchToken: UUID?
    private var appliedAppearance: TerminalThemeAppearance?
    private var onProcessStart: (() -> Void)?
    private var onTitleChange: ((String) -> Void)?
    private var onDirectoryChange: ((String?) -> Void)?
    private var onProcessExit: ((Int32?) -> Void)?

    override init() {
        super.init()
        hostView.terminalView.processDelegate = self
    }

    func setEventHandlers(
        onProcessStart: @escaping () -> Void,
        onTitleChange: @escaping (String) -> Void,
        onDirectoryChange: @escaping (String?) -> Void,
        onProcessExit: @escaping (Int32?) -> Void
    ) {
        self.onProcessStart = onProcessStart
        self.onTitleChange = onTitleChange
        self.onDirectoryChange = onDirectoryChange
        self.onProcessExit = onProcessExit
    }

    func mount(
        in container: TerminalMountContainerView,
        request: TerminalLaunchRequest,
        appearance: TerminalThemeAppearance,
        isActive: Bool
    ) {
        container.mount(hostView)
        applyAppearance(appearance)
        setActive(isActive)
        scheduleStartIfNeeded(for: request)
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
            self?.onTitleChange?(title)
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor [weak self] in
            self?.onDirectoryChange?(directory)
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            self?.onProcessExit?(exitCode)
        }
    }

    private func scheduleStartIfNeeded(for request: TerminalLaunchRequest) {
        let launchToken = request.launchToken
        guard startedLaunchToken != launchToken else { return }
        guard scheduledLaunchToken != launchToken else { return }
        scheduledLaunchToken = launchToken

        Task { @MainActor [weak self] in
            self?.startIfNeeded(for: request)
        }
    }

    private func startIfNeeded(for request: TerminalLaunchRequest) {
        scheduledLaunchToken = nil
        guard startedLaunchToken != request.launchToken else { return }
        startedLaunchToken = request.launchToken

        hostView.terminalView.startProcess(
            executable: "/usr/bin/ssh",
            args: request.sshArguments,
            environment: request.terminalEnvironment,
            execName: "ssh"
        )
        onProcessStart?()
    }

    private func applyAppearance(_ appearance: TerminalThemeAppearance) {
        guard appliedAppearance != appearance else { return }
        appliedAppearance = appearance
        hostView.apply(appearance: appearance)
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
        scheduledLaunchToken = nil
        startedLaunchToken = nil
        hostView.terminalView.terminate()
    }
}

struct TerminalLaunchRequest {
    let sshArguments: [String]
    let launchToken: UUID
    let terminalEnvironment: [String]
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

    func apply(appearance: TerminalThemeAppearance) {
        let backgroundColor = appearance.backgroundColor.nsColor
        let foregroundColor = appearance.foregroundColor.nsColor

        layer?.backgroundColor = backgroundColor.cgColor
        terminalView.nativeBackgroundColor = backgroundColor
        terminalView.nativeForegroundColor = foregroundColor
        terminalView.selectedTextBackgroundColor = foregroundColor.withAlphaComponent(0.28)
        terminalView.caretColor = foregroundColor
        terminalView.caretTextColor = backgroundColor
        terminalView.installColors(appearance.ansiPalette.map(Self.makeTerminalColor(from:)))
    }

    private static func makeTerminalColor(from themeColor: TerminalThemeColor) -> SwiftTerm.Color {
        let color = themeColor.nsColor.usingColorSpace(.deviceRGB) ?? .black
        return SwiftTerm.Color(
            red: UInt16(color.redComponent * 65535),
            green: UInt16(color.greenComponent * 65535),
            blue: UInt16(color.blueComponent * 65535)
        )
    }
}
