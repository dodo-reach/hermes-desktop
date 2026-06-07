import SwiftUI
import AppKit

private let workbenchPrimaryColumnWidth: CGFloat = 460

struct RootView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState
    @SceneStorage("RootView.isWorkspaceSidebarCollapsed") private var isWorkspaceSidebarCollapsed = false
    @State private var workspaceSplitLayout = HermesSplitLayout(
        minPrimaryWidth: 160,
        defaultPrimaryWidth: 188,
        maxPrimaryWidth: 220
    )
    @State private var sessionsSplitLayout = HermesSplitLayout(
        minPrimaryWidth: workbenchPrimaryColumnWidth,
        defaultPrimaryWidth: workbenchPrimaryColumnWidth
    )
    @State private var cronJobsSplitLayout = HermesSplitLayout(
        minPrimaryWidth: workbenchPrimaryColumnWidth,
        defaultPrimaryWidth: workbenchPrimaryColumnWidth
    )
    @State private var workflowsSplitLayout = HermesSplitLayout(
        minPrimaryWidth: workbenchPrimaryColumnWidth,
        defaultPrimaryWidth: workbenchPrimaryColumnWidth
    )
    @State private var kanbanSplitLayout = HermesSplitLayout(
        minPrimaryWidth: workbenchPrimaryColumnWidth,
        defaultPrimaryWidth: workbenchPrimaryColumnWidth
    )
    @State private var filesSplitLayout = HermesSplitLayout(minPrimaryWidth: 300, defaultPrimaryWidth: 360)
    @State private var skillsSplitLayout = HermesSplitLayout(
        minPrimaryWidth: workbenchPrimaryColumnWidth,
        defaultPrimaryWidth: workbenchPrimaryColumnWidth
    )

    var body: some View {
        rootContent
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    HermesToolbarControlCluster {
                        HermesCollapseToolbarButton(
                            systemImage: "sidebar.left",
                            isActive: isWorkspaceSidebarCollapsed,
                            isEnabled: isWorkspaceSidebarCollapseEnabled,
                            help: workspaceSidebarCollapseHelp
                        ) {
                            guard isWorkspaceSidebarCollapseEnabled else { return }
                            workspaceSidebarSplitLayout.wrappedValue.isPrimaryCollapsed.toggle()
                        }

                        HermesCollapseToolbarButton(
                            systemImage: "rectangle.leftthird.inset.filled",
                            isActive: currentWorkbenchPrimaryColumnCollapsed,
                            isEnabled: currentWorkbenchPrimaryColumnLayout != nil,
                            help: currentWorkbenchPrimaryColumnCollapsed
                                ? L10n.string("Show Section Browser")
                                : L10n.string("Hide Section Browser")
                        ) {
                            toggleCurrentWorkbenchPrimaryColumn()
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    HermesToolbarPrincipalTitle(title: "Hermes Desktop")
                }

                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        Task {
                            await appState.refreshCurrentSectionFromCommand()
                        }
                    } label: {
                        Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
                    }
                    .disabled(!appState.canRefreshCurrentSection)
                    .help(L10n.string("Refresh Current Section"))
                }
            }
            .overlay(alignment: .bottom) {
                if let statusMessage = appState.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding()
                }
            }
            .alert(item: $appState.activeAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(L10n.string("OK")))
                )
            }
            .alert(L10n.string("Discard unsaved changes?"), isPresented: $appState.showDiscardChangesAlert) {
                Button(L10n.string("Discard"), role: .destructive) {
                    appState.discardChangesAndContinue()
                }
                Button(L10n.string("Stay"), role: .cancel) {
                    appState.stayOnCurrentSection()
                }
            } message: {
                Text(L10n.string("USER.md, MEMORY.md, or SOUL.md has unsaved edits."))
            }
            .sheet(item: $appState.availableUpdate) { update in
                UpdateAvailableSheet(
                    update: update,
                    automaticallyChecksForUpdates: Binding(
                        get: { appState.connectionStore.automaticallyChecksForUpdates },
                        set: { appState.updateAutomaticUpdateChecks($0) }
                    ),
                    openRelease: {
                        appState.noteOpenedRelease(for: update)
                        openURL(update.htmlURL)
                    },
                    dismiss: {
                        appState.dismissAvailableUpdate()
                    }
                )
            }
            .task {
                await appState.checkForUpdatesAtLaunch()
            }
            .onAppear {
                appState.connectionStore.appAppearance.applyToApplication()
                ensureWorkspaceSidebarVisibleForCurrentSection()
            }
            .onChange(of: appState.connectionStore.appAppearance) { _, newValue in
                newValue.applyToApplication()
            }
            .onChange(of: appState.selectedSection) { _, _ in
                ensureWorkspaceSidebarVisibleForCurrentSection()
            }
            .onChange(of: appState.connectionStore.visibleSidebarSections) { _, _ in
                ensureSelectedSectionAvailable()
            }
            .onChange(of: appState.sessionTUITerminal?.id) { _, _ in
                ensureWorkspaceSidebarVisibleForCurrentSection()
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        ZStack {
            if appState.connectionStore.backgroundImagePath != nil {
                backgroundImageView
            }

            mainSplitView
        }
    }
    @ViewBuilder
    private var backgroundImageView: some View {
        if let imagePath = appState.connectionStore.backgroundImagePath,
           let nsImage = NSImage(contentsOfFile: imagePath) {
            GeometryReader { geometry in
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()
            }
            .ignoresSafeArea()
            .overlay(Color.black.opacity(0.25))
        }
    }

    private var mainSplitView: some View {
        HermesCollapsibleHSplitView(layout: workspaceSidebarSplitLayout, detailMinWidth: 0) {
            workspaceSidebar
        } detail: {
            detailView
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .clipped()
        }
        .environment(\.backgroundImageActive, appState.connectionStore.backgroundImagePath != nil)
    }

    private var workspaceSidebar: some View {
        List(selection: sectionSelection) {
            if let activeConnection = appState.activeConnection {
                Section(L10n.string("Workspace")) {
                    WorkspaceSidebarCard(connection: activeConnection)
                }
            }

            Section(L10n.string("Sections")) {
                ForEach(availableSections) { section in
                    SidebarSectionRow(section: section)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(alignment: .leading) {
            if appState.connectionStore.backgroundImagePath != nil {
                Rectangle().fill(HermesTheme.sidebarBackground.opacity(0.45))
            }
        }
        .frame(minWidth: 160, idealWidth: 188, maxWidth: 220)
    }

    private var workspaceSidebarSplitLayout: Binding<HermesSplitLayout> {
        Binding {
            var layout = workspaceSplitLayout
            layout.isPrimaryCollapsed = isWorkspaceSidebarCollapsed
            return layout
        } set: { newValue in
            workspaceSplitLayout = newValue
            isWorkspaceSidebarCollapsed = newValue.isPrimaryCollapsed
        }
    }

    private var isWorkspaceSidebarCollapseEnabled: Bool {
        appState.selectedSection != .terminal && !isSessionTUIVisible
    }

    private var workspaceSidebarCollapseHelp: String {
        if !isWorkspaceSidebarCollapseEnabled {
            if isSessionTUIVisible {
                return L10n.string("Workspace Sidebar is locked while Chat TUI is active")
            }
            return L10n.string("Workspace Sidebar is always visible in Terminal")
        }

        return isWorkspaceSidebarCollapsed
            ? L10n.string("Show Workspace Sidebar")
            : L10n.string("Hide Workspace Sidebar")
    }

    private var isSessionTUIVisible: Bool {
        guard appState.selectedSection == .sessions,
              let terminal = appState.sessionTUITerminal else {
            return false
        }

        return terminal.terminalSession.exitCode == nil
    }

    private var currentWorkbenchPrimaryColumnLayout: Binding<HermesSplitLayout>? {
        guard appState.activeConnection != nil else { return nil }

        switch appState.selectedSection {
        case .sessions:
            return $sessionsSplitLayout
        case .cronjobs:
            return $cronJobsSplitLayout
        case .workflows:
            return $workflowsSplitLayout
        case .kanban:
            return $kanbanSplitLayout
        case .files:
            return $filesSplitLayout
        case .skills:
            return $skillsSplitLayout
        case .connections, .usage, .terminal:
            return nil
        }
    }

    private var currentWorkbenchPrimaryColumnCollapsed: Bool {
        currentWorkbenchPrimaryColumnLayout?.wrappedValue.isPrimaryCollapsed ?? false
    }

    private func toggleCurrentWorkbenchPrimaryColumn() {
        guard let layout = currentWorkbenchPrimaryColumnLayout else { return }
        layout.wrappedValue.isPrimaryCollapsed.toggle()
    }

    private func ensureWorkspaceSidebarVisibleForCurrentSection() {
        guard !isWorkspaceSidebarCollapseEnabled, isWorkspaceSidebarCollapsed else { return }
        workspaceSidebarSplitLayout.wrappedValue.isPrimaryCollapsed = false
    }

    private func ensureSelectedSectionAvailable() {
        guard !availableSections.contains(appState.selectedSection) else { return }
        appState.requestSectionSelection(.connections)
    }

    private var availableSections: [AppSection] {
        if appState.activeConnection == nil {
            return [.connections]
        }
        return [.connections] + appState.connectionStore.visibleSidebarSections
    }

    private var sectionSelection: Binding<AppSection?> {
        Binding {
            appState.selectedSection
        } set: { newValue in
            guard let newValue else { return }
            appState.requestSectionSelection(newValue)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        activeDetailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var activeDetailContent: some View {
        if appState.activeConnection == nil {
            ConnectionsView()
        } else {
            ZStack {
                SessionsView(
                    splitLayout: $sessionsSplitLayout,
                    isActive: appState.selectedSection == .sessions
                )
                .opacity(appState.selectedSection == .sessions ? 1 : 0)
                .allowsHitTesting(appState.selectedSection == .sessions)
                .accessibilityHidden(appState.selectedSection != .sessions)

                if appState.selectedSection != .sessions {
                    nonSessionDetailContent
                }
            }
        }
    }

    @ViewBuilder
    private var nonSessionDetailContent: some View {
        switch appState.selectedSection {
        case .connections:
            ConnectionsView()
        case .files:
            FilesView(splitLayout: $filesSplitLayout)
        case .sessions:
            EmptyView()
        case .workflows:
            WorkflowsView(splitLayout: $workflowsSplitLayout)
        case .cronjobs:
            CronJobsView(splitLayout: $cronJobsSplitLayout)
        case .kanban:
            KanbanView(splitLayout: $kanbanSplitLayout)
        case .usage:
            UsageView()
        case .skills:
            SkillsView(splitLayout: $skillsSplitLayout)
        case .terminal:
            TerminalWorkspaceView(
                workspace: appState.terminalWorkspace,
                context: TerminalWorkspaceContext(
                    activeConnection: appState.activeConnection,
                    activeWorkspaceScopeFingerprint: appState.activeConnection?.workspaceScopeFingerprint,
                    isTerminalSectionActive: appState.selectedSection == .terminal,
                    terminalTheme: appState.connectionStore.terminalTheme,
                    terminalFontSize: appState.connectionStore.terminalFontSize
                ),
                ensureTerminalSession: {
                    appState.ensureTerminalSession()
                },
                updateTerminalTheme: { newValue in
                    appState.connectionStore.terminalTheme = newValue
                },
                updateTerminalFontSize: { newValue in
                    appState.connectionStore.terminalFontSize = newValue
                }
            )
        }
    }
}

private struct UpdateAvailableSheet: View {
    let update: AvailableUpdate
    @Binding var automaticallyChecksForUpdates: Bool
    let openRelease: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("Hermes Desktop %@ is available", update.latestVersion))
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        L10n.string(
                            "You are running Hermes Desktop %@. The latest Hermes Desktop release is %@.",
                            update.currentVersion,
                            update.latestVersion
                        )
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(update.resolvedName)
                    .font(.headline)
                    .lineLimit(2)

                if let releaseNotesPreview = update.releaseNotesPreview {
                    ScrollView {
                        Text(releaseNotesPreview)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 220)
                } else {
                    Text(L10n.string("Open the GitHub release to download the latest Hermes Desktop build."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(L10n.string("This checks only the Hermes Desktop app. It does not update Hermes Agent on your host."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(L10n.string("Check Automatically for Hermes Desktop Updates"), isOn: $automaticallyChecksForUpdates)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()

                Button(L10n.string("Not Now")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.string("Open Release")) {
                    openRelease()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

private struct SidebarSectionRow: View {
    let section: AppSection

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: section.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(section.title)
                .font(.body)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
        .help(section.title)
        .accessibilityElement(children: .combine)
    }
}

private struct WorkspaceSidebarCard: View {
    @EnvironmentObject private var appState: AppState

    let connection: ConnectionProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Hermes Profile"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if availableProfiles.count > 1 {
                Menu {
                    ForEach(availableProfiles) { profile in
                        Button {
                            Task {
                                await appState.switchHermesProfile(to: profile.name)
                            }
                        } label: {
                            if profile.name == connection.resolvedHermesProfileName {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(connection.resolvedHermesProfileName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 6)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(appState.isRefreshingOverview || appState.isBusy)
            } else {
                Text(connection.resolvedHermesProfileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(connection.displayDestination)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
    }

    private var availableProfiles: [RemoteHermesProfile] {
        if !appState.visibleHermesProfiles.isEmpty {
            return appState.visibleHermesProfiles
        }

        return [
            RemoteHermesProfile(
                name: connection.resolvedHermesProfileName,
                path: connection.remoteHermesHomePath,
                isDefault: connection.usesDefaultHermesProfile,
                exists: true
            )
        ]
    }
}

