import SwiftUI

struct SkillsView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var splitLayout: HermesSplitLayout
    @State private var searchText = ""
    @State private var libraryTab: SkillLibraryTab = .installed
    @State private var editorMode: SkillEditorMode?
    @State private var editorDraft = SkillDraft()
    @State private var rawMarkdownContent = ""
    @State private var workspaceSkills: [WorkspaceSkillItem] = []
    @State private var hubSkills: [WorkspaceSkillHubItem] = []
    @State private var sharedSkillsError: String?
    @State private var sharedSkillsWarning: String?
    @State private var isLoadingSharedSkills = false
    @State private var actionSkillID: String?

    var body: some View {
        HermesCollapsibleHSplitView(layout: $splitLayout, detailMinWidth: 420) {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Skills",
                    subtitle: "Browse installed skills, featured skills, and marketplace search from the shared Workspace API."
                ) {
                    HermesExpandableSearchField(
                        text: $searchText,
                        prompt: L10n.string("Search skills"),
                        expandedWidth: 220,
                        focusRequestID: appState.searchFocusRequestID
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }

                skillsToolbar
                skillsContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        } detail: {
            detailContent
                .hermesSplitDetailColumn(minWidth: 420, idealWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appState.activeConnectionID) {
            if appState.skills.isEmpty {
                await appState.loadSkills(reset: true)
            }
        }
        .task(id: sharedSkillsReloadID) {
            await loadSharedSkillsIfNeeded(force: false)
        }
    }

    @ViewBuilder
    private var skillsContent: some View {
        switch libraryTab {
        case .installed:
            skillsPanel
        case .featured:
            workspaceSkillsPanel(
                title: "Featured Skills",
                subtitle: "Featured skills are loaded from the same Workspace API used by the web app."
            )
        case .marketplace:
            marketplacePanel
        }
    }

    @ViewBuilder
    private var skillsPanel: some View {
        if appState.isLoadingSkills && appState.skills.isEmpty {
            HermesSurfacePanel {
                HermesLoadingState(
                    label: "Loading skills…",
                    minHeight: 300
                )
            }
        } else if let error = appState.skillsError, appState.skills.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Unable to load skills"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if appState.skills.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No skills found"),
                    systemImage: "book.closed",
                    description: Text(L10n.string("No readable SKILL.md files were discovered in the Hermes skill roots for this SSH target."))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else {
            HermesSurfacePanel(
                title: panelTitle,
                subtitle: "Select a skill to inspect its metadata, related assets and full SKILL.md content."
            ) {
                if filteredSkills.isEmpty {
                    ContentUnavailableView(
                        L10n.string("No matching skills"),
                        systemImage: "magnifyingglass",
                        description: Text(L10n.string("Try searching by skill name or category."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(filteredSkills) { skill in
                                SkillCardRow(
                                    skill: skill,
                                    isSelected: skill.id == appState.selectedSkillID
                                ) {
                                    Task {
                                        await appState.loadSkillDetail(summary: skill)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingSkills && !appState.isRefreshingSkills && !appState.skills.isEmpty {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
    }

    @ViewBuilder
    private var workspaceSkillsPanel: some View {
        workspaceSkillsPanel(
            title: "Workspace Skills",
            subtitle: "Skills returned by the shared Workspace API."
        )
    }

    private func workspaceSkillsPanel(title: String, subtitle: String) -> some View {
        HermesSurfacePanel(title: title, subtitle: subtitle) {
            sharedSkillsListContent
        }
        .overlay(alignment: .topTrailing) {
            if isLoadingSharedSkills && (!workspaceSkills.isEmpty || !hubSkills.isEmpty) {
                HermesLoadingOverlay()
                    .padding(18)
            }
        }
    }

    @ViewBuilder
    private var marketplacePanel: some View {
        HermesSurfacePanel(
            title: "Marketplace Search",
            subtitle: "Search the skills hub through the server-side Workspace route. Install actions stay server-gated."
        ) {
            sharedSkillsListContent
        }
        .overlay(alignment: .topTrailing) {
            if isLoadingSharedSkills && !hubSkills.isEmpty {
                HermesLoadingOverlay()
                    .padding(18)
            }
        }
    }

    @ViewBuilder
    private var sharedSkillsListContent: some View {
        if isLoadingSharedSkills && workspaceSkills.isEmpty && hubSkills.isEmpty {
            HermesLoadingState(label: "Loading skills…", minHeight: 300)
        } else if let sharedSkillsError, workspaceSkills.isEmpty && hubSkills.isEmpty {
            ContentUnavailableView(
                "Unable to load Workspace skills",
                systemImage: "exclamationmark.triangle",
                description: Text(sharedSkillsError)
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        } else if libraryTab == .marketplace {
            if hubSkills.isEmpty {
                ContentUnavailableView(
                    "No marketplace results",
                    systemImage: "shippingbox",
                    description: Text(sharedSkillsWarning ?? "Try another marketplace search.")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let sharedSkillsWarning {
                            Text(sharedSkillsWarning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(hubSkills, id: \.resolvedIdentifier) { skill in
                            WorkspaceHubSkillCardRow(
                                skill: skill,
                                actionSkillID: actionSkillID,
                                onInstall: {
                                    await runSharedSkillAction(
                                        action: "install",
                                        identifier: skill.resolvedIdentifier,
                                        category: skill.category
                                    )
                                }
                            )
                        }
                    }
                }
            }
        } else if workspaceSkills.isEmpty {
            ContentUnavailableView(
                "No featured skills",
                systemImage: "star",
                description: Text("The Workspace API did not return any featured skills for the current filters.")
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(workspaceSkills) { skill in
                        WorkspaceSkillCardRow(
                            skill: skill,
                            actionSkillID: actionSkillID,
                            onInstall: {
                                await runSharedSkillAction(
                                    action: "install",
                                    identifier: skill.id,
                                    category: skill.category
                                )
                            },
                            onToggle: {
                                await runSharedSkillAction(
                                    action: "toggle",
                                    identifier: skill.id,
                                    enabled: !skill.isEnabled
                                )
                            },
                            onUninstall: {
                                await runSharedSkillAction(
                                    action: "uninstall",
                                    identifier: skill.id
                                )
                            }
                        )
                    }
                }
            }
        }
    }

    private var skillsToolbar: some View {
        HStack(spacing: 10) {
            Picker("Skills view", selection: $libraryTab) {
                ForEach(SkillLibraryTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 330)

            if libraryTab == .installed {
                HermesCreateActionButton("New Skill") {
                    startCreating()
                }
                .disabled(appState.isSavingSkillDraft || appState.isLoadingSkills)
            } else {
                Button {
                    Task { await loadSharedSkillsIfNeeded(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingSharedSkills)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var panelTitle: String {
        let total = appState.skills.count
        let filtered = filteredSkills.count

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Discovered Skills (%@)", "\(total)")
        }

        return L10n.string("Discovered Skills (%@ of %@)", "\(filtered)", "\(total)")
    }

    private var filteredSkills: [SkillSummary] {
        appState.skills.filter { $0.matchesSearch(searchText) }
    }

    private var selectedSkill: SkillSummary? {
        guard let selectedSkillID = appState.selectedSkillID else { return nil }
        return appState.skills.first(where: { $0.id == selectedSkillID })
    }

    private var sharedSkillsReloadID: String {
        "\(appState.activeConnectionID?.uuidString ?? "none")|\(libraryTab.rawValue)|\(searchText)"
    }

    @ViewBuilder
    private var detailContent: some View {
        if let editorMode {
            SkillEditorView(
                mode: editorMode,
                draft: $editorDraft,
                rawMarkdownContent: $rawMarkdownContent,
                detail: appState.selectedSkillDetail,
                errorMessage: appState.skillsError,
                isSaving: appState.isSavingSkillDraft,
                onCancel: {
                    self.editorMode = nil
                },
                onSave: {
                    await saveEditor()
                }
            )
        } else {
            SkillDetailView(
                summary: selectedSkill,
                detail: appState.selectedSkillDetail,
                errorMessage: appState.skillsError,
                isLoading: appState.isLoadingSkillDetail,
                onCreate: {
                    startCreating()
                },
                onEdit: {
                    startEditing()
                }
            )
        }
    }

    private func loadSharedSkillsIfNeeded(force: Bool) async {
        guard libraryTab != .installed else { return }
        guard let connection = appState.activeConnection else { return }
        if isLoadingSharedSkills && !force { return }

        isLoadingSharedSkills = true
        sharedSkillsError = nil
        sharedSkillsWarning = nil

        do {
            switch libraryTab {
            case .installed:
                break
            case .featured:
                let response = try await appState.caelWorkspaceAPIService.loadWorkspaceSkills(
                    connection: connection,
                    tab: "featured",
                    search: searchText,
                    limit: 30
                )
                workspaceSkills = response.skills
                hubSkills = []
                sharedSkillsError = response.error
            case .marketplace:
                let response = try await appState.caelWorkspaceAPIService.searchWorkspaceSkillsHub(
                    connection: connection,
                    query: searchText,
                    limit: 20
                )
                workspaceSkills = []
                hubSkills = response.results
                sharedSkillsWarning = response.warning
                sharedSkillsError = response.error
            }
        } catch {
            workspaceSkills = []
            hubSkills = []
            sharedSkillsError = error.localizedDescription
        }

        isLoadingSharedSkills = false
    }

    private func runSharedSkillAction(
        action: String,
        identifier: String,
        enabled: Bool? = nil,
        category: String? = nil
    ) async {
        guard let connection = appState.activeConnection else { return }
        actionSkillID = identifier
        sharedSkillsError = nil

        do {
            _ = try await appState.caelWorkspaceAPIService.runWorkspaceSkillAction(
                connection: connection,
                action: action,
                identifier: identifier,
                enabled: enabled,
                category: category
            )
            await appState.loadSkills(reset: true)
            await loadSharedSkillsIfNeeded(force: true)
        } catch {
            let message = error.localizedDescription
            sharedSkillsError = message
            appState.activeAlert = AppAlert(
                title: "Skill action failed",
                message: message
            )
        }

        actionSkillID = nil
    }

    private func startCreating() {
        var draft = SkillDraft()
        draft.refreshSuggestedSlug()
        editorDraft = draft
        rawMarkdownContent = draft.generatedMarkdown
        editorMode = .create
    }

    private func startEditing() {
        guard let detail = appState.selectedSkillDetail, !detail.isReadOnly else { return }
        editorDraft = SkillDraft.from(detail: detail)
        rawMarkdownContent = detail.markdownContent
        editorMode = .edit
    }

    private func saveEditor() async {
        switch editorMode {
        case .create:
            let didSave = await appState.createSkill(editorDraft)
            if didSave {
                editorMode = nil
            }
        case .edit:
            guard let detail = appState.selectedSkillDetail else { return }
            let didSave = await appState.updateSkill(
                detail,
                markdownContent: rawMarkdownContent,
                ensureReferencesFolder: editorDraft.includeReferencesFolder,
                ensureScriptsFolder: editorDraft.includeScriptsFolder,
                ensureTemplatesFolder: editorDraft.includeTemplatesFolder
            )
            if didSave {
                editorMode = nil
            }
        case nil:
            break
        }
    }
}

private enum SkillLibraryTab: String, CaseIterable, Identifiable {
    case installed
    case featured
    case marketplace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed:
            return "Installed"
        case .featured:
            return "Featured"
        case .marketplace:
            return "Marketplace"
        }
    }
}

private struct WorkspaceSkillCardRow: View {
    let skill: WorkspaceSkillItem
    let actionSkillID: String?
    let onInstall: () async -> Void
    let onToggle: () async -> Void
    let onUninstall: () async -> Void

    private var isOperating: Bool { actionSkillID == skill.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(skill.resolvedName)
                        .font(.headline)
                    if let description = skill.resolvedDescription {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    HermesBadge(text: skill.resolvedCategory, tint: .secondary)
                    HermesBadge(text: skill.isInstalled ? (skill.isEnabled ? "Enabled" : "Disabled") : "Not installed", tint: skill.isEnabled ? .green : .secondary)
                }
            }

            HStack(spacing: 8) {
                if skill.isInstalled {
                    Button(skill.isEnabled ? "Disable" : "Enable") {
                        Task { await onToggle() }
                    }
                    .buttonStyle(.bordered)

                    Button("Uninstall") {
                        Task { await onUninstall() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(skill.isBuiltin)
                } else {
                    Button("Install") {
                        Task { await onInstall() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                Text(skill.resolvedOrigin)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(isOperating)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct WorkspaceHubSkillCardRow: View {
    let skill: WorkspaceSkillHubItem
    let actionSkillID: String?
    let onInstall: () async -> Void

    private var isOperating: Bool { actionSkillID == skill.resolvedIdentifier }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(skill.resolvedName)
                        .font(.headline)
                    if let description = skill.resolvedDescription {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    HermesBadge(text: skill.resolvedSource, tint: .secondary)
                    if skill.isInstalled {
                        HermesBadge(text: "Installed", tint: .green)
                    }
                }
            }

            HStack(spacing: 8) {
                if skill.isInstalled {
                    Button("Installed") {}
                        .buttonStyle(.bordered)
                        .disabled(true)
                } else {
                    Button("Install") {
                        Task { await onInstall() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isOperating)
                }

                Spacer()

                Text(skill.resolvedIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}


private struct SkillCardRow: View {
    let skill: SkillSummary
    let isSelected: Bool
    let onSelect: () -> Void

    private var cardFillColor: Color {
        isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(skill.resolvedName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            if !skill.source.isLocal {
                                HermesBadge(text: skill.sourceLabel, tint: .secondary)
                            }
                        }

                        Text(skill.relativePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    if let category = skill.category {
                        HermesBadge(text: category, tint: .secondary)
                    }
                }

                if let description = skill.trimmedDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(L10n.string("No description in frontmatter"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }

                if !skill.previewBadges.isEmpty {
                    SkillCardBadgeScroller(
                        badges: skill.previewBadges,
                        backgroundColor: cardFillColor
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardFillColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.12 : 0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SkillCardBadgeScroller: View {
    let badges: [SkillPreviewBadge]
    let backgroundColor: Color

    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(badges) { badge in
                    HermesBadge(
                        text: badge.text,
                        tint: badge.tint,
                        isMonospaced: badge.isMonospaced
                    )
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: SkillBadgeContentWidthKey.self, value: proxy.size.width)
                }
            )
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SkillBadgeViewportWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(SkillBadgeContentWidthKey.self) { contentWidth = $0 }
        .onPreferenceChange(SkillBadgeViewportWidthKey.self) { viewportWidth = $0 }
        .overlay(alignment: .trailing) {
            if contentWidth > viewportWidth + 1 {
                LinearGradient(
                    colors: [.clear, backgroundColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 34)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct SkillPreviewBadge: Identifiable {
    let id: String
    let text: String
    let tint: Color
    var isMonospaced = false
}

private struct SkillBadgeContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SkillBadgeViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension SkillSummary {
    var previewBadges: [SkillPreviewBadge] {
        var badges: [SkillPreviewBadge] = []

        if let version, !version.isEmpty {
            badges.append(
                SkillPreviewBadge(
                    id: "version-\(version)",
                    text: version,
                    tint: .secondary,
                    isMonospaced: true
                )
            )
        }

        for tag in tags {
            badges.append(
                SkillPreviewBadge(
                    id: "tag-\(tag)",
                    text: tag,
                    tint: .accentColor
                )
            )
        }

        for relatedSkill in relatedSkills {
            badges.append(
                SkillPreviewBadge(
                    id: "related-\(relatedSkill)",
                    text: relatedSkill,
                    tint: .secondary,
                    isMonospaced: true
                )
            )
        }

        for feature in featureBadges {
            badges.append(
                SkillPreviewBadge(
                    id: "feature-\(feature.id)",
                    text: feature.title,
                    tint: feature.color
                )
            )
        }

        return badges
    }
}
