import AppKit
import SwiftUI

struct KanbanView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var splitLayout: HermesSplitLayout

    @State private var searchText = ""
    @State private var statusFilter: KanbanStatusFilter = .all
    @State private var assigneeFilter = KanbanFilterOption.all
    @State private var tenantFilter = KanbanFilterOption.all
    @State private var isCreatingTask = false
    @State private var isCreatingBoard = false
    @State private var isEditingWorkspaceTask = false
    @State private var taskDraft = KanbanTaskDraft()
    @State private var workspaceTaskDraft = KanbanTaskDraft()
    @State private var boardDraft = KanbanBoardDraft()
    @State private var boardPendingArchive: KanbanProject?
    @State private var showArchiveBoardConfirmation = false

    var body: some View {
        HermesCollapsibleHSplitView(layout: $splitLayout, detailMinWidth: 420) {
            primaryContent
        } detail: {
            detailContent
                .hermesSplitDetailColumn(minWidth: 420, idealWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appState.activeConnectionID) {
            await appState.loadKanbanBoards()
            if appState.kanbanBoard == nil {
                await appState.loadKanbanBoard()
            }
        }
        .onChange(of: appState.includeArchivedKanbanTasks) { _, includeArchived in
            Task { await appState.refreshKanbanBoard(includeArchived: includeArchived) }
        }
        .onChange(of: statusFilter) { _, filter in
            if filter == .archived, !appState.includeArchivedKanbanTasks {
                appState.includeArchivedKanbanTasks = true
            }
        }
        .alert(L10n.string("Archive this Kanban board?"), isPresented: $showArchiveBoardConfirmation, presenting: boardPendingArchive) { board in
            Button(L10n.string("Archive"), role: .destructive) {
                Task { await appState.archiveKanbanBoard(board) }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: { board in
            Text(L10n.string("“%@” will be moved out of the active board list. Existing task data stays recoverable on the remote host.", board.resolvedName))
        }
    }

    private var primaryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HermesPageHeader(
                title: "Kanban",
                subtitle: "Inspect and operate Hermes Kanban projects over SSH."
            ) {
                HermesExpandableSearchField(
                    text: $searchText,
                    prompt: L10n.string("Search tasks"),
                    expandedWidth: 220,
                    focusRequestID: appState.searchFocusRequestID
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            kanbanToolbar
            boardContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var kanbanToolbar: some View {
        HermesWrappingFlowLayout(horizontalSpacing: 10, verticalSpacing: 8) {
            HStack(spacing: 8) {
                boardPicker
                statusPicker
                advancedFilterMenu
            }
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 8) {
                createTaskButton
                if !appState.isWorkspaceKanbanBoardSelected {
                    dispatchButton
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var boardPicker: some View {
        Menu {
            Section {
                ForEach(appState.kanbanBoards) { board in
                    Button {
                        isCreatingBoard = false
                        isCreatingTask = false
                        isEditingWorkspaceTask = false
                        Task { await appState.selectKanbanBoard(board.slug) }
                    } label: {
                        HStack {
                            menuLabel(board.resolvedName, isSelected: board.slug == appState.selectedKanbanBoardSlug, shouldLocalize: false)
                            if board.taskTotal > 0 {
                                Text("\(board.taskTotal)")
                            }
                        }
                    }
                }
            } header: {
                Text(L10n.string("Boards"))
            }

            Divider()

            if appState.supportsKanbanBoardManagement {
                Button {
                    boardDraft = KanbanBoardDraft()
                    isCreatingTask = false
                    isEditingWorkspaceTask = false
                    isCreatingBoard = true
                } label: {
                    Label(L10n.string("New Board"), systemImage: "plus")
                }
            } else {
                Text(L10n.string("Run hermes update to enable multiple boards"))
            }

            if appState.supportsKanbanBoardManagement,
               let selectedBoard = appState.selectedKanbanBoard,
               !selectedBoard.isDefault,
               selectedBoard.slug != KanbanProject.workspaceTasksSlug {
                Divider()

                Button(L10n.string("Archive Board"), role: .destructive) {
                    boardPendingArchive = selectedBoard
                    showArchiveBoardConfirmation = true
                }
                .disabled(appState.isOperatingOnKanbanBoard)
            }
        } label: {
            KanbanToolbarMenuLabel(
                title: "Board",
                value: selectedBoardTitle,
                systemImage: "rectangle.3.group",
                width: 172
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(appState.isLoadingKanbanBoards || appState.isSavingKanbanBoardDraft || appState.isOperatingOnKanbanBoard)
        .help(L10n.string("Select Kanban board"))
    }

    private var statusPicker: some View {
        Menu {
            Section {
                ForEach(KanbanStatusFilter.allCases, id: \.self) { option in
                    Button {
                        statusFilter = option
                    } label: {
                        menuLabel(option.title, isSelected: statusFilter == option)
                    }
                }
            } header: {
                Text(L10n.string("Status"))
            }
        } label: {
            KanbanToolbarMenuLabel(
                title: "Status",
                value: L10n.string(statusFilter.title),
                systemImage: "circle.dashed.inset.filled",
                width: 136
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var createTaskButton: some View {
        Button {
            startCreatingTask()
        } label: {
            Label(L10n.string("New Task"), systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: false)
        .help(L10n.string("Create a Kanban task"))
        .disabled(appState.isSavingKanbanTaskDraft || appState.isOperatingOnKanbanTask)
    }

    private var dispatchButton: some View {
        Button {
            Task { await appState.dispatchKanbanNow() }
        } label: {
            if appState.isDispatchingKanban {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            } else {
                Label(L10n.string("Nudge dispatcher"), systemImage: "bolt")
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(L10n.string("Nudge dispatcher"))
        .disabled(appState.isDispatchingKanban || appState.isLoadingKanbanBoard)
    }

    private var advancedFilterMenu: some View {
        Menu {
            Section {
                Button {
                    assigneeFilter = .all
                } label: {
                    menuLabel("All assignees", isSelected: assigneeFilter == .all)
                }

                ForEach(assigneeOptions, id: \.self) { assignee in
                    Button {
                        assigneeFilter = .value(assignee)
                    } label: {
                        menuLabel(assignee, isSelected: assigneeFilter == .value(assignee), shouldLocalize: false)
                    }
                }
            } header: {
                Text(L10n.string("Assignee"))
            }

            Section {
                Button {
                    tenantFilter = .all
                } label: {
                    menuLabel("All tenants", isSelected: tenantFilter == .all)
                }

                ForEach(tenantOptions, id: \.self) { tenant in
                    Button {
                        tenantFilter = .value(tenant)
                    } label: {
                        menuLabel(tenant, isSelected: tenantFilter == .value(tenant), shouldLocalize: false)
                    }
                }
            } header: {
                Text(L10n.string("Tenant"))
            }

            Divider()

            Button {
                appState.includeArchivedKanbanTasks.toggle()
            } label: {
                menuLabel("Archived", isSelected: appState.includeArchivedKanbanTasks)
            }
        } label: {
            Label {
                HStack(spacing: 6) {
                    Text(L10n.string("Filter"))

                    if activeAdvancedFilterCount > 0 {
                        Text("\(activeAdvancedFilterCount)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
            } icon: {
                Image(systemName: hasAdvancedFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(hasAdvancedFilters ? .accentColor : nil)
    }

    private func menuLabel(_ text: String, isSelected: Bool, shouldLocalize: Bool = true) -> some View {
        Group {
            if isSelected {
                Label(shouldLocalize ? L10n.string(text) : text, systemImage: "checkmark")
            } else {
                Text(shouldLocalize ? L10n.string(text) : text)
            }
        }
    }

    private var hasAdvancedFilters: Bool {
        activeAdvancedFilterCount > 0
    }

    private var activeAdvancedFilterCount: Int {
        var count = 0
        if assigneeFilter != .all { count += 1 }
        if tenantFilter != .all { count += 1 }
        if appState.includeArchivedKanbanTasks { count += 1 }
        return count
    }

    private var isFilteringTasks: Bool {
        statusFilter != .all ||
            assigneeFilter != .all ||
            tenantFilter != .all ||
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            appState.includeArchivedKanbanTasks
    }

    private var selectedBoardTitle: String {
        appState.selectedKanbanBoard?.resolvedName ?? L10n.string("Default")
    }

    @ViewBuilder
    private var boardContent: some View {
        if (appState.isLoadingKanbanBoards || appState.isLoadingKanbanBoard) && appState.kanbanBoard == nil {
            HermesSurfacePanel {
                HermesLoadingState(
                    label: "Loading Kanban board...",
                    minHeight: 320
                )
            }
        } else if let error = appState.kanbanError, appState.kanbanBoard == nil {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Unable to load Kanban"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else if let board = appState.kanbanBoard, !board.isInitialized {
            HermesSurfacePanel {
                VStack(alignment: .leading, spacing: 18) {
                    ContentUnavailableView(
                        L10n.string("No Kanban board yet"),
                        systemImage: "rectangle.3.group",
                        description: Text(L10n.string("No Kanban database exists at %@. Create the first task to initialize this board on the remote host.", board.databasePath))
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)

                    Button {
                        startCreatingTask()
                    } label: {
                        Label(L10n.string("Create First Task"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isSavingKanbanTaskDraft)
                }
            }
        } else if let board = appState.kanbanBoard {
            HermesSurfacePanel(
                title: panelTitle,
                subtitle: boardSubtitle(board)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if let warning = board.warning {
                        KanbanWarningBanner(message: warning)
                    }

                    if let warning = dispatcherWarning(for: board) {
                        KanbanWarningBanner(message: warning)
                    }

                    if let error = appState.kanbanError {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if filteredTasks.isEmpty {
                        KanbanEmptyTaskState(
                            isFiltering: isFilteringTasks,
                            isSaving: appState.isSavingKanbanTaskDraft,
                            onCreate: startCreatingTask
                        )
                    } else {
                        ScrollView {
                            kanbanGroupedList(board)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingKanbanBoard && !appState.isRefreshingKanbanBoard {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
    }

    private func kanbanBoardLayout(_ board: KanbanBoard) -> some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(displayStatuses, id: \.rawValue) { status in
                    KanbanColumnView(
                        status: status,
                        tasks: filteredTasks(for: status),
                        selectedTaskID: appState.selectedKanbanTaskID,
                        onSelect: selectTask
                    )
                    .frame(width: 250)
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func kanbanGroupedList(_ board: KanbanBoard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(displayStatuses, id: \.rawValue) { status in
                let tasks = filteredTasks(for: status)
                if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(L10n.string(status.displayTitle))
                                .font(.headline)

                            HermesBadge(text: "\(tasks.count)", tint: KanbanColors.tint(for: status))
                        }

                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(tasks) { task in
                                KanbanTaskCard(
                                    task: task,
                                    isSelected: task.id == appState.selectedKanbanTaskID,
                                    onSelect: { selectTask(task) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var detailContent: some View {
        if isCreatingBoard {
            KanbanBoardEditorView(
                draft: $boardDraft,
                errorMessage: appState.kanbanError,
                isSaving: appState.isSavingKanbanBoardDraft,
                onCancel: {
                    isCreatingBoard = false
                },
                onSave: {
                    if await appState.createKanbanBoard(boardDraft) {
                        isCreatingBoard = false
                    }
                }
            )
        } else if isCreatingTask {
            KanbanTaskEditorView(
                draft: $taskDraft,
                errorMessage: appState.kanbanError,
                isSaving: appState.isSavingKanbanTaskDraft,
                assignees: assigneeOptions,
                onCancel: {
                    isCreatingTask = false
                },
                onSave: {
                    if await appState.createKanbanTask(taskDraft) {
                        isCreatingTask = false
                    }
                }
            )
        } else if isEditingWorkspaceTask {
            KanbanTaskEditorView(
                draft: $workspaceTaskDraft,
                errorMessage: appState.kanbanError,
                isSaving: appState.isOperatingOnKanbanTask,
                assignees: assigneeOptions,
                onCancel: {
                    isEditingWorkspaceTask = false
                },
                onSave: {
                    guard let taskID = appState.selectedKanbanTaskID else { return }
                    if await appState.updateWorkspaceKanbanTask(taskID: taskID, draft: workspaceTaskDraft) {
                        isEditingWorkspaceTask = false
                    }
                }
            )
        } else if appState.isWorkspaceKanbanBoardSelected {
            WorkspaceTaskDetailView(
                task: selectedTask,
                errorMessage: appState.kanbanError,
                operationInFlight: selectedTask.map { task in
                    appState.isOperatingOnKanbanTask && appState.operatingKanbanTaskID == task.id
                } ?? false,
                onCreate: {
                    taskDraft = KanbanTaskDraft()
                    isCreatingBoard = false
                    isEditingWorkspaceTask = false
                    isCreatingTask = true
                },
                onEdit: { task in
                    workspaceTaskDraft = draft(from: task)
                    isCreatingBoard = false
                    isCreatingTask = false
                    isEditingWorkspaceTask = true
                },
                onMove: { taskID, status in
                    await appState.moveWorkspaceKanbanTask(taskID: taskID, to: status)
                },
                onDelete: { taskID in
                    await appState.deleteWorkspaceKanbanTask(taskID: taskID)
                }
            )
        } else {
            KanbanTaskDetailView(
                task: selectedTask,
                detail: appState.selectedKanbanTaskDetail,
                errorMessage: appState.kanbanError,
                isLoading: appState.isLoadingKanbanTaskDetail,
                operationInFlight: selectedTask.map { task in
                    appState.isOperatingOnKanbanTask && appState.operatingKanbanTaskID == task.id
                } ?? false,
                assignees: assigneeOptions,
                onCreate: {
                    taskDraft = KanbanTaskDraft()
                    isCreatingBoard = false
                    isCreatingTask = true
                },
                onSpecify: { taskID in
                    await appState.specifyKanbanTask(taskID: taskID)
                },
                onAssign: { taskID, assignee in
                    await appState.assignKanbanTask(taskID: taskID, assignee: assignee)
                },
                onUpdateFields: { taskID, body, tenant, priority, skills in
                    await appState.updateKanbanTaskFields(
                        taskID: taskID,
                        body: body,
                        tenant: tenant,
                        priority: priority,
                        skills: skills
                    )
                },
                onSetParents: { taskID, parentIDs in
                    await appState.setKanbanTaskParents(taskID: taskID, parentIDs: parentIDs)
                },
                onSetChildren: { taskID, childIDs in
                    await appState.setKanbanTaskChildren(taskID: taskID, childIDs: childIDs)
                },
                onComment: { taskID, comment in
                    await appState.addKanbanComment(taskID: taskID, body: comment)
                },
                onBlock: { taskID, reason in
                    await appState.blockKanbanTask(taskID: taskID, reason: reason)
                },
                onUnblock: { taskID in
                    await appState.unblockKanbanTask(taskID: taskID)
                },
                onComplete: { taskID, result in
                    await appState.completeKanbanTask(taskID: taskID, result: result)
                },
                onReclaim: { taskID, reason in
                    await appState.reclaimKanbanTask(taskID: taskID, reason: reason)
                },
                onReassign: { taskID, assignee, reclaimFirst, reason in
                    await appState.reassignKanbanTask(
                        taskID: taskID,
                        assignee: assignee,
                        reclaimFirst: reclaimFirst,
                        reason: reason
                    )
                },
                onEditResult: { taskID, result, summary, metadataJSON in
                    await appState.editKanbanTaskResult(
                        taskID: taskID,
                        result: result,
                        summary: summary,
                        metadataJSON: metadataJSON
                    )
                },
                onArchive: { taskID in
                    await appState.archiveKanbanTask(taskID: taskID)
                },
                onDelete: { taskID in
                    await appState.deleteKanbanTask(taskID: taskID)
                },
                onSetHomeSubscription: { taskID, homeChannel, subscribed in
                    await appState.setKanbanHomeSubscription(
                        taskID: taskID,
                        homeChannel: homeChannel,
                        subscribed: subscribed
                    )
                }
            )
        }
    }

    private var filteredTasks: [KanbanTask] {
        guard let board = appState.kanbanBoard else { return [] }
        return board.tasks.filter { task in
            if !appState.includeArchivedKanbanTasks && task.status == .archived {
                return false
            }
            if let status = statusFilter.status, task.status != status {
                return false
            }
            if case .value(let assignee) = assigneeFilter, task.assignee != assignee {
                return false
            }
            if case .value(let tenant) = tenantFilter, task.tenant != tenant {
                return false
            }
            return task.matchesSearch(searchText)
        }
    }

    private func filteredTasks(for status: KanbanTaskStatus) -> [KanbanTask] {
        filteredTasks.filter { $0.status == status }
    }

    private var displayStatuses: [KanbanTaskStatus] {
        if let status = statusFilter.status {
            return [status]
        }

        return KanbanTaskStatus.boardStatuses.filter { status in
            status != .archived || appState.includeArchivedKanbanTasks
        }
    }

    private var assigneeOptions: [String] {
        let boardAssignees = appState.kanbanBoard?.assignees.map(\.name) ?? []
        let taskAssignees = appState.kanbanBoard?.tasks.compactMap(\.assignee) ?? []
        return Array(Set(boardAssignees + taskAssignees)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var tenantOptions: [String] {
        let boardTenants = appState.kanbanBoard?.tenants ?? []
        let taskTenants = appState.kanbanBoard?.tasks.compactMap(\.tenant) ?? []
        return Array(Set(boardTenants + taskTenants)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var selectedTask: KanbanTask? {
        appState.kanbanBoard?.task(id: appState.selectedKanbanTaskID)
    }

    private var panelTitle: String {
        let total = appState.kanbanBoard?.tasks.count ?? 0
        let filtered = filteredTasks.count

        if isFilteringTasks {
            return L10n.string("Kanban Tasks (%@ of %@)", "\(filtered)", "\(total)")
        }

        return L10n.string("Kanban Tasks (%@)", "\(total)")
    }

    private func boardSubtitle(_ board: KanbanBoard) -> String {
        let boardName = appState.selectedKanbanBoard?.resolvedName ?? selectedBoardTitle
        if appState.isWorkspaceKanbanBoardSelected {
            return L10n.string(
                "Workspace task board %@ from %@. Shared with the :3077 web and mobile app.",
                boardName,
                board.databasePath
            )
        }
        return L10n.string(
            "Kanban board %@ at %@. SSH-native; active profile is the operator.",
            boardName,
            board.databasePath
        )
    }

    private func dispatcherWarning(for board: KanbanBoard) -> String? {
        guard board.tasks.contains(where: { $0.status == .ready }) else { return nil }
        guard board.dispatcher?.isKnownInactive == true else { return nil }
        return board.dispatcher?.message ?? "Ready tasks are waiting, but the remote Hermes dispatcher does not appear to be active."
    }

    private func selectTask(_ task: KanbanTask) {
        Task { await appState.loadKanbanTaskDetail(taskID: task.id) }
    }

    private func startCreatingTask() {
        taskDraft = KanbanTaskDraft()
        isCreatingBoard = false
        isEditingWorkspaceTask = false
        isCreatingTask = true
    }

    private func draft(from task: KanbanTask) -> KanbanTaskDraft {
        var draft = KanbanTaskDraft()
        draft.title = task.resolvedTitle
        draft.body = task.body ?? ""
        draft.assignee = task.assignee ?? ""
        draft.priority = task.priority
        draft.skillsText = task.skills.joined(separator: ", ")
        draft.startsInTriage = task.status == .triage
        return draft
    }
}

private enum KanbanStatusFilter: Hashable, CaseIterable {
    case all
    case triage
    case todo
    case ready
    case running
    case review
    case blocked
    case done
    case archived

    var title: String {
        switch self {
        case .all:
            "All"
        case .triage:
            "Triage"
        case .todo:
            "Todo"
        case .ready:
            "Ready"
        case .running:
            "Running"
        case .review:
            "Review"
        case .blocked:
            "Blocked"
        case .done:
            "Done"
        case .archived:
            "Archived"
        }
    }

    var status: KanbanTaskStatus? {
        switch self {
        case .all:
            nil
        case .triage:
            .triage
        case .todo:
            .todo
        case .ready:
            .ready
        case .running:
            .running
        case .review:
            .review
        case .blocked:
            .blocked
        case .done:
            .done
        case .archived:
            .archived
        }
    }
}

private enum KanbanFilterOption: Hashable {
    case all
    case value(String)

    var displayTitle: String {
        switch self {
        case .all:
            L10n.string("All")
        case .value(let value):
            value
        }
    }
}

private enum KanbanActionKind: Hashable {
    case specify
    case details
    case parents
    case children
    case assign
    case comment
    case complete
    case recovery
    case editResult
    case block
}

private enum KanbanColors {
    static func tint(for status: KanbanTaskStatus) -> Color {
        switch status {
        case .triage:
            .secondary
        case .todo:
            .blue
        case .ready:
            .green
        case .running:
            .orange
        case .review:
            .cyan
        case .blocked:
            .red
        case .done:
            .purple
        case .archived:
            .secondary
        case .other:
            .secondary
        }
    }
}

private struct WorkspaceTaskDetailView: View {
    let task: KanbanTask?
    let errorMessage: String?
    let operationInFlight: Bool
    let onCreate: () -> Void
    let onEdit: (KanbanTask) -> Void
    let onMove: (String, KanbanTaskStatus) async -> Void
    let onDelete: (String) async -> Void

    var body: some View {
        HermesSurfacePanel(title: "Workspace Task", subtitle: "Shared with web and mobile /tasks.") {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                if let task {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(task.resolvedTitle)
                                .font(.headline)
                                .textSelection(.enabled)

                            Spacer()

                            HermesBadge(text: task.status.displayTitle, tint: KanbanColors.tint(for: task.status))
                        }

                        if let body = task.trimmedBody {
                            Text(body)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            WorkspaceTaskFact(label: "ID", value: task.id)
                            WorkspaceTaskFact(label: "Assignee", value: task.assignee ?? "Unassigned")
                            WorkspaceTaskFact(label: "Priority", value: task.priorityLabel)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            onEdit(task)
                        } label: {
                            Label(L10n.string("Edit"), systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                        .disabled(operationInFlight)

                        Menu {
                            ForEach([KanbanTaskStatus.triage, .ready, .running, .review, .blocked, .done], id: \.rawValue) { status in
                                Button(L10n.string(status.displayTitle)) {
                                    Task { await onMove(task.id, status) }
                                }
                            }
                        } label: {
                            Label(L10n.string("Move"), systemImage: "arrow.right")
                        }
                        .buttonStyle(.bordered)
                        .disabled(operationInFlight)
                        Button(role: .destructive) {
                            Task { await onDelete(task.id) }
                        } label: {
                            Label(L10n.string("Delete"), systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(operationInFlight)

                    }

                    Text("Deletes use the canonical /api/hermes-tasks backend so web and desktop mutate the same task ledger.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView(
                        L10n.string("Select a task"),
                        systemImage: "checklist",
                        description: Text(L10n.string("Choose a Workspace task from the board, or create a new one."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)

                    Button {
                        onCreate()
                    } label: {
                        Label(L10n.string("New Task"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct WorkspaceTaskFact: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L10n.string(label))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}

private struct KanbanToolbarMenuLabel: View {
    let title: String
    let value: String
    let systemImage: String
    let width: CGFloat

    var body: some View {
        Label {
            HStack(spacing: 5) {
                Text(L10n.string(title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct KanbanEmptyTaskState: View {
    let isFiltering: Bool
    let isSaving: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )

            if !isFiltering {
                Button {
                    onCreate()
                } label: {
                    Label(L10n.string("Create Task"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var title: String {
        isFiltering ? L10n.string("No matching tasks") : L10n.string("No tasks")
    }

    private var systemImage: String {
        isFiltering ? "magnifyingglass" : "checklist"
    }

    private var description: String {
        if isFiltering {
            return L10n.string("Try a different search, status, assignee, tenant, or archive filter.")
        }

        return L10n.string("Choose a task from the selected board, or create a new one.")
    }
}

private struct KanbanWarningBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct KanbanColumnView: View {
    let status: KanbanTaskStatus
    let tasks: [KanbanTask]
    let selectedTaskID: String?
    let onSelect: (KanbanTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            LazyVStack(alignment: .leading, spacing: 8) {
                if tasks.isEmpty {
                    emptyState
                } else {
                    ForEach(tasks) { task in
                        KanbanTaskCard(
                            task: task,
                            isSelected: task.id == selectedTaskID,
                            onSelect: { onSelect(task) }
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.026), in: RoundedRectangle(cornerRadius: HermesTheme.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.panelCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(KanbanColors.tint(for: status))
                .frame(width: 7, height: 7)

            Text(L10n.string(status.displayTitle))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text("\(tasks.count)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(KanbanColors.tint(for: status).opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        Text(L10n.string("No tasks"))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous))
    }
}

private struct KanbanTaskCard: View {
    let task: KanbanTask
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text(task.resolvedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    priorityBadge
                }

                if let body = task.trimmedBody {
                    Text(body.replacingOccurrences(of: "\n", with: " "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                metadataStrip
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? HermesTheme.selectedFill : isHovering ? Color.secondary.opacity(0.07) : HermesTheme.rowFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? HermesTheme.selectedStroke : HermesTheme.subtleStroke, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 9)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(L10n.string("Copy Task ID")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(task.id, forType: .string)
            }
        }
    }

    private var priorityBadge: some View {
        Text(task.priorityLabel)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(task.priority == 0 ? Color.secondary : Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((task.priority == 0 ? Color.secondary : Color.orange).opacity(0.10), in: Capsule())
    }

    private var metadataStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            HermesWrappingFlowLayout(horizontalSpacing: 7, verticalSpacing: 5) {
                KanbanTaskMetadataChip(text: task.shortID, systemImage: "number", isMonospaced: true)

                if let assignee = task.assignee {
                    KanbanTaskMetadataChip(text: "@\(assignee)", systemImage: "person.crop.circle", tint: .accentColor, isMonospaced: true)
                }

                if let tenant = task.tenant {
                    KanbanTaskMetadataChip(text: tenant, systemImage: "building.2")
                }

                if task.commentCount > 0 {
                    KanbanTaskMetadataChip(text: "\(task.commentCount)", systemImage: "text.bubble")
                }

                if let progress = task.progressLabel {
                    KanbanTaskMetadataChip(text: progress, systemImage: "checkmark.circle", tint: .green, isMonospaced: true)
                }

                if !task.parentIDs.isEmpty {
                    KanbanTaskMetadataChip(text: "\(task.parentIDs.count)", systemImage: "link")
                }

                if task.hasActiveWarnings {
                    KanbanTaskMetadataChip(text: "\(task.warnings?.count ?? 0)", systemImage: "exclamationmark.triangle", tint: .orange, isMonospaced: true)
                }
            }

            if let latest = task.latestActivityDate {
                Text(L10n.string("Active %@", DateFormatters.relativeFormatter().localizedString(for: latest, relativeTo: .now)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct KanbanTaskMetadataChip: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary
    var isMonospaced = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))

            Text(text)
                .font(isMonospaced ? .system(.caption2, design: .monospaced).weight(.semibold) : .caption2.weight(.medium))
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct KanbanBoardEditorView: View {
    @Binding var draft: KanbanBoardDraft
    let errorMessage: String?
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HermesSurfacePanel {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.string("New Kanban Board"))
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(L10n.string("The board will be created on the active Hermes host over SSH."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button(L10n.string("Create Board")) {
                                Task { await onSave() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving || draft.validationError != nil)

                            Button(L10n.string("Cancel"), action: onCancel)
                                .buttonStyle(.bordered)
                                .disabled(isSaving)

                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if let validationError = draft.validationError {
                            HermesValidationMessage(text: validationError)
                        }
                    }
                }

                if let errorMessage {
                    KanbanWarningBanner(message: errorMessage)
                }

                HermesSurfacePanel(title: "Board") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            KanbanFormField(label: "Slug") {
                                TextField(L10n.string("project-alpha"), text: $draft.slug)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }

                            KanbanFormField(label: "Name") {
                                TextField(L10n.string("Project Alpha"), text: $draft.name)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        KanbanFormField(label: "Description") {
                            TextEditor(text: $draft.description)
                                .font(.body)
                                .frame(minHeight: 96)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                }
                        }

                        Toggle(L10n.string("Make remote current board"), isOn: $draft.switchAfterCreate)
                            .toggleStyle(.checkbox)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }
}

private struct KanbanTaskEditorView: View {
    @Binding var draft: KanbanTaskDraft
    let errorMessage: String?
    let isSaving: Bool
    let assignees: [String]
    let onCancel: () -> Void
    let onSave: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HermesSurfacePanel {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.string("New Kanban Task"))
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(L10n.string("The task will be created in the selected Hermes Kanban board over SSH."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button(L10n.string("Create Task")) {
                                Task { await onSave() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving || draft.validationError != nil)

                            Button(L10n.string("Cancel"), action: onCancel)
                                .buttonStyle(.bordered)
                                .disabled(isSaving)

                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if let validationError = draft.validationError {
                            HermesValidationMessage(text: validationError)
                        }
                    }
                }

                if let errorMessage {
                    KanbanWarningBanner(message: errorMessage)
                }

                HermesSurfacePanel(
                    title: "Task",
                    subtitle: "Describe the work and optionally assign it to a Hermes profile."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        KanbanFormField(label: "Title") {
                            TextField(L10n.string("Investigate failing release check"), text: $draft.title)
                                .textFieldStyle(.roundedBorder)
                        }

                        KanbanFormField(label: "Body") {
                            TextEditor(text: $draft.body)
                                .font(.body)
                                .frame(minHeight: 160)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                }
                        }

                        HStack(alignment: .top, spacing: 14) {
                            KanbanFormField(label: "Assignee") {
                                ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "researcher")
                            }

                            KanbanFormField(label: "Tenant") {
                                TextField(L10n.string("optional"), text: $draft.tenant)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(alignment: .top, spacing: 16) {
                            KanbanFormField(label: "Priority") {
                                VStack(alignment: .leading, spacing: 5) {
                                    TextField("0", value: $draft.priority, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 96)

                                    Text(L10n.string("Higher values sort first. 0 is the Hermes default."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            KanbanFormField(label: "Max retries") {
                                VStack(alignment: .leading, spacing: 5) {
                                    TextField(L10n.string("board default"), text: $draft.maxRetriesText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 120)

                                    Text(L10n.string("Leave empty to inherit the board failure limit. Set a value above 0 to override it for this task."))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Toggle(L10n.string("Start in triage"), isOn: $draft.startsInTriage)
                            .toggleStyle(.checkbox)

                        KanbanFormField(label: "Skills") {
                            TextField(L10n.string("deploy-check, release-notes"), text: $draft.skillsText)
                                .textFieldStyle(.roundedBorder)
                        }

                        KanbanFormField(label: "Parents") {
                            TextField(L10n.string("t_parent_a, t_parent_b"), text: $draft.parentIDsText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }
}

private struct KanbanTaskDetailView: View {
    let task: KanbanTask?
    let detail: KanbanTaskDetail?
    let errorMessage: String?
    let isLoading: Bool
    let operationInFlight: Bool
    let assignees: [String]
    let onCreate: () -> Void
    let onSpecify: (String) async -> Void
    let onAssign: (String, String?) async -> Void
    let onUpdateFields: (String, String, String, Int, [String]) async -> Void
    let onSetParents: (String, [String]) async -> Void
    let onSetChildren: (String, [String]) async -> Void
    let onComment: (String, String) async -> Bool
    let onBlock: (String, String?) async -> Void
    let onUnblock: (String) async -> Void
    let onComplete: (String, String?) async -> Void
    let onReclaim: (String, String?) async -> Void
    let onReassign: (String, String?, Bool, String?) async -> Void
    let onEditResult: (String, String, String?, String?) async -> Void
    let onArchive: (String) async -> Void
    let onDelete: (String) async -> Void
    let onSetHomeSubscription: (String, KanbanHomeChannel, Bool) async -> Bool

    @State private var draft = KanbanActionDraft()
    @State private var showArchiveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var expandedAction: KanbanActionKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let task {
                    headerPanel(task)

                    if let errorMessage {
                        KanbanWarningBanner(message: errorMessage)
                    }

                    if isLoading && detail == nil {
                        HermesSurfacePanel {
                            HermesLoadingState(label: "Loading task detail...", minHeight: 180)
                        }
                    } else {
                        metadataPanel(task)
                        actionPanel(task)
                        recoveryWarningPanel(task)

                        if let body = task.trimmedBody {
                            HermesSurfacePanel(
                                title: "Body",
                                subtitle: "Task description stored on the remote board."
                            ) {
                                HermesInsetSurface {
                                    Text(body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        if let result = task.trimmedResult {
                            HermesSurfacePanel(
                                title: "Result",
                                subtitle: "Completion handoff stored by Hermes."
                            ) {
                                HermesInsetSurface {
                                    Text(result)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        if let detail {
                            homeChannelsPanel(task, detail)
                            linksPanel(detail)
                            commentsPanel(task, detail)
                            runsPanel(detail)
                            eventsPanel(detail)
                            logPanel(detail)
                        }
                    }
                } else {
                    HermesSurfacePanel {
                        VStack(alignment: .leading, spacing: 18) {
                            ContentUnavailableView(
                                L10n.string("Select a Kanban task"),
                                systemImage: "rectangle.3.group",
                                description: Text(L10n.string("Choose a task from the selected board, or create a new one."))
                            )
                            .frame(maxWidth: .infinity, minHeight: 280)

                            Button {
                                onCreate()
                            } label: {
                                Label(L10n.string("Create Kanban Task"), systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .onChange(of: task?.id) { _, _ in
            resetDraft()
            expandedAction = nil
        }
        .onChange(of: detail?.parentIDs) { _, _ in
            resetDraft()
        }
        .onChange(of: detail?.childIDs) { _, _ in
            resetDraft()
        }
        .onAppear {
            resetDraft()
        }
        .alert(L10n.string("Archive this task?"), isPresented: $showArchiveConfirmation, presenting: task) { task in
            Button(L10n.string("Archive"), role: .destructive) {
                Task { await onArchive(task.id) }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: { task in
            Text(L10n.string("“%@” will be hidden from the active board unless archived tasks are shown.", task.resolvedTitle))
        }
        .alert(L10n.string("Delete this task?"), isPresented: $showDeleteConfirmation, presenting: task) { task in
            Button(L10n.string("Delete"), role: .destructive) {
                Task { await onDelete(task.id) }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: { task in
            Text(L10n.string("“%@” will be permanently removed from the remote Kanban database, including comments, links, events, and run history. Remote workspace files are left untouched.", task.resolvedTitle))
        }
    }

    private func resetDraft() {
        draft = KanbanActionDraft(
            comment: "",
            result: task?.trimmedResult ?? "",
            blockReason: "",
            recoveryReason: "",
            recoverySummary: task?.trimmedResult ?? "",
            recoveryMetadata: "",
            reclaimBeforeReassign: task?.isRunning == true,
            assignee: task?.assignee ?? "",
            body: task?.trimmedBody ?? "",
            tenant: task?.tenant ?? "",
            priority: task?.priority ?? 0,
            skillsText: KanbanTaskDraft.listText(task?.skills ?? []),
            parentIDsText: KanbanTaskDraft.listText(detail?.parentIDs ?? task?.parentIDs ?? []),
            childIDsText: KanbanTaskDraft.listText(detail?.childIDs ?? task?.childIDs ?? [])
        )
    }

    private func headerPanel(_ task: KanbanTask) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.resolvedTitle)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(task.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .contextMenu {
                                Button(L10n.string("Copy Task ID")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(task.id, forType: .string)
                                }
                            }
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        HermesBadge(text: task.status.displayTitle, tint: KanbanColors.tint(for: task.status))
                        HermesBadge(text: task.priorityLabel, tint: task.priority == 0 ? .secondary : .orange, isMonospaced: true)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        primaryActions(task)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        primaryActions(task)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func primaryActions(_ task: KanbanTask) -> some View {
        if task.canUnblock {
            Button(L10n.string("Unblock")) {
                Task { await onUnblock(task.id) }
            }
            .buttonStyle(.borderedProminent)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(operationInFlight)
        }

        if task.canSpecify {
            Button(L10n.string("Specify")) {
                toggleAction(.specify)
            }
            .buttonStyle(.borderedProminent)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(operationInFlight)
        }

        if task.canComplete {
            if task.status == .blocked {
                Button(L10n.string("Complete")) {
                    toggleAction(.complete)
                }
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(operationInFlight)
            } else {
                Button(L10n.string("Complete")) {
                    toggleAction(.complete)
                }
                .buttonStyle(.borderedProminent)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(operationInFlight)
            }
        }

        if task.canBlock {
            Button(L10n.string("Block")) {
                toggleAction(.block)
            }
            .buttonStyle(.bordered)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(operationInFlight)
        }

        Menu {
            Button(L10n.string("Archive"), role: .destructive) {
                showArchiveConfirmation = true
            }
            .disabled(task.status == .archived)

            Button(L10n.string("Delete"), role: .destructive) {
                showDeleteConfirmation = true
            }
        } label: {
            Label(L10n.string("More"), systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(operationInFlight)
        .help(L10n.string("More task actions"))

        if operationInFlight {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func metadataPanel(_ task: KanbanTask) -> some View {
        HermesSurfacePanel(
            title: "Details",
            subtitle: "Board metadata from the remote host."
        ) {
            HermesInspectorFieldList(fields: metadataFields(for: task))

            if !task.skills.isEmpty {
                Divider()
                    .opacity(0.5)

                HermesWrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(task.skills, id: \.self) { skill in
                        HermesBadge(text: skill, tint: .accentColor, isMonospaced: true)
                    }
                }
            }

            if let lastSpawnError = task.lastSpawnError {
                Divider()
                    .opacity(0.5)

                KanbanWarningBanner(message: lastSpawnError)
            }
        }
    }

    private func metadataFields(for task: KanbanTask) -> [HermesInspectorField] {
        var fields = [
            HermesInspectorField(
                id: "status",
                label: "Status",
                value: L10n.string(task.status.displayTitle),
                emphasizeValue: true
            ),
            HermesInspectorField(
                id: "assignee",
                label: "Assignee",
                value: task.assignee ?? L10n.string("Unassigned"),
                isMonospaced: task.assignee != nil
            ),
            HermesInspectorField(
                id: "priority",
                label: "Priority",
                value: "\(task.priority)",
                isMonospaced: true
            ),
            HermesInspectorField(
                id: "max-retries",
                label: "Max retries",
                value: task.maxRetries.map(String.init) ?? L10n.string("Board default"),
                isMonospaced: task.maxRetries != nil
            ),
            HermesInspectorField(
                id: "workspace",
                label: "Workspace",
                value: L10n.string(task.workspaceKind.displayTitle)
            )
        ]

        if let workspacePath = task.workspacePath {
            fields.append(HermesInspectorField(
                id: "workspace-path",
                label: "Workspace path",
                value: workspacePath,
                isMonospaced: true
            ))
        }

        if let progress = task.progressLabel {
            fields.append(HermesInspectorField(
                id: "child-progress",
                label: "Child progress",
                value: progress,
                isMonospaced: true
            ))
        }

        if let tenant = task.tenant {
            fields.append(HermesInspectorField(
                id: "tenant",
                label: "Tenant",
                value: tenant,
                isMonospaced: true
            ))
        }

        if let createdBy = task.createdBy {
            fields.append(HermesInspectorField(
                id: "created-by",
                label: "Created by",
                value: createdBy,
                isMonospaced: true
            ))
        }

        if let created = task.createdDate {
            fields.append(HermesInspectorField(
                id: "created",
                label: "Created",
                value: DateFormatters.shortDateTimeFormatter().string(from: created)
            ))
        }

        if let latest = task.latestActivityDate {
            fields.append(HermesInspectorField(
                id: "latest-activity",
                label: "Latest activity",
                value: DateFormatters.shortDateTimeFormatter().string(from: latest)
            ))
        }

        if let workerPID = task.workerPID {
            fields.append(HermesInspectorField(
                id: "worker-pid",
                label: "Worker PID",
                value: "\(workerPID)",
                isMonospaced: true
            ))
        }

        if let heartbeat = task.lastHeartbeatAt {
            fields.append(HermesInspectorField(
                id: "heartbeat",
                label: "Heartbeat",
                value: DateFormatters.shortDateTimeFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(heartbeat)))
            ))
        }

        return fields
    }

    private func actionPanel(_ task: KanbanTask) -> some View {
        HermesSurfacePanel(
            title: "Update Task",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if task.canSpecify {
                    KanbanActionDisclosureRow(
                        title: "Specify",
                        summary: "Promote this triage idea into a concrete todo",
                        systemImage: "sparkles.rectangle.stack",
                        isExpanded: expandedAction == .specify,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.specify) }
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.string("Hermes may refine the title and body before moving this task from Triage to Todo."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button(L10n.string("Specify Task")) {
                                Task {
                                    await onSpecify(task.id)
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight)
                        }
                    }

                    KanbanActionDivider()
                }

                KanbanActionDisclosureRow(
                    title: "Details",
                    summary: "Edit body, tenant, priority, and skills",
                    systemImage: "slider.horizontal.3",
                    isExpanded: expandedAction == .details,
                    isDisabled: operationInFlight,
                    onToggle: { toggleAction(.details) }
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        KanbanFormField(label: "Body") {
                            KanbanTextEditor(text: $draft.body, placeholder: L10n.string("Task description"))
                        }

                        HStack(alignment: .top, spacing: 12) {
                            KanbanFormField(label: "Tenant") {
                                TextField(L10n.string("optional"), text: $draft.tenant)
                                    .textFieldStyle(.roundedBorder)
                            }

                            KanbanFormField(label: "Priority") {
                                TextField("0", value: $draft.priority, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 96)
                            }
                        }

                        KanbanFormField(label: "Skills") {
                            TextField(L10n.string("deploy-check, release-notes"), text: $draft.skillsText)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(L10n.string("Apply")) {
                            Task {
                                await onUpdateFields(
                                    task.id,
                                    draft.normalizedBodyForUpdate,
                                    draft.normalizedTenantForUpdate,
                                    draft.priority,
                                    draft.skills
                                )
                                expandedAction = nil
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(operationInFlight || !detailsChanged(for: task))
                    }
                }

                KanbanActionDivider()

                if let detail {
                    KanbanActionDisclosureRow(
                        title: "Parents",
                        summary: dependencySummary(detail.parentIDs),
                        systemImage: "arrow.up.right.and.arrow.down.left.rectangle",
                        isExpanded: expandedAction == .parents,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.parents) }
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(L10n.string("t_parent_a, t_parent_b"), text: $draft.parentIDsText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                            Button(L10n.string("Apply")) {
                                Task {
                                    await onSetParents(task.id, draft.parentIDs)
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight || draft.parentIDs == detail.parentIDs)
                        }
                    }

                    KanbanActionDivider()

                    KanbanActionDisclosureRow(
                        title: "Children",
                        summary: dependencySummary(detail.childIDs),
                        systemImage: "point.3.connected.trianglepath.dotted",
                        isExpanded: expandedAction == .children,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.children) }
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(L10n.string("t_child_a, t_child_b"), text: $draft.childIDsText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                            Button(L10n.string("Apply")) {
                                Task {
                                    await onSetChildren(task.id, draft.childIDs)
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight || draft.childIDs == detail.childIDs)
                        }
                    }

                    KanbanActionDivider()
                }

                KanbanActionDisclosureRow(
                    title: "Assignee",
                    summary: task.assignee.map { "@\($0)" } ?? "Unassigned",
                    systemImage: "person.crop.circle",
                    isExpanded: expandedAction == .assign,
                    isDisabled: operationInFlight,
                    onToggle: { toggleAction(.assign) }
                ) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "unassigned")

                            Button(L10n.string("Apply")) {
                                Task {
                                    await onAssign(task.id, draft.normalizedAssignee)
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight || draft.normalizedAssignee == task.assignee)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "unassigned")

                            Button(L10n.string("Apply")) {
                                Task {
                                    await onAssign(task.id, draft.normalizedAssignee)
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight || draft.normalizedAssignee == task.assignee)
                        }
                    }
                }

                KanbanActionDivider()

                KanbanActionDisclosureRow(
                    title: "Comment",
                    summary: "Add a note to the task history",
                    systemImage: "text.bubble",
                    isExpanded: expandedAction == .comment,
                    isDisabled: operationInFlight,
                    onToggle: { toggleAction(.comment) }
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        KanbanTextEditor(text: $draft.comment, placeholder: L10n.string("Write a short update..."))

                        Button(L10n.string("Add Comment")) {
                            Task {
                                if await onComment(task.id, draft.comment) {
                                    draft.comment = ""
                                    expandedAction = nil
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(operationInFlight || draft.normalizedComment == nil)
                    }
                }

                if task.canComplete {
                    KanbanActionDivider()

                    KanbanActionDisclosureRow(
                        title: "Complete",
                        summary: "Finish the task with an optional handoff",
                        systemImage: "checkmark.circle",
                        isExpanded: expandedAction == .complete,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.complete) }
                    ) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                TextField(L10n.string("Optional handoff summary"), text: $draft.result)
                                    .textFieldStyle(.roundedBorder)

                                Button(L10n.string("Complete")) {
                                    Task {
                                        await onComplete(task.id, draft.normalizedResult)
                                        expandedAction = nil
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(operationInFlight)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                TextField(L10n.string("Optional handoff summary"), text: $draft.result)
                                    .textFieldStyle(.roundedBorder)

                                Button(L10n.string("Complete")) {
                                    Task {
                                        await onComplete(task.id, draft.normalizedResult)
                                        expandedAction = nil
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(operationInFlight)
                            }
                        }
                    }
                }

                if task.hasActiveWarnings || task.isRunning || task.status == .done {
                    KanbanActionDivider()

                    KanbanActionDisclosureRow(
                        title: "Recovery",
                        summary: recoverySummary(for: task),
                        systemImage: "wrench.and.screwdriver",
                        isExpanded: expandedAction == .recovery,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.recovery) }
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            if let warnings = task.warnings, warnings.hasWarnings {
                                KanbanRecoveryWarningSummary(warnings: warnings)
                            }

                            if task.isRunning {
                                KanbanFormField(label: "Reason") {
                                    TextField(L10n.string("Optional recovery reason"), text: $draft.recoveryReason)
                                        .textFieldStyle(.roundedBorder)
                                }

                                Button(L10n.string("Reclaim Running Claim")) {
                                    Task {
                                        await onReclaim(task.id, draft.normalizedRecoveryReason)
                                        expandedAction = nil
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(operationInFlight)
                            }

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "unassigned")

                                    Toggle(L10n.string("Reclaim first"), isOn: $draft.reclaimBeforeReassign)
                                        .toggleStyle(.checkbox)
                                        .disabled(!task.isRunning)

                                    Button(L10n.string("Reassign")) {
                                        Task {
                                            await onReassign(
                                                task.id,
                                                draft.normalizedAssignee,
                                                draft.reclaimBeforeReassign,
                                                draft.normalizedRecoveryReason
                                            )
                                            expandedAction = nil
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(operationInFlight || draft.normalizedAssignee == task.assignee)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "unassigned")

                                    Toggle(L10n.string("Reclaim first"), isOn: $draft.reclaimBeforeReassign)
                                        .toggleStyle(.checkbox)
                                        .disabled(!task.isRunning)

                                    Button(L10n.string("Reassign")) {
                                        Task {
                                            await onReassign(
                                                task.id,
                                                draft.normalizedAssignee,
                                                draft.reclaimBeforeReassign,
                                                draft.normalizedRecoveryReason
                                            )
                                            expandedAction = nil
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(operationInFlight || draft.normalizedAssignee == task.assignee)
                                }
                            }
                        }
                    }
                }

                if task.status == .done {
                    KanbanActionDivider()

                    KanbanActionDisclosureRow(
                        title: "Edit Result",
                        summary: "Backfill completion handoff and clear warnings",
                        systemImage: "square.and.pencil",
                        isExpanded: expandedAction == .editResult,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.editResult) }
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            KanbanFormField(label: "Result") {
                                KanbanTextEditor(text: $draft.result, placeholder: L10n.string("Updated completion handoff"))
                            }

                            KanbanFormField(label: "Summary") {
                                TextField(L10n.string("Optional structured handoff summary"), text: $draft.recoverySummary)
                                    .textFieldStyle(.roundedBorder)
                            }

                            KanbanFormField(label: "Metadata JSON") {
                                TextField(L10n.string(#"Optional: {"changed_files":["README.md"]}"#), text: $draft.recoveryMetadata)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }

                            Button(L10n.string("Save Result")) {
                                Task {
                                    await onEditResult(
                                        task.id,
                                        draft.normalizedResult ?? "",
                                        draft.normalizedRecoverySummary,
                                        draft.normalizedRecoveryMetadata
                                    )
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight || draft.normalizedResult == nil)
                        }
                    }
                }

                if task.canBlock {
                    KanbanActionDivider()

                    KanbanActionDisclosureRow(
                        title: "Block",
                        summary: "Pause the task and record the reason",
                        systemImage: "hand.raised",
                        isExpanded: expandedAction == .block,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.block) }
                    ) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                TextField(L10n.string("Optional reason"), text: $draft.blockReason)
                                    .textFieldStyle(.roundedBorder)

                                Button(L10n.string("Block")) {
                                    Task {
                                        await onBlock(task.id, draft.normalizedBlockReason)
                                        expandedAction = nil
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(operationInFlight)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                TextField(L10n.string("Optional reason"), text: $draft.blockReason)
                                    .textFieldStyle(.roundedBorder)

                                Button(L10n.string("Block")) {
                                    Task {
                                        await onBlock(task.id, draft.normalizedBlockReason)
                                        expandedAction = nil
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(operationInFlight)
                            }
                        }
                    }
                }
            }
        }
    }

    private func detailsChanged(for task: KanbanTask) -> Bool {
        draft.normalizedBodyForUpdate != (task.trimmedBody ?? "") ||
            draft.normalizedTenantForUpdate != (task.tenant ?? "") ||
            draft.priority != task.priority ||
            draft.skills != task.skills
    }

    @ViewBuilder
    private func recoveryWarningPanel(_ task: KanbanTask) -> some View {
        if let warnings = task.warnings, warnings.hasWarnings {
            HermesSurfacePanel(
                title: warnings.displayTitle,
                subtitle: "Hermes Agent marked this task for recovery."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    KanbanRecoveryWarningSummary(warnings: warnings)

                    Text(L10n.string("Use Recovery to reclaim a stuck claim, retry with another assignee, or edit the final result after verifying the board state."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func recoverySummary(for task: KanbanTask) -> String {
        if task.hasActiveWarnings {
            return L10n.string("Review warnings and retry safely")
        }
        if task.isRunning {
            return L10n.string("Release or reassign a running worker")
        }
        return L10n.string("Edit a completed handoff")
    }

    private func dependencySummary(_ ids: [String]) -> String {
        if ids.isEmpty {
            return L10n.string("None")
        }
        if ids.count == 1 {
            return ids[0]
        }
        return L10n.string("%@ links", "\(ids.count)")
    }

    private func toggleAction(_ action: KanbanActionKind) {
        withAnimation(.snappy(duration: 0.16)) {
            expandedAction = expandedAction == action ? nil : action
        }
    }

    @ViewBuilder
    private func homeChannelsPanel(_ task: KanbanTask, _ taskDetail: KanbanTaskDetail) -> some View {
        if !taskDetail.homeChannels.isEmpty {
            HermesSurfacePanel(
                title: "Home Channels",
                subtitle: "Gateway home subscriptions for this task."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(taskDetail.homeChannels, id: \.id) { homeChannel in
                        KanbanHomeChannelRow(
                            homeChannel: homeChannel,
                            isDisabled: operationInFlight,
                            onToggle: {
                                await onSetHomeSubscription(task.id, homeChannel, !homeChannel.subscribed)
                            }
                        )
                    }
                }
            }
        }
    }

    private func linksPanel(_ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Dependencies",
            subtitle: "Parent and child task links discovered on the board."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                KanbanIDGroup(title: "Parents", ids: detail.parentIDs)
                KanbanIDGroup(title: "Children", ids: detail.childIDs)
            }
        }
    }

    private func commentsPanel(_ task: KanbanTask, _ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Comments",
            subtitle: "Human and agent notes attached to this task."
        ) {
            if detail.comments.isEmpty {
                Text(L10n.string("No comments yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.comments) { comment in
                        KanbanCommentRow(comment: comment)
                    }
                }
            }
        }
    }

    private func runsPanel(_ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Runs",
            subtitle: "Attempt history recorded by Hermes."
        ) {
            if detail.runs.isEmpty {
                Text(L10n.string("No runs recorded yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.runs) { run in
                        KanbanRunRow(run: run)
                    }
                }
            }
        }
    }

    private func eventsPanel(_ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Events",
            subtitle: "Chronological board events for this task."
        ) {
            if detail.events.isEmpty {
                Text(L10n.string("No events recorded yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.events.suffix(20)) { event in
                        KanbanEventRow(event: event)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func logPanel(_ detail: KanbanTaskDetail) -> some View {
        if let log = detail.workerLog?.trimmingCharacters(in: .whitespacesAndNewlines), !log.isEmpty {
            HermesSurfacePanel(
                title: "Worker Log",
                subtitle: "Tail of the remote worker log for this task."
            ) {
                HermesInsetSurface {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct KanbanFormField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(.caption)
                .foregroundStyle(.secondary)

            content
        }
    }
}

private struct KanbanActionDisclosureRow<Content: View>: View {
    let title: String
    let summary: String
    let systemImage: String
    let isExpanded: Bool
    let isDisabled: Bool
    let onToggle: () -> Void
    let content: Content

    init(
        title: String,
        summary: String,
        systemImage: String,
        isExpanded: Bool,
        isDisabled: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.isExpanded = isExpanded
        self.isDisabled = isDisabled
        self.onToggle = onToggle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 11) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string(title))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(L10n.string(summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)

            if isExpanded {
                content
                    .padding(.leading, 29)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }
}

private struct KanbanActionDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 29)
            .opacity(0.55)
    }
}

private struct KanbanHomeChannelRow: View {
    let homeChannel: KanbanHomeChannel
    let isDisabled: Bool
    let onToggle: () async -> Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: homeChannel.subscribed ? "bell.badge.fill" : "bell")
                .foregroundStyle(homeChannel.subscribed ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(homeChannel.displayPlatform)
                    .font(.subheadline.weight(.semibold))

                Text("\(homeChannel.resolvedName) · \(homeChannel.destinationLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            toggleButton
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var toggleButton: some View {
        if homeChannel.subscribed {
            Button(L10n.string("Subscribed")) {
                Task { _ = await onToggle() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isDisabled)
        } else {
            Button(L10n.string("Subscribe")) {
                Task { _ = await onToggle() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDisabled)
        }
    }
}

private struct KanbanRecoveryWarningSummary: View {
    let warnings: KanbanTaskWarnings

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(warnings.displayMessage))
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    HermesBadge(text: L10n.string("%@ warning events", "\(warnings.count)"), tint: .orange)

                    if let latestDate = warnings.latestDate {
                        Text(DateFormatters.relativeFormatter().localizedString(for: latestDate, relativeTo: .now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct KanbanTextEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 68)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.string(placeholder))
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ComboBoxTextField: View {
    @Binding var text: String
    let suggestions: [String]
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            TextField(L10n.string(placeholder), text: $text)
                .textFieldStyle(.roundedBorder)
                .layoutPriority(1)

            if !suggestions.isEmpty {
                Menu {
                    Button(L10n.string("Unassigned")) {
                        text = ""
                    }

                    Divider()

                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            text = suggestion
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help(L10n.string("Pick a discovered assignee"))
            }
        }
    }
}

private struct KanbanIDGroup: View {
    let title: String
    let ids: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)

            if ids.isEmpty {
                Text(L10n.string("None"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HermesWrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(ids, id: \.self) { id in
                        HermesBadge(text: id, tint: .secondary, isMonospaced: true)
                    }
                }
            }
        }
    }
}

private struct KanbanCommentRow: View {
    let comment: KanbanComment

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(comment.author)
                        .font(.subheadline.weight(.semibold))

                    Text(DateFormatters.relativeFormatter().localizedString(for: comment.createdDate, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(comment.body)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct KanbanRunRow: View {
    let run: KanbanRun

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HermesBadge(text: "#\(run.id)", tint: .secondary, isMonospaced: true)
                    HermesBadge(text: run.resolvedOutcome, tint: run.endedAt == nil ? .orange : .secondary)

                    if let profile = run.profile {
                        HermesBadge(text: "@\(profile)", tint: .accentColor, isMonospaced: true)
                    }
                }

                Text(DateFormatters.shortDateTimeFormatter().string(from: run.startedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let summary = run.summary {
                    Text(summary)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }

                if let error = run.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct KanbanEventRow: View {
    let event: KanbanEvent

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    HermesBadge(text: event.kind, tint: .secondary)

                    if let runID = event.runID {
                        HermesBadge(text: "run \(runID)", tint: .secondary, isMonospaced: true)
                    }

                    Spacer(minLength: 8)

                    Text(DateFormatters.relativeFormatter().localizedString(for: event.createdDate, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let payload = event.displayPayload {
                    Text(payload)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
