import AppKit
import SwiftUI

private let sessionDetailBottomID = "session-detail-bottom"
private let approvalNeededMessage = "Hermes requested command approval, but this chat turn cannot collect manual approvals. Retry this turn with Auto-approve enabled, or resume the session in Terminal to review the command yourself."
private let autoApproveHelpText = "Approves command requests for this turn. Without it, approval-required commands may be blocked in chat."
private let sessionImageAttachmentMaxBytes = 10 * 1024 * 1024

private func sessionMessageScrollID(_ message: SessionMessageDisplay) -> String {
    "session-message-\(message.id)"
}

private func pendingTurnScrollID(_ turn: PendingSessionTurn) -> String {
    "pending-turn-\(turn.id.uuidString)"
}

private enum SessionScrollReason {
    case sessionChanged
    case messagesLoaded
    case pendingTurnChanged
    case messagesChangedWhilePending

    var delay: DispatchTimeInterval {
        switch self {
        case .sessionChanged:
            return .milliseconds(120)
        case .messagesLoaded:
            return .milliseconds(60)
        case .pendingTurnChanged:
            return .milliseconds(40)
        case .messagesChangedWhilePending:
            return .milliseconds(80)
        }
    }

    var followUpDelay: DispatchTimeInterval? {
        switch self {
        case .sessionChanged:
            return .milliseconds(360)
        case .messagesLoaded:
            return .milliseconds(220)
        case .pendingTurnChanged:
            return .milliseconds(140)
        case .messagesChangedWhilePending:
            return nil
        }
    }

    var animated: Bool {
        switch self {
        case .sessionChanged, .messagesLoaded:
            return false
        case .pendingTurnChanged:
            return true
        case .messagesChangedWhilePending:
            return false
        }
    }
}

private struct SessionScrollRequest: Equatable {
    let id = UUID()
    let reason: SessionScrollReason?

    init(reason: SessionScrollReason? = nil) {
        self.reason = reason
    }

    var isPending: Bool {
        reason != nil
    }
}

struct SessionDetailView: View {
    let connection: ConnectionProfile?
    let session: SessionSummary?
    let messages: [SessionMessageDisplay]
    let errorMessage: String?
    let conversationError: String?
    let isSendingMessage: Bool
    let isDeletingSession: Bool
    let isSessionPinned: Bool
    let sessionCompactionNotice: SessionCompactionNotice?
    let activeRun: WorkspaceSessionActiveRun?
    let pendingTurn: PendingSessionTurn?
    let liveMessages: [SessionMessageDisplay]
    let liveToolActivityCards: [HermesToolActivityCard]
    let promptCards: [HermesPromptCard]
    let mode: SessionDetailMode
    let terminal: SessionTUITerminal?
    let terminalTheme: TerminalThemePreference
    let terminalAppearance: TerminalThemeAppearance
    let isActive: Bool
    let savedScrollOffset: CGFloat?
    let onSaveScrollOffset: (String, CGFloat?) -> Void
    let onResumeInTerminal: (SessionSummary) -> Void
    let onDeleteSession: (SessionSummary) async -> Void
    let onToggleSessionPin: (SessionSummary) -> Void
    let onModeChange: (SessionDetailMode) -> Void
    let onStartChat: () -> Void
    let onStartSession: (String, Bool, [WorkspaceChatAttachment]) async -> Bool
    let onSendMessage: (String, Bool, [WorkspaceChatAttachment]) async -> Bool
    let onRespondToPrompt: (HermesPromptCard, HermesPromptResponse) async -> Void
    let onUpdateTerminalTheme: (TerminalThemePreference) -> Void
    let onTerminalExitRefresh: () async -> Void

    @State private var showDeleteConfirmation = false
    @State private var isShowingChatAppearanceEditor = false
    @State private var scrollRequest = SessionScrollRequest()
    @State private var expandedMetadataMessageIDs: Set<String> = []
    @State private var scrollMetrics = SessionScrollMetrics()
    @State private var scrollOffsetRestoreRequestID = UUID()
    @State private var shouldAutoScrollNextMessageLoad = true

    private var latestMessageScrollKey: String {
        "\(messages.count):\(messages.last?.id ?? "none"):live=\(liveMessages.count):\(liveMessages.last?.id ?? "none"):pending=\(pendingTurn?.id.uuidString ?? "none"):prompts=\(promptCards.count):tools=\(liveToolActivityCards.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar

            Divider()

            nativeChatMode
        }
        .alert(L10n.string("Delete this session?"), isPresented: $showDeleteConfirmation, presenting: session) { session in
            Button(L10n.string("Delete"), role: .destructive) {
                Task {
                    await onDeleteSession(session)
                }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: { session in
            Text(L10n.string(
                "“%@” will be removed from Hermes Desktop and deleted on the remote Hermes host as well. This action cannot be undone.",
                session.resolvedTitle
            ))
        }
    }

    @ViewBuilder
    private var detailToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
        if let session {
            SessionSummaryPanel(
                session: session,
                isDeleting: isDeletingSession,
                isPinned: isSessionPinned,
                onOpenInTerminal: { onResumeInTerminal(session) },
                onTogglePin: { onToggleSessionPin(session) },
                onDelete: { showDeleteConfirmation = true }
            )
        } else {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("New Chat"))
                        .font(.title3.weight(.semibold))

                    Text(newChatSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }

        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var terminalThemeBinding: Binding<TerminalThemePreference> {
        Binding {
            terminalTheme
        } set: { newValue in
            onUpdateTerminalTheme(newValue)
        }
    }

    private var newChatSubtitle: String {
        guard let connection else {
            return L10n.string("Select an SSH host to start a live Hermes chat.")
        }
        return "\(connection.label) - \(connection.displayDestination) - \(connection.resolvedHermesProfileName)"
    }

    private var nativeChatMode: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        nativeChatScrollContent

                        Color.clear
                            .frame(height: 1)
                            .id(sessionDetailBottomID)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                }
                .background {
                    SessionScrollOffsetObserver(
                        sessionID: session?.id,
                        savedOffset: savedScrollOffset,
                        restoreRequestID: scrollOffsetRestoreRequestID,
                        onSaveOffset: onSaveScrollOffset,
                        onMetricsChange: { metrics in
                            scrollMetrics = metrics
                        }
                    )
                }
                .overlay(alignment: .bottomTrailing) {
                    if shouldShowJumpToLatestButton {
                        Button {
                            requestScrollToLatest(proxy, reason: .pendingTurnChanged)
                        } label: {
                            Label(L10n.string("Jump to Latest"), systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(18)
                        .transition(.opacity)
                        .help(L10n.string("Scroll to the latest message"))
                    }
                }
                .onChange(of: session?.id) { _, _ in
                    expandedMetadataMessageIDs.removeAll()
                    shouldAutoScrollNextMessageLoad = true
                    restoreSavedScrollOffsetOrScrollToLatest(proxy)
                }
                .onChange(of: latestMessageScrollKey) { _, _ in
                    handleMessageScrollChange(proxy)
                }
                .task(id: session?.id) {
                    restoreSavedScrollOffsetOrScrollToLatest(proxy)
                }
            }

            Divider()
                .opacity(0.6)

            composerDock
        }
    }

    @ViewBuilder
    private var nativeChatScrollContent: some View {
        if let errorMessage {
            HermesSurfacePanel {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }

        if let session {
            if let sessionCompactionNotice,
               sessionCompactionNotice.sourceSessionID == session.id {
                SessionCompactionNoticeView(notice: sessionCompactionNotice)
            }

            nativeConversationContent(for: session)
        } else if let pendingTurn, pendingTurn.sessionID == nil {
            HermesSurfacePanel(title: "Starting Session") {
                PendingSessionTurnView(turn: pendingTurn, showPrompt: !allChatMessages.containsUserPrompt(pendingTurn.prompt))
                    .id(pendingTurnScrollID(pendingTurn))
            }
        } else {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Start or select a session"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(L10n.string("Write below to begin a new Hermes conversation, or choose an existing session from the list."))
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
    }

    @ViewBuilder
    private func nativeConversationContent(for session: SessionSummary) -> some View {
        let matchingPendingTurn = pendingTurn?.sessionID == session.id ? pendingTurn : nil

        if allChatMessages.isEmpty && matchingPendingTurn == nil && liveToolActivityCards.isEmpty && promptCards.isEmpty && activeRunForSession(session) == nil {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No messages yet"),
                    systemImage: "text.bubble",
                    description: Text(L10n.string("This session has no readable message rows yet."))
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let run = activeRunForSession(session) {
                    WorkspaceSessionActiveRunCard(run: run)
                }

                ForEach(allChatMessages) { message in
                    MessageCard(
                        message: message,
                        isShowingMetadata: metadataExpansionBinding(for: message.id)
                    )
                    .id(sessionMessageScrollID(message))
                }

                ForEach(liveToolActivityCards) { card in
                    SessionToolActivityCardView(card: card)
                }

                ForEach(promptCards) { card in
                    SessionPromptCardView(
                        card: card,
                        isDisabled: isSendingMessage,
                        onRespond: onRespondToPrompt
                    )
                }

                if let matchingPendingTurn {
                    PendingSessionTurnView(
                        turn: matchingPendingTurn,
                        showPrompt: !allChatMessages.containsUserPrompt(matchingPendingTurn.prompt)
                    )
                    .id(pendingTurnScrollID(matchingPendingTurn))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var allChatMessages: [SessionMessageDisplay] {
        var seen = Set<String>()
        return (messages + liveMessages).filter { message in
            let key = sessionMessageDeduplicationKey(for: message)
            return seen.insert(key).inserted
        }
    }

    private func sessionMessageDeduplicationKey(
        for message: SessionMessageDisplay
    ) -> String {
        let text = (message.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !text.isEmpty else {
            return "id:\(message.id)"
        }
        return "\(sessionMessageRoleKey(message.role)):\(text)"
    }

    private func sessionMessageRoleKey(_ role: SessionMessageRole) -> String {
        switch role {
        case .assistant:
            return "assistant"
        case .user:
            return "user"
        case .system:
            return "system"
        case .event:
            return "event"
        case .custom(let value):
            return value
        }
    }

    private func activeRunForSession(_ session: SessionSummary) -> WorkspaceSessionActiveRun? {
        guard let activeRun, activeRun.sessionKey == session.id else { return nil }
        return activeRun
    }

    private var composerDock: some View {
        SessionComposerPanel(
            title: session == nil ? "New Session" : "Continue Session",
            placeholder: session == nil ? "Start a new Hermes session…" : "Write a reply to continue this session…",
            errorMessage: conversationError,
            isSending: isSendingMessage,
            showsAutoApprove: true,
            onResumeInTerminal: session.map { selectedSession in
                { onResumeInTerminal(selectedSession) }
            },
            onSend: session == nil ? onStartSession : onSendMessage
        )
        .id(session?.id ?? "new-session")
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var sessionChatPlaceholder: some View {
        HermesSurfacePanel {
            VStack(alignment: .center, spacing: 14) {
                ContentUnavailableView(
                    chatPlaceholderTitle,
                    systemImage: "terminal",
                    description: Text(chatPlaceholderDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 240)

                HStack(spacing: 10) {
                    Button {
                        onStartChat()
                    } label: {
                        Label(startChatButtonTitle, systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    if let session {
                        Button {
                            onResumeInTerminal(session)
                        } label: {
                            Label(L10n.string("Open in Terminal"), systemImage: "macwindow.and.cursorarrow")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var chatPlaceholderTitle: String {
        if terminal != nil {
            return L10n.string("Another chat is running")
        }
        return session == nil ? L10n.string("Start a new Hermes TUI chat") : L10n.string("Start Chat for this session")
    }

    private var chatPlaceholderDescription: String {
        if let terminal {
            return L10n.string("%@ is active. Start a new embedded TUI when you are ready to switch.", terminal.targetLabel)
        }
        if let session {
            return L10n.string("Hermes TUI will resume %@ over the existing SSH-first terminal path.", shortSessionID(session.id))
        }
        return L10n.string("Hermes TUI will create the next session on the host; the conversation will appear here when it is available.")
    }

    private var startChatButtonTitle: String {
        session == nil ? L10n.string("Start New Chat") : L10n.string("Start Chat")
    }

    private func terminalMatchesCurrentSelection(_ terminal: SessionTUITerminal) -> Bool {
        guard let connection else { return false }
        return terminal.matches(sessionID: session?.id, connection: connection)
    }

    private func shortSessionID(_ sessionID: String) -> String {
        if sessionID.count <= 10 {
            return sessionID
        }
        return String(sessionID.prefix(10))
    }

    private func metadataExpansionBinding(for messageID: String) -> Binding<Bool> {
        Binding {
            expandedMetadataMessageIDs.contains(messageID)
        } set: { isExpanded in
            if isExpanded {
                expandedMetadataMessageIDs.insert(messageID)
            } else {
                expandedMetadataMessageIDs.remove(messageID)
            }
        }
    }

    private var shouldShowJumpToLatestButton: Bool {
        guard session != nil,
              hasLatestChatTarget,
              !scrollRequest.isPending else {
            return false
        }

        return scrollMetrics.distanceToBottom > 96
    }

    private var hasLatestChatTarget: Bool {
        let hasMatchingPendingTurn = pendingTurn.map { $0.sessionID == nil || $0.sessionID == session?.id } ?? false
        return !allChatMessages.isEmpty || hasMatchingPendingTurn || !promptCards.isEmpty || !liveToolActivityCards.isEmpty
    }

    private var isNearLatest: Bool {
        scrollMetrics.distanceToBottom <= 96
    }

    private func handleMessageScrollChange(_ proxy: ScrollViewProxy) {
        if shouldAutoScrollNextMessageLoad {
            shouldAutoScrollNextMessageLoad = false
            requestScrollToLatest(proxy, reason: .messagesLoaded)
            return
        }

        guard isActive, isNearLatest else { return }
        requestScrollToLatest(proxy, reason: .messagesLoaded)
    }

    private func restoreSavedScrollOffsetOrScrollToLatest(_ proxy: ScrollViewProxy) {
        if savedScrollOffset != nil {
            let request = SessionScrollRequest(reason: .sessionChanged)
            scrollRequest = request
            scrollOffsetRestoreRequestID = UUID()

            let followUpDelay = SessionScrollReason.sessionChanged.followUpDelay ?? .milliseconds(360)
            DispatchQueue.main.asyncAfter(deadline: .now() + followUpDelay) {
                guard scrollRequest == request else { return }
                scrollRequest = SessionScrollRequest()
            }
            return
        }

        requestScrollToLatest(proxy, reason: .sessionChanged)
    }

    private func requestScrollToLatest(_ proxy: ScrollViewProxy, reason: SessionScrollReason) {
        let request = SessionScrollRequest(reason: reason)
        scrollRequest = request

        scheduleScroll(
            proxy,
            request: request,
            target: latestScrollTarget,
            reason: reason,
            delay: reason.delay,
            completesRequest: reason.followUpDelay == nil
        )

        if let followUpDelay = reason.followUpDelay {
            scheduleScroll(
                proxy,
                request: request,
                target: latestScrollTarget,
                reason: reason,
                delay: followUpDelay,
                completesRequest: true
            )
        }
    }

    private func scheduleScroll(
        _ proxy: ScrollViewProxy,
        request: SessionScrollRequest,
        target: (id: String, anchor: UnitPoint),
        reason: SessionScrollReason,
        delay: DispatchTimeInterval,
        completesRequest: Bool
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard scrollRequest == request else { return }

            if reason.animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(target.id, anchor: target.anchor)
                }
            } else {
                proxy.scrollTo(target.id, anchor: target.anchor)
            }

            guard completesRequest else { return }
            scrollRequest = SessionScrollRequest()
        }
    }

    private var latestScrollTarget: (id: String, anchor: UnitPoint) {
        if let pendingTurn,
           pendingTurn.sessionID == nil || pendingTurn.sessionID == session?.id {
            return (pendingTurnScrollID(pendingTurn), .top)
        }

        if let lastMessage = allChatMessages.last {
            return (sessionMessageScrollID(lastMessage), .top)
        }

        return (sessionDetailBottomID, .bottom)
    }
}

private struct SessionScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var maxOffset: CGFloat = 0

    var distanceToBottom: CGFloat {
        max(0, maxOffset - offset)
    }
}

private struct SessionScrollOffsetObserver: NSViewRepresentable {
    let sessionID: String?
    let savedOffset: CGFloat?
    let restoreRequestID: UUID
    let onSaveOffset: (String, CGFloat?) -> Void
    let onMetricsChange: (SessionScrollMetrics) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SessionScrollOffsetProbeView {
        let view = SessionScrollOffsetProbeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: SessionScrollOffsetProbeView, context: Context) {
        context.coordinator.configure(
            sessionID: sessionID,
            savedOffset: savedOffset,
            restoreRequestID: restoreRequestID,
            onSaveOffset: onSaveOffset,
            onMetricsChange: onMetricsChange
        )
        nsView.attachWhenReady()
    }

    final class Coordinator: NSObject, @unchecked Sendable {
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var frameObserver: NSObjectProtocol?
        private var sessionID: String?
        private var savedOffset: CGFloat?
        private var restoreRequestID: UUID?
        private var lastAppliedRestoreRequestID: UUID?
        private var isRestoring = false
        private var onSaveOffset: ((String, CGFloat?) -> Void)?
        private var onMetricsChange: ((SessionScrollMetrics) -> Void)?

        @MainActor
        func configure(
            sessionID: String?,
            savedOffset: CGFloat?,
            restoreRequestID: UUID,
            onSaveOffset: @escaping (String, CGFloat?) -> Void,
            onMetricsChange: @escaping (SessionScrollMetrics) -> Void
        ) {
            self.sessionID = sessionID
            self.savedOffset = savedOffset
            self.restoreRequestID = restoreRequestID
            self.onSaveOffset = onSaveOffset
            self.onMetricsChange = onMetricsChange
            restoreIfNeeded()
            reportCurrentOffset(shouldSave: false)
        }

        @MainActor
        func attach(to scrollView: NSScrollView?) {
            guard self.scrollView !== scrollView else {
                restoreIfNeeded()
                reportCurrentOffset(shouldSave: false)
                return
            }

            detach()
            self.scrollView = scrollView

            guard let scrollView else { return }
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reportCurrentOffset(shouldSave: true)
                }
            }

            if let documentView = scrollView.documentView {
                documentView.postsFrameChangedNotifications = true
                frameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.reportCurrentOffset(shouldSave: false)
                    }
                }
            }

            restoreIfNeeded()
            reportCurrentOffset(shouldSave: false)
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
        }

        @MainActor
        private func detach() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            boundsObserver = nil
            frameObserver = nil
        }

        @MainActor
        private func restoreIfNeeded() {
            guard let restoreRequestID,
                  lastAppliedRestoreRequestID != restoreRequestID,
                  savedOffset != nil else {
                return
            }

            lastAppliedRestoreRequestID = restoreRequestID
            restoreSavedOffset(after: .milliseconds(40))
            restoreSavedOffset(after: .milliseconds(220))
        }

        @MainActor
        private func restoreSavedOffset(after delay: DispatchTimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      let scrollView,
                      let savedOffset else {
                    return
                }

                isRestoring = true
                let target = clampedOffset(savedOffset, in: scrollView)
                let clipView = scrollView.contentView
                clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: target))
                scrollView.reflectScrolledClipView(clipView)
                reportCurrentOffset(shouldSave: false)

                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
                    guard let self else { return }
                    isRestoring = false
                    reportCurrentOffset(shouldSave: true)
                }
            }
        }

        @MainActor
        private func reportCurrentOffset(shouldSave: Bool) {
            guard let scrollView else { return }

            let offset = clampedOffset(scrollView.contentView.bounds.origin.y, in: scrollView)
            let metrics = SessionScrollMetrics(
                offset: offset,
                maxOffset: maxOffset(in: scrollView)
            )

            onMetricsChange?(metrics)

            guard shouldSave,
                  !isRestoring,
                  let sessionID else {
                return
            }

            onSaveOffset?(sessionID, offset)
        }

        @MainActor
        private func maxOffset(in scrollView: NSScrollView) -> CGFloat {
            guard let documentView = scrollView.documentView else { return 0 }
            return max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        }

        @MainActor
        private func clampedOffset(_ offset: CGFloat, in scrollView: NSScrollView) -> CGFloat {
            min(max(0, offset), maxOffset(in: scrollView))
        }
    }
}

private final class SessionScrollOffsetProbeView: NSView {
    weak var coordinator: SessionScrollOffsetObserver.Coordinator?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachWhenReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachWhenReady()
    }

    func attachWhenReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            coordinator?.attach(to: enclosingScrollView)
        }
    }
}


private struct WorkspaceSessionActiveRunCard: View {
    let run: WorkspaceSessionActiveRun

    private var statusText: String {
        run.status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var statusTint: Color {
        switch run.status.lowercased() {
        case "error", "failed":
            return .red
        case "complete", "completed", "succeeded":
            return .green
        default:
            return .cyan
        }
    }

    private var detailText: String {
        if let errorMessage = run.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if let thinkingText = run.thinkingText, !thinkingText.isEmpty {
            return thinkingText
        }
        if let assistantText = run.assistantText, !assistantText.isEmpty {
            return assistantText
        }
        return L10n.string("Server-owned chat turn is being tracked by the Workspace run ledger.")
    }

    private var recentLifecycleEvents: [WorkspaceSessionRunLifecycleEvent] {
        Array(run.lifecycleEvents.suffix(6))
    }

    var body: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(statusText, systemImage: run.status == "error" ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTint)

                    Text(run.runId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if let lastEventAt = run.lastEventAt {
                        Text(runLedgerTimestamp(lastEventAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)

                if !recentLifecycleEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("Run Events"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(recentLifecycleEvents) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Text(nonBlank(event.emoji) ?? (event.isError ? "!" : "-"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(event.isError ? .red : .secondary)
                                    .frame(width: 16, alignment: .center)

                                Text(event.text)
                                    .font(.caption)
                                    .foregroundStyle(event.isError ? .red : .secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let timestamp = event.timestamp {
                                    Text(runLedgerTimestamp(timestamp))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if !run.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("Tools"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(run.toolCalls.prefix(6)) { tool in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    HermesBadge(
                                        text: tool.phase.replacingOccurrences(of: "_", with: " ").capitalized,
                                        tint: toolPhaseTint(tool.phase),
                                        systemImage: "wrench.and.screwdriver.fill",
                                        isMonospaced: false
                                    )

                                    Text(tool.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)

                                    Spacer()
                                }

                                if let preview = nonBlank(tool.preview) {
                                    Text(preview)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                }

                                if let result = nonBlank(tool.result) {
                                    Text(result)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func toolPhaseTint(_ phase: String) -> Color {
        switch phase.lowercased() {
        case "complete", "completed", "succeeded", "success":
            return .green
        case "error", "failed":
            return .red
        default:
            return .blue
        }
    }

    private func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func runLedgerTimestamp(_ value: Double) -> String {
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        let date = Date(timeIntervalSince1970: seconds)
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}

private struct SessionSummaryPanel: View {
    let session: SessionSummary
    let isDeleting: Bool
    let isPinned: Bool
    let onOpenInTerminal: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.resolvedTitle)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(session.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .contextMenu {
                                Button(L10n.string("Copy Session ID")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(session.id, forType: .string)
                                }
                            }
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        if let model = session.displayModel {
                            HermesBadge(text: model, tint: .orange)
                        }

                        if let count = session.messageCount {
                            HermesBadge(text: L10n.string("%@ messages", "\(count)"), tint: .accentColor)
                        }

                        Menu {
                            Button {
                                onOpenInTerminal()
                            } label: {
                                Label(L10n.string("Open in terminal"), systemImage: "terminal")
                            }

                            Button {
                                onTogglePin()
                            } label: {
                                Label(
                                    L10n.string(isPinned ? "Unpin session" : "Pin session"),
                                    systemImage: isPinned ? "pin.slash" : "pin"
                                )
                            }

                            Button(L10n.string("Delete session"), role: .destructive, action: onDelete)
                        } label: {
                            if isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label(L10n.string("More"), systemImage: "ellipsis.circle")
                                    .labelStyle(.iconOnly)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize(horizontal: true, vertical: false)
                        .help(L10n.string("More session actions"))
                        .accessibilityLabel(L10n.string("More session actions"))
                        .disabled(isDeleting)
                    }
                }

                if !sessionMetadataFields.isEmpty {
                    HermesInspectorFieldList(fields: sessionMetadataFields)
                }
            }
        }
    }

    private var sessionMetadataFields: [HermesInspectorField] {
        var fields: [HermesInspectorField] = []

        if let startedAt = session.startedAt?.dateValue {
            fields.append(HermesInspectorField(
                id: "started",
                label: "Started",
                value: DateFormatters.shortDateTimeFormatter().string(from: startedAt)
            ))
        }

        if let lastActive = session.lastActive?.dateValue {
            fields.append(HermesInspectorField(
                id: "last-active",
                label: "Last active",
                value: DateFormatters.shortDateTimeFormatter().string(from: lastActive)
            ))
        }

        return fields
    }
}

private struct SessionComposerPanel: View {
    @EnvironmentObject private var appState: AppState

    let title: String
    let placeholder: String
    let errorMessage: String?
    let isSending: Bool
    let showsAutoApprove: Bool
    let onResumeInTerminal: (() -> Void)?
    let onSend: (String, Bool, [WorkspaceChatAttachment]) async -> Bool

    @State private var draft = ""
    @State private var attachments: [WorkspaceChatAttachment] = []
    @State private var attachmentError: String?
    @State private var autoApproveCommands = false
    @State private var isExpanded = false
    @FocusState private var isEditorFocused: Bool

    private let compactPromptHeight: CGFloat = 28
    private let compactPromptLeadingInset: CGFloat = 8
    private let compactPromptTopInset: CGFloat = 3
    private let expandedPromptHeight: CGFloat = 96
    private let expandedPromptHorizontalInset: CGFloat = 12
    private let expandedPromptTopInset: CGFloat = 10
    private let expandedEditorCharacterThreshold = 140
    private let expandedEditorLongTokenThreshold = 52

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !isSending && (!trimmedDraft.isEmpty || !attachments.isEmpty)
    }

    private var shouldUseExpandedEditor: Bool {
        isExpanded || shouldExpandEditor(for: draft)
    }

    private var compactPlaceholder: String {
        title == "New Session" ? L10n.string("Start…") : L10n.string("Reply…")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)

                Text(L10n.string(title))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if let onResumeInTerminal {
                    Button(action: onResumeInTerminal) {
                        Label(L10n.string("Resume in Terminal"), systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSending)
                    .help(L10n.string("Open this Hermes session in a fresh Terminal tab"))
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                HermesInsetSurface {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            if isApprovalNeededError(errorMessage) {
                                Text(L10n.string("Approval needed"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }

                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            attachmentStrip

            composerInput
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.panelCornerRadius, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.84))
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.panelCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
        }
        .task(id: appState.activeConnectionID) {
            guard appState.activeConnectionID != nil else { return }
            guard appState.skills.isEmpty, !appState.isLoadingSkills else { return }
            await appState.loadSkills(reset: false)
        }
    }

    @ViewBuilder
    private var composerInput: some View {
        let usesExpandedEditor = shouldUseExpandedEditor

        VStack(alignment: .leading, spacing: usesExpandedEditor ? 10 : 0) {
            HStack(alignment: .center, spacing: 10) {
                promptEditor(
                    placeholderText: usesExpandedEditor ? L10n.string(placeholder) : compactPlaceholder,
                    height: usesExpandedEditor ? expandedPromptHeight : compactPromptHeight,
                    contentPadding: usesExpandedEditor
                        ? EdgeInsets(
                            top: expandedPromptTopInset,
                            leading: expandedPromptHorizontalInset,
                            bottom: 0,
                            trailing: expandedPromptHorizontalInset
                        )
                        : EdgeInsets(
                            top: compactPromptTopInset,
                            leading: compactPromptLeadingInset,
                            bottom: 0,
                            trailing: 0
                        ),
                    showsEditorBackground: usesExpandedEditor
                )
                .frame(minWidth: 80)
                .frame(height: usesExpandedEditor ? 108 : compactPromptHeight)

                if !usesExpandedEditor {
                    controlCluster
                }
            }
            .padding(.leading, usesExpandedEditor ? 0 : 12)
            .padding(.trailing, usesExpandedEditor ? 0 : 8)
            .frame(height: usesExpandedEditor ? nil : 46)
            .background {
                if !usesExpandedEditor {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(HermesTheme.insetFill)
                }
            }
            .overlay {
                if !usesExpandedEditor {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !usesExpandedEditor {
                    expandEditor()
                }
            }

            if usesExpandedEditor {
                HStack {
                    Spacer(minLength: 8)
                    controlCluster
                }
            }
        }
        .onChange(of: shouldUseExpandedEditor) { _, _ in
            preserveEditorFocusAfterLayoutChange()
        }
    }

    private func promptEditor(
        placeholderText: String,
        height: CGFloat,
        contentPadding: EdgeInsets,
        showsEditorBackground: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if showsEditorBackground {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(HermesTheme.insetFill)
            }

            SessionPromptTextView(
                text: $draft,
                placeholder: placeholderText,
                isFocused: $isEditorFocused,
                isDisabled: isSending,
                onCommandReturn: submit,
                onImagePaste: addImageAttachment,
                onImagePasteError: showImageAttachmentError
            )
                .padding(contentPadding)
                .frame(height: height)
        }
        .overlay {
            if showsEditorBackground {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if !attachments.isEmpty || attachmentError != nil {
            VStack(alignment: .leading, spacing: 6) {
                if !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(attachments) { attachment in
                                HStack(spacing: 6) {
                                    Image(systemName: "photo")
                                        .foregroundStyle(Color.accentColor)

                                    Text(attachment.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: 220, alignment: .leading)

                                    Text(byteCountString(attachment.size))
                                        .foregroundStyle(.secondary)

                                    Button {
                                        removeAttachment(attachment)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .imageScale(.small)
                                    }
                                    .buttonStyle(.plain)
                                    .help(L10n.string("Remove attachment"))
                                    .accessibilityLabel(L10n.string("Remove attachment"))
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(HermesTheme.insetFill)
                                }
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
                                }
                            }
                        }
                    }
                }

                if let attachmentError {
                    Label(attachmentError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var controlCluster: some View {
        HStack(spacing: 8) {
            skillInsertMenu

            if showsAutoApprove {
                ViewThatFits(in: .horizontal) {
                    autoApproveToggle
                    compactAutoApproveToggle
                }
            }

            Button {
                submit()
            } label: {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "paperplane.fill")

                        Text("⌘↩")
                            .font(.caption2.monospaced().weight(.semibold))
                    }
                    .frame(minWidth: 48)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help(L10n.string("Send with Command-Return"))
            .accessibilityLabel(L10n.string("Send"))
        }
    }

    private var skillInsertMenu: some View {
        Menu {
            if appState.isLoadingSkills {
                Text(L10n.string("Loading skills…"))
            } else if appState.skills.isEmpty {
                Button(L10n.string("Refresh Skills")) {
                    Task {
                        await appState.loadSkills(reset: false)
                    }
                }

                if let skillsError = appState.skillsError, !skillsError.isEmpty {
                    Text(skillsError)
                }
            } else {
                ForEach(appState.skills) { skill in
                    Button {
                        insertSkillCommand(skill)
                    } label: {
                        if let category = skill.category, !category.isEmpty {
                            Text("\(skill.resolvedName) (\(category))")
                        } else {
                            Text(skill.resolvedName)
                        }
                    }
                }
            }
        } label: {
            Label(L10n.string("Insert Skill"), systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help(L10n.string("Insert a skill command into the prompt"))
        .accessibilityLabel(L10n.string("Insert Skill"))
        .disabled(isSending)
    }

    private var autoApproveToggle: some View {
        Toggle(isOn: $autoApproveCommands) {
            Label(L10n.string("Auto-approve commands"), systemImage: "checkmark.shield")
        }
        .toggleStyle(.checkbox)
        .disabled(isSending)
        .help(L10n.string(autoApproveHelpText))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactAutoApproveToggle: some View {
        Toggle(isOn: $autoApproveCommands) {
            Label(L10n.string("Auto-approve commands"), systemImage: "checkmark.shield")
                .labelStyle(.iconOnly)
        }
        .toggleStyle(.checkbox)
        .disabled(isSending)
        .help(L10n.string(autoApproveHelpText))
        .accessibilityLabel(L10n.string("Auto-approve commands"))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func submit() {
        let originalPrompt = trimmedDraft
        let outgoingAttachments = attachments
        guard !isSending, !originalPrompt.isEmpty || !outgoingAttachments.isEmpty else { return }

        let prompt = originalPrompt.isEmpty
            ? L10n.string(outgoingAttachments.count == 1 ? "Please review the attached image." : "Please review the attached images.")
            : originalPrompt
        let shouldAutoApprove = autoApproveCommands
        autoApproveCommands = false
        isExpanded = false
        isEditorFocused = false
        draft = ""
        attachments = []
        attachmentError = nil

        Task {
            let didSend = await onSend(prompt, shouldAutoApprove, outgoingAttachments)
            if !didSend && draft.isEmpty && attachments.isEmpty {
                draft = originalPrompt
                attachments = outgoingAttachments
                isExpanded = shouldExpandEditor(for: prompt)
            }
        }
    }

    private func expandEditor() {
        guard !isSending else { return }
        isExpanded = true
        DispatchQueue.main.async {
            isEditorFocused = true
        }
    }

    private func insertSkillCommand(_ skill: SkillSummary) {
        let command = "/\(skill.slug)"
        let normalizedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDraft.contains(command) else {
            expandEditor()
            return
        }

        if normalizedDraft.isEmpty {
            draft = "\(command) "
        } else {
            draft = "\(command)\n\(normalizedDraft)"
        }

        expandEditor()
    }

    private func addImageAttachment(_ attachment: WorkspaceChatAttachment) {
        guard !isSending else { return }
        attachmentError = nil
        attachments.append(attachment)
        expandEditor()
    }

    private func showImageAttachmentError(_ message: String) {
        guard !isSending else { return }
        attachmentError = message
        expandEditor()
    }

    private func removeAttachment(_ attachment: WorkspaceChatAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    private func preserveEditorFocusAfterLayoutChange() {
        guard isEditorFocused, !isSending else { return }
        DispatchQueue.main.async {
            isEditorFocused = true
        }
    }

    private func shouldExpandEditor(for text: String) -> Bool {
        text.contains("\n") ||
            text.count > expandedEditorCharacterThreshold ||
            longestTokenLength(in: text) > expandedEditorLongTokenThreshold
    }

    private func longestTokenLength(in text: String) -> Int {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(\.count)
            .max() ?? 0
    }

    private func isApprovalNeededError(_ message: String) -> Bool {
        message.contains(approvalNeededMessage)
    }
}

private enum PastedImageAttachmentResult {
    case success(WorkspaceChatAttachment)
    case failure(String)
}

private func pastedImageAttachment(from pasteboard: NSPasteboard) -> PastedImageAttachmentResult? {
    guard let imageData = pastedImagePNGData(from: pasteboard) else { return nil }

    guard imageData.count <= sessionImageAttachmentMaxBytes else {
        return .failure(L10n.string("Pasted image is too large. Limit images to \(byteCountString(sessionImageAttachmentMaxBytes))."))
    }

    return .success(WorkspaceChatAttachment.imagePNG(data: imageData))
}

private func pastedImagePNGData(from pasteboard: NSPasteboard) -> Data? {
    if let pngData = pasteboard.data(forType: .png) {
        return pngData
    }

    if let tiffData = pasteboard.data(forType: .tiff),
       let image = NSImage(data: tiffData) {
        return pngData(from: image)
    }

    if let image = NSImage(pasteboard: pasteboard) {
        return pngData(from: image)
    }

    let imageFileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [
        .urlReadingFileURLsOnly: true
    ]) as? [URL] ?? []

    for url in imageFileURLs {
        guard let image = NSImage(contentsOf: url),
              let data = pngData(from: image) else { continue }
        return data
    }

    return nil
}

private func pngData(from image: NSImage) -> Data? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        return nil
    }

    return bitmap.representation(using: .png, properties: [:])
}

private func byteCountString(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

private struct SessionPromptTextView: NSViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let isFocused: FocusState<Bool>.Binding
    let isDisabled: Bool
    let onCommandReturn: () -> Void
    let onImagePaste: (WorkspaceChatAttachment) -> Void
    let onImagePasteError: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        let textView = PlaceholderCommandTextView()
        textView.placeholder = placeholder
        textView.commandReturnAction = onCommandReturn
        textView.imagePasteAction = onImagePaste
        textView.imagePasteErrorAction = onImagePasteError
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        configure(textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? PlaceholderCommandTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.placeholder = placeholder
        textView.commandReturnAction = onCommandReturn
        textView.imagePasteAction = onImagePaste
        textView.imagePasteErrorAction = onImagePasteError
        configure(textView)
        updateFocus(for: textView)
        textView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func configure(_ textView: PlaceholderCommandTextView) {
        textView.isEditable = !isDisabled
        textView.isSelectable = !isDisabled
        textView.alphaValue = isDisabled ? 0.62 : 1
    }

    private func updateFocus(for textView: NSTextView) {
        guard let window = textView.window else { return }

        if isFocused.wrappedValue {
            if window.firstResponder !== textView {
                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SessionPromptTextView
        weak var textView: PlaceholderCommandTextView?

        init(parent: SessionPromptTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PlaceholderCommandTextView else { return }
            parent.isFocused.wrappedValue = textView.window?.firstResponder === textView
            parent.text = textView.string
            textView.needsDisplay = true
        }
    }
}

private final class PlaceholderCommandTextView: NSTextView {
    var placeholder = "" {
        didSet {
            needsDisplay = true
        }
    }

    var commandReturnAction: (() -> Void)?
    var imagePasteAction: ((WorkspaceChatAttachment) -> Void)?
    var imagePasteErrorAction: ((String) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        NSAttributedString(string: placeholder, attributes: attributes)
            .draw(at: textContainerOrigin)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "\r" {
            commandReturnAction?()
            return
        }

        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v",
           pastedImageAttachment(from: .general) != nil {
            paste(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        switch pastedImageAttachment(from: .general) {
        case let .success(attachment):
            imagePasteAction?(attachment)
            return
        case let .failure(message):
            imagePasteErrorAction?(message)
            return
        case .none:
            super.paste(sender)
        }
    }
}

private struct SessionPromptCardView: View {
    let card: HermesPromptCard
    let isDisabled: Bool
    let onRespond: (HermesPromptCard, HermesPromptResponse) async -> Void

    @State private var draft = ""
    @State private var isSubmitting = false

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName)
                        .foregroundStyle(iconColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.title)
                            .font(.subheadline.weight(.semibold))

                        if !card.message.isEmpty {
                            Text(card.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }

                    Spacer()
                }

                if card.toolName != nil || card.actionText != nil || card.previewText != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        if let toolName = card.toolName {
                            promptContextRow(label: L10n.string("Tool"), value: toolName, isMonospaced: false)
                        }

                        if let actionText = card.actionText {
                            promptContextRow(label: L10n.string("Action"), value: actionText, isMonospaced: false)
                        }

                        if let previewText = card.previewText {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.string("Preview"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ScrollView {
                                    Text(previewText)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                }
                                .frame(maxHeight: 120)
                                .background(HermesTheme.insetFill, in: RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                                        .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
                                }
                            }
                        }
                    }
                }

                switch card.kind {
                case .approval:
                    HStack(spacing: 8) {
                        Button(L10n.string("Approve")) {
                            submitApproval(true)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDisabled || isSubmitting)

                        Button(L10n.string("Deny")) {
                            submitApproval(false)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDisabled || isSubmitting)
                    }
                case .clarify, .sudo, .secret:
                    HStack(spacing: 8) {
                        inputField

                        Button(L10n.string("Send")) {
                            submitText()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDisabled || isSubmitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func promptContextRow(label: String, value: String, isMonospaced: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(isMonospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var inputField: some View {
        if card.kind == .clarify {
            TextField(card.placeholder ?? L10n.string("Reply"), text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled || isSubmitting)
        } else {
            SecureField(card.placeholder ?? L10n.string("Required"), text: $draft)
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled || isSubmitting)
        }
    }

    private var iconName: String {
        switch card.kind {
        case .approval:
            return "checkmark.shield"
        case .clarify:
            return "text.bubble"
        case .sudo:
            return "lock.shield"
        case .secret:
            return "key.horizontal"
        }
    }

    private var iconColor: Color {
        switch card.kind {
        case .approval:
            return .orange
        case .clarify:
            return .blue
        case .sudo, .secret:
            return .purple
        }
    }

    private func submitApproval(_ approved: Bool) {
        guard !isDisabled, !isSubmitting else { return }
        isSubmitting = true
        Task {
            await onRespond(card, .approval(approved))
            await MainActor.run {
                isSubmitting = false
            }
        }
    }

    private func submitText() {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty, !isDisabled, !isSubmitting else { return }
        isSubmitting = true
        Task {
            await onRespond(card, .text(trimmedDraft))
            await MainActor.run {
                draft = ""
                isSubmitting = false
            }
        }
    }
}

private struct SessionCompactionNoticeView: View {
    let notice: SessionCompactionNotice

    var body: some View {
        HermesInsetSurface {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Conversation compacted"))
                        .font(.subheadline.weight(.semibold))

                    Text(L10n.string("Hermes compacted this conversation into a new session. This session is now closed. Open the new session from the history list to continue."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(notice.sourceSessionID) -> \(notice.targetSessionID)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct SessionToolActivityTickerView: View {
    let card: HermesToolActivityCard

    var body: some View {
        HermesInsetSurface {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: 28, height: 28)

                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(card.detail ?? card.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
    }

    private var normalizedStatus: String {
        card.status.lowercased()
    }

    private var tint: Color {
        if card.isRunning {
            return .orange
        }
        if normalizedStatus.contains("error") || normalizedStatus.contains("fail") {
            return .red
        }
        return Color(red: 0.0, green: 0.58, blue: 0.22)
    }

    private var iconName: String {
        if card.isRunning {
            return "hammer.circle.fill"
        }
        if normalizedStatus.contains("error") || normalizedStatus.contains("fail") {
            return "xmark.circle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var statusLabel: String {
        if card.isRunning {
            return L10n.string("Running")
        }
        if normalizedStatus.contains("error") || normalizedStatus.contains("fail") {
            return L10n.string("Error")
        }
        return L10n.string("Done")
    }
}

private struct SessionToolActivityCardView: View {
    let card: HermesToolActivityCard

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: card.isRunning ? "hammer.circle.fill" : "hammer.circle")
                        .foregroundStyle(card.isRunning ? Color.accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                            .font(.subheadline.weight(.semibold))

                        Text(card.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if card.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let detail = card.detail,
                   !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct PendingSessionTurnView: View {
    let turn: PendingSessionTurn
    let showPrompt: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showPrompt {
                PendingBubble(
                    title: "You",
                    icon: "person.crop.circle.fill",
                    content: turn.prompt,
                    tint: .green
                )
            }

            HermesInsetSurface {
                HStack(alignment: .center, spacing: 12) {
                    ProgressView()
                        .controlSize(.small)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(L10n.string("Agent is working"))
                                .font(.subheadline.weight(.semibold))

                            if turn.autoApproveCommands {
                                HermesBadge(text: "Auto-approve", tint: .orange)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PendingBubble: View {
    let title: String
    let icon: String
    let content: String
    let tint: Color

    var body: some View {
        ChatMessageSurface(tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)

                    Text(L10n.string(title))
                        .font(.subheadline.weight(.semibold))

                    Spacer()
                }

                Text(content)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ChatMessageSurface<Content: View>: View {
    let tint: Color
    let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                    .fill(HermesTheme.rowFill)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(tint.opacity(0.62))
                    .frame(width: 2)
                    .padding(.vertical, 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                    .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
            }
    }
}

private struct MessageCard: View {
    let message: SessionMessageDisplay
    @Binding var isShowingMetadata: Bool

    var body: some View {
        if message.isToolMessage {
            ToolMessageCard(
                message: message,
                isShowingMetadata: $isShowingMetadata
            )
        } else {
            ConversationMessageCard(
                message: message,
                isShowingMetadata: $isShowingMetadata
            )
        }
    }
}

private struct ConversationMessageCard: View {
    let message: SessionMessageDisplay
    @Binding var isShowingMetadata: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUserMessage {
                Spacer(minLength: 80)
            }

            messageSurface
                .frame(
                    maxWidth: isUserMessage ? 680 : .infinity,
                    alignment: isUserMessage ? .trailing : .leading
                )

            if !isUserMessage {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUserMessage ? .trailing : .leading)
    }

    private var messageSurface: some View {
        ChatMessageSurface(tint: roleTint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    RoleAvatar(role: message.role, tint: roleTint)

                    HermesBadge(
                        text: displayRole,
                        tint: roleTint,
                        systemImage: roleSystemImage,
                        isMonospaced: false
                    )

                    Spacer()

                    if let timestampText = message.timestampText {
                        Text(timestampText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let content = message.content, !content.isEmpty {
                    Text(message.isStreaming ? content + "▍" : content)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if message.isStreaming && message.role == .assistant {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text(L10n.string("Hermes is thinking…"))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(L10n.string("No text payload"))
                        .foregroundStyle(.secondary)
                        .italic()
                }

                if !message.metadataItems.isEmpty {
                    MetadataDisclosureView(
                        items: message.metadataItems,
                        isShowingMetadata: $isShowingMetadata
                    )
                }
            }
        }
    }

    private var isUserMessage: Bool {
        message.role == .user
    }

    private var displayRole: String {
        message.role.displayTitle
    }

    private var roleTint: Color {
        switch message.role {
        case .assistant:
            return .blue
        case .user:
            return .cyan
        case .system:
            return .orange
        case .event, .custom:
            return .secondary
        }
    }

    private var roleSystemImage: String? {
        switch message.role {
        case .assistant:
            return nil
        case .user:
            return "person.fill"
        case .system:
            return "gearshape.fill"
        case .event, .custom:
            return nil
        }
    }
}

private enum HermesDesktopResourceBundle {
    static let module: Bundle? = {
        let bundleName = "HermesDesktop_HermesDesktop.bundle"
        let candidates: [URL?] = [
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
        ]

        for candidate in candidates {
            guard let candidate, let bundle = Bundle(url: candidate) else { continue }
            return bundle
        }

        return nil
    }()
}

private struct RoleAvatar: View {
    let role: SessionMessageRole
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))

            avatarContent
        }
        .frame(width: 28, height: 28)
        .overlay {
            Circle()
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatarContent: some View {
        switch role {
        case .assistant:
            if let bundle = HermesDesktopResourceBundle.module,
               bundle.url(forResource: "CaelProfile", withExtension: "png") != nil {
                Image("CaelProfile", bundle: bundle)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
        case .user:
            Image(systemName: "person.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        case .system:
            Image(systemName: "gearshape.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        case .event, .custom:
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
    }
}

private struct ToolMessageCard: View {
    let message: SessionMessageDisplay
    @Binding var isShowingMetadata: Bool
    @State private var isExpanded = false

    private var summary: SessionToolMessageSummary? {
        message.toolSummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolHeader

            if isExpanded {
                ToolOutputView(content: message.content, summary: summary)

                if !message.metadataItems.isEmpty {
                    MetadataDisclosureView(
                        items: message.metadataItems,
                        isShowingMetadata: $isShowingMetadata
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(HermesTheme.rowFill)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(statusTint.opacity(0.72))
                .frame(width: 2)
                .padding(.vertical, 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.13), lineWidth: 1)
        }
    }

    private var toolHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                HermesBadge(
                    text: L10n.string("Tool"),
                    tint: .secondary,
                    systemImage: "wrench.and.screwdriver.fill",
                    isMonospaced: false
                )

                if let summary,
                   let statusText = summary.statusText {
                    HermesBadge(
                        text: statusText,
                        tint: statusTint,
                        systemImage: statusSystemImage,
                        prominence: statusProminence,
                        isMonospaced: false
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary?.title ?? L10n.string("Tool output"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(summaryPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                if let sizeText = summary?.sizeText {
                    Text(sizeText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(L10n.string(isExpanded ? "Hide details" : "Details"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var summaryPreview: String {
        if let preview = summary?.preview, !preview.isEmpty {
            return preview
        }

        return L10n.string("No output preview")
    }

    private var statusTint: Color {
        switch summary?.statusKind {
        case .success:
            return Color(red: 0.0, green: 0.58, blue: 0.22)
        case .failure:
            return .red
        case .neutral, .none:
            return .secondary
        }
    }

    private var statusSystemImage: String? {
        switch summary?.statusKind {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.octagon.fill"
        case .neutral, .none:
            return nil
        }
    }

    private var statusProminence: HermesBadge.BadgeProminence {
        switch summary?.statusKind {
        case .success, .failure:
            return .strong
        case .neutral, .none:
            return .subtle
        }
    }
}

private struct ToolOutputView: View {
    let content: String?
    let summary: SessionToolMessageSummary?
    @State private var isShowingFullOutput = false

    private var visibleContent: String? {
        guard isShowingFullOutput else {
            return SessionToolMessageSummary.detailPreview(from: content)
        }

        return content
    }

    private var isTruncated: Bool {
        summary?.isDetailPreviewTruncated == true && !isShowingFullOutput
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let visibleContent, !visibleContent.isEmpty {
                ScrollView {
                    Text(visibleContent)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: isShowingFullOutput ? 280 : 180)
                .background(HermesTheme.insetFill, in: RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                        .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
                }
            } else {
                Text(L10n.string("No text payload"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            if isTruncated {
                Button {
                    isShowingFullOutput = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text(L10n.string("Show full output"))
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help(L10n.string("Render the full tool output on demand"))
            }
        }
    }
}

private struct MetadataDisclosureView: View {
    let items: [SessionMetadataDisplayItem]
    @Binding var isShowingMetadata: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isShowingMetadata.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isShowingMetadata ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    Text(L10n.string("Metadata"))
                        .font(.caption.weight(.semibold))

                    Text("(\(items.count))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if isShowingMetadata {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        MetadataItemView(item: item)
                    }
                }
            }
        }
    }
}

private struct MetadataItemView: View {
    let item: SessionMetadataDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(item.displayValue)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }
}

private extension Array where Element == SessionMessageDisplay {
    func containsUserPrompt(_ prompt: String) -> Bool {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else { return false }

        return contains { message in
            guard message.role == .user,
                  let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return content == normalizedPrompt
        }
    }
}
