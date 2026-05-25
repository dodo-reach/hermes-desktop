import SwiftUI

struct TerminalWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var workspace: TerminalWorkspaceStore
    let context: TerminalWorkspaceContext
    let ensureTerminalSession: () -> Void
    let updateTerminalTheme: (TerminalThemePreference) -> Void
    @State private var isShowingAppearanceEditor = false
    @State private var isShowingAttachSheet = false
    @State private var attachSessionID = ""
    @State private var availableTerminalSessions: [WorkspaceTerminalSessionSummary] = []
    @State private var isLoadingTerminalSessions = false
    @State private var terminalSessionsError: String?
    private let tabStripHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                if !workspace.tabs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(workspace.tabs) { tab in
                                TerminalTabChip(
                                    profileName: tab.session.connection.resolvedHermesProfileName,
                                    hostLabel: tab.session.connection.label,
                                    modeLabel: tab.session.backendLabel,
                                    isWorkspacePTY: tab.session.isWorkspacePTY,
                                    isSelected: workspace.selectedTabID == tab.id,
                                    isCurrentWorkspace: isTabForActiveWorkspace(tab),
                                    onSelect: { requestTabSelection(tab.id) },
                                    onClose: { requestTabClose(tab) }
                                )
                                .frame(width: 190)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: tabStripHeight)
                    .layoutPriority(1)
                }

                if let activeConnection = context.activeConnection {
                    Button {
                        requestNewTab(for: activeConnection)
                    } label: {
                        Label(L10n.string("New Tab"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        requestSharedTab(for: activeConnection)
                    } label: {
                        Label(L10n.string("Shared PTY"), systemImage: "network")
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.string("Open a Workspace-backed terminal session that can share the web/mobile terminal contract."))

                    Button {
                        attachSessionID = ""
                        isShowingAttachSheet = true
                    } label: {
                        Label(L10n.string("Attach PTY"), systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.string("Attach to an existing Workspace terminal session ID from web or mobile."))
                }

                Spacer(minLength: 8)

                TerminalAppearanceToolbarButton(
                    appearance: terminalAppearance,
                    isPresented: $isShowingAppearanceEditor,
                    themePreference: terminalThemeBinding
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(height: tabStripHeight + 12)
            .background(.thinMaterial)

            if let selectedTab = workspace.selectedTab {
                TerminalTabContainer(
                    session: selectedTab.session,
                    appearance: terminalAppearance,
                    isActive: context.isTerminalSectionActive,
                    activeWorkspaceScopeFingerprint: context.activeWorkspaceScopeFingerprint
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    L10n.string("No terminal tab"),
                    systemImage: "terminal",
                    description: Text(L10n.string("Create a native SSH tab or a shared Workspace PTY tab for the active host."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: context.activeConnection?.id) {
            if context.isTerminalSectionActive {
                ensureTerminalSession()
            }
        }
        .onChange(of: context.isTerminalSectionActive) { _, isActive in
            if isActive {
                ensureTerminalSession()
            }
        }
        .sheet(isPresented: $isShowingAttachSheet) {
            attachWorkspacePTYSheet
        }
    }

    private var attachWorkspacePTYSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Attach Shared PTY"))
                        .font(.title3.weight(.semibold))
                    Text(L10n.string("Attach to a live Workspace terminal session from web or mobile, or paste a session ID manually."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    Task { await loadAvailableTerminalSessions() }
                } label: {
                    Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingTerminalSessions || context.activeConnection == nil)
            }

            terminalSessionPicker

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Manual session ID"))
                    .font(.headline)
                TextField(L10n.string("Session ID"), text: $attachSessionID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { attachWorkspacePTY() }
            }

            HStack {
                Spacer()
                Button(L10n.string("Cancel")) {
                    isShowingAttachSheet = false
                }
                Button(L10n.string("Attach")) {
                    attachWorkspacePTY()
                }
                .buttonStyle(.borderedProminent)
                .disabled(attachSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || context.activeConnection == nil)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
        .task {
            await loadAvailableTerminalSessions()
        }
    }

    private var terminalSessionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Live Workspace sessions"))
                .font(.headline)

            if isLoadingTerminalSessions {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("Loading sessions..."))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            } else if let terminalSessionsError {
                ContentUnavailableView(
                    L10n.string("Could not load sessions"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(terminalSessionsError)
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else if availableTerminalSessions.isEmpty {
                ContentUnavailableView(
                    L10n.string("No live Workspace PTYs"),
                    systemImage: "terminal",
                    description: Text(L10n.string("Open a Shared PTY tab in desktop or web, then refresh this list."))
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(availableTerminalSessions) { session in
                            terminalSessionRow(session)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 210)
            }
        }
    }

    private func terminalSessionRow(_ session: WorkspaceTerminalSessionSummary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "terminal")
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(terminalSessionTitle(session))
                    .font(.system(.body, design: terminalSessionHasLabel(session) ? .default : .monospaced).weight(.semibold))
                    .lineLimit(1)

                Text(terminalSessionSubtitle(session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(terminalSessionCreatedLabel(session))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(L10n.string("Attach")) {
                attachWorkspacePTY(sessionID: session.id)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var terminalAppearance: TerminalThemeAppearance {
        context.terminalTheme.resolvedAppearance
    }

    private var terminalThemeBinding: Binding<TerminalThemePreference> {
        Binding {
            context.terminalTheme
        } set: { newValue in
            updateTerminalTheme(newValue)
        }
    }

    private func isTabForActiveWorkspace(_ tab: TerminalTabModel) -> Bool {
        guard let activeConnection = context.activeConnection else { return true }
        return tab.workspaceScopeFingerprint == activeConnection.workspaceScopeFingerprint
    }

    private func requestNewTab(for connection: ConnectionProfile) {
        DispatchQueue.main.async {
            workspace.addTab(for: connection.updated())
        }
    }

    private func requestSharedTab(for connection: ConnectionProfile) {
        DispatchQueue.main.async {
            workspace.addWorkspaceTerminalTab(for: connection.updated())
        }
    }

    private func loadAvailableTerminalSessions() async {
        guard let connection = context.activeConnection else { return }
        isLoadingTerminalSessions = true
        terminalSessionsError = nil
        do {
            let response = try await appState.caelWorkspaceAPIService.loadWorkspaceTerminalSessions(connection: connection)
            availableTerminalSessions = response.sessions
            terminalSessionsError = response.ok == false ? response.error : nil
        } catch {
            availableTerminalSessions = []
            terminalSessionsError = error.localizedDescription
        }
        isLoadingTerminalSessions = false
    }

    private func attachWorkspacePTY() {
        let sessionID = attachSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        attachWorkspacePTY(sessionID: sessionID)
    }

    private func attachWorkspacePTY(sessionID: String) {
        guard let connection = context.activeConnection else { return }
        guard !sessionID.isEmpty else { return }
        DispatchQueue.main.async {
            workspace.addWorkspaceTerminalTab(for: connection.updated(), sessionId: sessionID)
            isShowingAttachSheet = false
            attachSessionID = ""
        }
    }

    private func shortTerminalSessionID(_ sessionID: String) -> String {
        if sessionID.count <= 12 { return sessionID }
        return String(sessionID.prefix(8)) + "..." + String(sessionID.suffix(4))
    }

    private func terminalSessionTitle(_ session: WorkspaceTerminalSessionSummary) -> String {
        let label = session.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return label?.isEmpty == false ? (label ?? "") : shortTerminalSessionID(session.id)
    }

    private func terminalSessionHasLabel(_ session: WorkspaceTerminalSessionSummary) -> Bool {
        let label = session.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return label?.isEmpty == false
    }

    private func terminalSessionSubtitle(_ session: WorkspaceTerminalSessionSummary) -> String {
        let command = session.command.joined(separator: " ")
        let cwd = session.cwd ?? "unknown cwd"
        let size = "\(session.cols ?? 0)x\(session.rows ?? 0)"
        return "\(shortTerminalSessionID(session.id)) - \(command.isEmpty ? "shell" : command) - \(cwd) - \(size)"
    }

    private func terminalSessionCreatedLabel(_ session: WorkspaceTerminalSessionSummary) -> String {
        let date = Date(timeIntervalSince1970: session.createdAt / 1000)
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func requestTabSelection(_ tabID: UUID) {
        DispatchQueue.main.async {
            workspace.selectTab(tabID)
        }
    }

    private func requestTabClose(_ tab: TerminalTabModel) {
        DispatchQueue.main.async {
            workspace.closeTab(tab)
        }
    }
}

private struct TerminalTabChip: View {
    let profileName: String
    let hostLabel: String
    let modeLabel: String
    let isWorkspacePTY: Bool
    let isSelected: Bool
    let isCurrentWorkspace: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(profileName)
                                .font(profileFont)
                                .lineLimit(1)

                            if !isCurrentWorkspace {
                                HermesBadge(text: "Other Profile", tint: .orange)
                            } else if isWorkspacePTY {
                                HermesBadge(text: modeLabel, tint: .blue)
                            }
                        }

                        Text(hostLabel)
                            .font(hostFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: closeButtonReserveWidth)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Close tab"))
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(height: 38)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    private var backgroundColor: Color {
        if !isCurrentWorkspace {
            return isSelected ? Color.orange.opacity(0.20) : Color.orange.opacity(0.10)
        }

        return isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)
    }

    private var borderColor: Color {
        if !isCurrentWorkspace {
            return Color.orange.opacity(isSelected ? 0.40 : 0.18)
        }

        return Color.primary.opacity(isSelected ? 0.12 : 0.06)
    }

    private var profileFont: Font {
        isCurrentWorkspace ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }

    private var hostFont: Font {
        .caption2
    }

    private var horizontalPadding: CGFloat {
        isCurrentWorkspace ? 10 : 8
    }

    private var verticalPadding: CGFloat {
        isCurrentWorkspace ? 5 : 4
    }

    private var closeButtonReserveWidth: CGFloat {
        22
    }
}

struct TerminalAppearanceToolbarButton: View {
    let appearance: TerminalThemeAppearance
    @Binding var isPresented: Bool
    @Binding var themePreference: TerminalThemePreference

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                ThemeSwatch(backgroundColor: appearance.backgroundColor.swiftUIColor, foregroundColor: appearance.foregroundColor.swiftUIColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("Theme"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(L10n.string(appearance.name))
                        .font(.subheadline.weight(.semibold))
                }

                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(height: 38)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            TerminalAppearanceEditor(themePreference: $themePreference)
        }
        .help(L10n.string("Customize terminal colors"))
    }
}

private struct TerminalAppearanceEditor: View {
    @Binding var themePreference: TerminalThemePreference
    @State private var customTarget = TerminalColorTarget.background
    @State private var draftBackgroundColor = TerminalThemeColor(hex: 0x12161D)
    @State private var draftForegroundColor = TerminalThemeColor(hex: 0xE7ECF3)

    private let presetColumns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7)
    ]

    var body: some View {
        let appearance = themePreference.resolvedAppearance

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Terminal Theme"))
                    .font(.title3.weight(.semibold))

                Text(L10n.string("Pick a preset for a coherent terminal look, then fine-tune background and text colors live if you want."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TerminalThemePreviewCard(appearance: appearance)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.string("Quick Presets"))
                        .font(.headline)

                    Spacer()

                    Button(L10n.string("Use System")) {
                        themePreference = .defaultValue
                    }
                    .buttonStyle(.borderless)
                }

                LazyVGrid(columns: presetColumns, spacing: 7) {
                    ForEach(TerminalThemePreference.quickPresets) { preset in
                        Button {
                            themePreference = themePreference.selectingPreset(preset.style)
                        } label: {
                            TerminalPresetCard(
                                preset: preset,
                                isSelected: themePreference.style == preset.style && !appearance.isCustom
                            )
                        }
                        .buttonStyle(.plain)
                        .help(L10n.string(preset.summary))
                    }
                }
            }

            HermesInsetSurface {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(L10n.string("Custom Colors"))
                            .font(.headline)

                        Spacer()
                    }

                    HStack(spacing: 12) {
                        TerminalCustomColorPreviewButton(
                            label: "Background",
                            color: draftBackgroundColor,
                            isSelected: customTarget == .background
                        ) {
                            customTarget = .background
                        }

                        TerminalCustomColorPreviewButton(
                            label: "Text",
                            color: draftForegroundColor,
                            isSelected: customTarget == .foreground
                        ) {
                            customTarget = .foreground
                        }
                    }

                    TerminalColorMatrixPicker(selection: customSelectionBinding)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Text(selectedCustomColor.hexString)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(L10n.string("Set Custom")) {
                            themePreference = themePreference.settingCustomColors(
                                backgroundColor: draftBackgroundColor,
                                foregroundColor: draftForegroundColor
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 400)
        .onAppear {
            resetCustomDraft(from: appearance)
        }
        .onChange(of: themePreference) { _, newValue in
            resetCustomDraft(from: newValue.resolvedAppearance)
        }
    }

    private var customSelectionBinding: Binding<TerminalThemeColor> {
        Binding {
            selectedCustomColor
        } set: { newValue in
            switch customTarget {
            case .background:
                draftBackgroundColor = newValue
            case .foreground:
                draftForegroundColor = newValue
            }
        }
    }

    private var selectedCustomColor: TerminalThemeColor {
        switch customTarget {
        case .background:
            return draftBackgroundColor
        case .foreground:
            return draftForegroundColor
        }
    }

    private func resetCustomDraft(from appearance: TerminalThemeAppearance) {
        draftBackgroundColor = appearance.backgroundColor
        draftForegroundColor = appearance.foregroundColor
    }
}

private struct TerminalThemePreviewCard: View {
    let appearance: TerminalThemeAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("Preview"))
                    .font(.headline)

                Spacer()

                ThemeSwatch(
                    backgroundColor: appearance.backgroundColor.swiftUIColor,
                    foregroundColor: appearance.foregroundColor.swiftUIColor
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("hermes@host:~/workspace$")
                    .foregroundStyle(appearance.foregroundColor.swiftUIColor.opacity(0.72))

                Text("git status")
                    .foregroundStyle(appearance.foregroundColor.swiftUIColor)

                HStack(spacing: 8) {
                    Text("main")
                        .foregroundStyle(appearance.ansiPalette[4].swiftUIColor)
                    Text("clean")
                        .foregroundStyle(appearance.ansiPalette[2].swiftUIColor)
                    Text("ssh")
                        .foregroundStyle(appearance.ansiPalette[6].swiftUIColor)
                }
                .font(.caption.weight(.semibold))
            }
            .font(.system(.body, design: .monospaced))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(appearance.backgroundColor.swiftUIColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(appearance.foregroundColor.swiftUIColor.opacity(0.12), lineWidth: 1)
            }
        }
    }
}

private struct TerminalPresetCard: View {
    let preset: TerminalThemePreset
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemeSwatch(
                backgroundColor: preset.backgroundColor.swiftUIColor,
                foregroundColor: preset.foregroundColor.swiftUIColor
            )

            HStack(spacing: 6) {
                Text(L10n.string(preset.name))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
    }
}

private enum TerminalColorTarget: String, CaseIterable, Identifiable {
    case background
    case foreground

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .background:
            return "Background"
        case .foreground:
            return "Text"
        }
    }
}

private struct TerminalCustomColorPreviewButton: View {
    let label: String
    let color: TerminalThemeColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.swiftUIColor)
                    .frame(width: 34, height: 34)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string(label))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(color.hexString)
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.62) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        }
        .help(L10n.string("Select %@ color", L10n.string(label)))
    }
}

private struct TerminalColorMatrixPicker: View {
    @Binding var selection: TerminalThemeColor

    private static let cellSize: CGFloat = 15
    private static let cellSpacing: CGFloat = 1
    private static let columnCount = TerminalColorMatrix.columnCount
    private static let rowCount = TerminalColorMatrix.rowCount
    private static let gridWidth = CGFloat(columnCount) * cellSize + CGFloat(columnCount - 1) * cellSpacing
    private static let gridHeight = CGFloat(rowCount) * cellSize + CGFloat(rowCount - 1) * cellSpacing

    private let columns = Array(
        repeating: GridItem(.fixed(Self.cellSize), spacing: Self.cellSpacing),
        count: Self.columnCount
    )
    private let colors = TerminalColorMatrix.palette

    var body: some View {
        LazyVGrid(columns: columns, spacing: Self.cellSpacing) {
            ForEach(colors, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    Rectangle()
                        .fill(color.swiftUIColor)
                        .frame(width: Self.cellSize, height: Self.cellSize)
                        .overlay {
                            if color == selection {
                                Rectangle()
                                    .strokeBorder(Color.white.opacity(0.88), lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help(color.hexString)
            }
        }
        .frame(width: Self.gridWidth, height: Self.gridHeight)
        .clipShape(RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }
}

private enum TerminalColorMatrix {
    static let columnCount = 20
    static let rowCount = 10
    static let palette: [TerminalThemeColor] = grayscaleRow + colorRows

    private static let colorRowCount = rowCount - 1
    private static let hues = [
        0.50, 0.54, 0.58, 0.62, 0.667,
        0.72, 0.78, 0.83, 0.88, 0.94,
        0.00, 0.03, 0.06, 0.10, 0.14,
        1.0 / 6.0, 0.20, 0.25, 0.333, 0.42
    ]
    private static let colorRowProfiles: [(saturation: Double, brightness: Double)] = [
        (0.90, 0.18),
        (1.00, 0.34),
        (0.92, 0.50),
        (1.00, 0.66),
        (0.96, 0.82),
        (1.00, 1.00),
        (0.76, 0.98),
        (0.52, 1.00),
        (0.28, 1.00)
    ]

    private static let grayscaleRow: [TerminalThemeColor] = (0..<columnCount).map { index in
        let brightness = 1 - Double(index) / Double(columnCount - 1)
        return TerminalThemeColor(red: brightness, green: brightness, blue: brightness)
    }

    private static let colorRows: [TerminalThemeColor] = {
        let rows = colorRowProfiles.prefix(colorRowCount).map { profile -> [TerminalThemeColor] in
            hues.prefix(columnCount).map { hue in
                TerminalThemeColor(
                    hue: hue,
                    saturation: profile.saturation,
                    brightness: profile.brightness
                )
            }
        }

        return rows.flatMap(\.self)
    }()
}

private struct ThemeSwatch: View {
    let backgroundColor: Color
    let foregroundColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)

            VStack(alignment: .leading, spacing: 3) {
                Capsule()
                    .fill(foregroundColor.opacity(0.85))
                    .frame(width: 18, height: 4)

                Capsule()
                    .fill(foregroundColor.opacity(0.55))
                    .frame(width: 12, height: 4)
            }
        }
        .frame(width: 32, height: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(foregroundColor.opacity(0.15), lineWidth: 1)
        }
    }
}
