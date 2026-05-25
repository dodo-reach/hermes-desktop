import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FilesView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var splitLayout: HermesSplitLayout
    @State private var pendingWorkspaceFileID: String?
    @State private var bookmarkPendingRemoval: UUID?
    @State private var collapsedBookmarkGroupIDs: Set<String> = []
    @State private var showBrowserSheet = false
    @State private var showDiscardFileAlert = false
    @State private var showReloadDiscardAlert = false
    @State private var showRemoveBookmarkAlert = false

    var body: some View {
        HermesCollapsibleHSplitView(layout: $splitLayout, detailMinWidth: 460) {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Files",
                    subtitle: "Read and edit selected remote files over SSH."
                )

                filesToolbar
                libraryPanel
                toolArtifactsPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        } detail: {
            editorPane
                .hermesSplitDetailColumn(minWidth: 460, idealWidth: 640)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: selectedFileLoadTaskID) {
            await appState.loadSelectedWorkspaceFile()
        }
        .task(id: appState.activeConnectionID) {
            await appState.loadToolArtifacts(resetSelection: true)
        }
        .sheet(isPresented: $showBrowserSheet) {
            WorkspaceFileBrowserSheet()
                .environmentObject(appState)
        }
        .alert(L10n.string("Discard unsaved edits in this file?"), isPresented: $showDiscardFileAlert) {
            Button(L10n.string("Discard"), role: .destructive) {
                if let currentFileID {
                    appState.discardWorkspaceFile(currentFileID)
                }
                if let pendingWorkspaceFileID {
                    appState.selectWorkspaceFile(pendingWorkspaceFileID)
                }
                pendingWorkspaceFileID = nil
            }
            Button(L10n.string("Stay"), role: .cancel) {
                pendingWorkspaceFileID = nil
            }
        } message: {
            Text(L10n.string("Switching away will drop the unsaved edits in the current file."))
        }
        .alert(L10n.string("Reload from remote and discard local edits?"), isPresented: $showReloadDiscardAlert) {
            Button(L10n.string("Reload"), role: .destructive) {
                if let selectedReference {
                    Task {
                        await appState.loadWorkspaceFile(selectedReference, forceReload: true)
                    }
                }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("This will replace the local unsaved changes with the current remote file content."))
        }
        .alert(L10n.string("Remove this bookmark?"), isPresented: $showRemoveBookmarkAlert) {
            Button(L10n.string("Remove"), role: .destructive) {
                if let bookmarkPendingRemoval {
                    appState.removeWorkspaceFileBookmark(id: bookmarkPendingRemoval)
                }
                bookmarkPendingRemoval = nil
            }
            Button(L10n.string("Cancel"), role: .cancel) {
                bookmarkPendingRemoval = nil
            }
        } message: {
            Text(L10n.string("The remote file stays untouched."))
        }
    }

    private var filesToolbar: some View {
        HStack(spacing: 10) {
            HermesCreateActionButton("Add File") {
                showBrowserSheet = true
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var libraryPanel: some View {
        HermesSurfacePanel(
            title: "Library",
            subtitle: "Pinned Hermes files and your bookmarks."
        ) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    fileGroup(title: "Canonical", references: appState.canonicalWorkspaceFileReferences)

                    if appState.bookmarkedWorkspaceFileGroups.isEmpty {
                        emptyBookmarks
                    } else {
                        bookmarkGroups(appState.bookmarkedWorkspaceFileGroups)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var toolArtifactsPanel: some View {
        HermesSurfacePanel(
            title: "Tool Artifacts",
            subtitle: "Externalized tool output from Workspace sessions."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if appState.isLoadingToolArtifacts {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    Button {
                        Task {
                            await appState.loadToolArtifacts(resetSelection: false)
                        }
                    } label: {
                        Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(appState.isLoadingToolArtifacts)
                }

                if let errorMessage = appState.toolArtifactsError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if appState.toolArtifacts.isEmpty {
                    Text(L10n.string("No tool artifacts surfaced."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(appState.toolArtifacts.prefix(8)) { artifact in
                                ToolArtifactRow(
                                    artifact: artifact,
                                    isSelected: artifact.id == appState.selectedToolArtifactID
                                ) {
                                    Task {
                                        await appState.selectToolArtifact(artifact.id)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        }
    }

    private func fileGroup(title: String, references: [WorkspaceFileReference]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(references) { reference in
                    WorkspaceFileCardRow(
                        reference: reference,
                        subtitle: reference.subtitle,
                        isSelected: reference.id == currentFileID,
                        isDirty: appState.workspaceFileDocument(for: reference.id)?.isDirty == true,
                        onSelect: {
                            select(reference)
                        },
                        onRemove: reference.bookmarkID.map { bookmarkID in
                            {
                                bookmarkPendingRemoval = bookmarkID
                                showRemoveBookmarkAlert = true
                            }
                        }
                    )
                }
            }
        }
    }

    private func bookmarkGroups(_ groups: [WorkspaceFileBookmarkGroup]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Bookmarks"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(groups) { group in
                    bookmarkFolderGroup(group)
                }
            }
        }
    }

    private func bookmarkFolderGroup(_ group: WorkspaceFileBookmarkGroup) -> some View {
        DisclosureGroup(isExpanded: bookmarkGroupExpansionBinding(for: group.id)) {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(group.references) { reference in
                    WorkspaceFileCardRow(
                        reference: reference,
                        subtitle: groupedBookmarkSubtitle(for: reference),
                        isSelected: reference.id == currentFileID,
                        isDirty: appState.workspaceFileDocument(for: reference.id)?.isDirty == true,
                        onSelect: {
                            select(reference)
                        },
                        onRemove: reference.bookmarkID.map { bookmarkID in
                            {
                                bookmarkPendingRemoval = bookmarkID
                                showRemoveBookmarkAlert = true
                            }
                        }
                    )
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(group.directoryPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Text("\(group.references.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .tint(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func bookmarkGroupExpansionBinding(for groupID: String) -> Binding<Bool> {
        Binding {
            !collapsedBookmarkGroupIDs.contains(groupID)
        } set: { isExpanded in
            if isExpanded {
                collapsedBookmarkGroupIDs.remove(groupID)
            } else {
                collapsedBookmarkGroupIDs.insert(groupID)
            }
        }
    }

    private func groupedBookmarkSubtitle(for reference: WorkspaceFileReference) -> String? {
        let filename = WorkspaceFileBookmark.displayTitle(for: reference.remotePath)
        return filename == reference.title ? nil : filename
    }

    private var emptyBookmarks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Bookmarks"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HermesInsetSurface {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bookmark")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.string("No remote files added yet"))
                            .font(.subheadline.weight(.semibold))

                        Text(L10n.string("Add files you want to revisit."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var editorPane: some View {
        Group {
            if let selectedReference {
                VStack(alignment: .leading, spacing: 16) {
                    if let artifact = appState.selectedToolArtifactDetail {
                        ToolArtifactDetailPanel(
                            artifact: artifact,
                            isLoading: appState.isLoadingToolArtifactDetail
                        )
                    }

                    WorkspaceFileEditorPane(
                        reference: selectedReference,
                        document: currentDocument,
                        text: editorBinding,
                        onReload: {
                            if currentDocument?.isDirty == true {
                                showReloadDiscardAlert = true
                            } else {
                                Task {
                                    await appState.loadWorkspaceFile(selectedReference, forceReload: true)
                                }
                            }
                        },
                        onSave: {
                            Task {
                                await appState.saveWorkspaceFile(fileID: selectedReference.id)
                            }
                        },
                        onRemove: selectedReference.bookmarkID.map { bookmarkID in
                            {
                                bookmarkPendingRemoval = bookmarkID
                                showRemoveBookmarkAlert = true
                            }
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    HermesSurfacePanel {
                        ContentUnavailableView(
                            L10n.string("No File Selected"),
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(L10n.string("Choose a file from the library."))
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                }
            }
        }
    }

    private func select(_ reference: WorkspaceFileReference) {
        guard reference.id != currentFileID else { return }

        if currentDocument?.isDirty == true {
            pendingWorkspaceFileID = reference.id
            showDiscardFileAlert = true
        } else {
            appState.selectWorkspaceFile(reference.id)
        }
    }

    private var editorBinding: Binding<String> {
        Binding {
            guard let currentFileID else { return "" }
            return appState.workspaceFileDocument(for: currentFileID)?.content ?? ""
        } set: { newValue in
            guard let currentFileID else { return }
            appState.updateWorkspaceFile(currentFileID, content: newValue)
        }
    }

    private var selectedReference: WorkspaceFileReference? {
        appState.selectedWorkspaceFileReference
    }

    private var currentFileID: String? {
        selectedReference?.id
    }

    private var currentDocument: FileEditorDocument? {
        guard let currentFileID else { return nil }
        return appState.workspaceFileDocument(for: currentFileID)
    }

    private var selectedFileLoadTaskID: String {
        "\(appState.activeConnectionID?.uuidString ?? "none")|\(appState.selectedWorkspaceFileID)"
    }
}

private struct ToolArtifactRow: View {
    let artifact: ToolArtifactSummary
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(artifact.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(artifact.kind)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }

                Text(artifact.preview.isEmpty ? artifact.summary : artifact.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch artifact.kind {
        case "diff":
            "plus.forwardslash.minus"
        case "terminal_log":
            "terminal"
        case "file_read":
            "doc.text.magnifyingglass"
        case "skill_doc":
            "puzzlepiece"
        default:
            "doc.text"
        }
    }
}

private struct ToolArtifactDetailPanel: View {
    let artifact: ToolArtifactDetail
    let isLoading: Bool

    var body: some View {
        HermesSurfacePanel(
            title: artifact.title,
            subtitle: "\(artifact.kind) / \(artifact.sessionId)"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(artifact.contentSize), countStyle: .file))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(DateFormatters.relativeFormatter().localizedString(for: artifact.createdDate, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(artifact.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                ScrollView {
                    Text(artifact.content.isEmpty ? artifact.preview : artifact.content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 180)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }
}

private struct WorkspaceFileCardRow: View {
    let reference: WorkspaceFileReference
    let subtitle: String?
    let isSelected: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onRemove: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: reference.systemImage)
                        .foregroundStyle(reference.isRemovable ? Color.accentColor : Color.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(reference.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if isDirty {
                                HermesBadge(text: "Unsaved", tint: .orange)
                            }
                        }

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 10)

                    if onRemove != nil {
                        Image(systemName: "bookmark.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.12 : 0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onRemove {
                Button(L10n.string("Remove Bookmark"), role: .destructive, action: onRemove)
            }
        }
    }
}

private struct WorkspaceFileEditorPane: View {
    let reference: WorkspaceFileReference
    let document: FileEditorDocument?
    @Binding var text: String
    let onReload: () -> Void
    let onSave: () -> Void
    let onRemove: (() -> Void)?
    @State private var showSaveReview = false

    private var isDirty: Bool {
        document?.isDirty == true
    }

    private var isLoading: Bool {
        document?.isLoading == true
    }

    private var hasLoaded: Bool {
        document?.hasLoaded == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerPanel

            if let errorMessage = document?.errorMessage {
                HermesSurfacePanel {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            editorPanel
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showSaveReview) {
            if let document {
                WorkspaceFileSaveReviewSheet(
                    reference: reference,
                    document: document,
                    editedText: text,
                    onCancel: { showSaveReview = false },
                    onConfirm: {
                        showSaveReview = false
                        onSave()
                    }
                )
            }
        }
    }

    private var headerPanel: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Image(systemName: reference.systemImage)
                                .foregroundStyle(.secondary)

                            Text(reference.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }

                        Text(reference.remotePath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 12)

                    if isDirty {
                        HermesBadge(text: "Unsaved", tint: .orange)
                    } else if let lastSavedAt = document?.lastSavedAt {
                        Text(L10n.string("Saved %@", DateFormatters.relativeFormatter().localizedString(for: lastSavedAt, relativeTo: .now)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        actionButtons
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        actionButtons
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        Group {
            Button(L10n.string("Reload"), action: onReload)
            .disabled(isLoading)

            Button(L10n.string("Save")) {
                showSaveReview = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isDirty || isLoading || !hasLoaded)

            if let onRemove {
                Button(L10n.string("Remove Bookmark"), role: .destructive, action: onRemove)
                .disabled(isLoading)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var editorPanel: some View {
        HermesSurfacePanel(
            title: "Content",
            subtitle: "Loaded from the active host."
        ) {
            ZStack {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isLoading || !hasLoaded)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isLoading {
                    HermesLoadingOverlay()
                } else if !hasLoaded {
                    ContentUnavailableView(
                        L10n.string("Loading file"),
                        systemImage: "doc.text",
                        description: Text(L10n.string("Reading over SSH."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WorkspaceFileSaveReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reference: WorkspaceFileReference
    let document: FileEditorDocument
    let editedText: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var summary: WorkspaceFileChangeSummary {
        WorkspaceFileChangeSummary(original: document.originalContent, edited: editedText)
    }

    private var rows: [WorkspaceFileDiffRow] {
        WorkspaceFileDiffRow.rows(original: document.originalContent, edited: editedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Review Save"))
                        .font(.title2.weight(.semibold))

                    Text(reference.remotePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                HermesBadge(text: "Unsaved", tint: .orange)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                WorkspaceFileChangeMetric(label: "Changed", value: "\(summary.changedLineCount)")
                WorkspaceFileChangeMetric(label: "Added", value: "\(summary.addedLineCount)")
                WorkspaceFileChangeMetric(label: "Removed", value: "\(summary.removedLineCount)")
                WorkspaceFileChangeMetric(label: "Characters", value: summary.characterDeltaText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Server guard"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(document.remoteContentHash.map { L10n.string("Save will use the last loaded content hash: %@", $0) } ?? L10n.string("Reload this file before saving so the server can detect remote changes."))
                    .font(.caption)
                    .foregroundStyle(document.remoteContentHash == nil ? .orange : .secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.string("Changed lines"))
                        .font(.headline)

                    Spacer()

                    if rows.count > WorkspaceFileDiffRow.previewLimit {
                        Text(L10n.string("Showing %@ of %@", "\(WorkspaceFileDiffRow.previewLimit)", "\(rows.count)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if rows.isEmpty {
                            Text(L10n.string("No line-level changes detected."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(rows.prefix(WorkspaceFileDiffRow.previewLimit)) { row in
                                WorkspaceFileDiffRowView(row: row)
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 180, maxHeight: 300)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }

            HStack {
                Button(L10n.string("Cancel")) {
                    dismiss()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(L10n.string("Save to Workspace")) {
                    dismiss()
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(document.remoteContentHash == nil)
            }
        }
        .padding(22)
        .frame(width: 680)
        .frame(minHeight: 560)
    }
}

private struct WorkspaceFileChangeSummary {
    let changedLineCount: Int
    let addedLineCount: Int
    let removedLineCount: Int
    let originalCharacterCount: Int
    let editedCharacterCount: Int

    init(original: String, edited: String) {
        let originalLines = WorkspaceFileDiffRow.lines(original)
        let editedLines = WorkspaceFileDiffRow.lines(edited)
        let sharedCount = min(originalLines.count, editedLines.count)
        let changed = (0..<sharedCount).filter { originalLines[$0] != editedLines[$0] }.count

        self.changedLineCount = changed
        self.addedLineCount = max(0, editedLines.count - originalLines.count)
        self.removedLineCount = max(0, originalLines.count - editedLines.count)
        self.originalCharacterCount = original.count
        self.editedCharacterCount = edited.count
    }

    var characterDeltaText: String {
        let delta = editedCharacterCount - originalCharacterCount
        if delta > 0 { return "+\(delta)" }
        return "\(delta)"
    }
}

private struct WorkspaceFileChangeMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.string(label))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct WorkspaceFileDiffRow: Identifiable {
    enum Kind {
        case added
        case removed
    }

    static let previewLimit = 120
    let id: String
    let kind: Kind
    let lineNumber: Int
    let text: String

    static func rows(original: String, edited: String) -> [WorkspaceFileDiffRow] {
        let originalLines = lines(original)
        let editedLines = lines(edited)
        let maxCount = max(originalLines.count, editedLines.count)
        var rows: [WorkspaceFileDiffRow] = []

        for index in 0..<maxCount {
            let lineNumber = index + 1
            let originalLine = index < originalLines.count ? originalLines[index] : nil
            let editedLine = index < editedLines.count ? editedLines[index] : nil

            switch (originalLine, editedLine) {
            case let (old?, new?) where old != new:
                rows.append(WorkspaceFileDiffRow(id: "\(lineNumber)-removed", kind: .removed, lineNumber: lineNumber, text: old))
                rows.append(WorkspaceFileDiffRow(id: "\(lineNumber)-added", kind: .added, lineNumber: lineNumber, text: new))
            case let (old?, nil):
                rows.append(WorkspaceFileDiffRow(id: "\(lineNumber)-removed", kind: .removed, lineNumber: lineNumber, text: old))
            case let (nil, new?):
                rows.append(WorkspaceFileDiffRow(id: "\(lineNumber)-added", kind: .added, lineNumber: lineNumber, text: new))
            default:
                break
            }
        }

        return rows
    }

    static func lines(_ value: String) -> [String] {
        value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

private struct WorkspaceFileDiffRowView: View {
    let row: WorkspaceFileDiffRow

    private var marker: String {
        switch row.kind {
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private var tint: Color {
        switch row.kind {
        case .added: return .green
        case .removed: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 12)

            Text("\(row.lineNumber)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)

            Text(row.text.isEmpty ? " " : row.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}


private struct WorkspaceFileBrowserSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pathText = ""
    @State private var didLoadInitialDirectory = false
    @State private var pathActionDraft: WorkspaceFilePathActionDraft?
    @State private var pendingDeleteEntry: RemoteDirectoryEntry?
    @State private var showDeletePathAlert = false
    @State private var showUploadImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("Add Remote File"))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(L10n.string("Browse the active host."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.string("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                TextField(L10n.string("Remote path"), text: $pathText)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        browse(pathText)
                    }

                Button {
                    browse(pathText)
                } label: {
                    Label(L10n.string("Go"), systemImage: "arrow.forward")
                }
            }

            HStack(spacing: 8) {
                Button {
                    browse(appState.workspaceFileBrowserDefaultPath)
                } label: {
                    Label(L10n.string("Hermes Home"), systemImage: "house")
                }

                Button {
                    browse("~")
                } label: {
                    Label(L10n.string("Home"), systemImage: "person.crop.circle")
                }

                if let parentDisplayPath = appState.workspaceFileBrowserListing?.parentDisplayPath {
                    Button {
                        browse(parentDisplayPath)
                    } label: {
                        Label(L10n.string("Up"), systemImage: "arrow.up")
                    }
                }

                Button {
                    beginCreateFolder()
                } label: {
                    Label(L10n.string("New Folder"), systemImage: "folder.badge.plus")
                }
                .disabled(appState.workspaceFileBrowserListing == nil)

                Button {
                    showUploadImporter = true
                } label: {
                    Label(L10n.string("Upload"), systemImage: "square.and.arrow.up")
                }
                .disabled(appState.workspaceFileBrowserListing == nil || appState.isUploadingWorkspaceFile)

                if appState.isUploadingWorkspaceFile {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }
            .controlSize(.small)

            if let errorMessage = appState.workspaceFileBrowserError {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let notice = appState.workspaceFileBrowserNotice {
                Text(notice)
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            browserContent
            previewPanel

            HStack {
                if let listing = appState.workspaceFileBrowserListing {
                    let visibleCount = listing.entries.count
                    let total = listing.totalEntryCount
                    Text(
                        listing.isTruncated
                            ? L10n.string("Showing %@ of %@ items", "\(visibleCount)", "\(total)")
                            : L10n.string("%@ items", "\(total)")
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    addTypedPath()
                } label: {
                    Label(L10n.string("Add Path"), systemImage: "plus")
                }
                .disabled(pathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 820, height: 700)
        .fileImporter(
            isPresented: $showUploadImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleUploadSelection(result)
        }
        .sheet(item: $pathActionDraft) { draft in
            WorkspaceFilePathActionSheet(draft: draft) { submittedPath in
                switch draft.kind {
                case .newFolder:
                    Task {
                        await appState.createWorkspaceDirectory(path: submittedPath)
                    }
                case .rename(let sourcePath):
                    Task {
                        await appState.renameWorkspacePath(from: sourcePath, to: submittedPath)
                    }
                }
            }
        }
        .alert(L10n.string("Delete this path?"), isPresented: $showDeletePathAlert, presenting: pendingDeleteEntry) { entry in
            Button(L10n.string("Delete"), role: .destructive) {
                Task {
                    await appState.deleteWorkspacePath(path: entry.displayPath)
                    pendingDeleteEntry = nil
                }
            }
            Button(L10n.string("Cancel"), role: .cancel) {
                pendingDeleteEntry = nil
            }
        } message: { entry in
            Text(L10n.string("This removes %@ from the active workspace.", entry.name))
        }
        .task {
            guard !didLoadInitialDirectory else { return }
            didLoadInitialDirectory = true
            let initialPath = appState.workspaceFileBrowserDefaultPath
            pathText = initialPath
            await appState.browseWorkspaceDirectory(path: initialPath)
            if let displayPath = appState.workspaceFileBrowserListing?.displayPath {
                pathText = displayPath
            }
        }
    }

    private var browserContent: some View {
        Group {
            if appState.isLoadingWorkspaceFileBrowser && appState.workspaceFileBrowserListing == nil {
                HermesLoadingState(label: "Loading remote files...", minHeight: 300)
            } else if let listing = appState.workspaceFileBrowserListing {
                List {
                    ForEach(listing.entries) { entry in
                        browserRow(entry)
                    }
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            } else {
                ContentUnavailableView(
                    L10n.string("No Directory Loaded"),
                    systemImage: "folder",
                    description: Text(L10n.string("Enter a remote path to browse files over SSH."))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    private func browserRow(_ entry: RemoteDirectoryEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entryIcon(for: entry))
                .foregroundStyle(entry.kind == .directory ? .blue : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .lineLimit(1)

                Text(entryMetadata(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if entry.canOpenDirectory {
                Button {
                    browse(entry.displayPath)
                } label: {
                    Label(L10n.string("Open"), systemImage: "folder")
                }
                .controlSize(.small)
            } else if entry.isTooLargeToEdit {
                Text(L10n.string("Too large to edit"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if isBookmarked(entry) {
                Button {
                } label: {
                    Label(L10n.string("Added"), systemImage: "checkmark")
                }
                .controlSize(.small)
                .disabled(true)
            } else if entry.canBookmark {
                Button {
                    addBookmark(entry)
                } label: {
                    Label(L10n.string("Add"), systemImage: "plus")
                }
                .controlSize(.small)
            }

            Menu {
                if entry.kind == .file {
                    Button {
                        Task {
                            await appState.previewWorkspacePath(entry.displayPath)
                        }
                    } label: {
                        Label(L10n.string("Preview"), systemImage: "eye")
                    }
                }

                Button {
                    beginRename(entry)
                } label: {
                    Label(L10n.string("Rename"), systemImage: "pencil")
                }

                Button(role: .destructive) {
                    pendingDeleteEntry = entry
                    showDeletePathAlert = true
                } label: {
                    Label(L10n.string("Delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if entry.canOpenDirectory {
                browse(entry.displayPath)
            } else if entry.canBookmark, !isBookmarked(entry) {
                addBookmark(entry)
            }
        }
    }

    @ViewBuilder
    private var previewPanel: some View {
        if appState.isLoadingWorkspacePreview || appState.workspacePreviewFile != nil || appState.workspacePreviewError != nil {
            HermesSurfacePanel(
                title: "Preview",
                subtitle: appState.workspacePreviewFile?.path ?? "Workspace preview endpoint"
            ) {
                if appState.isLoadingWorkspacePreview {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.string("Loading preview..."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let errorMessage = appState.workspacePreviewError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let preview = appState.workspacePreviewFile {
                    WorkspacePreviewPanel(preview: preview)
                }
            }
            .frame(maxHeight: 190)
        }
    }

    private func beginCreateFolder() {
        let parentPath = appState.workspaceFileBrowserListing?.displayPath ?? pathText
        pathActionDraft = WorkspaceFilePathActionDraft(
            kind: .newFolder,
            title: L10n.string("Create Folder"),
            prompt: L10n.string("Enter the full workspace path for the new folder."),
            initialPath: appendingPathComponent("New Folder", to: parentPath),
            submitTitle: L10n.string("Create")
        )
    }

    private func beginRename(_ entry: RemoteDirectoryEntry) {
        pathActionDraft = WorkspaceFilePathActionDraft(
            kind: .rename(sourcePath: entry.displayPath),
            title: L10n.string("Rename Path"),
            prompt: L10n.string("Enter the new full workspace path."),
            initialPath: entry.displayPath,
            submitTitle: L10n.string("Rename")
        )
    }

    private func browse(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pathText = trimmed
        Task {
            await appState.browseWorkspaceDirectory(path: trimmed)
            if let displayPath = appState.workspaceFileBrowserListing?.displayPath {
                pathText = displayPath
            }
        }
    }

    private func addTypedPath() {
        let trimmed = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.addWorkspaceFileBookmark(remotePath: trimmed, selectAfterAdd: false)
    }

    private func addBookmark(_ entry: RemoteDirectoryEntry) {
        appState.addWorkspaceFileBookmark(remotePath: entry.displayPath, selectAfterAdd: false)
    }

    private func handleUploadSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await appState.uploadWorkspaceFile(localFileURL: url, to: currentUploadTargetPath)
            }
        case .failure(let error):
            appState.workspaceFileBrowserError = error.localizedDescription
        }
    }

    private var currentUploadTargetPath: String {
        appState.workspaceFileBrowserListing?.displayPath ?? pathText
    }

    private func isBookmarked(_ entry: RemoteDirectoryEntry) -> Bool {
        appState.bookmarkedWorkspaceFileReferences.contains { reference in
            reference.remotePath == entry.displayPath
        }
    }

    private func entryIcon(for entry: RemoteDirectoryEntry) -> String {
        switch entry.kind {
        case .directory:
            return "folder"
        case .file:
            return "doc.text"
        case .symlink:
            return "link"
        case .other:
            return "questionmark.square"
        }
    }

    private func entryMetadata(for entry: RemoteDirectoryEntry) -> String {
        var parts: [String] = []

        switch entry.kind {
        case .directory:
            parts.append(L10n.string("Folder"))
        case .file:
            if let size = entry.size {
                parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            } else {
                parts.append(L10n.string("File"))
            }
        case .symlink:
            parts.append(L10n.string("Link"))
        case .other:
            parts.append(L10n.string("Other"))
        }

        if entry.isSymlink, entry.kind != .symlink {
            parts.append(L10n.string("Link"))
        }

        if let modifiedDate = entry.modifiedDate {
            parts.append(DateFormatters.relativeFormatter().localizedString(for: modifiedDate, relativeTo: .now))
        }

        if !entry.isReadable {
            parts.append(L10n.string("No read access"))
        }

        return parts.joined(separator: " / ")
    }

    private func appendingPathComponent(_ component: String, to parent: String) -> String {
        let trimmedParent = parent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedParent.isEmpty else { return component }
        return trimmedParent.hasSuffix("/") ? "\(trimmedParent)\(component)" : "\(trimmedParent)/\(component)"
    }
}

private struct WorkspacePreviewPanel: View {
    let preview: WorkspacePreviewFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(preview.kind)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.10), in: Capsule())

                Text(preview.mime)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(ByteCountFormatter.string(fromByteCount: preview.size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if preview.isText {
                ScrollView {
                    Text(preview.content ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if preview.isImage,
                      let encoded = preview.contentBase64,
                      let data = Data(base64Encoded: encoded),
                      let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 110, alignment: .leading)
            } else {
                Text(L10n.string("Binary preview metadata loaded."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum WorkspaceFilePathActionKind {
    case newFolder
    case rename(sourcePath: String)
}

private struct WorkspaceFilePathActionDraft: Identifiable {
    let id = UUID()
    let kind: WorkspaceFilePathActionKind
    let title: String
    let prompt: String
    let initialPath: String
    let submitTitle: String
}

private struct WorkspaceFilePathActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: WorkspaceFilePathActionDraft
    let onSubmit: (String) -> Void
    @State private var pathText: String

    init(draft: WorkspaceFilePathActionDraft, onSubmit: @escaping (String) -> Void) {
        self.draft = draft
        self.onSubmit = onSubmit
        _pathText = State(initialValue: draft.initialPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.title)
                .font(.title3.weight(.semibold))

            Text(draft.prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(L10n.string("Workspace path"), text: $pathText)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button(L10n.string("Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(draft.submitTitle) {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func submit() {
        let trimmed = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        dismiss()
    }
}
