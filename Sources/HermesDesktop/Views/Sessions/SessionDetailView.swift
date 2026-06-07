import AppKit
import SwiftUI

private let sessionDetailBottomID = "session-detail-bottom"

private func sessionMessageScrollID(_ message: SessionMessageDisplay) -> String {
    "session-message-\(message.id)"
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
    let isDeletingSession: Bool
    let isSessionPinned: Bool
    let sessionCompactionNotice: SessionCompactionNotice?
    let mode: SessionDetailMode
    let terminal: SessionTUITerminal?
    let terminalTheme: TerminalThemePreference
    let terminalAppearance: TerminalThemeAppearance
    let terminalFontSize: Double
    let isActive: Bool
    let savedScrollOffset: CGFloat?
    let onSaveScrollOffset: (String, CGFloat?) -> Void
    let onResumeInTerminal: (SessionSummary) -> Void
    let onDeleteSession: (SessionSummary) async -> Void
    let onToggleSessionPin: (SessionSummary) -> Void
    let onModeChange: (SessionDetailMode) -> Void
    let onStartChat: () -> Void
    let onUpdateTerminalTheme: (TerminalThemePreference) -> Void
    let onUpdateTerminalFontSize: (Double) -> Void
    let onTerminalExitRefresh: () async -> Void

    @State private var showDeleteConfirmation = false
    @State private var isShowingChatAppearanceEditor = false
    @State private var scrollRequest = SessionScrollRequest()
    @State private var expandedMetadataMessageIDs: Set<String> = []
    @State private var scrollMetrics = SessionScrollMetrics()
    @State private var scrollOffsetRestoreRequestID = UUID()
    @State private var shouldAutoScrollNextMessageLoad = true

    private var latestMessageScrollKey: String {
        "\(messages.count):\(messages.last?.id ?? "none")"
    }

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar

            Divider()

            if mode == .transcript {
                transcriptMode
            } else {
                chatMode
            }
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                detailToolbarSummary

                Picker("", selection: modeBinding) {
                    Text(L10n.string("Transcript")).tag(SessionDetailMode.transcript)
                    Text(L10n.string("Chat")).tag(SessionDetailMode.chat)
                }
                .pickerStyle(.segmented)
                .frame(width: 196)
            }

            VStack(alignment: .leading, spacing: 8) {
                detailToolbarSummary

                Picker("", selection: modeBinding) {
                    Text(L10n.string("Transcript")).tag(SessionDetailMode.transcript)
                    Text(L10n.string("Chat")).tag(SessionDetailMode.chat)
                }
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.bar)
    }

    @ViewBuilder
    private var detailToolbarSummary: some View {
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
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("New Chat"))
                    .font(.headline.weight(.semibold))

                Text(newChatSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modeBinding: Binding<SessionDetailMode> {
        Binding {
            mode
        } set: { newValue in
            onModeChange(newValue)
        }
    }

    private var terminalThemeBinding: Binding<TerminalThemePreference> {
        Binding {
            terminalTheme
        } set: { newValue in
            onUpdateTerminalTheme(newValue)
        }
    }

    private var terminalFontSizeBinding: Binding<Double> {
        Binding {
            terminalFontSize
        } set: { newValue in
            onUpdateTerminalFontSize(newValue)
        }
    }

    private var newChatSubtitle: String {
        guard let connection else {
            return L10n.string("Select an SSH host to start a live Hermes TUI.")
        }
        return "\(connection.label) - \(connection.displayDestination) - \(connection.resolvedHermesProfileName)"
    }

    private var transcriptMode: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    transcriptScrollContent

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
                guard session != nil, !messages.isEmpty else { return }
                handleMessageScrollChange(proxy)
            }
            .task(id: session?.id) {
                restoreSavedScrollOffsetOrScrollToLatest(proxy)
            }
        }
    }

    @ViewBuilder
    private var transcriptScrollContent: some View {
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

            transcriptContent(for: session)
        } else {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Start or select a session"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(L10n.string("Use New Chat to start the real Hermes TUI, or choose an existing session to inspect its stored transcript."))
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
    }

    @ViewBuilder
    private func transcriptContent(for session: SessionSummary) -> some View {
        if messages.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No transcript entries"),
                    systemImage: "text.bubble",
                    description: Text(L10n.string("This session has no readable message rows yet."))
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        } else {
            HermesSurfacePanel(
                title: "Transcript",
                subtitle: "Messages are shown in the order Hermes stored them for this session."
            ) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        MessageCard(
                            message: message,
                            isShowingMetadata: metadataExpansionBinding(for: message.id)
                        )
                        .id(sessionMessageScrollID(message))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chatMode: some View {
        if let terminal, terminalMatchesCurrentSelection(terminal) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: terminal.terminalSession.isRunning ? "terminal.fill" : "terminal")
                        .foregroundStyle(terminal.terminalSession.isRunning ? Color.green : Color.secondary)

                    Text(L10n.string(terminal.targetLabel))
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    TerminalAppearanceToolbarButton(
                        appearance: terminalAppearance,
                        isPresented: $isShowingChatAppearanceEditor,
                        themePreference: terminalThemeBinding,
                        fontSize: terminalFontSizeBinding
                    )

                    if let exitCode = terminal.terminalSession.exitCode {
                        HermesBadge(text: L10n.string("Exited %@", "\(exitCode)"), tint: exitCode == 0 ? .secondary : .orange)
                    } else if terminal.terminalSession.isRunning {
                        HermesBadge(text: L10n.string("Running"), tint: Color(red: 0.0, green: 0.58, blue: 0.22))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(HermesTheme.rowFill)

                SwiftTermTerminalView(
                    session: terminal.terminalSession,
                    appearance: terminalAppearance,
                    fontSize: terminalFontSize,
                    isActive: isActive && mode == .chat
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: terminal.terminalSession.exitCode) { _, _ in
                Task { await onTerminalExitRefresh() }
            }
        } else {
            sessionChatPlaceholder
        }
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
        return L10n.string("Hermes TUI will create the next session on the host; refresh Sessions after it exits or when you return to Transcript.")
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
              hasLatestTranscriptTarget,
              !scrollRequest.isPending else {
            return false
        }

        return scrollMetrics.distanceToBottom > 96
    }

    private var hasLatestTranscriptTarget: Bool {
        !messages.isEmpty
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
        if let lastMessage = messages.last {
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

private struct SessionSummaryPanel: View {
    let session: SessionSummary
    let isDeleting: Bool
    let isPinned: Bool
    let onOpenInTerminal: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.resolvedTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    if let model = session.displayModel {
                        HermesBadge(text: model, tint: .orange)
                    }

                    if let count = session.messageCount {
                        HermesBadge(text: L10n.string("%@ messages", "\(count)"), tint: .accentColor)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        sessionIDLabel
                        metadataLine
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        sessionIDLabel
                        metadataLine
                    }
                }
            }

            Spacer(minLength: 8)

            actionsMenu
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionIDLabel: some View {
        Text(session.id)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .contextMenu {
                Button(L10n.string("Copy Session ID")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.id, forType: .string)
                }
            }
    }

    @ViewBuilder
    private var metadataLine: some View {
        if !sessionMetadataItems.isEmpty {
            HStack(spacing: 8) {
                ForEach(sessionMetadataItems, id: \.0) { item in
                    HStack(spacing: 4) {
                        Text(L10n.string(item.0))
                            .fontWeight(.semibold)

                        Text(item.1)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var actionsMenu: some View {
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

    private var sessionMetadataItems: [(String, String)] {
        var items: [(String, String)] = []

        if let startedAt = session.startedAt?.dateValue {
            items.append((
                "Started",
                DateFormatters.shortDateTimeFormatter().string(from: startedAt)
            ))
        }

        if let lastActive = session.lastActive?.dateValue {
            items.append((
                "Active",
                DateFormatters.shortDateTimeFormatter().string(from: lastActive)
            ))
        }

        return items
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

private struct TranscriptMessageSurface<Content: View>: View {
    let tint: Color
    let content: Content

    @Environment(\.backgroundImageActive) private var backgroundImageActive

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
                    .fill(backgroundImageActive ? AnyShapeStyle(HermesTheme.rowFill.opacity(0.45)) : AnyShapeStyle(HermesTheme.rowFill))
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
        TranscriptMessageSurface(tint: roleTint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
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
            return "sparkles"
        case .user:
            return "person.fill"
        case .system:
            return "gearshape.fill"
        case .event, .custom:
            return nil
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
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
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

    @Environment(\.backgroundImageActive) private var backgroundImageActive

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
                .background(
                    backgroundImageActive ? AnyShapeStyle(HermesTheme.insetFill.opacity(0.45)) : AnyShapeStyle(HermesTheme.insetFill),
                    in: RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                )
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
