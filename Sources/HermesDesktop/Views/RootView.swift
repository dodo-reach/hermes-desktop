import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HSplitView {
            List(selection: sectionSelection) {
                if let activeConnection = appState.activeConnection {
                    Section("Workspace") {
                        WorkspaceSidebarCard(connection: activeConnection)
                    }
                }

                Section("Sections") {
                    ForEach(availableSections) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150, idealWidth: 170, maxWidth: 210)

            detailView
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
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
        .alert("Discard unsaved changes?", isPresented: $appState.showDiscardChangesAlert) {
            Button("Discard", role: .destructive) {
                appState.discardChangesAndContinue()
            }
            Button("Stay", role: .cancel) {
                appState.stayOnCurrentSection()
            }
        } message: {
            Text(L10n.string("USER.md, MEMORY.md, or SOUL.md has unsaved edits."))
        }
    }

    private var availableSections: [AppSection] {
        if appState.activeConnection == nil {
            return [.connections]
        }
        return [.connections, .overview, .sessions, .cronjobs, .files, .usage, .skills, .terminal]
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
        switch appState.selectedSection {
        case .connections:
            ConnectionsView()
        case .overview:
            OverviewView()
        case .files:
            FilesView()
        case .sessions:
            SessionsView()
        case .cronjobs:
            CronJobsView()
        case .usage:
            UsageView()
        case .skills:
            SkillsView()
        case .terminal:
            TerminalWorkspaceView(
                workspace: appState.terminalWorkspace,
                context: TerminalWorkspaceContext(
                    activeConnection: appState.activeConnection,
                    activeWorkspaceScopeFingerprint: appState.activeConnection?.workspaceScopeFingerprint,
                    isTerminalSectionActive: appState.selectedSection == .terminal,
                    terminalTheme: appState.connectionStore.terminalTheme
                ),
                ensureTerminalSession: {
                    appState.ensureTerminalSession()
                },
                updateTerminalTheme: { newValue in
                    appState.connectionStore.terminalTheme = newValue
                }
            )
        }
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
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        if let overview = appState.overview, !overview.availableProfiles.isEmpty {
            return overview.availableProfiles
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
