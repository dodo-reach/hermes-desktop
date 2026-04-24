import SwiftUI

struct SkillDetailView: View {
    let summary: SkillSummary?
    let detail: SkillDetail?
    let errorMessage: String?
    let isLoading: Bool
    let onCreate: () -> Void
    let onEdit: () -> Void

    private let metadataColumns = [
        GridItem(.adaptive(minimum: 180), alignment: .topLeading)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let detail {
                    headerPanel(detail)

                    if let description = detail.trimmedDescription {
                        HermesSurfacePanel(
                            title: "Description",
                            subtitle: "Frontmatter summary for the selected skill."
                        ) {
                            Text(description)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }

                    if !detail.tags.isEmpty || !detail.relatedSkills.isEmpty || !detail.featureBadges.isEmpty {
                        metadataPanel(detail)
                    }

                    HermesSurfacePanel(
                        title: "SKILL.md",
                        subtitle: "Full source content loaded from the active host."
                    ) {
                        HermesInsetSurface {
                            Text(detail.markdownContent)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                } else if let summary, isLoading {
                    HermesSurfacePanel {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Text(summary.resolvedName)
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                if !summary.source.isLocal {
                                    HermesBadge(text: summary.sourceLabel, tint: .secondary)
                                }
                            }

                            Text(summary.relativePath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            HermesLoadingState(
                                label: "Loading skill detail…",
                                minHeight: 140
                            )
                        }
                    }
                } else if let errorMessage, summary != nil {
                    HermesSurfacePanel {
                        ContentUnavailableView(
                            "Unable to load skill detail",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                } else {
                    HermesSurfacePanel {
                        VStack(alignment: .leading, spacing: 18) {
                            ContentUnavailableView(
                                "Select a skill",
                                systemImage: "book.closed",
                                description: Text("Choose a Hermes skill from the active host to inspect its metadata and full SKILL.md.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 240)

                            Button {
                                onCreate()
                            } label: {
                                Label("Create New Skill", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }

    private func headerPanel(_ detail: SkillDetail) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(detail.resolvedName)
                                .font(.title2)
                                .fontWeight(.semibold)

                            HermesBadge(
                                text: detail.sourceLabel,
                                tint: detail.source.isLocal ? .accentColor : .secondary
                            )
                        }

                        Text(detail.relativePath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 8) {
                        if let category = detail.category {
                            HermesBadge(text: category, tint: .secondary)
                        }

                        Button("Edit SKILL.md") {
                            onEdit()
                        }
                        .buttonStyle(.bordered)
                        .disabled(detail.isReadOnly)
                    }
                }

                LazyVGrid(columns: metadataColumns, alignment: .leading, spacing: 14) {
                    HermesLabeledValue(
                        label: "Slug",
                        value: detail.slug,
                        isMonospaced: true
                    )

                    HermesLabeledValue(
                        label: "Category",
                        value: detail.category ?? "Root",
                        isMonospaced: detail.category != nil
                    )

                    HermesLabeledValue(
                        label: "Relative path",
                        value: detail.relativePath,
                        isMonospaced: true,
                        emphasizeValue: true
                    )

                    HermesLabeledValue(
                        label: "Source",
                        value: detail.sourceLabel
                    )

                    if let version = detail.version {
                        HermesLabeledValue(
                            label: "Version",
                            value: version,
                            isMonospaced: true
                        )
                    }
                }

                HermesInsetSurface {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Remote path")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(detail.skillFilePath)
                            .font(.system(.subheadline, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if detail.isReadOnly {
                    Text("External skill directories are discovery-only in Hermes. This skill is available to inspect here, but edits still belong in the local Hermes skills store.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metadataPanel(_ detail: SkillDetail) -> some View {
        HermesSurfacePanel(
            title: "Metadata",
            subtitle: "Optional frontmatter fields and companion directories discovered for this skill."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if !detail.tags.isEmpty {
                    SkillMetadataSection(title: "Tags") {
                        SkillMetadataBadgeGroup(values: detail.tags, tint: .accentColor)
                    }
                }

                if !detail.relatedSkills.isEmpty {
                    SkillMetadataSection(title: "Related skills") {
                        SkillMetadataBadgeGroup(
                            values: detail.relatedSkills,
                            tint: .secondary,
                            monospaced: true
                        )
                    }
                }

                if !detail.featureBadges.isEmpty {
                    SkillMetadataSection(title: "Companion directories") {
                        WrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                            ForEach(detail.featureBadges) { badge in
                                SkillMetadataBadge(text: badge.title, tint: badge.color)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SkillEditorView: View {
    @EnvironmentObject private var appState: AppState

    let mode: SkillEditorMode
    @Binding var draft: SkillDraft
    @Binding var rawMarkdownContent: String
    let detail: SkillDetail?
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

                switch mode {
                case .create:
                    createBasicsPanel
                    createMetadataPanel
                    createInstructionsPanel
                    generatedPreviewPanel
                case .edit:
                    editScopePanel
                    rawMarkdownPanel
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .onChange(of: draft.name) { _, _ in
            guard mode == .create else { return }
            draft.refreshSuggestedSlug()
        }
    }

    private var headerPanel: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string(mode.title))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(L10n.string(headerSubtitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(L10n.string(mode.actionTitle)) {
                        Task { await onSave() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || saveDisabled)

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

    private var createBasicsPanel: some View {
        HermesSurfacePanel(
            title: "Basics",
            subtitle: "Use plain language. The app will turn these fields into the right SKILL.md frontmatter and folder path."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SkillFormField(label: "Skill Name") {
                    TextField("Remote debugging, Deploy to VPS, Research notes", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }

                SkillFormField(label: "Short Description") {
                    TextField("When Hermes should use this skill and what it helps it do.", text: $draft.description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...3)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        SkillFormField(label: "Category Path") {
                            TextField("Optional: agent-workflows, ssh/tools", text: $draft.categoryPath)
                                .textFieldStyle(.roundedBorder)
                        }

                        SkillFormField(label: "Folder Name") {
                            TextField("deploy-to-vps", text: $draft.slug)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SkillFormField(label: "Category Path") {
                            TextField("Optional: agent-workflows, ssh/tools", text: $draft.categoryPath)
                                .textFieldStyle(.roundedBorder)
                        }

                        SkillFormField(label: "Folder Name") {
                            TextField("deploy-to-vps", text: $draft.slug)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                SkillFormField(label: "Version") {
                    TextField("Optional: 1.0.0", text: $draft.version)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                HermesInsetSurface {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Remote path")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(generatedRemoteSkillPath)
                            .font(.system(.subheadline, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var createMetadataPanel: some View {
        HermesSurfacePanel(
            title: "Metadata",
            subtitle: "Optional tags and related skills help Hermes and the user understand the role of the skill."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SkillFormField(label: "Tags") {
                    TextField("Comma-separated: ssh, deploy, troubleshooting", text: $draft.tagsText)
                        .textFieldStyle(.roundedBorder)
                }

                SkillFormField(label: "Related Skills") {
                    TextField("Comma-separated slugs: playwright, security-best-practices", text: $draft.relatedSkillsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Companion Folders")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Toggle("Create references/ for longer docs or domain notes", isOn: $draft.includeReferencesFolder)
                    Toggle("Create scripts/ for deterministic helpers", isOn: $draft.includeScriptsFolder)
                    Toggle("Create templates/ for reusable output files", isOn: $draft.includeTemplatesFolder)
                }
            }
        }
    }

    private var createInstructionsPanel: some View {
        HermesSurfacePanel(
            title: "Instructions",
            subtitle: "Write the actual guidance Hermes should follow once the skill triggers."
        ) {
            TextEditor(text: $draft.instructions)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 300)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var generatedPreviewPanel: some View {
        HermesSurfacePanel(
            title: "Generated Preview",
            subtitle: "This is the SKILL.md the app will write on the remote Hermes host."
        ) {
            HermesInsetSurface {
                Text(draft.generatedMarkdown)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private var editScopePanel: some View {
        HermesSurfacePanel(
            title: "Editing Scope",
            subtitle: "The existing skill path stays fixed while you edit the raw SKILL.md source."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HermesInsetSurface {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Remote path")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(existingRemoteSkillPath)
                            .font(.system(.subheadline, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Companion Folders")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Toggle("Ensure references/ exists", isOn: $draft.includeReferencesFolder)
                    Toggle("Ensure scripts/ exists", isOn: $draft.includeScriptsFolder)
                    Toggle("Ensure templates/ exists", isOn: $draft.includeTemplatesFolder)
                }
            }
        }
    }

    private var rawMarkdownPanel: some View {
        HermesSurfacePanel(
            title: "SKILL.md",
            subtitle: "Edit the existing skill source directly. Saves are atomic and checked against the last loaded remote version."
        ) {
            TextEditor(text: $rawMarkdownContent)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 420)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .create:
            return "Create a new Hermes skill from a guided form instead of writing YAML frontmatter and folder structure by hand."
        case .edit:
            return "Update the existing SKILL.md directly while keeping the remote path fixed and protected by a conflict check."
        }
    }

    private var generatedRemoteSkillPath: String {
        let root = appState.activeConnection?.remoteSkillsPath ?? "~/.hermes/skills"
        let relativePath = draft.relativePath.isEmpty ? "<folder-name>" : draft.relativePath
        return "\(root)/\(relativePath)/SKILL.md"
    }

    private var existingRemoteSkillPath: String {
        detail?.skillFilePath ?? "<selected-skill>"
    }

    private var saveDisabled: Bool {
        switch mode {
        case .create:
            return draft.validationError != nil
        case .edit:
            return rawMarkdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

private struct SkillFormField<Content: View>: View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkillMetadataSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
    }
}

private struct SkillMetadataBadgeGroup: View {
    let values: [String]
    let tint: Color
    var monospaced = false

    var body: some View {
        WrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(values, id: \.self) { value in
                SkillMetadataBadge(
                    text: value,
                    tint: tint,
                    monospaced: monospaced
                )
            }
        }
    }
}

private struct SkillMetadataBadge: View {
    let text: String
    let tint: Color
    var monospaced = false

    var body: some View {
        Text(text)
            .font(monospaced ? .system(.caption, design: .monospaced).weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(monospaced ? .middle : .tail)
            .frame(maxWidth: 220, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.12), lineWidth: 1)
            }
            .help(text)
        }
}

private struct WrappingFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let lines = computeLines(for: sizes, maxWidth: proposal.width)
        let height = lines.reduce(CGFloat.zero) { partial, line in
            partial + line.height
        } + verticalSpacing * CGFloat(max(0, lines.count - 1))
        let width = proposal.width ?? lines.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let lines = computeLines(for: sizes, maxWidth: bounds.width)
        var currentY = bounds.minY

        for line in lines {
            var currentX = bounds.minX
            for item in line.items {
                let size = sizes[item.index]
                subviews[item.index].place(
                    at: CGPoint(x: currentX, y: currentY),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                currentX += size.width + horizontalSpacing
            }
            currentY += line.height + verticalSpacing
        }
    }

    private func computeLines(for sizes: [CGSize], maxWidth: CGFloat?) -> [FlowLine] {
        let availableWidth = maxWidth ?? .greatestFiniteMagnitude
        guard !sizes.isEmpty else { return [] }

        var lines: [FlowLine] = []
        var currentItems: [FlowLineItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for (index, size) in sizes.enumerated() {
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width

            if !currentItems.isEmpty && proposedWidth > availableWidth {
                lines.append(
                    FlowLine(
                        items: currentItems,
                        width: currentWidth,
                        height: currentHeight
                    )
                )
                currentItems = [FlowLineItem(index: index)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowLineItem(index: index))
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            lines.append(
                FlowLine(
                    items: currentItems,
                    width: currentWidth,
                    height: currentHeight
                )
            )
        }

        return lines
    }
}

private struct FlowLine {
    let items: [FlowLineItem]
    let width: CGFloat
    let height: CGFloat
}

private struct FlowLineItem {
    let index: Int
}
