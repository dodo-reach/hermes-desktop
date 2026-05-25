import AppKit
import Foundation
@preconcurrency import SwiftTerm

@MainActor
final class WorkspaceTerminalViewHost: NSObject, TerminalViewDelegate {
    private let hostView = WorkspaceTerminalHostView()
    private var appliedAppearance: TerminalThemeAppearance?
    private var startedLaunchToken: UUID?
    private var scheduledLaunchToken: UUID?
    private var streamTask: Task<Void, Never>?
    private var sessionId: String?
    private var baseURL: URL?
    private var shouldCloseServerSessionOnTerminate = true
    private var onProcessStart: (() -> Void)?
    private var onTitleChange: ((String) -> Void)?
    private var onDirectoryChange: ((String?) -> Void)?
    private var onProcessExit: ((Int32?) -> Void)?

    override init() {
        super.init()
        hostView.terminalView.terminalDelegate = self
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
        request: WorkspaceTerminalLaunchRequest,
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
        Task { @MainActor [weak self] in
            self?.terminateOnMainThread()
        }
    }

    nonisolated func send(source _: TerminalView, data: ArraySlice<UInt8>) {
        let text = String(decoding: data, as: UTF8.self)
        Task { [weak self] in
            await self?.sendInput(text)
        }
    }

    nonisolated func sizeChanged(source _: TerminalView, newCols: Int, newRows: Int) {
        Task { [weak self] in
            await self?.resize(cols: newCols, rows: newRows)
        }
    }

    nonisolated func setTerminalTitle(source _: TerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.onTitleChange?(title)
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source _: TerminalView, directory: String?) {
        Task { @MainActor [weak self] in
            self?.onDirectoryChange?(directory)
        }
    }

    nonisolated func scrolled(source _: TerminalView, position _: Double) {}

    nonisolated func requestOpenLink(source _: TerminalView, link: String, params _: [String: String]) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated func bell(source _: TerminalView) {
        NSSound.beep()
    }

    nonisolated func clipboardCopy(source _: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    nonisolated func iTermContent(source _: TerminalView, content _: ArraySlice<UInt8>) {}

    nonisolated func rangeChanged(source _: TerminalView, startY _: Int, endY _: Int) {}

    private func scheduleStartIfNeeded(for request: WorkspaceTerminalLaunchRequest) {
        let launchToken = request.launchToken
        guard startedLaunchToken != launchToken else { return }
        guard scheduledLaunchToken != launchToken else { return }
        scheduledLaunchToken = launchToken

        Task { @MainActor [weak self] in
            self?.startIfNeeded(for: request)
        }
    }

    private func startIfNeeded(for request: WorkspaceTerminalLaunchRequest) {
        scheduledLaunchToken = nil
        guard startedLaunchToken != request.launchToken else { return }
        guard let url = URL(string: request.baseURL) else {
            feedStatusLine("Invalid Workspace terminal URL: \(request.baseURL)")
            onProcessExit?(1)
            return
        }

        startedLaunchToken = request.launchToken
        baseURL = url
        sessionId = request.attachedSessionId
        shouldCloseServerSessionOnTerminate = request.attachedSessionId == nil
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.runStream(baseURL: url, launchToken: request.launchToken)
        }
        onProcessStart?()
    }

    private func runStream(baseURL: URL, launchToken: UUID) async {
        do {
            var body: [String: Any] = [
                "cols": max(20, hostView.terminalView.terminal.cols),
                "rows": max(5, hostView.terminalView.terminal.rows)
            ]
            if let sessionId {
                body["sessionId"] = sessionId
            }

            var request = URLRequest(url: try endpoint(baseURL: baseURL, path: "/api/terminal-stream"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (lines, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                feedStatusLine("Workspace terminal stream failed.")
                onProcessExit?(1)
                return
            }

            var eventName = "message"
            var eventDataLines: [String] = []
            for try await line in lines.lines {
                if Task.isCancelled || startedLaunchToken != launchToken { return }
                if line.isEmpty {
                    handleSSEEvent(name: eventName, data: eventDataLines.joined(separator: "\n"))
                    eventName = "message"
                    eventDataLines.removeAll(keepingCapacity: true)
                    continue
                }
                if line.hasPrefix("event: ") {
                    eventName = String(line.dropFirst(7))
                } else if line.hasPrefix("data: ") {
                    eventDataLines.append(String(line.dropFirst(6)))
                }
            }
        } catch is CancellationError {
            return
        } catch {
            feedStatusLine("Workspace terminal stream error: \(error.localizedDescription)")
            onProcessExit?(1)
        }
    }

    private func handleSSEEvent(name: String, data: String) {
        guard !data.isEmpty else { return }
        switch name {
        case "session":
            if let payload = decode(WorkspaceTerminalSessionPayload.self, from: data) {
                sessionId = payload.sessionId
                shouldCloseServerSessionOnTerminate = payload.reattach != true && shouldCloseServerSessionOnTerminate
                let prefix = payload.reattach == true ? "Attached PTY" : "Shared PTY"
                onTitleChange?("\(prefix) · \(payload.sessionId.prefix(8))")
            }
        case "data":
            if let text = decode(String.self, from: data) {
                hostView.terminalView.feed(byteArray: Array(text.utf8)[...])
            } else if let payload = decode(WorkspaceTerminalDataPayload.self, from: data) {
                hostView.terminalView.feed(byteArray: Array(payload.data.utf8)[...])
            }
        case "exit":
            let code = decode(WorkspaceTerminalExitPayload.self, from: data)?.exitCode
            onProcessExit?(code)
        case "close":
            onProcessExit?(0)
        default:
            break
        }
    }

    private func sendInput(_ text: String) async {
        guard !text.isEmpty, let sessionId, let baseURL else { return }
        try? await post(baseURL: baseURL, path: "/api/terminal-input", body: [
            "sessionId": sessionId,
            "data": text
        ])
    }

    private func resize(cols: Int, rows: Int) async {
        guard let sessionId, let baseURL else { return }
        try? await post(baseURL: baseURL, path: "/api/terminal-resize", body: [
            "sessionId": sessionId,
            "cols": max(20, cols),
            "rows": max(5, rows)
        ])
    }

    private func post(baseURL: URL, path: String, body: [String: Any]) async throws {
        var request = URLRequest(url: try endpoint(baseURL: baseURL, path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: request)
    }

    private func closeServerSessionIfNeeded() {
        guard shouldCloseServerSessionOnTerminate, let sessionId, let baseURL else { return }
        let closeSessionId = sessionId
        Task {
            try? await post(baseURL: baseURL, path: "/api/terminal-close", body: ["sessionId": closeSessionId])
        }
    }

    private func terminateOnMainThread() {
        scheduledLaunchToken = nil
        startedLaunchToken = nil
        streamTask?.cancel()
        streamTask = nil
        closeServerSessionIfNeeded()
        sessionId = nil
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
        } else {
            hostView.window?.makeFirstResponder(hostView.terminalView)
        }
    }

    private func feedStatusLine(_ text: String) {
        hostView.terminalView.feed(text: "\r\n\(text)\r\n")
    }

    private func endpoint(baseURL: URL, path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw URLError(.badURL)
        }
        return url
    }

    private func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

struct WorkspaceTerminalLaunchRequest {
    let baseURL: String
    let launchToken: UUID
    let attachedSessionId: String?
}

private struct WorkspaceTerminalSessionPayload: Decodable {
    let sessionId: String
    let reattach: Bool?
}

private struct WorkspaceTerminalDataPayload: Decodable {
    let data: String
}

private struct WorkspaceTerminalExitPayload: Decodable {
    let exitCode: Int32?
}

final class WorkspaceTerminalHostView: NSView {
    let terminalView = TerminalView(frame: .zero)

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
        terminalView.installColors(appearance.ansiPalette.map(TerminalHostView.makeTerminalColor(from:)))
    }
}
