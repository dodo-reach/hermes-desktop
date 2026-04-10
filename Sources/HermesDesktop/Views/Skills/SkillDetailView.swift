import SwiftUI

struct SkillDetailView: View {
    let summary: SkillSummary?
    let detail: SkillDetail?
    let errorMessage: String?
    let isLoading: Bool

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
                            Text(summary.resolvedName)
                                .font(.title2)
                                .fontWeight(.semibold)

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
                        ContentUnavailableView(
                            "Select a skill",
                            systemImage: "book.closed",
                            description: Text("Choose a Hermes skill from the active host to inspect its metadata and full SKILL.md.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
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
                        Text(detail.resolvedName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(detail.relativePath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 12)

                    if let category = detail.category {
                        HermesBadge(text: category, tint: .secondary)
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

                    if let version = detail.version {
                        HermesLabeledValue(
                            label: "Version",
                            value: version,
                            isMonospaced: true
                        )
                    }
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

private struct SkillMetadataSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
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
