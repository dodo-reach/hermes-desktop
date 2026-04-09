import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HSplitView {
            List(selection: sectionSelection) {
                if let activeConnection = appState.activeConnection {
                    Section("Active Connection") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activeConnection.label)
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(activeConnection.displayDestination)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Workspace") {
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
                dismissButton: .default(Text("OK"))
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
            Text("USER.md, MEMORY.md, or SOUL.md has unsaved edits.")
        }
    }

    private var availableSections: [AppSection] {
        if appState.activeConnection == nil {
            return [.connections]
        }
        return [.connections, .overview, .files, .sessions, .terminal]
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
        ZStack(alignment: .topLeading) {
            activeDetailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if appState.activeConnection != nil {
                // Keep the terminal mounted so section switches do not tear down the SSH process.
                TerminalWorkspaceView(workspace: appState.terminalWorkspace)
                    .opacity(appState.selectedSection == .terminal ? 1 : 0)
                    .allowsHitTesting(appState.selectedSection == .terminal)
                    .zIndex(appState.selectedSection == .terminal ? 1 : 0)
            }
        }
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
        case .terminal:
            Color.clear
        }
    }
}
