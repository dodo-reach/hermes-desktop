import SwiftUI

struct SkillsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Skills",
                    subtitle: "Browse the Hermes skill library discovered on the active host."
                ) {
                    HermesRefreshButton(isRefreshing: appState.isRefreshingSkills) {
                        Task { await appState.refreshSkills() }
                    }
                    .disabled(appState.isLoadingSkills)
                }

                skillsContent
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)

            SkillDetailView(
                summary: selectedSkill,
                detail: appState.selectedSkillDetail,
                errorMessage: appState.skillsError,
                isLoading: appState.isLoadingSkillDetail
            )
            .frame(minWidth: 420, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appState.activeConnectionID) {
            if appState.skills.isEmpty {
                await appState.loadSkills(reset: true)
            }
        }
    }

    @ViewBuilder
    private var skillsContent: some View {
        if appState.skills.isEmpty {
            skillsPanel
        } else {
            skillsPanel
                .overlay(alignment: .topTrailing) {
                    skillsSearchToolbar
                        .offset(y: -38)
                }
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
                    "Unable to load skills",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if appState.skills.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "No skills found",
                    systemImage: "book.closed",
                    description: Text("No readable SKILL.md files were discovered under ~/.hermes/skills on this SSH target.")
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
                        "No matching skills",
                        systemImage: "magnifyingglass",
                        description: Text("Try searching by skill name or category.")
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
                                        await appState.loadSkillDetail(relativePath: skill.id)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var skillsSearchToolbar: some View {
        HStack(spacing: 10) {
            if appState.isLoadingSkills && !appState.isRefreshingSkills && !appState.skills.isEmpty {
                HermesLoadingOverlay()
            }

            HermesExpandableSearchField(
                text: $searchText,
                prompt: "Search skills"
            )
        }
    }

    private var panelTitle: String {
        let total = appState.skills.count
        let filtered = filteredSkills.count

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Discovered Skills (\(total))"
        }

        return "Discovered Skills (\(filtered) of \(total))"
    }

    private var filteredSkills: [SkillSummary] {
        appState.skills.filter { $0.matchesSearch(searchText) }
    }

    private var selectedSkill: SkillSummary? {
        guard let selectedSkillID = appState.selectedSkillID else { return nil }
        return appState.skills.first(where: { $0.id == selectedSkillID })
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
                        Text(skill.resolvedName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

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
                    Text("No description in frontmatter")
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
