import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ConnectionsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState

    @State private var editingConnection = ConnectionProfile()
    @State private var editorPresentationID = UUID()
    @State private var isPresentingEditor = false
    @State private var editingExistingConnection = false
    @State private var isPresentingProfiles = false
    @State private var inspectorTab: SettingsInspectorTab = .overview
    @State private var profilePendingDelete: RemoteHermesProfile?
    @State private var profilePendingStopTracking: RemoteHermesProfile?

    private let documentationURL = URL(string: "https://dodo-reach.github.io/hermes-desktop/")!

    var body: some View {
        HermesPageContainer(width: .dashboard) {
            VStack(alignment: .leading, spacing: 22) {
                HermesPageHeader(
                    title: "Settings",
                    subtitle: "Manage the active host connection, Hermes profile, and local app preferences."
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        settingsColumn
                            .frame(minWidth: 520, maxWidth: .infinity, alignment: .topLeading)

                        inspectorPanel
                            .frame(width: 430, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        settingsColumn
                        inspectorPanel
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isPresentingEditor) {
            ConnectionEditorSheet(
                connection: editingConnection,
                isEditing: editingExistingConnection
            ) { updatedConnection in
                appState.saveConnection(updatedConnection)
            }
            .id(editorPresentationID)
        }
        .sheet(isPresented: $isPresentingProfiles) {
            ManageProfilesSheet(
                profiles: allDiscoveredProfiles,
                activeProfileName: appState.activeConnection?.resolvedHermesProfileName,
                hostConnectionFingerprint: appState.activeConnection?.hostConnectionFingerprint,
                isBusy: appState.isBusy,
                isHidden: { profile in
                    guard let hostFingerprint = appState.activeConnection?.hostConnectionFingerprint else { return false }
                    return appState.connectionStore.isHermesProfileHidden(
                        name: profile.name,
                        hostConnectionFingerprint: hostFingerprint
                    )
                },
                onDelete: { profile in
                    profilePendingDelete = profile
                },
                onStopTracking: { profile in
                    profilePendingStopTracking = profile
                },
                onResumeTracking: { profile in
                    appState.resumeTrackingHermesProfile(profile)
                }
            )
        }
        .alert(
            L10n.string("Delete Hermes profile?"),
            isPresented: Binding(
                get: { profilePendingDelete != nil },
                set: { if !$0 { profilePendingDelete = nil } }
            )
        ) {
            Button(L10n.string("Delete Profile"), role: .destructive) {
                guard let profile = profilePendingDelete else { return }
                profilePendingDelete = nil
                Task {
                    await appState.deleteRemoteHermesProfile(profile)
                }
            }

            Button(L10n.string("Cancel"), role: .cancel) {
                profilePendingDelete = nil
            }
        } message: {
            Text(deleteProfileConfirmationMessage)
        }
        .alert(
            L10n.string("Stop tracking this profile?"),
            isPresented: Binding(
                get: { profilePendingStopTracking != nil },
                set: { if !$0 { profilePendingStopTracking = nil } }
            )
        ) {
            Button(L10n.string("Stop Tracking"), role: .destructive) {
                guard let profile = profilePendingStopTracking else { return }
                profilePendingStopTracking = nil
                Task {
                    await appState.stopTrackingHermesProfile(profile)
                }
            }

            Button(L10n.string("Cancel"), role: .cancel) {
                profilePendingStopTracking = nil
            }
        } message: {
            Text(L10n.string("Hermes Desktop will no longer track or display this profile. The profile will remain available on the host and can still be accessed via terminal."))
        }
        .onAppear {
            presentPendingNewConnectionEditorIfNeeded()
        }
        .task(id: appState.activeConnectionID) {
            guard appState.activeConnection != nil else { return }
            guard appState.overview == nil else { return }
            await appState.refreshOverview(manual: false)
        }
        .onChange(of: appState.pendingNewConnectionEditorRequestID) { _, _ in
            presentPendingNewConnectionEditorIfNeeded()
        }
    }

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            workspaceProfileCard
            preferencesCard
        }
    }

    private var workspaceProfileCard: some View {
        HermesSurfacePanel {
            SettingsCardHeader(
                systemImage: "person.crop.circle",
                title: "Workspace & Profile",
                subtitle: "Manage which Hermes profiles this Mac tracks on the active host.",
                badge: nil
            )

            if let activeConnection = appState.activeConnection {
                VStack(alignment: .leading, spacing: 14) {
                    HermesInspectorFieldList(
                        fields: workspaceFields(activeConnection),
                        labelWidth: 118
                    )

                    HStack(spacing: 10) {
                        Button {
                            isPresentingProfiles = true
                        } label: {
                            Label(L10n.string("Manage Profiles"), systemImage: "person.2")
                        }
                        .buttonStyle(.bordered)
                        .disabled(allDiscoveredProfiles.isEmpty)
                    }
                }
            } else {
                EmptySettingsState(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No active workspace",
                    message: "Profile settings appear after a host is connected."
                )
            }
        }
    }

    private var preferencesCard: some View {
        HermesSurfacePanel {
            SettingsCardHeader(
                systemImage: "slider.horizontal.3",
                title: "Preferences",
                subtitle: "Local settings saved on this Mac and applied at launch.",
                badge: nil
            )

            VStack(alignment: .leading, spacing: 16) {
                SettingsControlRow(title: "Theme", subtitle: "Choose the app appearance.") {
                    Picker("", selection: appAppearanceBinding) {
                        ForEach(AppAppearancePreference.allCases) { appearance in
                            Text(L10n.string(appearance.title))
                                .tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                Divider()

                SidebarCustomizationPanel(
                    sections: appState.connectionStore.sidebarSectionOrder,
                    isVisible: { appState.connectionStore.isSidebarSectionVisible($0) },
                    canMoveUp: canMoveSidebarSectionUp,
                    canMoveDown: canMoveSidebarSectionDown,
                    setVisible: { section, isVisible in
                        appState.connectionStore.setSidebarSection(section, isVisible: isVisible)
                    },
                    moveUp: { appState.connectionStore.moveSidebarSection($0, direction: .up) },
                    moveDown: { appState.connectionStore.moveSidebarSection($0, direction: .down) }
                )

                Divider()

                TerminalAppearanceEditor(
                    themePreference: terminalThemeBinding,
                    fontSize: terminalFontSizeBinding,
                    showsHeader: false,
                    fixedWidth: nil,
                    contentPadding: 0
                )

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("Background Image"))
                        .font(.headline)

                    Text(L10n.string("Choose an image to use as terminal background."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let imagePath = appState.connectionStore.backgroundImagePath,
                       let image = NSImage(contentsOfFile: imagePath) {
                        HStack(spacing: 10) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: imagePath).lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)

                                Button(L10n.string("Change Image…")) {
                                    chooseBackgroundImage()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                            }

                            Spacer()
                        }

                        Button(role: .destructive) {
                            appState.connectionStore.backgroundImagePath = nil
                        } label: {
                            Label(L10n.string("Clear Image"), systemImage: "xmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button(L10n.string("Choose Image…")) {
                            chooseBackgroundImage()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Divider()

                Toggle(
                    L10n.string("Check automatically for Hermes Desktop updates"),
                    isOn: Binding(
                        get: { appState.connectionStore.automaticallyChecksForUpdates },
                        set: { appState.updateAutomaticUpdateChecks($0) }
                    )
                )
                .toggleStyle(.checkbox)
            }
        }
    }

    private var inspectorPanel: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("Host Connection"))
                            .font(.title3.weight(.semibold))

                        Text(L10n.string("Detailed information about your host connection."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    connectionStatusBadge
                }

                if let activeConnection = appState.activeConnection {
                    VStack(alignment: .leading, spacing: 12) {
                        HermesInspectorFieldList(
                            fields: inspectorFields(activeConnection),
                            labelWidth: 112
                        )

                        hostManagementActions(activeConnection)
                    }
                } else {
                    EmptySettingsState(
                        systemImage: "network",
                        title: "Waiting for host",
                        message: "Add or select a host to see connection details."
                    ) {
                        Button {
                            presentEditor(for: ConnectionProfile(), isEditing: false)
                        } label: {
                            Label(L10n.string("Add Host"), systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Picker("", selection: $inspectorTab) {
                    ForEach(SettingsInspectorTab.allCases) { tab in
                        Text(L10n.string(tab.title)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch inspectorTab {
                case .overview:
                    inspectorOverview
                case .diagnostics:
                    diagnosticsOverview
                }

                helpFooter
            }
        }
    }

    private var inspectorOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HealthSummaryRow(
                isHealthy: appState.activeConnection != nil && appState.overviewError == nil,
                title: connectionHealthTitle,
                subtitle: connectionHealthSubtitle
            )

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("Next steps"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SettingsActionRow(
                    systemImage: "terminal",
                    title: "Open Terminal",
                    subtitle: "Start a host-first SSH shell.",
                    action: { appState.requestSectionSelection(.terminal) }
                )

                SettingsActionRow(
                    systemImage: "doc.text",
                    title: "Browse Files",
                    subtitle: "Explore files and directories on your host.",
                    action: { appState.requestSectionSelection(.files) }
                )

                SettingsActionRow(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "View Sessions",
                    subtitle: "See recent conversations and history.",
                    action: { appState.requestSectionSelection(.sessions) }
                )
            }

        }
    }

    private var diagnosticsOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let activeConnection = appState.activeConnection {
                diagnosticsActionBar(activeConnection)
            }

            if let overviewError = appState.overviewError {
                HealthSummaryRow(
                    isHealthy: false,
                    title: "Discovery failed",
                    subtitle: overviewError
                )
            } else if let overview = appState.overview {
                ForEach(diagnosticRows(for: overview)) { row in
                    HealthSummaryRow(isHealthy: row.isReady, title: row.title, subtitle: row.subtitle)
                }
            } else if appState.activeConnection == nil {
                HealthSummaryRow(
                    isHealthy: false,
                    title: "No host selected",
                    subtitle: "Add or select a host, then run diagnostics."
                )
            } else {
                HealthSummaryRow(
                    isHealthy: false,
                    title: "Diagnostics not run yet",
                    subtitle: "Press Run Diagnostics or Test Connection to check this host."
                )
            }
        }
    }

    private func diagnosticsActionBar(_ activeConnection: ConnectionProfile) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await appState.refreshOverview(manual: true)
                }
            } label: {
                Label(L10n.string("Run Diagnostics"), systemImage: "stethoscope")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(appState.isBusy || appState.isRefreshingOverview)

            Button {
                appState.testConnection(activeConnection)
            } label: {
                Label(L10n.string("Test Connection"), systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.isBusy)

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var helpFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            Button {
                openURL(documentationURL)
            } label: {
                Label(L10n.string("Need help? Check documentation"), systemImage: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
    }

    private func hostManagementActions(_ activeConnection: ConnectionProfile) -> some View {
        HermesInsetSurface {
            HStack(spacing: 8) {
                Label(L10n.string("Host Actions"), systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    presentEditor(for: activeConnection, isEditing: true)
                } label: {
                    Label(L10n.string("Edit"), systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                hostSelectionMenu

                Button {
                    presentEditor(for: ConnectionProfile(), isEditing: false)
                } label: {
                    Label(L10n.string("Add Host"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var hostSelectionMenu: some View {
        if appState.connectionStore.connections.count > 1 {
            Menu {
                ForEach(appState.connectionStore.connections) { connection in
                    Button {
                        appState.connect(to: connection)
                    } label: {
                        if appState.activeConnectionID == connection.id {
                            Label(connection.label, systemImage: "checkmark")
                        } else {
                            Text(connection.label)
                        }
                    }
                }
            } label: {
                Label(L10n.string("Switch Host"), systemImage: "chevron.up.chevron.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var connectionStatusBadge: HermesBadge {
        if appState.activeConnection == nil {
            return HermesBadge(text: "Not configured", tint: .secondary)
        }
        if appState.isBusy || appState.isRefreshingOverview {
            return HermesBadge(text: "Checking", tint: .orange)
        }
        if appState.overviewError != nil {
            return HermesBadge(text: "Needs attention", tint: .orange)
        }
        if appState.overview != nil {
            return HermesBadge(text: "Connected", tint: .green, systemImage: "circle.fill")
        }
        return HermesBadge(text: "Ready", tint: .secondary)
    }

    private var allDiscoveredProfiles: [RemoteHermesProfile] {
        if let overview = appState.overview, !overview.availableProfiles.isEmpty {
            return overview.availableProfiles
        }
        return appState.visibleHermesProfiles
    }

    private var appAppearanceBinding: Binding<AppAppearancePreference> {
        Binding {
            appState.connectionStore.appAppearance
        } set: { newValue in
            appState.connectionStore.appAppearance = newValue
        }
    }

    private var terminalThemeBinding: Binding<TerminalThemePreference> {
        Binding {
            appState.connectionStore.terminalTheme
        } set: { newValue in
            appState.connectionStore.terminalTheme = newValue
        }
    }

    private var terminalFontSizeBinding: Binding<Double> {
        Binding {
            appState.connectionStore.terminalFontSize
        } set: { newValue in
            appState.connectionStore.terminalFontSize = newValue
        }
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choose Image…")
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                appState.connectionStore.backgroundImagePath = url.path
            }
        }
    }

    private func canMoveSidebarSectionUp(_ section: AppSection) -> Bool {
        guard let index = appState.connectionStore.sidebarSectionOrder.firstIndex(of: section) else { return false }
        return index > appState.connectionStore.sidebarSectionOrder.startIndex
    }

    private func canMoveSidebarSectionDown(_ section: AppSection) -> Bool {
        guard let index = appState.connectionStore.sidebarSectionOrder.firstIndex(of: section) else { return false }
        return index < appState.connectionStore.sidebarSectionOrder.index(before: appState.connectionStore.sidebarSectionOrder.endIndex)
    }

    private var connectionHealthTitle: String {
        if appState.activeConnection == nil { return "No host selected" }
        if appState.overviewError != nil { return "Connection needs attention" }
        return "Connection is healthy"
    }

    private var connectionHealthSubtitle: String {
        if let overviewError = appState.overviewError {
            return overviewError
        }
        if appState.activeConnection == nil {
            return "Create or select a host to begin discovery."
        }
        return "Hermes Desktop is connected to your host and ready."
    }

    private var deleteProfileConfirmationMessage: String {
        guard let profilePendingDelete else {
            return L10n.string("This removes the profile directory from the host.")
        }
        return L10n.string("This permanently deletes %@ from the host. This cannot be undone.", profilePendingDelete.path)
    }

    private func workspaceFields(_ connection: ConnectionProfile) -> [HermesInspectorField] {
        [
            HermesInspectorField(label: "Workspace", value: connection.label, emphasizeValue: true),
            HermesInspectorField(label: "Profile Path", value: appState.overview?.activeProfile.path ?? connection.remoteHermesHomePath, isMonospaced: true),
            HermesInspectorField(label: "Tracked Profiles", value: "\(appState.visibleHermesProfiles.count)")
        ]
    }

    private func inspectorFields(_ connection: ConnectionProfile) -> [HermesInspectorField] {
        [
            HermesInspectorField(label: "Host", value: connection.label, emphasizeValue: true),
            HermesInspectorField(label: "Address", value: connection.effectiveTarget, isMonospaced: true),
            HermesInspectorField(label: "Port", value: connection.resolvedPort.map { "\($0) (SSH)" } ?? "Default"),
            HermesInspectorField(label: "Profile", value: connection.resolvedHermesProfileName, isMonospaced: true),
            HermesInspectorField(label: "Last Checked", value: lastCheckedText)
        ]
    }

    private var lastCheckedText: String {
        guard let date = appState.lastOverviewRefreshedAt else { return "Not checked" }
        return DateFormatters.relativeFormatter().localizedString(for: date, relativeTo: .now)
    }

    private func diagnosticRows(for overview: RemoteDiscovery) -> [SettingsDiagnosticRow] {
        [
            SettingsDiagnosticRow(title: "USER.md", subtitle: overview.paths.user, isReady: overview.exists.user),
            SettingsDiagnosticRow(title: "MEMORY.md", subtitle: overview.paths.memory, isReady: overview.exists.memory),
            SettingsDiagnosticRow(title: "SOUL.md", subtitle: overview.paths.soul, isReady: overview.exists.soul),
            SettingsDiagnosticRow(title: "Sessions", subtitle: overview.paths.sessionsDir, isReady: overview.exists.sessionsDir),
            SettingsDiagnosticRow(title: "Cron Jobs", subtitle: overview.paths.cronJobs, isReady: overview.exists.cronJobs),
            SettingsDiagnosticRow(title: "Kanban", subtitle: overview.paths.kanbanDatabase ?? "~/.hermes/kanban.db", isReady: overview.exists.kanbanDatabase ?? false)
        ]
    }

    private func presentEditor(for connection: ConnectionProfile, isEditing: Bool) {
        editingConnection = connection
        editingExistingConnection = isEditing
        editorPresentationID = UUID()
        isPresentingEditor = true
    }

    private func presentPendingNewConnectionEditorIfNeeded() {
        guard let requestID = appState.pendingNewConnectionEditorRequestID else { return }
        presentEditor(for: ConnectionProfile(), isEditing: false)
        appState.consumeNewConnectionEditorRequest(requestID)
    }
}

private enum SettingsInspectorTab: String, CaseIterable, Identifiable {
    case overview
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .diagnostics:
            return "Diagnostics"
        }
    }
}

private struct SettingsDiagnosticRow: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let isReady: Bool
}

private struct SettingsCardHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let badge: HermesBadge?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string(title))
                    .font(.headline)

                Text(L10n.string(subtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let badge {
                badge
            }
        }
    }
}

private struct SettingsControlRow<Control: View>: View {
    let title: String
    let subtitle: String
    let control: Control

    init(title: String, subtitle: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(title))
                    .font(.subheadline.weight(.semibold))

                Text(L10n.string(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            control
        }
    }
}

private struct SidebarCustomizationPanel: View {
    let sections: [AppSection]
    let isVisible: (AppSection) -> Bool
    let canMoveUp: (AppSection) -> Bool
    let canMoveDown: (AppSection) -> Bool
    let setVisible: (AppSection, Bool) -> Void
    let moveUp: (AppSection) -> Void
    let moveDown: (AppSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Sidebar"))
                    .font(.headline)

                Text(L10n.string("Choose which sections appear in the sidebar."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HermesInsetSurface {
                VStack(spacing: 0) {
                    ForEach(sections) { section in
                        SidebarCustomizationRow(
                            section: section,
                            isVisible: Binding(
                                get: { isVisible(section) },
                                set: { setVisible(section, $0) }
                            ),
                            canMoveUp: canMoveUp(section),
                            canMoveDown: canMoveDown(section),
                            moveUp: { moveUp(section) },
                            moveDown: { moveDown(section) }
                        )

                        if section.id != sections.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct SidebarCustomizationRow: View {
    let section: AppSection
    @Binding var isVisible: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(section.title)
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 12)

            HStack(spacing: 2) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                .help(L10n.string("Move Up"))

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                .help(L10n.string("Move Down"))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            Toggle("", isOn: $isVisible)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(L10n.string("Show in Sidebar"))
        }
        .padding(.vertical, 7)
    }
}

private struct EmptySettingsState<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    let actions: Actions

    init(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions()
    }

    init(systemImage: String, title: String, message: String) where Actions == EmptyView {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = EmptyView()
    }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(L10n.string(title))
                    .font(.headline)

                Text(L10n.string(message))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            actions
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

private struct HealthSummaryRow: View {
    let isHealthy: Bool
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isHealthy ? Color.green : Color.orange)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(title))
                    .font(.subheadline.weight(.semibold))

                Text(L10n.string(subtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct SettingsActionRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string(title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(L10n.string(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ManageProfilesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let profiles: [RemoteHermesProfile]
    let activeProfileName: String?
    let hostConnectionFingerprint: String?
    let isBusy: Bool
    let isHidden: (RemoteHermesProfile) -> Bool
    let onDelete: (RemoteHermesProfile) -> Void
    let onStopTracking: (RemoteHermesProfile) -> Void
    let onResumeTracking: (RemoteHermesProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Manage Profiles"))
                        .font(.title3.weight(.semibold))

                    Text(L10n.string("Control which Hermes profiles Desktop tracks locally, or delete a non-default profile from the host."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(L10n.string("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            if profiles.isEmpty {
                EmptySettingsState(
                    systemImage: "person.2.slash",
                    title: "No profiles discovered",
                    message: "Refresh Settings after the host is reachable."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(profiles) { profile in
                            ManagedProfileRow(
                                profile: profile,
                                isActive: profile.name == activeProfileName,
                                isHidden: isHidden(profile),
                                isBusy: isBusy,
                                canDelete: !profile.isDefault && profile.name != "default",
                                onDelete: { onDelete(profile) },
                                onStopTracking: { onStopTracking(profile) },
                                onResumeTracking: { onResumeTracking(profile) }
                            )
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 560, height: 440)
    }
}

private struct ManagedProfileRow: View {
    let profile: RemoteHermesProfile
    let isActive: Bool
    let isHidden: Bool
    let isBusy: Bool
    let canDelete: Bool
    let onDelete: () -> Void
    let onStopTracking: () -> Void
    let onResumeTracking: () -> Void

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(profile.name)
                                .font(.headline)

                            if isActive {
                                HermesBadge(text: "Active", tint: .accentColor)
                            }
                            if isHidden {
                                HermesBadge(text: "Hidden", tint: .orange)
                            }
                            if profile.isDefault {
                                HermesBadge(text: "Default", tint: .secondary)
                            }
                        }

                        Text(profile.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    Button(L10n.string("Delete Profile"), role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                        .disabled(isBusy || !canDelete)

                    if isHidden {
                        Button(L10n.string("Track Profile"), action: onResumeTracking)
                            .buttonStyle(.bordered)
                            .disabled(isBusy)
                    } else {
                        Button(L10n.string("Stop Tracking"), role: .destructive, action: onStopTracking)
                            .buttonStyle(.bordered)
                            .disabled(isBusy)
                    }
                }
            }
        }
    }
}
