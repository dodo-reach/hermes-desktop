import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pendingTrackedFile: RemoteTrackedFile?
    @State private var showDiscardFileAlert = false
    @State private var showReloadDiscardAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Canonical Files")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Edits are written remotely with atomic replace semantics and conflict checks over SSH.")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Picker("File", selection: trackedFileSelection) {
                ForEach(RemoteTrackedFile.allCases) { trackedFile in
                    Text(trackedFile.title).tag(trackedFile)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Reload from Remote") {
                    if currentDocument.isDirty {
                        showReloadDiscardAlert = true
                    } else {
                        Task {
                            await appState.loadTrackedFile(appState.selectedTrackedFile, forceReload: true)
                        }
                    }
                }

                Button("Save") {
                    Task {
                        await appState.saveTrackedFile(appState.selectedTrackedFile)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!currentDocument.isDirty || currentDocument.isLoading)

                Spacer()

                if currentDocument.isDirty {
                    Label("Unsaved changes", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let lastSavedAt = currentDocument.lastSavedAt {
                    Text("Saved \(DateFormatters.relativeFormatter().localizedString(for: lastSavedAt, relativeTo: .now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = currentDocument.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(12)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            ZStack {
                TextEditor(text: editorBinding)
                    .font(.system(.body, design: .monospaced))
                    .disabled(currentDocument.isLoading)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if currentDocument.isLoading {
                    HermesLoadingOverlay()
                }
            }
        }
        .padding(24)
        .task(id: appState.activeConnectionID) {
            await appState.loadTrackedFile(.user)
            await appState.loadTrackedFile(.memory)
            await appState.loadTrackedFile(.soul)
        }
        .alert("Discard unsaved edits in this file?", isPresented: $showDiscardFileAlert) {
            Button("Discard", role: .destructive) {
                if let pendingTrackedFile {
                    let currentFile = appState.selectedTrackedFile
                    let current = document(for: currentFile)
                    appState.updateDocument(currentFile, content: current.originalContent)
                    appState.selectedTrackedFile = pendingTrackedFile
                    self.pendingTrackedFile = nil
                }
            }
            Button("Stay", role: .cancel) {
                pendingTrackedFile = nil
            }
        } message: {
            Text("Switching away will drop the unsaved edits in the current file.")
        }
        .alert("Reload from remote and discard local edits?", isPresented: $showReloadDiscardAlert) {
            Button("Reload", role: .destructive) {
                Task {
                    await appState.loadTrackedFile(appState.selectedTrackedFile, forceReload: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace the local unsaved changes with the current remote file content.")
        }
    }

    private var currentDocument: FileEditorDocument {
        document(for: appState.selectedTrackedFile)
    }

    private func document(for trackedFile: RemoteTrackedFile) -> FileEditorDocument {
        switch trackedFile {
        case .user:
            appState.userDocument
        case .memory:
            appState.memoryDocument
        case .soul:
            appState.soulDocument
        }
    }

    private var trackedFileSelection: Binding<RemoteTrackedFile> {
        Binding {
            appState.selectedTrackedFile
        } set: { newValue in
            guard newValue != appState.selectedTrackedFile else { return }
            if currentDocument.isDirty {
                pendingTrackedFile = newValue
                showDiscardFileAlert = true
            } else {
                appState.selectedTrackedFile = newValue
            }
        }
    }

    private var editorBinding: Binding<String> {
        Binding {
            currentDocument.content
        } set: { newValue in
            appState.updateDocument(appState.selectedTrackedFile, content: newValue)
        }
    }
}
