import SwiftUI

struct CronJobsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var searchText = ""
    @State private var filterMode: CronFilterMode = .all
    @State private var jobToDelete: CronJob?
    @State private var showDeleteConfirmation = false
    @State private var editorMode: CronEditorMode?
    @State private var editorDraft = CronJobDraft()

    enum CronFilterMode: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case paused = "Paused"
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Cron Jobs",
                    subtitle: "Browse, create and maintain Hermes jobs discovered on the active host."
                ) {
                    HermesRefreshButton(isRefreshing: appState.isRefreshingCronJobs) {
                        Task { await appState.refreshCronJobs() }
                    }
                    .disabled(appState.isLoadingCronJobs || appState.isSavingCronJobDraft)
                }

                filterBar
                jobsContent
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)

            detailContent
                .frame(minWidth: 460, idealWidth: 580, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appState.activeConnectionID) {
            if appState.cronJobs.isEmpty {
                await appState.loadCronJobs()
            }
        }
        .alert("Remove cron job?", isPresented: $showDeleteConfirmation) {
            Button("Remove", role: .destructive) {
                guard let jobToDelete else { return }
                Task { await appState.deleteCronJob(jobToDelete) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let jobToDelete {
                Text("“\(jobToDelete.resolvedName)” will be removed from the remote Hermes scheduler. This cannot be undone.")
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Filter", selection: $filterMode) {
                ForEach(CronFilterMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Button {
                startCreating()
            } label: {
                Label("New", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .help("Create a new cron job")
            .disabled(appState.isSavingCronJobDraft || appState.isOperatingOnCronJob)

            Spacer(minLength: 12)

            HermesExpandableSearchField(
                text: $searchText,
                prompt: "Search jobs"
            )
        }
    }

    @ViewBuilder
    private var jobsContent: some View {
        if appState.isLoadingCronJobs && appState.cronJobs.isEmpty {
            HermesSurfacePanel {
                HermesLoadingState(
                    label: "Loading cron jobs…",
                    minHeight: 300
                )
            }
        } else if let error = appState.cronJobsError, appState.cronJobs.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load cron jobs",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if appState.cronJobs.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "No cron jobs found",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("No saved Hermes cron jobs were discovered under \(cronJobsPath) on this SSH target.")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else {
            HermesSurfacePanel(
                title: panelTitle,
                subtitle: "Select a job to inspect its schedule, payload and recent activity."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = appState.cronJobsError {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if filteredJobs.isEmpty {
                        ContentUnavailableView(
                            "No matching cron jobs",
                            systemImage: "magnifyingglass",
                            description: Text("Try searching by title, schedule, skill, model, delivery target or prompt text.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(filteredJobs) { job in
                                    CronJobCardRow(
                                        job: job,
                                        isSelected: appState.selectedCronJobID == job.id && editorMode == nil
                                    ) {
                                        editorMode = nil
                                        appState.selectedCronJobID = job.id
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingCronJobs && !appState.isRefreshingCronJobs && !appState.cronJobs.isEmpty {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let editorMode {
            CronJobEditorView(
                mode: editorMode,
                draft: $editorDraft,
                errorMessage: appState.cronJobsError,
                isSaving: appState.isSavingCronJobDraft,
                onCancel: {
                    self.editorMode = nil
                },
                onSave: {
                    await saveEditor()
                }
            )
        } else {
            CronJobDetailView(
                job: selectedJob,
                operationInFlight: operationInFlight(for: selectedJob),
                onEdit: {
                    guard let selectedJob else { return }
                    startEditing(selectedJob)
                },
                onCreate: {
                    startCreating()
                },
                onRunNow: {
                    guard let selectedJob else { return }
                    Task { await appState.runCronJobNow(selectedJob) }
                },
                onTogglePause: {
                    guard let selectedJob else { return }
                    Task {
                        if selectedJob.isPaused {
                            await appState.resumeCronJob(selectedJob)
                        } else {
                            await appState.pauseCronJob(selectedJob)
                        }
                    }
                },
                onDelete: {
                    guard let selectedJob else { return }
                    jobToDelete = selectedJob
                    showDeleteConfirmation = true
                }
            )
        }
    }

    private var filteredJobs: [CronJob] {
        appState.cronJobs.filter { job in
            switch filterMode {
            case .all:
                break
            case .active:
                guard job.isActive else { return false }
            case .paused:
                guard job.isPaused else { return false }
            }

            return job.matchesSearch(searchText)
        }
    }

    private var panelTitle: String {
        let total = appState.cronJobs.count
        let filtered = filteredJobs.count
        let isFiltering = filterMode != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isFiltering {
            return "Cron Jobs (\(filtered) of \(total))"
        }

        return "Cron Jobs (\(total))"
    }

    private var cronJobsPath: String {
        if let activeConnection = appState.activeConnection {
            return activeConnection.remoteCronJobsPath
        }

        return "~/.hermes/cron/jobs.json"
    }

    private var selectedJob: CronJob? {
        guard let selectedCronJobID = appState.selectedCronJobID else { return nil }
        return appState.cronJobs.first(where: { $0.id == selectedCronJobID })
    }

    private func operationInFlight(for job: CronJob?) -> Bool {
        guard let job else { return false }
        return appState.isOperatingOnCronJob && appState.operatingCronJobID == job.id
    }

    private func startCreating() {
        editorDraft = CronJobDraft()
        editorMode = .create
    }

    private func startEditing(_ job: CronJob) {
        editorDraft = CronJobDraft(job: job)
        editorMode = .edit(jobID: job.id)
    }

    private func saveEditor() async {
        switch editorMode {
        case .create:
            if await appState.createCronJob(editorDraft) {
                editorMode = nil
            }
        case .edit(let jobID):
            guard let job = appState.cronJobs.first(where: { $0.id == jobID }) else { return }
            if await appState.updateCronJob(job, draft: editorDraft) {
                editorMode = nil
            }
        case .none:
            return
        }
    }
}

private enum CronEditorMode: Equatable {
    case create
    case edit(jobID: String)

    var title: String {
        switch self {
        case .create:
            return "New Cron Job"
        case .edit:
            return "Edit Cron Job"
        }
    }

    var actionTitle: String {
        switch self {
        case .create:
            return "Create Job"
        case .edit:
            return "Save Changes"
        }
    }
}

private struct CronJobCardRow: View {
    let job: CronJob
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(job.resolvedName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Text(job.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        CronStatusBadge(job: job)

                        if let model = job.displayModel {
                            HermesBadge(text: model, tint: .orange)
                        }
                    }
                }

                Text(job.previewPrompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        CronMetaLabel(text: job.resolvedScheduleDisplay)

                        if let lastRunAt = job.lastRunAt {
                            CronMetaLabel(
                                text: "Last run \(DateFormatters.relativeFormatter().localizedString(for: lastRunAt, relativeTo: .now))"
                            )
                        } else if let nextRunAt = job.nextRunAt {
                            CronMetaLabel(
                                text: "Next run \(DateFormatters.relativeFormatter().localizedString(for: nextRunAt, relativeTo: .now))"
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        CronMetaLabel(text: job.resolvedScheduleDisplay)

                        if let lastRunAt = job.lastRunAt {
                            CronMetaLabel(
                                text: "Last run \(DateFormatters.relativeFormatter().localizedString(for: lastRunAt, relativeTo: .now))"
                            )
                        } else if let nextRunAt = job.nextRunAt {
                            CronMetaLabel(
                                text: "Next run \(DateFormatters.relativeFormatter().localizedString(for: nextRunAt, relativeTo: .now))"
                            )
                        }
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
    }
}

private struct CronJobDetailView: View {
    let job: CronJob?
    let operationInFlight: Bool
    let onEdit: () -> Void
    let onCreate: () -> Void
    let onRunNow: () -> Void
    let onTogglePause: () -> Void
    let onDelete: () -> Void

    private let metadataColumns = [
        GridItem(.adaptive(minimum: 180), alignment: .topLeading)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let job {
                    headerPanel(job)

                    if let lastError = job.lastError {
                        HermesSurfacePanel(
                            title: "Last Error",
                            subtitle: "Most recent execution failure reported by Hermes."
                        ) {
                            Text(lastError)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }

                    metadataPanel(job)

                    if !job.skills.isEmpty {
                        HermesSurfacePanel(
                            title: "Skills",
                            subtitle: "Skills attached to this cron job payload."
                        ) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(job.skills, id: \.self) { skill in
                                        HermesBadge(
                                            text: skill,
                                            tint: .accentColor,
                                            isMonospaced: true
                                        )
                                    }
                                }
                            }
                        }
                    }

                    HermesSurfacePanel(
                        title: "Prompt",
                        subtitle: "Payload Hermes will run for this scheduled job."
                    ) {
                        HermesInsetSurface {
                            Text(job.trimmedPrompt ?? "No prompt payload saved for this job.")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    HermesSurfacePanel {
                        ContentUnavailableView(
                            "Select a cron job",
                            systemImage: "calendar.badge.clock",
                            description: Text("Choose a Hermes cron job from the active host to inspect it, or create a new one.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)

                        Button("Create Cron Job", action: onCreate)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }

    private func headerPanel(_ job: CronJob) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(job.resolvedName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(job.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        CronStatusBadge(job: job)

                        if let model = job.displayModel {
                            HermesBadge(text: model, tint: .orange)
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button("Edit", action: onEdit)
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight)

                        Button("Run Now", action: onRunNow)
                            .buttonStyle(.bordered)
                            .disabled(operationInFlight)

                        Button(job.isPaused ? "Resume" : "Pause", action: onTogglePause)
                            .buttonStyle(.bordered)
                            .disabled(operationInFlight)

                        Button("Remove", role: .destructive, action: onDelete)
                            .buttonStyle(.bordered)
                            .disabled(operationInFlight)

                        if operationInFlight {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button("Edit", action: onEdit)
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight)

                        HStack(spacing: 8) {
                            Button("Run Now", action: onRunNow)
                                .buttonStyle(.bordered)
                                .disabled(operationInFlight)

                            Button(job.isPaused ? "Resume" : "Pause", action: onTogglePause)
                                .buttonStyle(.bordered)
                                .disabled(operationInFlight)
                        }

                        Button("Remove", role: .destructive, action: onDelete)
                            .buttonStyle(.bordered)
                            .disabled(operationInFlight)
                    }
                }
            }
        }
    }

    private func metadataPanel(_ job: CronJob) -> some View {
        HermesSurfacePanel(
            title: "Details",
            subtitle: "Schedule metadata and recent execution markers reported by Hermes."
        ) {
            LazyVGrid(columns: metadataColumns, alignment: .leading, spacing: 14) {
                HermesLabeledValue(
                    label: "Schedule",
                    value: job.resolvedScheduleDisplay,
                    emphasizeValue: true
                )

                if let timezone = job.schedule?.timezone {
                    HermesLabeledValue(
                        label: "Timezone",
                        value: timezone,
                        isMonospaced: true
                    )
                }

                if job.nextRunAt != nil || job.lastRunAt != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if let nextRunAt = job.nextRunAt {
                            HermesLabeledValue(
                                label: "Next run",
                                value: DateFormatters.shortDateTimeFormatter().string(from: nextRunAt)
                            )
                        }

                        if let lastRunAt = job.lastRunAt {
                            HermesLabeledValue(
                                label: "Last run",
                                value: DateFormatters.shortDateTimeFormatter().string(from: lastRunAt)
                            )
                        }
                    }
                }

                if let createdAt = job.createdAt {
                    HermesLabeledValue(
                        label: "Created",
                        value: DateFormatters.shortDateTimeFormatter().string(from: createdAt)
                    )
                }

                if let lastStatus = job.lastStatus {
                    HermesLabeledValue(
                        label: "Last status",
                        value: lastStatus
                    )
                }

                if let provider = job.provider {
                    HermesLabeledValue(
                        label: "Provider",
                        value: provider,
                        isMonospaced: true
                    )
                }

                if let baseURL = job.baseURL {
                    HermesLabeledValue(
                        label: "Base URL",
                        value: baseURL,
                        isMonospaced: true
                    )
                }

                if let deliveryTarget = job.deliveryTarget {
                    HermesLabeledValue(
                        label: "Delivery",
                        value: deliveryTarget
                    )
                }

                if let remaining = job.recurrence?.remaining {
                    HermesLabeledValue(
                        label: "Remaining runs",
                        value: String(remaining),
                        isMonospaced: true
                    )
                } else if let times = job.recurrence?.times {
                    HermesLabeledValue(
                        label: "Planned runs",
                        value: String(times),
                        isMonospaced: true
                    )
                }

                if let origin = job.origin?.label ?? job.origin?.source ?? job.origin?.kind {
                    HermesLabeledValue(
                        label: "Origin",
                        value: origin,
                        isMonospaced: job.origin?.source != nil
                    )
                }

                if let lastDeliveryError = job.lastDeliveryError {
                    HermesLabeledValue(
                        label: "Delivery error",
                        value: lastDeliveryError
                    )
                }
            }
        }
    }
}

private struct CronJobEditorView: View {
    @EnvironmentObject private var appState: AppState
    let mode: CronEditorMode
    @Binding var draft: CronJobDraft
    let errorMessage: String?
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerPanel

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                basicsPanel
                schedulePanel
                metadataPanel
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }

    private var headerPanel: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("The app will write the right cron job structure into `\(cronJobsPath)` on the active host.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(mode.actionTitle) {
                        Task { await onSave() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)

                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .disabled(isSaving)

                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var basicsPanel: some View {
        HermesSurfacePanel(
            title: "Basics",
            subtitle: "Define what this cron job should do."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                CronFormField(label: "Title") {
                    TextField("Morning Briefing", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }

                CronFormField(label: "Prompt") {
                    TextEditor(text: $draft.prompt)
                        .font(.body)
                        .frame(minHeight: 170)
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
            }
        }
    }

    private var schedulePanel: some View {
        HermesSurfacePanel(
            title: "Schedule",
            subtitle: "Choose whether Hermes should run this once or on a recurring cadence."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                CronFormField(label: "Frequency") {
                    Picker("Frequency", selection: schedulePresetBinding) {
                        ForEach(CronSchedulePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                switch draft.schedule.preset {
                case .afterDelay:
                    delayRow
                case .atDateTime:
                    dateTimeRow
                case .everyInterval:
                    intervalRow
                case .hourly:
                    hourlyRow
                case .daily, .weekdays, .monthly, .weekly:
                    timeRow
                case .custom:
                    customExpressionRow
                }

                if draft.schedule.preset == .weekly {
                    CronFormField(label: "Day") {
                        Picker("Day", selection: scheduleWeekdayBinding) {
                            ForEach(Array(CronScheduleFormatter.weekdayPickerLabels.enumerated()), id: \.offset) { index, label in
                                Text(label).tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                if draft.schedule.preset == .monthly {
                    CronFormField(label: "Day of Month") {
                        Stepper(value: scheduleDayOfMonthBinding, in: 1...31) {
                            Text("Day \(draft.schedule.dayOfMonth)")
                        }
                    }
                }

                if showsTimezoneField {
                    CronFormField(label: "Timezone") {
                        TextField("Europe/Rome, UTC, America/New_York", text: $draft.timezone)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HermesInsetSurface {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(draft.schedule.summary)
                            .font(.headline)

                        if let expression = draft.schedule.expression {
                            Text(expression)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var metadataPanel: some View {
        HermesSurfacePanel(
            title: "Metadata",
            subtitle: "Delivery is required. Skills and model overrides remain optional."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                CronFormField(label: "Skills") {
                    TextField("daily-robi, morning-briefing", text: $draft.skillsText)
                        .textFieldStyle(.roundedBorder)
                }

                CronFormField(label: "Delivery") {
                    Picker("Delivery", selection: deliveryPresetBinding) {
                        ForEach(CronDeliveryPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                if draft.deliveryPreset == .custom {
                    CronFormField(label: "Custom Target") {
                        TextField("telegram:-1001234567890:17585", text: customDeliveryBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    Text("Use full Hermes target syntax such as `telegram:-1001234567890`, `telegram:-1001234567890:17585`, or another supported platform target.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if draft.deliveryPreset == .local {
                    Text("`Local Only` saves cron output under `\(cronOutputPath)` on the active host.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                CronFormField(label: "Model") {
                    TextField("gpt-5.4-mini", text: $draft.model)
                        .textFieldStyle(.roundedBorder)
                }

                CronFormField(label: "Provider") {
                    TextField("openai", text: $draft.provider)
                        .textFieldStyle(.roundedBorder)
                }

                CronFormField(label: "Base URL") {
                    TextField("https://api.openai.com/v1", text: $draft.baseURL)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var delayRow: some View {
        HStack(alignment: .top, spacing: 12) {
            CronFormField(label: "Delay") {
                Stepper(value: scheduleIntervalValueBinding, in: 1...999) {
                    Text("\(draft.schedule.intervalValue)")
                }
            }

            CronFormField(label: "Unit") {
                Picker("Unit", selection: scheduleIntervalUnitBinding) {
                    ForEach(CronIntervalUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var dateTimeRow: some View {
        CronFormField(label: "Run At") {
            DatePicker(
                "Run At",
                selection: scheduleOneTimeDateBinding,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
        }
    }

    private var intervalRow: some View {
        HStack(alignment: .top, spacing: 12) {
            CronFormField(label: "Every") {
                Stepper(value: scheduleIntervalValueBinding, in: 1...999) {
                    Text("\(draft.schedule.intervalValue)")
                }
            }

            CronFormField(label: "Unit") {
                Picker("Unit", selection: scheduleIntervalUnitBinding) {
                    ForEach(CronIntervalUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var hourlyRow: some View {
        CronFormField(label: "Minute") {
            Picker("Minute", selection: scheduleMinuteBinding) {
                ForEach(0..<60, id: \.self) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var timeRow: some View {
        HStack(alignment: .top, spacing: 12) {
            CronFormField(label: "Hour") {
                Picker("Hour", selection: scheduleHourBinding) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            CronFormField(label: "Minute") {
                Picker("Minute", selection: scheduleMinuteBinding) {
                    ForEach(0..<60, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var customExpressionRow: some View {
        CronFormField(label: "Schedule") {
            TextField("0 8 * * * or daily at 9am", text: customExpressionBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var showsTimezoneField: Bool {
        switch draft.schedule.preset {
        case .hourly, .daily, .weekdays, .weekly, .monthly, .custom:
            return true
        case .afterDelay, .atDateTime, .everyInterval:
            return false
        }
    }

    private var schedulePresetBinding: Binding<CronSchedulePreset> {
        Binding(
            get: { draft.schedule.preset },
            set: { draft.schedule.preset = $0 }
        )
    }

    private var scheduleHourBinding: Binding<Int> {
        Binding(
            get: { draft.schedule.hour },
            set: { draft.schedule.hour = $0 }
        )
    }

    private var scheduleMinuteBinding: Binding<Int> {
        Binding(
            get: { draft.schedule.minute },
            set: { draft.schedule.minute = $0 }
        )
    }

    private var scheduleWeekdayBinding: Binding<Int> {
        Binding(
            get: { draft.schedule.weekday },
            set: { draft.schedule.weekday = $0 }
        )
    }

    private var scheduleDayOfMonthBinding: Binding<Int> {
        Binding(
            get: { draft.schedule.dayOfMonth },
            set: { draft.schedule.dayOfMonth = $0 }
        )
    }

    private var scheduleIntervalValueBinding: Binding<Int> {
        Binding(
            get: { draft.schedule.intervalValue },
            set: { draft.schedule.intervalValue = max(1, $0) }
        )
    }

    private var scheduleIntervalUnitBinding: Binding<CronIntervalUnit> {
        Binding(
            get: { draft.schedule.intervalUnit },
            set: { draft.schedule.intervalUnit = $0 }
        )
    }

    private var scheduleOneTimeDateBinding: Binding<Date> {
        Binding(
            get: { draft.schedule.oneTimeDate },
            set: { draft.schedule.oneTimeDate = $0 }
        )
    }

    private var customExpressionBinding: Binding<String> {
        Binding(
            get: { draft.schedule.customExpression },
            set: { draft.schedule.customExpression = $0 }
        )
    }

    private var deliveryPresetBinding: Binding<CronDeliveryPreset> {
        Binding(
            get: { draft.deliveryPreset },
            set: { draft.deliveryPreset = $0 }
        )
    }

    private var customDeliveryBinding: Binding<String> {
        Binding(
            get: { draft.customDeliveryTarget },
            set: { draft.customDeliveryTarget = $0 }
        )
    }

    private var cronJobsPath: String {
        appState.activeConnection?.remoteCronJobsPath ?? "~/.hermes/cron/jobs.json"
    }

    private var cronOutputPath: String {
        (appState.activeConnection?.remoteHermesHomePath ?? "~/.hermes") + "/cron/output/"
    }
}

private struct CronFormField<Content: View>: View {
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

private struct CronStatusBadge: View {
    let job: CronJob

    var body: some View {
        HermesBadge(text: job.displayState, tint: tint)
    }

    private var tint: Color {
        switch job.state {
        case .running:
            return .blue
        case .paused:
            return .orange
        case .failed, .error:
            return .red
        case .scheduled, .other:
            return .green
        }
    }
}

private struct CronMetaLabel: View {
    let text: String

    var body: some View {
        Text(L10n.string(text))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
