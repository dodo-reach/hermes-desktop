#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit

enum HermesChatMessageRole: String, Sendable {
    case user
    case assistant
    case system
    case error
}

struct HermesChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    var role: HermesChatMessageRole
    var text: String
    var timestamp: Date
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: HermesChatMessageRole,
        text: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

struct HermesChatToolCard: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var status: String
    var detail: String?
    var toolType: String?
    var actionPreview: String?
    var expandedDetail: String?
    var isRunning: Bool
    var updatedAt: Date
}

enum HermesChatPromptKind: String, Sendable {
    case approval
    case clarify
    case sudo
    case secret
}

struct HermesChatPromptCard: Identifiable, Hashable, Sendable {
    let id: String
    let sessionID: String?
    let requestID: String
    let kind: HermesChatPromptKind
    var title: String
    var message: String
    var choices: [String]
    var placeholder: String?
    var toolType: String?
    var actionSummary: String?
    var commandPreview: String?
    var payloadPreview: String?
}

struct CompactionNotice: Identifiable, Hashable, Sendable {
    let id = UUID()
    var message: String
    var oldSessionID: String?
    var newSessionID: String?
    var isCurrentSession: Bool
}

struct HermesChatContinuation: Identifiable, Hashable, Sendable {
    let id = UUID()
    var parentSessionID: String
    var currentSessionID: String
    var title: String?
    var message: String
}

struct HermesGatewayPreview: Hashable, Sendable {
    var toolType: String?
    var actionSummary: String?
    var commandPreview: String?
    var payloadPreview: String?
}

struct HermesChatCommandSuggestion: Identifiable, Hashable, Sendable {
    let command: String
    let title: String
    let summary: String
    let acceptsDraftAsArgument: Bool

    var id: String { command }

    static let dailyFallbacks: [HermesChatCommandSuggestion] = [
        HermesChatCommandSuggestion(command: "/stop", title: "Stop", summary: "Interrupt the running agent.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/help", title: "Help", summary: "Show Hermes command help.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/status", title: "Status", summary: "Show session, model, profile and working state.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/model", title: "Model", summary: "Show or change the current model.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/title", title: "Title", summary: "Set the current session title.", acceptsDraftAsArgument: true),
        HermesChatCommandSuggestion(command: "/goal", title: "Goal", summary: "Set a standing goal Hermes works toward across turns.", acceptsDraftAsArgument: true),
        HermesChatCommandSuggestion(command: "/goal status", title: "Goal Status", summary: "Check the active goal loop.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/goal pause", title: "Pause Goal", summary: "Pause goal auto-continuation.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/goal resume", title: "Resume Goal", summary: "Resume a paused goal loop.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/goal clear", title: "Clear Goal", summary: "Clear the active goal.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/retry", title: "Retry", summary: "Retry the last message.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/undo", title: "Undo", summary: "Remove the last user/assistant exchange.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/queue", title: "Queue", summary: "Queue a prompt for the next turn.", acceptsDraftAsArgument: true),
        HermesChatCommandSuggestion(command: "/steer", title: "Steer", summary: "Inject guidance after the next tool call without interrupting.", acceptsDraftAsArgument: true),
        HermesChatCommandSuggestion(command: "/compress", title: "Compress", summary: "Manually compress conversation context.", acceptsDraftAsArgument: true),
        HermesChatCommandSuggestion(command: "/usage", title: "Usage", summary: "Show token usage, cost and quota details.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/tools", title: "Tools", summary: "List or manage available tools for this session.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/toolsets", title: "Toolsets", summary: "List available toolsets.", acceptsDraftAsArgument: false),
        HermesChatCommandSuggestion(command: "/reload-skills", title: "Reload Skills", summary: "Re-scan installed skills on the host.", acceptsDraftAsArgument: false)
    ]

    static func dailySuggestions(catalog: [HermesSlashCommandCatalogEntry]) -> [HermesChatCommandSuggestion] {
        guard !catalog.isEmpty else { return dailyFallbacks }
        let catalogByName = Dictionary(uniqueKeysWithValues: catalog.map { ($0.name.lowercased(), $0) })
        return dailyFallbacks.map { fallback in
            let lookupName = fallback.command.split(separator: " ").first.map(String.init) ?? fallback.command
            guard let entry = catalogByName[lookupName.lowercased()] else { return fallback }
            return HermesChatCommandSuggestion(
                command: fallback.command,
                title: fallback.title,
                summary: entry.description ?? fallback.summary,
                acceptsDraftAsArgument: fallback.acceptsDraftAsArgument
            )
        }
    }
}

enum HermesGatewayPreviewBuilder {
    static func preview(
        from payload: [String: JSONValue],
        redactsSensitiveContent: Bool = false
    ) -> HermesGatewayPreview {
        let toolType = value(in: payload, keys: ["tool", "tool_type", "type", "name"])
        let actionSummary = value(in: payload, keys: ["description", "summary", "preview", "message", "title"])
        let commandPreview = redactsSensitiveContent ? nil : value(in: payload, keys: ["command", "cmd"])
        let payloadPreview = redactsSensitiveContent ? nil : compactPayloadPreview(from: payload)

        return HermesGatewayPreview(
            toolType: toolType,
            actionSummary: actionSummary,
            commandPreview: commandPreview,
            payloadPreview: payloadPreview
        )
    }

    private static func value(in payload: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return sanitize(value)
            }
        }

        for key in keys {
            if let value = payload[key] {
                let display = value.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !display.isEmpty {
                    return sanitize(display)
                }
            }
        }
        return nil
    }

    private static func compactPayloadPreview(from payload: [String: JSONValue]) -> String? {
        let redactedKeys = Set(["password", "secret", "token", "api_key", "apikey", "authorization"])
        let filtered = payload.filter { key, value in
            !redactedKeys.contains(key.lowercased()) && value != .null
        }
        guard !filtered.isEmpty else { return nil }

        return sanitize(JSONValue.object(filtered).displayString)
    }

    private static func sanitize(_ value: String) -> String {
        let compact = HermesGatewayTextSanitizer.sanitize(value)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard compact.count > 220 else { return compact }
        return String(compact.prefix(217)) + "..."
    }
}

@MainActor
final class HermesNativeChatStore: ObservableObject {
    @Published var bootstrapStatus: HermesChatBootstrapStatus?
    @Published var connectionStatus = "Idle"
    @Published var sessionStatus = "No active chat session"
    @Published var currentSessionID: String?
    @Published var messages: [HermesChatMessage] = []
    @Published var toolCards: [HermesChatToolCard] = []
    @Published var promptCards: [HermesChatPromptCard] = []
    @Published var compactionNotice: CompactionNotice?
    @Published var continuation: HermesChatContinuation?
    @Published var diagnostics: [String] = []
    @Published var rawEvents: [HermesGatewayEvent] = []
    @Published var slashCommandCatalog: [HermesSlashCommandCatalogEntry] = []
    @Published var isLoadingSlashCommandCatalog = false
    @Published var slashCommandCatalogError: String?
    @Published var draftMessage = ""
    @Published var lastError: String?
    @Published var showDiagnostics = false
    @Published var gatewayInfo: [String: String] = [:]
    @Published var isCheckingBootstrap = false
    @Published var isConnecting = false
    @Published var isPreparingSession = false
    @Published var isPerformingRequest = false
    @Published var isResumingSession = false
    @Published private(set) var pendingResumeTitle: String?
    @Published private(set) var pendingResumeRequestID: UUID?

    weak var phoneStore: HermesPhoneStore?

    private let sshTransport: SSHTransport
    private var gatewaySession: HermesGatewaySSHSession?
    private var eventTask: Task<Void, Never>?
    private var activeConnectionFingerprint: String?
    private var currentAssistantMessageID: UUID?
    private var pendingResumeSession: SessionSummary?
    private var isCreatingSession = false
    private var conversationGeneration = 0

    init(phoneStore: HermesPhoneStore, sshTransport: SSHTransport) {
        self.phoneStore = phoneStore
        self.sshTransport = sshTransport
    }

    var canUseNativeChat: Bool {
        bootstrapStatus?.canUseNativeChat == true
    }

    var fallbackReason: String? {
        bootstrapStatus?.fallbackReason
    }

    var hasConversationContent: Bool {
        currentSessionID != nil || !messages.isEmpty || !toolCards.isEmpty || !promptCards.isEmpty
    }

    var hasRestorableConversation: Bool {
        hasConversationContent && !isResumingSession
    }

    var restorableConversationTitle: String {
        if let title = continuation?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let title = pendingResumeTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let currentSessionID, !currentSessionID.isEmpty {
            return "Session \(currentSessionID.prefix(8))"
        }
        return "Current Chat"
    }

    var restorableConversationPreview: String {
        if let prompt = promptCards.last {
            return compactPreview("Action required: \(prompt.title)")
        }
        if let tool = latestToolCard {
            let status = tool.isRunning ? "Running" : tool.status
            let detail = tool.actionPreview ?? tool.detail ?? tool.expandedDetail
            return compactPreview([status, tool.title, detail].compactMap { $0 }.joined(separator: " · "))
        }
        if let message = messages.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return compactPreview(message.text)
        }
        return sessionStatus
    }

    var restorableConversationStatus: String {
        if !promptCards.isEmpty {
            return "Needs input"
        }
        if isPreparingSession {
            return "Preparing"
        }
        if isPerformingRequest || messages.contains(where: \.isStreaming) || latestToolCard?.isRunning == true {
            return "Working"
        }
        return "Open in background"
    }

    var restorableConversationUpdatedAt: Date? {
        [
            messages.last?.timestamp,
            latestToolCard?.updatedAt
        ]
        .compactMap { $0 }
        .max()
    }

    var latestToolCard: HermesChatToolCard? {
        toolCards.max(by: { $0.updatedAt < $1.updatedAt })
    }

    var dailyCommandSuggestions: [HermesChatCommandSuggestion] {
        HermesChatCommandSuggestion.dailySuggestions(catalog: slashCommandCatalog)
    }

    var activeLineageSessionIDs: Set<String> {
        var ids = Set<String>()
        if let currentSessionID {
            ids.insert(currentSessionID)
        }
        if let continuation {
            ids.insert(continuation.parentSessionID)
            ids.insert(continuation.currentSessionID)
        }
        return ids
    }

    func isActiveConversation(_ summary: SessionSummary) -> Bool {
        if activeLineageSessionIDs.contains(summary.id) {
            return true
        }
        if let parentSessionID = summary.parentSessionID,
           activeLineageSessionIDs.contains(parentSessionID) {
            return true
        }
        return false
    }

    func prepareNewChat() {
        pendingResumeSession = nil
        pendingResumeTitle = nil
        pendingResumeRequestID = nil
        isResumingSession = false
        clearConversationState(keepDiagnostics: true)
        sessionStatus = "Ready to start a new chat"
        connectionStatus = phoneStore?.activeConnection == nil ? "No active SSH connection" : "Ready for native chat"
    }

    func prepareNewChatReplacingActiveConversation() async {
        await closeActiveConversationIfNeeded()
        prepareNewChat()
        await prepareSessionForNewChat()
    }

    func syncWithActiveConnection() async {
        let fingerprint = phoneStore?.activeWorkspaceScopeFingerprint
        guard fingerprint != activeConnectionFingerprint else { return }

        await disconnectFromGateway(resetMessages: true)
        bootstrapStatus = nil
        gatewayInfo = [:]
        slashCommandCatalog = []
        slashCommandCatalogError = nil
        currentSessionID = nil
        pendingResumeSession = nil
        pendingResumeTitle = nil
        pendingResumeRequestID = nil
        isResumingSession = false
        activeConnectionFingerprint = fingerprint
        connectionStatus = fingerprint == nil ? "No active SSH connection" : "Idle"
        sessionStatus = "No active chat session"
        lastError = nil
    }

    func refreshBootstrapStatus(force: Bool = false) async {
        await syncWithActiveConnection()

        if isCheckingBootstrap {
            connectionStatus = "Checking remote Hermes environment..."
            await waitForBootstrapProbe()
            if !force || bootstrapStatus?.canUseNativeChat == true {
                return
            }
        }

        guard force || bootstrapStatus == nil else { return }
        guard let connection = phoneStore?.activeConnection else {
            isCheckingBootstrap = false
            bootstrapStatus = HermesChatBootstrapStatus(
                sshConnected: false,
                pythonAvailable: false,
                hermesCLIAvailable: false,
                hermesVersion: nil,
                tuiGatewayAvailable: false,
                canUseNativeChat: false,
                fallbackReason: "Choose a saved connection before opening Chat."
            )
            connectionStatus = "No active SSH connection"
            return
        }

        isCheckingBootstrap = true
        defer { isCheckingBootstrap = false }
        connectionStatus = "Checking remote Hermes environment..."
        let requestedFingerprint = connection.workspaceScopeFingerprint
        let status = await sshTransport.probeNativeChatAvailability(on: connection)
        guard phoneStore?.activeWorkspaceScopeFingerprint == requestedFingerprint else { return }
        bootstrapStatus = status

        if status.canUseNativeChat {
            connectionStatus = "Ready for native chat"
            if let version = status.hermesVersion, !version.isEmpty {
                gatewayInfo["Hermes"] = version
            }
        } else {
            connectionStatus = "Native chat unavailable"
        }
    }

    private func createSession() async {
        if isCreatingSession {
            sessionStatus = "Preparing chat session..."
            await waitForSessionCreation()
            return
        }

        isCreatingSession = true
        isPreparingSession = true
        defer {
            isCreatingSession = false
            isPreparingSession = false
        }

        await ensureGatewaySession()
        guard let session = gatewaySession else { return }

        clearConversationState(keepDiagnostics: true)
        sessionStatus = "Creating chat session..."

        do {
            let result = try await session.request(
                method: "session.create",
                params: [
                    "client": .string("HermesPhone"),
                    "source": .string("ios"),
                    "ui": .string("native")
                ],
                timeout: 60
            )
            applySessionResult(result, preferredSessionID: nil)
            sessionStatus = "Chat session ready"
        } catch {
            present(error)
        }
    }

    @discardableResult
    private func ensureCurrentChatSession() async -> Bool {
        await ensureGatewaySession()
        guard gatewaySession != nil else { return false }
        if currentSessionID != nil { return true }

        await createSession()
        return currentSessionID != nil
    }

    private func prepareSessionForNewChat() async {
        guard !isResumingSession else { return }
        await ensureCurrentChatSession()
    }

    @discardableResult
    func continueSession(_ summary: SessionSummary) async -> Bool {
        pendingResumeTitle = summary.resolvedTitle
        isResumingSession = true
        defer {
            if pendingResumeSession?.id == summary.id {
                pendingResumeSession = nil
                pendingResumeRequestID = nil
            }
            pendingResumeTitle = nil
            isResumingSession = false
        }

        sessionStatus = "Resuming \(summary.resolvedTitle)..."
        await ensureGatewaySession()
        guard let session = gatewaySession else {
            sessionStatus = fallbackReason ?? "Hermes TUI Gateway is not available on this host."
            return false
        }

        clearConversationState(keepDiagnostics: true)
        sessionStatus = "Loading \(summary.resolvedTitle)..."

        do {
            let result = try await session.request(
                method: "session.resume",
                params: [
                    "session_id": .string(summary.id),
                    "id": .string(summary.id)
                ],
                timeout: 60
            )
            applySessionResult(result, preferredSessionID: summary.id)

            let historySessionID = currentSessionID ?? summary.id
            let history = try await session.request(
                method: "session.history",
                params: [
                    "session_id": .string(historySessionID),
                    "id": .string(historySessionID)
                ],
                timeout: 60
            )
            applyHistoryResult(history)

            if messages.isEmpty, let cachedHistory = phoneStore?.cachedTranscript(for: summary.id) {
                applyTranscript(cachedHistory)
            }

            if let parentSessionID = summary.parentSessionID,
               let currentSessionID {
                registerContinuation(
                    parentSessionID: parentSessionID,
                    currentSessionID: currentSessionID,
                    title: summary.title,
                    message: "Resumed the latest compacted continuation for this conversation."
                )
            }

            sessionStatus = "Chat resumed"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func queueResumeSession(_ summary: SessionSummary) {
        pendingResumeSession = summary
        pendingResumeTitle = summary.resolvedTitle
        pendingResumeRequestID = UUID()
        clearConversationState(keepDiagnostics: true)
        isResumingSession = true
        sessionStatus = "Preparing to resume \(summary.resolvedTitle)..."
    }

    func queueResumeSessionReplacingActiveConversation(_ summary: SessionSummary) async {
        guard !(hasConversationContent && isActiveConversation(summary)) else {
            pendingResumeSession = nil
            pendingResumeTitle = nil
            pendingResumeRequestID = nil
            isResumingSession = false
            return
        }

        await closeActiveConversationIfNeeded()
        queueResumeSession(summary)
    }

    func performPendingResumeIfNeeded() async {
        guard let summary = pendingResumeSession else { return }
        await continueSession(summary)
    }

    func sendCurrentDraft() async {
        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        guard !isResumingSession else { return }

        draftMessage = ""
        if message == "/stop" {
            await interrupt()
            return
        }

        sessionStatus = currentSessionID == nil ? "Preparing chat session..." : "Sending prompt..."
        isPerformingRequest = true
        defer { isPerformingRequest = false }

        await ensureCurrentChatSession()
        guard let session = gatewaySession,
              let currentSessionID else { return }
        messages.append(HermesChatMessage(role: .user, text: message))
        sessionStatus = "Sending prompt..."

        do {
            if message.hasPrefix("/") {
                try await submitSlashCommand(message, session: session, sessionID: currentSessionID)
            } else {
                _ = try await session.request(
                    method: "prompt.submit",
                    params: [
                        "session_id": .string(currentSessionID),
                        "text": .string(message)
                    ],
                    timeout: 120
                )
            }
        } catch {
            present(error)
        }
    }

    func runChatTest() async -> String {
        if draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftMessage = "Hello Hermes, this is the HermesPhone native chat test."
        }
        await sendCurrentDraft()
        return lastError ?? "Chat test sent. Follow the live response below."
    }

    func loadSlashCommandCatalogIfNeeded(force: Bool = false) async {
        if isLoadingSlashCommandCatalog { return }
        if !force && !slashCommandCatalog.isEmpty { return }

        isLoadingSlashCommandCatalog = true
        slashCommandCatalogError = nil
        defer { isLoadingSlashCommandCatalog = false }

        let requestedFingerprint = phoneStore?.activeWorkspaceScopeFingerprint
        await ensureGatewaySession()
        guard phoneStore?.activeWorkspaceScopeFingerprint == requestedFingerprint else { return }
        guard let session = gatewaySession else { return }

        var params: [String: JSONValue] = [:]
        if let currentSessionID {
            params["session_id"] = .string(currentSessionID)
        }

        do {
            let result = try await session.request(
                method: "commands.catalog",
                params: params,
                timeout: 30
            )
            guard phoneStore?.activeWorkspaceScopeFingerprint == requestedFingerprint else { return }
            slashCommandCatalog = HermesSlashCommandCatalogParser.parse(result)
            if slashCommandCatalog.isEmpty {
                appendDiagnostic("commands.catalog returned no usable command entries; using curated mobile shortcuts.")
            }
        } catch {
            slashCommandCatalogError = error.localizedDescription
            appendDiagnostic("commands.catalog failed: \(error.localizedDescription)")
        }
    }

    func interrupt() async {
        await ensureGatewaySession()
        guard let session = gatewaySession, let currentSessionID else { return }
        do {
            sessionStatus = "Interrupting..."
            _ = try await session.request(
                method: "session.interrupt",
                params: ["session_id": .string(currentSessionID)],
                timeout: 20
            )
            sessionStatus = "Interrupt requested"
        } catch {
            present(error)
        }
    }

    func closeChat(clearsConversation: Bool = true, disconnectsGateway: Bool = true) async {
        if let session = gatewaySession, let currentSessionID {
            do {
                _ = try await session.request(
                    method: "session.close",
                    params: ["session_id": .string(currentSessionID)],
                    timeout: 20
                )
            } catch {
                appendDiagnostic("session.close failed: \(error.localizedDescription)")
            }
        }

        if disconnectsGateway {
            await disconnectFromGateway(resetMessages: false)
        }

        if clearsConversation {
            clearConversationState(keepDiagnostics: true)
        } else {
            currentSessionID = nil
            currentAssistantMessageID = nil
        }
        pendingResumeSession = nil
        pendingResumeTitle = nil
        pendingResumeRequestID = nil
        isResumingSession = false
        sessionStatus = "Chat closed"
    }

    func openTerminal() {
        phoneStore?.ensureTerminalConnected()
    }

    func refreshCurrentConversationFromRemote() async {
        guard let currentSessionID, hasConversationContent else { return }
        guard !isResumingSession else { return }
        await ensureGatewaySession()
        guard let session = gatewaySession else { return }

        do {
            let history = try await session.request(
                method: "session.history",
                params: [
                    "session_id": .string(currentSessionID),
                    "id": .string(currentSessionID)
                ],
                timeout: 60
            )
            applyHistoryResult(history)
            sessionStatus = "Chat resumed"
        } catch {
            appendDiagnostic("Conversation refresh failed for \(currentSessionID): \(error.localizedDescription)")
        }
    }

    func continueSessionByIDInChat(_ sessionID: String) async {
        let summary = SessionSummary(
            id: sessionID,
            title: "Compacted session",
            model: nil,
            parentSessionID: nil,
            startedAt: nil,
            lastActive: nil,
            messageCount: nil,
            preview: nil
        )
        await continueSession(summary)
    }

    func respondToPrompt(
        _ card: HermesChatPromptCard,
        approved: Bool? = nil,
        responseText: String? = nil
    ) async {
        guard let session = gatewaySession else { return }

        let method: String
        var params: [String: JSONValue] = [
            "request_id": .string(card.requestID)
        ]
        if let sessionID = card.sessionID ?? currentSessionID {
            params["session_id"] = .string(sessionID)
        }

        switch card.kind {
        case .approval:
            method = "approval.respond"
            let allowed = approved ?? false
            params["choice"] = .string(allowed ? "approve" : "deny")
        case .clarify:
            method = "clarify.respond"
            let value = responseText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            params["answer"] = .string(value)
        case .sudo:
            method = "sudo.respond"
            let value = responseText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            params["password"] = .string(value)
        case .secret:
            method = "secret.respond"
            let value = responseText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            params["value"] = .string(value)
        }

        do {
            _ = try await session.request(method: method, params: params, timeout: 45)
            promptCards.removeAll { $0.id == card.id }
            sessionStatus = "Reply sent"
        } catch {
            present(error)
        }
    }

    private func ensureGatewaySession(forceBootstrapRefresh: Bool = false) async {
        await syncWithActiveConnection()

        if isConnecting {
            connectionStatus = "Waiting for Hermes TUI Gateway..."
            await waitForGatewayConnection()
            return
        }

        let shouldRefreshBootstrap = forceBootstrapRefresh || bootstrapStatus?.canUseNativeChat == false
        await refreshBootstrapStatus(force: shouldRefreshBootstrap)

        guard canUseNativeChat else {
            connectionStatus = "Native chat unavailable"
            return
        }
        guard gatewaySession == nil else { return }
        guard let connection = phoneStore?.activeConnection else { return }

        isConnecting = true
        defer { isConnecting = false }

        connectionStatus = "Connecting to Hermes TUI Gateway..."
        let session = HermesGatewaySSHSession(connection: connection, sshTransport: sshTransport)
        gatewaySession = session
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in session.events {
                await self.apply(event)
            }
        }

        do {
            try await session.start()
            connectionStatus = "Gateway connected"
            appendDiagnostic("TUI gateway started successfully.")
        } catch {
            present(error)
            await disconnectFromGateway(resetMessages: false)
        }
    }

    private func submitSlashCommand(
        _ command: String,
        session: HermesGatewaySSHSession,
        sessionID: String
    ) async throws {
        let params = slashCommandParams(command, sessionID: sessionID)

        if slashCommandParts(command).name == "commands" {
            let result = try await session.request(method: "commands.catalog", params: ["session_id": .string(sessionID)], timeout: 30)
            appendSystemNotice(commandCatalogSummary(result))
            return
        }

        do {
            let result = try await session.request(method: "slash.exec", params: params, timeout: 120)
            _ = try await handleCommandResult(result, originalCommand: command, session: session, sessionID: sessionID)
            return
        } catch let error as HermesGatewayError {
            guard shouldFallbackToCommandDispatch(error) else { throw error }
        }

        let result = try await session.request(method: "command.dispatch", params: params, timeout: 120)
        _ = try await handleCommandResult(result, originalCommand: command, session: session, sessionID: sessionID)
    }

    @discardableResult
    private func handleCommandResult(
        _ result: JSONValue?,
        originalCommand: String,
        session: HermesGatewaySSHSession,
        sessionID: String,
        aliasDepth: Int = 0
    ) async throws -> Bool {
        let commandResult = HermesGatewayCommandResult(result)
        if let notice = commandResult.notice {
            appendSystemNotice(notice)
        }

        switch commandResult.primaryAction {
        case .submit(let message):
            _ = try await session.request(
                method: "prompt.submit",
                params: [
                    "session_id": .string(sessionID),
                    "text": .string(message)
                ],
                timeout: 120
            )
            return true
        case .render(let output):
            if isBareSlashCommand(originalCommand, named: "model"), output == "(no output)" {
                let result = try await session.request(method: "model.options", params: ["session_id": .string(sessionID)], timeout: 30)
                appendSystemNotice(modelOptionsSummary(result))
            } else {
                appendSystemNotice(output)
            }
            return true
        case .alias(let target):
            guard aliasDepth < 3 else {
                appendSystemNotice("Alias chain is too deep for \(originalCommand).")
                return true
            }
            let result = try await session.request(
                method: "command.dispatch",
                params: slashCommandParams(target, sessionID: sessionID),
                timeout: 120
            )
            return try await handleCommandResult(
                result,
                originalCommand: originalCommand,
                session: session,
                sessionID: sessionID,
                aliasDepth: aliasDepth + 1
            )
        case .handled:
            return true
        case .none:
            return false
        }
    }

    private func slashCommandParams(_ command: String, sessionID: String) -> [String: JSONValue] {
        let parts = slashCommandParts(command)
        return [
            "session_id": .string(sessionID),
            "line": .string(command),
            "text": .string(command),
            "command": .string(command),
            "input": .string(command),
            "name": .string(parts.name),
            "arg": .string(parts.arg)
        ]
    }

    private func slashCommandParts(_ command: String) -> (name: String, arg: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutSlash = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        let pieces = withoutSlash.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let name = pieces.first.map { String($0).lowercased() } ?? ""
        let arg = pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return (name, arg)
    }

    private func isBareSlashCommand(_ command: String, named name: String) -> Bool {
        let parts = slashCommandParts(command)
        return parts.name == name && parts.arg.isEmpty
    }

    private func shouldFallbackToCommandDispatch(_ error: HermesGatewayError) -> Bool {
        guard case .remote(_, let message) = error else { return false }
        let lowered = message.lowercased()
        if lowered.contains("not a quick/plugin/skill command") { return false }
        return lowered.contains("command.dispatch") ||
            lowered.contains("pending input") ||
            lowered.contains("skill command") ||
            (lowered.contains("dispatch") && lowered.contains("skill"))
    }

    private func modelOptionsSummary(_ result: JSONValue?) -> String {
        guard let object = result?.objectValue else {
            return "No model options available."
        }

        let model = string(in: object, keys: ["model", "current_model"]) ?? "Unknown"
        let provider = string(in: object, keys: ["provider", "current_provider"])
        var lines = ["Current model: \(model)\(provider.map { " (\($0))" } ?? "")"]

        let providers = object["providers"]?.arrayValue?.compactMap(\.objectValue) ?? []
        if let currentProvider = providers.first(where: { $0["is_current"]?.boolValue == true }) {
            let providerName = string(in: currentProvider, keys: ["name", "slug"]) ?? provider ?? "Current provider"
            let models = currentProvider["models"]?.arrayValue?.compactMap(\.stringValue) ?? []
            if !models.isEmpty {
                lines.append("")
                lines.append("\(providerName) models:")
                lines.append(contentsOf: models.prefix(8).map { $0 == model ? "• \($0) ✓" : "• \($0)" })
                if models.count > 8 {
                    lines.append("• … \(models.count - 8) more")
                }
            }
        }

        let configuredProviders = providers.filter { $0["authenticated"]?.boolValue == true }
        if !configuredProviders.isEmpty {
            lines.append("")
            lines.append("Configured providers:")
            lines.append(contentsOf: configuredProviders.prefix(8).compactMap { provider in
                let slug = string(in: provider, keys: ["slug"])
                let name = string(in: provider, keys: ["name"]) ?? slug
                guard let name else { return nil }
                let currentMarker = provider["is_current"]?.boolValue == true ? " ✓" : ""
                return "• \(name)\(currentMarker)"
            })
            if configuredProviders.count > 8 {
                lines.append("• … \(configuredProviders.count - 8) more")
            }
        }

        lines.append("")
        lines.append("To switch: /model <model> --provider <provider>")
        return lines.joined(separator: "\n")
    }

    private func commandCatalogSummary(_ result: JSONValue?) -> String {
        guard let object = result?.objectValue else {
            return "No command catalog available."
        }

        if let categories = object["categories"]?.arrayValue?.compactMap(\.objectValue), !categories.isEmpty {
            var lines = ["Available commands"]
            for category in categories.prefix(8) {
                guard let name = string(in: category, keys: ["name"]) else { continue }
                let pairs = category["pairs"]?.arrayValue?.compactMap(\.arrayValue) ?? []
                let commands = pairs.prefix(12).compactMap { $0.first?.stringValue }
                guard !commands.isEmpty else { continue }
                lines.append("")
                lines.append(name)
                lines.append(commands.joined(separator: "  "))
            }
            if let skillCount = object["skill_count"]?.stringValue, skillCount != "0" {
                lines.append("")
                lines.append("Skill commands: \(skillCount) installed. Search the Skills section to insert one.")
            }
            return lines.joined(separator: "\n")
        }

        let pairs = object["pairs"]?.arrayValue?.compactMap(\.arrayValue) ?? []
        let commands = pairs.prefix(80).compactMap { pair -> String? in
            guard let command = pair.first?.stringValue else { return nil }
            let description = pair.count > 1 ? pair[1].stringValue : nil
            return description.map { "\(command) — \($0)" } ?? command
        }
        return commands.isEmpty ? "No commands available." : commands.joined(separator: "\n")
    }

    private func string(in object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return HermesGatewayTextSanitizer.sanitize(value)
            }
        }
        return nil
    }

    private func waitForBootstrapProbe() async {
        while isCheckingBootstrap {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func waitForGatewayConnection() async {
        while isConnecting {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func waitForSessionCreation() async {
        while isCreatingSession {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func disconnectFromGateway(resetMessages: Bool) async {
        eventTask?.cancel()
        eventTask = nil

        if let gatewaySession {
            await gatewaySession.close()
        }
        gatewaySession = nil

        if resetMessages {
            clearConversationState(keepDiagnostics: false)
        }

        connectionStatus = "Idle"
    }

    private func closeActiveConversationIfNeeded() async {
        guard hasConversationContent else { return }
        isResumingSession = true
        sessionStatus = "Closing background chat..."
        await closeChat()
    }

    private func clearConversationState(keepDiagnostics: Bool) {
        conversationGeneration += 1
        currentSessionID = nil
        currentAssistantMessageID = nil
        messages = []
        toolCards = []
        promptCards = []
        compactionNotice = nil
        continuation = nil
        rawEvents = []
        lastError = nil
        if !keepDiagnostics {
            diagnostics = []
        }
    }

    private func apply(_ event: HermesGatewayEvent) async {
        rawEvents.append(event)
        if rawEvents.count > 120 {
            rawEvents.removeFirst(rawEvents.count - 120)
        }

        switch event.type {
        case "gateway.ready":
            connectionStatus = "Gateway ready"
            if let skin = value(in: event.payload, keys: ["skin", "name"]) {
                gatewayInfo["Skin"] = skin
            }
        case "session.info":
            if let sessionID = event.sessionID ?? value(in: event.payload, keys: ["session_id", "id"]) {
                currentSessionID = sessionID
            }
            if let model = value(in: event.payload, keys: ["model"]) {
                gatewayInfo["Model"] = model
            }
            if let version = value(in: event.payload, keys: ["version", "gateway_version"]) {
                gatewayInfo["Gateway"] = version
            }
        case "message.start":
            startAssistantMessage(with: event.payload)
        case "message.delta":
            appendAssistantDelta(from: event.payload)
        case "message.complete":
            completeAssistantMessage(from: event.payload)
        case "tool.start":
            updateToolCard(for: event.payload, defaultRunning: true)
        case "tool.progress":
            updateToolCard(for: event.payload, defaultRunning: true)
        case "tool.complete":
            updateToolCard(for: event.payload, defaultRunning: false)
        case "approval.request":
            upsertPromptCard(kind: .approval, payload: event.payload, fallbackSessionID: event.sessionID)
        case "clarify.request":
            upsertPromptCard(kind: .clarify, payload: event.payload, fallbackSessionID: event.sessionID)
        case "sudo.request":
            upsertPromptCard(kind: .sudo, payload: event.payload, fallbackSessionID: event.sessionID)
        case "secret.request":
            upsertPromptCard(kind: .secret, payload: event.payload, fallbackSessionID: event.sessionID)
        case "status.update":
            sessionStatus = value(in: event.payload, keys: ["text", "status", "message"]) ?? sessionStatus
        case "session.compacted", "context.compacted", "compaction.complete":
            await applyCompactionNotice(from: event)
        case "error":
            let message = value(in: event.payload, keys: ["message", "error"]) ?? "Unknown gateway error"
            lastError = message
            messages.append(HermesChatMessage(role: .error, text: message))
        case "gateway.stderr":
            if let line = value(in: event.payload, keys: ["text"]) {
                appendDiagnostic(line)
            }
        case "gateway.closed":
            connectionStatus = "Gateway closed"
        default:
            if isCompactionEvent(event) {
                await applyCompactionNotice(from: event)
            }
        }
    }

    private func isCompactionEvent(_ event: HermesGatewayEvent) -> Bool {
        event.type.localizedCaseInsensitiveContains("compact") ||
            (value(in: event.payload, keys: ["status", "message", "text"])?
                .localizedCaseInsensitiveContains("compact") == true)
    }

    private func applyCompactionNotice(from event: HermesGatewayEvent) async {
        let oldSessionID = value(in: event.payload, keys: ["old_session_id", "parent_session_id"]) ?? currentSessionID
        let newSessionID = value(in: event.payload, keys: ["new_session_id", "child_session_id", "continuation_session_id", "session_id", "id"])
        let message = value(in: event.payload, keys: ["message", "text", "summary"]) ??
            "This session was compacted and will continue in a new session."
        let title = value(in: event.payload, keys: ["title", "session_title", "name"])
        let isCurrentSession = newSessionID != nil && newSessionID != oldSessionID

        compactionNotice = CompactionNotice(
            message: message,
            oldSessionID: oldSessionID,
            newSessionID: newSessionID == oldSessionID ? nil : newSessionID,
            isCurrentSession: isCurrentSession
        )

        if let oldSessionID,
           let newSessionID,
           newSessionID != oldSessionID {
            currentSessionID = newSessionID
            registerContinuation(
                parentSessionID: oldSessionID,
                currentSessionID: newSessionID,
                title: title,
                message: message
            )
            sessionStatus = "Continuing compacted session"
        } else {
            sessionStatus = "Session compacted"
        }

        appendSystemNotice(message)
        if isCurrentSession {
            HermesPhoneNotificationService.shared.notifyContinuation(
                sessionID: newSessionID,
                workspaceFingerprint: phoneStore?.activeWorkspaceScopeFingerprint,
                message: message
            )
        }
        await phoneStore?.loadSessions()
    }

    private func registerContinuation(
        parentSessionID: String,
        currentSessionID: String,
        title: String?,
        message: String
    ) {
        continuation = HermesChatContinuation(
            parentSessionID: parentSessionID,
            currentSessionID: currentSessionID,
            title: title,
            message: message
        )
    }

    private func appendSystemNotice(_ message: String) {
        let sanitizedMessage = HermesGatewayTextSanitizer.sanitize(message).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedMessage.isEmpty else { return }
        guard messages.last?.role != .system || messages.last?.text != sanitizedMessage else {
            return
        }
        messages.append(HermesChatMessage(role: .system, text: sanitizedMessage))
    }

    private func applyTranscript(_ transcript: [SessionMessage]) {
        let restored = transcript.compactMap { message -> HermesChatMessage? in
            guard let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                return nil
            }

            let role: HermesChatMessageRole
            switch message.role {
            case .user:
                role = .user
            case .assistant:
                role = .assistant
            case .system:
                role = .system
            case .event, .custom:
                return nil
            }

            return HermesChatMessage(
                role: role,
                text: content,
                timestamp: message.timestamp?.dateValue ?? Date()
            )
        }

        if !restored.isEmpty {
            messages = restored
        }
    }


    private func startAssistantMessage(with payload: [String: JSONValue]) {
        let initialText = value(in: payload, keys: ["text", "delta", "content"]) ?? ""
        let messageID = UUID()
        currentAssistantMessageID = messageID
        messages.append(
            HermesChatMessage(
                id: messageID,
                role: .assistant,
                text: initialText,
                isStreaming: true
            )
        )
        sessionStatus = "Hermes is responding..."
    }

    private func appendAssistantDelta(from payload: [String: JSONValue]) {
        let delta = value(in: payload, keys: ["text", "delta", "content"]) ?? ""
        guard !delta.isEmpty else { return }

        if currentAssistantMessageID == nil {
            startAssistantMessage(with: payload)
            return
        }

        guard let messageID = currentAssistantMessageID,
              let index = messages.lastIndex(where: { $0.id == messageID }) else {
            return
        }

        messages[index].text.append(delta)
        messages[index].isStreaming = true
    }

    private func completeAssistantMessage(from payload: [String: JSONValue]) {
        if currentAssistantMessageID == nil {
            startAssistantMessage(with: payload)
        }

        var completedMessage: HermesChatMessage?
        if let messageID = currentAssistantMessageID,
           let index = messages.lastIndex(where: { $0.id == messageID }) {
            let trailingText = value(in: payload, keys: ["text", "content"])
            if let trailingText, messages[index].text.isEmpty {
                messages[index].text = trailingText
            }
            messages[index].isStreaming = false
            completedMessage = messages[index]
        }

        if let completedMessage {
            HermesPhoneNotificationService.shared.notifyAssistantReply(
                messageID: completedMessage.id,
                sessionID: currentSessionID,
                workspaceFingerprint: phoneStore?.activeWorkspaceScopeFingerprint,
                text: completedMessage.text
            )
        }

        currentAssistantMessageID = nil
        sessionStatus = "Response completed"
    }

    private func normalizedChatToolPayload(_ payload: [String: JSONValue]) -> [String: JSONValue] {
        var normalized = payload
        if let function = payload["function"]?.objectValue {
            if normalized["name"] == nil, let name = function["name"] {
                normalized["name"] = name
            }
            if normalized["arguments"] == nil, let arguments = function["arguments"] {
                normalized["arguments"] = arguments
            }
        }
        if normalized["type"] == nil {
            normalized["type"] = .string("function_call")
        }
        if normalized["status"] == nil {
            normalized["status"] = .string("Running")
        }
        return normalized
    }

    private func updateToolCard(for payload: [String: JSONValue], defaultRunning: Bool) {
        let toolID = value(in: payload, keys: ["tool_call_id", "call_id", "item_id", "id", "tool_id", "name"]) ?? UUID().uuidString
        let incomingTitle = value(in: payload, keys: ["title", "name", "tool", "type"])
        let title = incomingTitle ?? toolCards.first(where: { $0.id == toolID })?.title ?? fallbackToolTitle(from: payload)
        let status = value(in: payload, keys: ["status", "message", "state"]) ?? (defaultRunning ? "Running" : "Complete")
        let detail = value(in: payload, keys: ["detail", "summary", "output"])
        let isRunning = payload["running"]?.boolValue ?? defaultRunning
        let preview = HermesGatewayPreviewBuilder.preview(from: payload)
        let updatedAt = Date()

        if let index = toolCards.firstIndex(where: { $0.id == toolID }) {
            toolCards[index].title = title
            toolCards[index].status = status
            toolCards[index].detail = detail
            toolCards[index].toolType = preview.toolType
            toolCards[index].actionPreview = preview.commandPreview ?? preview.actionSummary
            toolCards[index].expandedDetail = preview.commandPreview ?? detail ?? preview.payloadPreview
            toolCards[index].isRunning = isRunning
            toolCards[index].updatedAt = updatedAt
        } else {
            toolCards.append(
                HermesChatToolCard(
                    id: toolID,
                    title: title,
                    status: status,
                    detail: detail,
                    toolType: preview.toolType,
                    actionPreview: preview.commandPreview ?? preview.actionSummary,
                    expandedDetail: preview.commandPreview ?? detail ?? preview.payloadPreview,
                    isRunning: isRunning,
                    updatedAt: updatedAt
                )
            )
        }

        if toolCards.count > 12 {
            toolCards.removeFirst(toolCards.count - 12)
        }
    }

    private func fallbackToolTitle(from payload: [String: JSONValue]) -> String {
        let type = value(in: payload, keys: ["type"])
        if type == "function_call_output" {
            return "Tool output"
        }
        return "Tool activity"
    }

    private func upsertPromptCard(
        kind: HermesChatPromptKind,
        payload: [String: JSONValue],
        fallbackSessionID: String?
    ) {
        let requestID = value(in: payload, keys: ["request_id", "id", "approval_id"]) ?? UUID().uuidString
        let title = value(in: payload, keys: ["title", "prompt", "kind"]) ?? kind.rawValue.capitalized
        let message = value(in: payload, keys: ["message", "text", "body"]) ?? ""
        let sessionID = value(in: payload, keys: ["session_id"]) ?? fallbackSessionID
        let choices = payload["choices"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let placeholder = value(in: payload, keys: ["placeholder", "hint"])
        let preview = HermesGatewayPreviewBuilder.preview(
            from: payload,
            redactsSensitiveContent: kind == .sudo || kind == .secret
        )

        let card = HermesChatPromptCard(
            id: "\(kind.rawValue)-\(requestID)",
            sessionID: sessionID,
            requestID: requestID,
            kind: kind,
            title: title,
            message: message,
            choices: choices,
            placeholder: placeholder,
            toolType: preview.toolType,
            actionSummary: preview.actionSummary,
            commandPreview: preview.commandPreview,
            payloadPreview: preview.payloadPreview
        )

        if let index = promptCards.firstIndex(where: { $0.id == card.id }) {
            promptCards[index] = card
        } else {
            promptCards.append(card)
            HermesPhoneNotificationService.shared.notifyPendingRequest(
                requestID: requestID,
                kindTitle: notificationTitle(for: card),
                sessionID: sessionID,
                workspaceFingerprint: phoneStore?.activeWorkspaceScopeFingerprint
            )
        }
    }

    private func notificationTitle(for card: HermesChatPromptCard) -> String {
        switch card.kind {
        case .approval:
            return "Approval requested"
        case .clarify:
            return "Clarification requested"
        case .sudo:
            return "Sudo password requested"
        case .secret:
            return "Secret requested"
        }
    }

    private func applySessionResult(_ result: JSONValue?, preferredSessionID: String?) {
        guard let object = result?.objectValue else {
            if let preferredSessionID {
                currentSessionID = preferredSessionID
            }
            return
        }

        let previousSessionID = currentSessionID
        let resolvedSessionID = value(in: object, keys: ["session_id", "id"]) ?? preferredSessionID ?? currentSessionID
        currentSessionID = resolvedSessionID

        if let parentSessionID = value(in: object, keys: ["parent_session_id", "parent_id"]),
           let resolvedSessionID,
           resolvedSessionID != parentSessionID {
            registerContinuation(
                parentSessionID: parentSessionID,
                currentSessionID: resolvedSessionID,
                title: value(in: object, keys: ["title", "name"]),
                message: "Continuing compacted conversation."
            )
        } else if let previousSessionID,
                  let resolvedSessionID,
                  previousSessionID != resolvedSessionID,
                  continuation?.currentSessionID == previousSessionID {
            continuation?.currentSessionID = resolvedSessionID
        }

        if let messagesValue = object["messages"] ?? object["history"] {
            applyHistoryResult(messagesValue)
        }

        if let model = value(in: object, keys: ["model"]) {
            gatewayInfo["Model"] = model
        }
    }

    private func applyHistoryResult(_ result: JSONValue?) {
        guard let items = result?.arrayValue else {
            if let object = result?.objectValue,
               let nestedItems = object["messages"]?.arrayValue ?? object["items"]?.arrayValue {
                applyHistoryArray(nestedItems)
            }
            return
        }

        applyHistoryArray(items)
    }

    private func applyHistoryArray(_ items: [JSONValue]) {
        let restored = items.compactMap { item -> HermesChatMessage? in
            guard let object = item.objectValue else { return nil }
            let roleText = value(in: object, keys: ["role"]) ?? "system"
            let content = value(in: object, keys: ["content", "text", "message"]) ?? ""
            guard !content.isEmpty else { return nil }

            let role: HermesChatMessageRole
            switch roleText.lowercased() {
            case "user":
                role = .user
            case "assistant":
                role = .assistant
            case "error":
                role = .error
            default:
                role = .system
            }

            return HermesChatMessage(role: role, text: content)
        }

        if !restored.isEmpty {
            messages = restored
        }
    }

    private func appendDiagnostic(_ line: String) {
        let sanitizedLine = HermesGatewayTextSanitizer.sanitize(line)
        guard !sanitizedLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        diagnostics.append(sanitizedLine)
        if diagnostics.count > 200 {
            diagnostics.removeFirst(diagnostics.count - 200)
        }
    }

    private func present(_ error: Error) {
        let message = HermesGatewayTextSanitizer.sanitize(error.localizedDescription)
        lastError = message
        sessionStatus = message
        connectionStatus = "Chat error"
        appendDiagnostic(message)
    }

    private func value(in payload: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return HermesGatewayTextSanitizer.sanitize(value)
            }
        }
        return nil
    }

    private func compactPreview(_ value: String) -> String {
        let compact = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard compact.count > 160 else { return compact }
        return String(compact.prefix(157)) + "..."
    }
}

struct NativeChatScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @ObservedObject var chatStore: HermesNativeChatStore
    @StateObject private var keyboard = KeyboardObserver()
    @State private var dismissedLatestToolActivityID: String?
    @State private var isToolTickerExpanded = false
    @State private var isAwayFromBottom = false
    @State private var scrollMetrics = NativeChatScrollMetrics()
    @State private var bottomControlsHeight: CGFloat = 0
    private let bottomAnchorID = "native-chat-bottom-anchor"
    private let bottomDistanceThreshold: CGFloat = 72
    private let scrollToBottomButtonSize: CGFloat = 38
    private let scrollToBottomButtonGap: CGFloat = 112

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                NativeChatContentView(
                    chatStore: chatStore,
                    connection: store.activeConnection,
                    bottomAnchorID: bottomAnchorID
                )
                .background(
                    NativeChatScrollMetricsObserver { metrics in
                        scrollMetrics = metrics
                        updateBottomVisibility(using: metrics)
                    }
                )
            }
            .background(Color(.systemGroupedBackground))
            .onPreferenceChange(ChatBottomControlsHeightPreferenceKey.self) { height in
                let wasPinnedToBottom = !isAwayFromBottom
                bottomControlsHeight = height
                updateBottomVisibility()
                if wasPinnedToBottom {
                    scrollToBottom(using: proxy)
                }
            }
            .onChange(of: chatContentRevision) { _, _ in
                scrollToBottomAfterContentChange(using: proxy)
            }
            .onChange(of: chatStore.currentSessionID) { _, newSessionID in
                HermesPhoneNotificationService.shared.updateVisibleConversationSession(newSessionID)
                dismissedLatestToolActivityID = nil
                isToolTickerExpanded = false
                scrollToBottom(using: proxy, animated: false)
            }
            .onChange(of: keyboard.bottomInset) { _, newInset in
                if newInset > 0 || !isAwayFromBottom {
                    scrollToBottom(using: proxy)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NativeChatBottomControls(
                    chatStore: chatStore,
                    visibleToolCard: visibleToolCard,
                    isToolTickerExpanded: $isToolTickerExpanded,
                    skills: store.skills,
                    isLoadingSkills: store.isLoadingSkills,
                    loadSkills: { await store.loadSkills() },
                    onDismissToolTicker: dismissToolTicker
                )
                .animation(.easeOut(duration: 0.24), value: keyboard.bottomInset)
            }
            .overlay(alignment: .bottomTrailing) {
                scrollToBottomButton(using: proxy)
                    .padding(.trailing, 18)
                    .padding(.bottom, bottomControlsHeight + scrollToBottomButtonGap)
            }
            .task(id: toolTickerAutoDismissKey) {
                await autoDismissVisibleToolTickerIfNeeded()
            }
        }
        .navigationTitle(chatStore.isResumingSession ? "Continuing" : (chatStore.currentSessionID == nil ? "New Chat" : "Conversation"))
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: visibleToolActivityID)
        .onAppear {
            HermesPhoneNotificationService.shared.setConversationVisible(true, sessionID: chatStore.currentSessionID)
        }
        .onDisappear {
            HermesPhoneNotificationService.shared.setConversationVisible(false, sessionID: nil)
        }
        .onChange(of: latestToolActivityID) { _, newValue in
            if newValue.isEmpty {
                dismissedLatestToolActivityID = nil
                isToolTickerExpanded = false
            }
        }
        .toolbar {
            if keyboard.isVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismissKeyboard()
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New Chat", systemImage: "square.and.pencil") {
                        Task { await chatStore.prepareNewChatReplacingActiveConversation() }
                    }
                    Button("Open Terminal", systemImage: "terminal") {
                        chatStore.openTerminal()
                    }
                    Button(chatStore.showDiagnostics ? "Hide Diagnostics" : "Show Diagnostics", systemImage: "waveform.path.ecg") {
                        chatStore.showDiagnostics.toggle()
                    }
                    Button("Close Chat", systemImage: "xmark.circle") {
                        Task { await chatStore.closeChat() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: store.activeWorkspaceScopeFingerprint) {
            await chatStore.syncWithActiveConnection()
            await chatStore.refreshBootstrapStatus()
        }
        .task(id: chatStore.pendingResumeRequestID) {
            await chatStore.performPendingResumeIfNeeded()
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if isAwayFromBottom {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isAwayFromBottom = false
                }
            }

            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func scrollToBottomAfterContentChange(using proxy: ScrollViewProxy) {
        guard chatStore.hasConversationContent else {
            updateBottomVisibility()
            return
        }

        if !isAwayFromBottom || chatStore.messages.last?.role == .user {
            scrollToBottom(using: proxy)
        }
    }

    private func updateBottomVisibility(using metrics: NativeChatScrollMetrics? = nil) {
        let currentMetrics = metrics ?? scrollMetrics
        guard chatStore.hasConversationContent, currentMetrics.viewportHeight > 0 else {
            setAwayFromBottom(false)
            return
        }

        setAwayFromBottom(currentMetrics.distanceToBottom > bottomDistanceThreshold)
    }

    private func setAwayFromBottom(_ shouldShow: Bool) {
        guard isAwayFromBottom != shouldShow else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            isAwayFromBottom = shouldShow
        }
    }

    private var showsScrollToBottomButton: Bool {
        chatStore.canUseNativeChat && chatStore.hasConversationContent && isAwayFromBottom
    }

    @ViewBuilder
    private func scrollToBottomButton(using proxy: ScrollViewProxy) -> some View {
        if showsScrollToBottomButton {
            Button {
                scrollToBottom(using: proxy)
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: scrollToBottomButtonSize, height: scrollToBottomButtonSize)
                    .background(.regularMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 5)
            .accessibilityLabel("Scroll to bottom")
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .zIndex(1)
        }
    }

    private var chatContentRevision: String {
        let latestMessageToken = chatStore.messages.last.map {
            "\($0.id.uuidString):\($0.role.rawValue):\($0.text.count):\($0.isStreaming)"
        } ?? "none"
        let promptToken = chatStore.promptCards.map(\.id).joined(separator: ",")
        let noticeToken = chatStore.compactionNotice?.id.uuidString ?? "none"
        let diagnosticsToken = chatStore.showDiagnostics ? "\(chatStore.diagnostics.count)" : "hidden"
        return [
            "\(chatStore.messages.count)",
            latestMessageToken,
            promptToken,
            noticeToken,
            diagnosticsToken,
            "\(chatStore.isResumingSession)"
        ].joined(separator: "|")
    }

    private var visibleToolCard: HermesChatToolCard? {
        guard let latestToolCard = chatStore.latestToolCard else { return nil }
        let token = "\(latestToolCard.id)-\(latestToolCard.updatedAt.timeIntervalSinceReferenceDate)"
        guard dismissedLatestToolActivityID != token else { return nil }
        return latestToolCard
    }

    private var latestToolActivityID: String {
        guard let latestToolCard = chatStore.latestToolCard else { return "" }
        return "\(latestToolCard.id)-\(latestToolCard.updatedAt.timeIntervalSinceReferenceDate)"
    }

    private var visibleToolActivityID: String {
        guard let visibleToolCard else { return "" }
        return "\(visibleToolCard.id)-\(visibleToolCard.updatedAt.timeIntervalSinceReferenceDate)"
    }

    private var toolTickerAutoDismissKey: String {
        "\(visibleToolActivityID)-prompts-\(chatStore.promptCards.count)"
    }

    private func dismissToolTicker(_ card: HermesChatToolCard) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
            dismissedLatestToolActivityID = "\(card.id)-\(card.updatedAt.timeIntervalSinceReferenceDate)"
            isToolTickerExpanded = false
        }
    }

    private func autoDismissVisibleToolTickerIfNeeded() async {
        guard let card = visibleToolCard, chatStore.promptCards.isEmpty else { return }
        let token = "\(card.id)-\(card.updatedAt.timeIntervalSinceReferenceDate)"
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled,
              chatStore.promptCards.isEmpty,
              visibleToolActivityID == token else { return }
        dismissToolTicker(card)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct NativeChatContentView: View {
    @ObservedObject var chatStore: HermesNativeChatStore
    let connection: ConnectionProfile?
    let bottomAnchorID: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ChatStatusHeader(chatStore: chatStore, connection: connection)
                chatBody
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)

            bottomAnchor
        }
    }

    @ViewBuilder
    private var chatBody: some View {
        if chatStore.isCheckingBootstrap || chatStore.bootstrapStatus == nil {
            ChatProgressStateView(
                title: "Checking Hermes",
                message: "Verifying SSH, python3, Hermes CLI, and the TUI Gateway on this host."
            )
        } else if !chatStore.canUseNativeChat {
            NativeChatUnavailableView(chatStore: chatStore)
        } else {
            if chatStore.isResumingSession {
                ConversationResumeLoadingView(
                    title: chatStore.pendingResumeTitle,
                    sessionStatus: chatStore.sessionStatus,
                    connectionStatus: chatStore.connectionStatus
                )
            } else if !chatStore.hasConversationContent {
                ConversationEmptyState(chatStore: chatStore, connection: connection)
            }

            NativeChatMessagesView(chatStore: chatStore)
        }
    }

    private var bottomAnchor: some View {
        Color.clear
            .frame(height: 1)
            .id(bottomAnchorID)
    }
}

private struct NativeChatMessagesView: View {
    @ObservedObject var chatStore: HermesNativeChatStore

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(chatStore.messages) { message in
                ChatBubble(message: message)
            }

            if !chatStore.promptCards.isEmpty {
                promptSection
            }

            if let notice = chatStore.compactionNotice {
                CompactionNoticeView(notice: notice, chatStore: chatStore)
            }

            if chatStore.showDiagnostics && !chatStore.diagnostics.isEmpty {
                DiagnosticsCard(lines: chatStore.diagnostics)
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Action Required")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(chatStore.promptCards) { card in
                PromptCardView(card: card, chatStore: chatStore)
            }
        }
    }
}

private struct NativeChatBottomControls: View {
    @ObservedObject var chatStore: HermesNativeChatStore
    let visibleToolCard: HermesChatToolCard?
    @Binding var isToolTickerExpanded: Bool
    let skills: [SkillSummary]
    let isLoadingSkills: Bool
    let loadSkills: () async -> Void
    let onDismissToolTicker: (HermesChatToolCard) -> Void

    var body: some View {
        if chatStore.canUseNativeChat {
            controls
        } else {
            Color.clear
                .frame(height: 0)
                .preference(key: ChatBottomControlsHeightPreferenceKey.self, value: 0)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if let visibleToolCard {
                ToolActivityTickerView(card: visibleToolCard, isExpanded: $isToolTickerExpanded) {
                    onDismissToolTicker(visibleToolCard)
                }
                .id("\(visibleToolCard.id)-\(visibleToolCard.updatedAt.timeIntervalSinceReferenceDate)")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            ChatComposerView(
                chatStore: chatStore,
                skills: skills,
                isLoadingSkills: isLoadingSkills,
                loadSkills: loadSkills
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            GeometryReader { controlsProxy in
                Color.clear.preference(
                    key: ChatBottomControlsHeightPreferenceKey.self,
                    value: controlsProxy.size.height
                )
            }
        )
    }
}

private struct NativeChatScrollMetrics: Equatable, Sendable {
    var offsetY: CGFloat = 0
    var maxOffsetY: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var contentHeight: CGFloat = 0

    var distanceToBottom: CGFloat {
        max(0, maxOffsetY - offsetY)
    }
}

private struct NativeChatScrollMetricsObserver: UIViewRepresentable {
    let onMetricsChange: @MainActor (NativeChatScrollMetrics) -> Void

    func makeUIView(context: Context) -> NativeChatScrollMetricsProbeView {
        let view = NativeChatScrollMetricsProbeView()
        view.onMetricsChange = onMetricsChange
        return view
    }

    func updateUIView(_ uiView: NativeChatScrollMetricsProbeView, context: Context) {
        uiView.onMetricsChange = onMetricsChange
        uiView.scheduleScrollViewResolution()
    }

    static func dismantleUIView(_ uiView: NativeChatScrollMetricsProbeView, coordinator: ()) {
        uiView.detach()
    }
}

private final class NativeChatScrollMetricsProbeView: UIView {
    var onMetricsChange: (@MainActor (NativeChatScrollMetrics) -> Void)?
    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var lastMetrics = NativeChatScrollMetrics()

    override var intrinsicContentSize: CGSize {
        .zero
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        scheduleScrollViewResolution()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleScrollViewResolution()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publishMetrics()
    }

    func scheduleScrollViewResolution() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            attach(to: enclosingScrollView())
        }
    }

    func detach() {
        observations.removeAll()
        scrollView = nil
        onMetricsChange = nil
    }

    private func enclosingScrollView() -> UIScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }

    private func attach(to newScrollView: UIScrollView?) {
        guard scrollView !== newScrollView else {
            publishMetrics()
            return
        }

        observations.removeAll()
        scrollView = newScrollView
        guard let newScrollView else { return }

        observations = [
            newScrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.publishMetrics()
                }
            },
            newScrollView.observe(\.contentSize, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.publishMetrics()
                }
            },
            newScrollView.observe(\.bounds, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.publishMetrics()
                }
            },
            newScrollView.observe(\.contentInset, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.publishMetrics()
                }
            },
            newScrollView.observe(\.adjustedContentInset, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.publishMetrics()
                }
            }
        ]
        publishMetrics()
    }

    private func publishMetrics() {
        guard let scrollView else { return }

        let minOffsetY = -scrollView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        let metrics = NativeChatScrollMetrics(
            offsetY: scrollView.contentOffset.y,
            maxOffsetY: maxOffsetY,
            viewportHeight: scrollView.bounds.height,
            contentHeight: scrollView.contentSize.height
        )
        guard metrics != lastMetrics else { return }
        lastMetrics = metrics

        Task { @MainActor [weak self] in
            self?.onMetricsChange?(metrics)
        }
    }
}

private struct ChatBottomControlsHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CompactionNoticeView: View {
    let notice: CompactionNotice
    @ObservedObject var chatStore: HermesNativeChatStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(notice.isCurrentSession ? "Continuing After Compaction" : "Session Compacted", systemImage: "rectangle.stack.badge.plus")
                .font(.headline)
            Text(notice.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let oldSessionID = notice.oldSessionID {
                    StatusPill(title: "From \(oldSessionID.prefix(8))", color: .secondary)
                }
                if let newSessionID = notice.newSessionID {
                    StatusPill(title: "Now \(newSessionID.prefix(8))", color: .blue)
                }
            }

            if let newSessionID = notice.newSessionID,
               newSessionID != chatStore.currentSessionID {
                Button {
                    Task { await chatStore.continueSessionByIDInChat(newSessionID) }
                } label: {
                    Label("Open continuation", systemImage: "arrow.forward.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ChatStatusHeader: View {
    @ObservedObject var chatStore: HermesNativeChatStore
    let connection: ConnectionProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(connection?.resolvedHermesProfileName ?? "Hermes")
                        .font(.headline)
                    if let connection {
                        Text("\(connection.label) · \(connection.displayDestination)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Select a saved host to start chatting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                StatusPill(
                    title: availabilityTitle,
                    color: availabilityColor
                )
            }

            Text(chatStore.lastError ?? chatStore.sessionStatus)
                .font(.subheadline)
                .foregroundStyle(chatStore.lastError == nil ? Color.primary : Color.red)

            HStack(alignment: .top, spacing: 12) {
                StatusPill(title: chatStore.connectionStatus, color: .blue)

                if let currentSessionID = chatStore.currentSessionID, !currentSessionID.isEmpty {
                    StatusPill(title: "Session \(currentSessionID.prefix(8))", color: .secondary)
                }

                if chatStore.continuation != nil {
                    StatusPill(title: "Continuation", color: .orange)
                }
            }

            if !chatStore.gatewayInfo.isEmpty {
                FlowInfoRow(items: chatStore.gatewayInfo)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var availabilityTitle: String {
        if chatStore.isCheckingBootstrap || chatStore.bootstrapStatus == nil {
            return "Checking"
        }
        return chatStore.canUseNativeChat ? "Native" : "Unavailable"
    }

    private var availabilityColor: Color {
        if chatStore.isCheckingBootstrap || chatStore.bootstrapStatus == nil {
            return .secondary
        }
        return chatStore.canUseNativeChat ? .green : .orange
    }
}

private struct NativeChatUnavailableView: View {
    @ObservedObject var chatStore: HermesNativeChatStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Native chat is not available on this host yet.")
                .font(.headline)
            Text(chatStore.fallbackReason ?? "Open Terminal to use the Hermes TUI fallback, or install a Hermes build with tui_gateway.entry.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button("Retry") {
                    Task { await chatStore.refreshBootstrapStatus(force: true) }
                }
                .buttonStyle(.borderedProminent)

                Button("Open Terminal") {
                    chatStore.openTerminal()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ChatProgressStateView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ConversationEmptyState: View {
    @ObservedObject var chatStore: HermesNativeChatStore
    let connection: ConnectionProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a new Hermes chat")
                .font(.headline)

            Text(promptText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let connection {
                HStack(spacing: 8) {
                    StatusPill(title: connection.label, color: .secondary)
                    StatusPill(title: connection.resolvedHermesProfileName, color: .blue)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var promptText: String {
        if let lastError = chatStore.lastError, !lastError.isEmpty {
            return lastError
        }
        return "Write a message below to create a fresh conversation with the selected Hermes profile. You can always jump back to Terminal for power-user work."
    }
}

private struct ConversationResumeLoadingView: View {
    let title: String?
    let sessionStatus: String
    let connectionStatus: String

    var body: some View {
        ChatProgressStateView(
            title: "Loading Conversation",
            message: message
        )
    }

    private var message: String {
        let liveStatus = [sessionStatus, connectionStatus]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { status in
                !status.isEmpty &&
                    status != "Idle" &&
                    status != "No active chat session" &&
                    status != "Ready for native chat" &&
                    status != "Gateway connected"
            }
        if let liveStatus {
            return liveStatus
        }

        guard let title, !title.isEmpty else {
            return "Restoring the previous chat history before accepting new prompts."
        }
        return "Restoring \(title) before accepting new prompts."
    }
}

private struct ChatComposerView: View {
    @ObservedObject var chatStore: HermesNativeChatStore
    let skills: [SkillSummary]
    let isLoadingSkills: Bool
    let loadSkills: () async -> Void
    @State private var isPresentingInsertSheet = false
    @FocusState private var isMessageFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                Button {
                    isPresentingInsertSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.18, green: 0.72, blue: 0.62))
                .disabled(!canEdit)
                .opacity(canEdit ? 1 : 0.45)

                TextField("Message Hermes", text: $chatStore.draftMessage, axis: .vertical)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .lineLimit(1 ... 6)
                    .focused($isMessageFocused)
                    .disabled(!canEdit)

                if chatStore.isPerformingRequest {
                    Button {
                        Task { await chatStore.interrupt() }
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 34))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                } else {
                    Button {
                        Task { await chatStore.sendCurrentDraft() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(
                        canSend ? Color(red: 0.18, green: 0.72, blue: 0.62) : Color.secondary
                    )
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.12))
            )

            if statusLine != nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusLine ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .sheet(isPresented: $isPresentingInsertSheet) {
            ChatInsertSheet(
                commands: chatStore.dailyCommandSuggestions,
                isLoadingCommands: chatStore.isLoadingSlashCommandCatalog,
                commandsError: chatStore.slashCommandCatalogError,
                skills: skills,
                isLoadingSkills: isLoadingSkills,
                onLoadCommands: { await chatStore.loadSlashCommandCatalogIfNeeded() },
                onLoadSkills: loadSkills,
                onSelectCommand: insertCommand,
                onSelectSkill: insertSkill
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var trimmedDraft: String {
        chatStore.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canEdit: Bool {
        !chatStore.isResumingSession && !chatStore.isCheckingBootstrap
    }

    private var canSend: Bool {
        canEdit && !trimmedDraft.isEmpty
    }

    private var statusLine: String? {
        if chatStore.isCheckingBootstrap {
            return "Checking host…"
        }
        if chatStore.isConnecting {
            return "Connecting to Hermes…"
        }
        if chatStore.isPreparingSession {
            return "Preparing chat…"
        }
        if chatStore.isResumingSession {
            return "Loading conversation…"
        }
        return nil
    }

    private func insertCommand(_ command: HermesChatCommandSuggestion) {
        insertSlashCommand(command.command, acceptsDraftAsArgument: command.acceptsDraftAsArgument)
    }

    private func insertSkill(_ skill: SkillSummary) {
        insertSlashCommand("/\(skill.slug)", acceptsDraftAsArgument: true)
    }

    private func insertSlashCommand(_ command: String, acceptsDraftAsArgument: Bool) {
        let trimmedDraft = chatStore.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft.isEmpty {
            chatStore.draftMessage = acceptsDraftAsArgument ? "\(command) " : command
        } else if acceptsDraftAsArgument && !trimmedDraft.hasPrefix("/") {
            chatStore.draftMessage = "\(command) \(trimmedDraft)"
        } else {
            chatStore.draftMessage = acceptsDraftAsArgument ? "\(command) " : command
        }
        isPresentingInsertSheet = false
        isMessageFocused = true
    }
}

private struct ChatInsertSheet: View {
    @Environment(\.dismiss) private var dismiss
    let commands: [HermesChatCommandSuggestion]
    let isLoadingCommands: Bool
    let commandsError: String?
    let skills: [SkillSummary]
    let isLoadingSkills: Bool
    let onLoadCommands: () async -> Void
    let onLoadSkills: () async -> Void
    let onSelectCommand: (HermesChatCommandSuggestion) -> Void
    let onSelectSkill: (SkillSummary) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                commandSection
                skillSections
            }
            .navigationTitle("Insert")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search commands or skills")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await onLoadCommands()
            }
            .task {
                if skills.isEmpty {
                    await onLoadSkills()
                }
            }
        }
    }

    @ViewBuilder
    private var commandSection: some View {
        Section {
            if isLoadingCommands && commands.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading commands...")
                    Spacer()
                }
            }

            ForEach(filteredCommands) { command in
                Button {
                    onSelectCommand(command)
                } label: {
                    ChatCommandRow(command: command)
                }
            }

            if filteredCommands.isEmpty && !isLoadingCommands && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No matching commands")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let commandsError, !commandsError.isEmpty {
                Text("Using mobile shortcuts because the command catalog is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Commands")
        } footer: {
            Text("Commands are dispatched through the Hermes TUI runtime. Use /commands for the complete catalog.")
        }
    }

    @ViewBuilder
    private var skillSections: some View {
        if isLoadingSkills && skills.isEmpty {
            Section("Skills") {
                HStack {
                    Spacer()
                    ProgressView("Loading skills...")
                    Spacer()
                }
            }
        } else if filteredSkills.isEmpty {
            Section("Skills") {
                ContentUnavailableView(
                    "No Skills",
                    systemImage: "book.closed",
                    description: Text(skills.isEmpty ? "Enabled Hermes skills will appear here." : "No skills match this search.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        } else {
            ForEach(groupedFilteredSkills) { group in
                Section("Skills · \(group.category)") {
                    ForEach(group.skills) { skill in
                        Button {
                            onSelectSkill(skill)
                        } label: {
                            ChatSkillRow(skill: skill)
                        }
                    }
                }
            }
        }
    }

    private var filteredCommands: [HermesChatCommandSuggestion] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return commands }
        return commands.filter { command in
            [command.command, command.title, command.summary].contains { value in
                value.localizedCaseInsensitiveContains(trimmedQuery)
            }
        }
    }

    private var filteredSkills: [SkillSummary] {
        skills.filter { $0.matchesSearch(query) }
    }

    private var groupedFilteredSkills: [SkillInsertGroup] {
        let groups = Dictionary(grouping: filteredSkills) { $0.resolvedCategory }
        return groups
            .map { category, skills in
                SkillInsertGroup(
                    category: category,
                    skills: skills.sorted { lhs, rhs in
                        lhs.resolvedName.localizedStandardCompare(rhs.resolvedName) == .orderedAscending
                    }
                )
            }
            .sorted { lhs, rhs in
                lhs.category.localizedStandardCompare(rhs.category) == .orderedAscending
            }
    }
}

private struct SkillInsertGroup: Identifiable, Hashable {
    let category: String
    let skills: [SkillSummary]

    var id: String { category }
}

private struct ChatCommandRow: View {
    let command: HermesChatCommandSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(command.command)
                    .font(.callout.monospaced())
                    .foregroundStyle(Color(red: 0.18, green: 0.72, blue: 0.62))
                Text(command.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Text(command.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}

private struct ChatSkillRow: View {
    let skill: SkillSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(skill.resolvedName)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("/\(skill.slug)")
                .font(.caption.monospaced())
                .foregroundStyle(Color(red: 0.18, green: 0.72, blue: 0.62))
            if let description = skill.trimmedDescription {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ChatBubble: View {
    let message: HermesChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 36)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.text + (message.isStreaming ? "▍" : ""))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if message.role != .user {
                Spacer(minLength: 36)
            }
        }
    }

    private var label: String {
        switch message.role {
        case .user:
            return "You"
        case .assistant:
            return "Hermes"
        case .system:
            return "System"
        case .error:
            return "Error"
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color(red: 0.16, green: 0.62, blue: 0.54).opacity(0.18)
        case .assistant:
            return Color(.secondarySystemBackground)
        case .system:
            return Color.blue.opacity(0.12)
        case .error:
            return Color.red.opacity(0.12)
        }
    }
}

private struct ToolActivityTickerView: View {
    let card: HermesChatToolCard
    @Binding var isExpanded: Bool
    let onDismiss: () -> Void
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    @State private var isTouchTracking = false
    @State private var hasCancelledPressExpansion = false
    @State private var pressExpansionTask: Task<Void, Never>?

    private static let expansionDelayNanoseconds: UInt64 = 650_000_000
    private static let expansionMovementTolerance: CGFloat = 18
    private static let dismissThreshold: CGFloat = 90
    private static let dismissTravel: CGFloat = 520
    private static let dismissAnimationDuration: TimeInterval = 0.24

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 34, height: 34)

                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(compactTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? 5 : 1)
                if isExpanded, let expandedDetail = card.expandedDetail, !expandedDetail.isEmpty {
                    Text(expandedDetail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }
            }

            Spacer(minLength: 0)

            Text(statusLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isExpanded ? 14 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: isExpanded ? 18 : 999, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 18 : 999, style: .continuous)
                .stroke(Color.white.opacity(0.16))
        )
        .offset(x: dragOffset)
        .opacity(isDismissing ? 0 : 1)
        .allowsHitTesting(!isDismissing)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isTouchTracking {
                        beginTickerPress()
                    }
                    dragOffset = max(0, value.translation.width)
                    if shouldCancelPressExpansion(for: value.translation) {
                        cancelPendingPressExpansion()
                    }
                }
                .onEnded { value in
                    endTickerPress()
                    if value.translation.width > Self.dismissThreshold {
                        dismissTowardTrailingEdge()
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onDisappear {
            pressExpansionTask?.cancel()
        }
        .overlay(alignment: .trailing) {
            if dragOffset > 18 {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 14)
            }
        }
    }

    private func dismissTowardTrailingEdge() {
        guard !isDismissing else { return }
        isDismissing = true
        cancelPendingPressExpansion()
        withAnimation(.easeOut(duration: Self.dismissAnimationDuration)) {
            dragOffset = Self.dismissTravel
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissAnimationDuration) {
            onDismiss()
        }
    }

    private func beginTickerPress() {
        isTouchTracking = true
        hasCancelledPressExpansion = false
        pressExpansionTask?.cancel()
        pressExpansionTask = Task {
            try? await Task.sleep(nanoseconds: Self.expansionDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isTouchTracking,
                      !hasCancelledPressExpansion,
                      dragOffset <= Self.expansionMovementTolerance else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                    isExpanded = true
                }
            }
        }
    }

    private func endTickerPress() {
        pressExpansionTask?.cancel()
        isTouchTracking = false
        hasCancelledPressExpansion = false
        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
            isExpanded = false
        }
    }

    private func cancelPendingPressExpansion() {
        guard !hasCancelledPressExpansion else { return }
        hasCancelledPressExpansion = true
        pressExpansionTask?.cancel()
    }

    private func shouldCancelPressExpansion(for translation: CGSize) -> Bool {
        abs(translation.width) > Self.expansionMovementTolerance ||
        abs(translation.height) > Self.expansionMovementTolerance
    }

    private var normalizedStatus: String {
        card.status.lowercased()
    }

    private var compactTitle: String {
        card.toolType ?? card.title
    }

    private var previewText: String {
        card.actionPreview ?? card.detail ?? card.status
    }

    private var tint: Color {
        if card.isRunning {
            return .orange
        }
        if normalizedStatus.contains("error") || normalizedStatus.contains("fail") {
            return .red
        }
        return .green
    }

    private var iconName: String {
        if card.isRunning {
            return "gearshape.2.fill"
        }
        if normalizedStatus.contains("error") || normalizedStatus.contains("fail") {
            return "xmark.octagon.fill"
        }
        return "checkmark.circle.fill"
    }

    private var statusLabel: String {
        if card.isRunning {
            return "Running"
        }
        if normalizedStatus.contains("error") || normalizedStatus.contains("fail") {
            return "Failed"
        }
        return "Done"
    }
}

private struct PromptCardView: View {
    let card: HermesChatPromptCard
    @ObservedObject var chatStore: HermesNativeChatStore
    @State private var responseText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.title)
                .font(.headline)
            if hasPreview {
                VStack(alignment: .leading, spacing: 6) {
                    if let summaryLine {
                        Label(summaryLine, systemImage: "wrench.and.screwdriver")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    if let commandPreview = card.commandPreview, !commandPreview.isEmpty {
                        Text(commandPreview)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let payloadPreview = card.payloadPreview, !payloadPreview.isEmpty {
                        Text(payloadPreview)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !card.message.isEmpty {
                Text(card.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if card.kind == .approval {
                HStack {
                    Button("Approve") {
                        Task { await chatStore.respondToPrompt(card, approved: true) }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Deny") {
                        Task { await chatStore.respondToPrompt(card, approved: false) }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                TextField(card.placeholder ?? "Response", text: $responseText)
                    .textFieldStyle(.roundedBorder)

                if !card.choices.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(card.choices, id: \.self) { choice in
                                Button(choice) {
                                    responseText = choice
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Button("Send Reply") {
                    Task { await chatStore.respondToPrompt(card, responseText: responseText) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var hasPreview: Bool {
        summaryLine != nil || card.commandPreview != nil || card.payloadPreview != nil
    }

    private var summaryLine: String? {
        let parts = [card.toolType, card.actionSummary]
            .compactMap { value -> String? in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " - ")
    }
}

private struct DiagnosticsCard: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Diagnostics")
                .font(.headline)

            ForEach(Array(lines.suffix(25).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct FlowInfoRow: View {
    let items: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.keys.sorted(), id: \.self) { key in
                if let value = items[key] {
                    DetailLine(label: key, value: value)
                }
            }
        }
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
    }
}
#endif
