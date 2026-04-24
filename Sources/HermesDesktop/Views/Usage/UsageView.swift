import Charts
import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var appState: AppState
    private let topRankingPanelHeight: CGFloat = 490

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HermesPageHeader(
                    title: "Usage",
                    subtitle: "The main cards and charts on this page are for the active Hermes profile. When more than one profile is discovered on the same host, a separate panel shows total token consumption across all profiles."
                ) {
                    HermesRefreshButton(isRefreshing: appState.isRefreshingUsage) {
                        Task { await appState.refreshUsage() }
                    }
                    .disabled(appState.isLoadingUsage)
                }

                usageContent
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .top)
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingUsage && !appState.isRefreshingUsage && appState.usageSummary != nil {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await appState.loadUsage()
        }
    }

    @ViewBuilder
    private var usageContent: some View {
        if appState.isLoadingUsage && appState.usageSummary == nil {
            HermesSurfacePanel {
                HermesLoadingState(
                    label: "Loading usage totals…",
                    minHeight: 320
                )
            }
        } else if let error = appState.usageError, appState.usageSummary == nil {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load usage",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else if let usageSummary = appState.usageSummary {
            Group {
                switch usageSummary.state {
                case .available:
                    availableUsageView(summary: usageSummary)
                case .unavailable:
                    HermesSurfacePanel {
                        ContentUnavailableView(
                            "Usage unavailable",
                            systemImage: "internaldrive.slash",
                            description: Text(
                                usageSummary.message ??
                                    "No readable Hermes session database is currently available for the active host."
                            )
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                }
            }
        } else {
            HermesSurfacePanel {
                HermesLoadingState(
                    label: "Loading usage totals…",
                    minHeight: 320
                )
            }
        }
    }

    private func availableUsageView(summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            activeProfileScopePanel(summary: summary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    UsageMetricCard(
                        title: "Input Tokens",
                        value: summary.inputTokens,
                        tint: .red,
                        systemImage: "arrow.down.circle.fill"
                    )
                    .frame(maxWidth: .infinity)

                    UsageMetricCard(
                        title: "Output Tokens",
                        value: summary.outputTokens,
                        tint: .yellow,
                        systemImage: "arrow.up.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 16) {
                    UsageMetricCard(
                        title: "Input Tokens",
                        value: summary.inputTokens,
                        tint: .red,
                        systemImage: "arrow.down.circle.fill"
                    )

                    UsageMetricCard(
                        title: "Output Tokens",
                        value: summary.outputTokens,
                        tint: .yellow,
                        systemImage: "arrow.up.circle.fill"
                    )
                }
            }

            if let usageProfileBreakdown = appState.usageProfileBreakdown,
               usageProfileBreakdown.profiles.count > 1 {
                profileBreakdownPanel(usageProfileBreakdown)
            }

            usageHighlightsPanel(summary: summary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    topSessionsPanel(summary: summary)
                        .frame(maxWidth: .infinity, minHeight: topRankingPanelHeight, maxHeight: topRankingPanelHeight, alignment: .top)

                    topModelsPanel(summary: summary)
                        .frame(maxWidth: .infinity, minHeight: topRankingPanelHeight, maxHeight: topRankingPanelHeight, alignment: .top)
                }

                VStack(alignment: .leading, spacing: 16) {
                    topSessionsPanel(summary: summary)
                    topModelsPanel(summary: summary)
                }
            }

            recentSessionsChartPanel(summary: summary)
        }
    }

    private func activeProfileScopePanel(summary: UsageSummary) -> some View {
        HermesSurfacePanel(
            title: "Active Profile",
            subtitle: "Everything below stays scoped to the currently selected Hermes profile."
        ) {
            HStack(alignment: .top, spacing: 12) {
                HermesInsetSurface {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profile")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(appState.activeConnection?.resolvedHermesProfileName ?? "default")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)

                HermesInsetSurface {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Total")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(UsageNumberFormatter.string(for: summary.totalTokens))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func profileBreakdownPanel(_ breakdown: UsageProfileBreakdown) -> some View {
        HermesSurfacePanel(
            title: "All Profiles Total Tokens",
            subtitle: "This panel is host-wide. It combines total token consumption across all readable Hermes profiles on the active host, including input, output, cache, and reasoning. The other cards on this page remain scoped to the active profile."
        ) {
            if breakdown.chartProfiles.count < 2 {
                ContentUnavailableView(
                    "Not enough profile data yet",
                    systemImage: "chart.pie",
                    description: Text("At least two profiles need readable usage data before the cross-profile breakdown becomes meaningful.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            UsageProfileDonutChart(
                                breakdown: breakdown,
                                colors: profileBreakdownColors
                            )
                            .frame(width: 300, height: 300)

                            VStack(alignment: .leading, spacing: 12) {
                                profileBreakdownHighlights(breakdown)

                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(breakdown.chartProfiles.enumerated()), id: \.element.id) { index, profile in
                                        UsageProfileLegendRow(
                                            profile: profile,
                                            total: breakdown.hostWideAllTokenCategoriesTotal,
                                            color: profileBreakdownColors[index % profileBreakdownColors.count]
                                        )
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            UsageProfileDonutChart(
                                breakdown: breakdown,
                                colors: profileBreakdownColors
                            )
                            .frame(height: 320)

                            profileBreakdownHighlights(breakdown)

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(breakdown.chartProfiles.enumerated()), id: \.element.id) { index, profile in
                                    UsageProfileLegendRow(
                                        profile: profile,
                                        total: breakdown.hostWideAllTokenCategoriesTotal,
                                        color: profileBreakdownColors[index % profileBreakdownColors.count]
                                    )
                                }
                            }
                        }
                    }

                    if !breakdown.unavailableProfiles.isEmpty {
                        HermesInsetSurface {
                            Text(L10n.string(
                                "Unavailable profiles are excluded from the donut: %@.",
                                breakdown.unavailableProfiles.map(\.profileName).joined(separator: ", ")
                            ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func profileBreakdownHighlights(_ breakdown: UsageProfileBreakdown) -> some View {
        let activeProfile = breakdown.readableProfiles.first { $0.isActiveProfile }
        let activeShare = activeProfile.map {
            breakdown.hostWideAllTokenCategoriesTotal > 0
                ? Double($0.allTokenCategoriesTotal) / Double(breakdown.hostWideAllTokenCategoriesTotal)
                : 0
        } ?? 0

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                UsageMiniStat(
                    title: "Readable Profiles",
                    valueText: UsageNumberFormatter.string(for: breakdown.readableProfiles.count),
                    tint: .secondary
                )
                .frame(maxWidth: .infinity)

                UsageMiniStat(
                    title: "Host-wide Total",
                    valueText: UsageNumberFormatter.string(for: breakdown.hostWideAllTokenCategoriesTotal),
                    tint: .primary
                )
                .frame(maxWidth: .infinity)

                UsageMiniStat(
                    title: "Active Profile Share",
                    valueText: UsageNumberFormatter.percentString(for: activeShare),
                    tint: .secondary
                )
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 12) {
                UsageMiniStat(
                    title: "Readable Profiles",
                    valueText: UsageNumberFormatter.string(for: breakdown.readableProfiles.count),
                    tint: .secondary
                )

                UsageMiniStat(
                    title: "Host-wide Total",
                    valueText: UsageNumberFormatter.string(for: breakdown.hostWideAllTokenCategoriesTotal),
                    tint: .primary
                )

                UsageMiniStat(
                    title: "Active Profile Share",
                    valueText: UsageNumberFormatter.percentString(for: activeShare),
                    tint: .secondary
                )
            }
        }
    }

    private var profileBreakdownColors: [Color] {
        [
            Color(red: 0.84, green: 0.33, blue: 0.27),
            Color(red: 0.91, green: 0.66, blue: 0.24),
            Color(red: 0.30, green: 0.58, blue: 0.85),
            Color(red: 0.30, green: 0.68, blue: 0.47),
            Color(red: 0.56, green: 0.42, blue: 0.79),
            Color(red: 0.80, green: 0.43, blue: 0.60)
        ]
    }

    private func usageHighlightsPanel(summary: UsageSummary) -> some View {
        HermesSurfacePanel(
            title: "Active Profile Totals",
            subtitle: "A compact summary of stored session usage for the currently selected Hermes profile."
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    UsageMiniStat(
                        title: "Stored Sessions",
                        valueText: UsageNumberFormatter.string(for: summary.sessionCount),
                        tint: .secondary
                    )
                    .frame(maxWidth: .infinity)

                    UsageMiniStat(
                        title: "Total Tokens",
                        valueText: UsageNumberFormatter.string(for: summary.totalTokens),
                        tint: .primary
                    )
                    .frame(maxWidth: .infinity)

                    UsageMiniStat(
                        title: "Avg. per Session",
                        valueText: UsageNumberFormatter.string(for: summary.averageTokensPerSession),
                        tint: .secondary
                    )
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 12) {
                    UsageMiniStat(
                        title: "Stored Sessions",
                        valueText: UsageNumberFormatter.string(for: summary.sessionCount),
                        tint: .secondary
                    )

                    UsageMiniStat(
                        title: "Total Tokens",
                        valueText: UsageNumberFormatter.string(for: summary.totalTokens),
                        tint: .primary
                    )

                    UsageMiniStat(
                        title: "Avg. per Session",
                        valueText: UsageNumberFormatter.string(for: summary.averageTokensPerSession),
                        tint: .secondary
                    )
                }
            }

            HermesInsetSurface {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("Input vs Output"))
                            .font(.headline)

                        Text(L10n.string("The visual balance between stored input and output token consumption."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    UsageStackedComparisonBar(summary: summary)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 18) {
                            UsageSharePill(
                                title: "Input",
                                value: summary.inputTokens,
                                total: summary.totalTokens,
                                tint: .red
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                            UsageSharePill(
                                title: "Output",
                                value: summary.outputTokens,
                                total: summary.totalTokens,
                                tint: .yellow
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            UsageSharePill(
                                title: "Input",
                                value: summary.inputTokens,
                                total: summary.totalTokens,
                                tint: .red
                            )

                            UsageSharePill(
                                title: "Output",
                                value: summary.outputTokens,
                                total: summary.totalTokens,
                                tint: .yellow
                            )
                        }
                    }
                }
            }
        }
    }

    private func topSessionsPanel(summary: UsageSummary) -> some View {
        HermesSurfacePanel(
            title: "Top 5 Sessions by Tokens",
            subtitle: "The stored sessions with the highest combined token consumption."
        ) {
            if summary.topSessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(1...5, id: \.self) { rank in
                        UsageTopSessionPlaceholderRow(
                            rank: rank,
                            title: rank == 1 ? topSessionsEmptyTitle(summary: summary) : "No session usage yet"
                        )
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<5, id: \.self) { index in
                        if let session = summary.topSessions[safe: index] {
                            UsageTopSessionRow(
                                rank: index + 1,
                                session: session
                            )
                        } else {
                            UsageTopSessionPlaceholderRow(
                                rank: index + 1,
                                title: "No additional session yet"
                            )
                        }
                    }
                }
            }
        }
    }

    private func topModelsPanel(summary: UsageSummary) -> some View {
        HermesSurfacePanel(
            title: "Top 5 Models by Tokens",
            subtitle: "Ranked by input/output tokens. Cache and reasoning stay secondary."
        ) {
            if summary.topModels.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(1...5, id: \.self) { rank in
                        UsageTopModelPlaceholderRow(
                            rank: rank,
                            title: rank == 1 ? topModelsEmptyTitle(summary: summary) : "No model usage yet"
                        )
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<5, id: \.self) { index in
                        if let model = summary.topModels[safe: index] {
                            UsageTopModelRow(
                                rank: index + 1,
                                model: model
                            )
                        } else {
                            UsageTopModelPlaceholderRow(
                                rank: index + 1,
                                title: "No additional model yet"
                            )
                        }
                    }
                }
            }
        }
    }

    private func recentSessionsChartPanel(summary: UsageSummary) -> some View {
        HermesSurfacePanel(
            title: "Recent Session History",
            subtitle: "The last 100 stored sessions, shown as token consumption over time."
        ) {
            if summary.recentSessions.isEmpty {
                ContentUnavailableView(
                    "No recent sessions available",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Recent session usage will appear here once Hermes has stored session data.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                let maxTokens = max(summary.recentSessions.map(\.totalTokens).max() ?? 0, 1)

                Chart(Array(summary.recentSessions.enumerated()), id: \.element.id) { index, session in
                    BarMark(
                        x: .value("Session", index + 1),
                        y: .value("Tokens", session.totalTokens)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .foregroundStyle(color(for: session.totalTokens, maxTokens: maxTokens))
                    .accessibilityLabel(session.title ?? session.id)
                    .accessibilityValue(L10n.string(
                        "%@ total tokens",
                        UsageNumberFormatter.string(for: session.totalTokens)
                    ))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 10)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(Color.secondary.opacity(0.14))
                        AxisTick()
                            .foregroundStyle(Color.secondary.opacity(0.40))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)")
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(Color.secondary.opacity(0.14))
                        AxisTick()
                            .foregroundStyle(Color.secondary.opacity(0.40))
                        AxisValueLabel {
                            if let intValue = value.as(Int64.self) {
                                Text(UsageNumberFormatter.shortString(for: intValue))
                            } else if let intValue = value.as(Int.self) {
                                Text(UsageNumberFormatter.shortString(for: Int64(intValue)))
                            }
                        }
                    }
                }
                .chartXAxisLabel(L10n.string("Recent sessions"), position: .bottom, alignment: .center)
                .chartYAxisLabel(L10n.string("Tokens"), position: .leading)
                .chartLegend(.hidden)
                .frame(height: 260)

                HermesInsetSurface {
                    HStack(alignment: .center, spacing: 16) {
                        UsageChartLegendItem(
                            color: color(for: 0, maxTokens: maxTokens),
                            title: "Lower"
                        )

                        UsageChartLegendItem(
                            color: color(for: maxTokens / 2, maxTokens: maxTokens),
                            title: "Medium"
                        )

                        UsageChartLegendItem(
                            color: color(for: maxTokens, maxTokens: maxTokens),
                            title: "Higher"
                        )

                        Spacer(minLength: 12)

                        Text(L10n.string("Older on the left, newer on the right"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func color(for totalTokens: Int64, maxTokens: Int64) -> Color {
        guard maxTokens > 0 else { return Color.secondary }

        let ratio = min(max(Double(totalTokens) / Double(maxTokens), 0), 1)
        switch ratio {
        case 0..<0.33:
            return Color.yellow.opacity(0.72)
        case 0.33..<0.66:
            return Color.orange.opacity(0.80)
        default:
            return Color.red.opacity(0.82)
        }
    }

    private func topModelsEmptyTitle(summary: UsageSummary) -> String {
        if summary.missingColumns.contains("model") {
            return "Model data unavailable"
        }

        return "No tracked models yet"
    }

    private func topSessionsEmptyTitle(summary: UsageSummary) -> String {
        if summary.sessionCount == 0 {
            return "No stored sessions yet"
        }

        return "No ranked sessions available"
    }
}

private struct UsageMetricCard: View {
    let title: String
    let value: Int64
    let tint: Color
    let systemImage: String

    private var borderTint: Color {
        switch title {
        case "Output Tokens":
            return Color(red: 0.78, green: 0.67, blue: 0.18)
        default:
            return tint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                HermesBadge(text: title, tint: tint)

                Spacer(minLength: 12)

                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
            }

            Text(UsageNumberFormatter.string(for: value))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Capsule()
                .fill(tint.opacity(0.85))
                .frame(height: 6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(borderTint.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

private struct UsageProfileDonutChart: View {
    let breakdown: UsageProfileBreakdown
    let colors: [Color]

    var body: some View {
        Chart(Array(breakdown.chartProfiles.enumerated()), id: \.element.id) { index, profile in
            SectorMark(
                angle: .value(L10n.string("All Tokens"), profile.allTokenCategoriesTotal),
                innerRadius: .ratio(0.62),
                angularInset: 2
            )
            .cornerRadius(6)
            .foregroundStyle(colors[index % colors.count])
            .accessibilityLabel(profile.profileName)
            .accessibilityValue(L10n.string(
                "%@ total tokens",
                UsageNumberFormatter.string(for: profile.allTokenCategoriesTotal)
            ))
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 6) {
                Text(L10n.string("Host-wide"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(UsageNumberFormatter.shortString(for: breakdown.hostWideAllTokenCategoriesTotal))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(L10n.string("all profiles total"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
        }
    }
}

private struct UsageProfileLegendRow: View {
    let profile: UsageProfileSlice
    let total: Int64
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(profile.profileName)
                        .font(.headline)
                        .lineLimit(1)

                    if profile.isActiveProfile {
                        HermesBadge(text: "Active", tint: .accentColor)
                    }
                }

                Text(profileBreakdownLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(UsageNumberFormatter.string(for: profile.allTokenCategoriesTotal))
                    .font(.headline)
                    .monospacedDigit()

                Text(UsageNumberFormatter.percentString(for: total > 0 ? Double(profile.allTokenCategoriesTotal) / Double(total) : 0))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var profileBreakdownLine: String {
        [
            L10n.string("Input %@", UsageNumberFormatter.shortString(for: profile.inputTokens)),
            L10n.string("Output %@", UsageNumberFormatter.shortString(for: profile.outputTokens)),
            L10n.string("Cache %@", UsageNumberFormatter.shortString(for: profile.cacheTokensTotal)),
            L10n.string("Reasoning %@", UsageNumberFormatter.shortString(for: profile.reasoningTokens))
        ].joined(separator: " · ")
    }
}

private struct UsageMiniStat: View {
    let title: String
    let valueText: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint == .primary ? .secondary : tint)

            Text(valueText)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct UsageSharePill: View {
    let title: String
    let value: Int64
    let total: Int64
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)

                Text(UsageNumberFormatter.percentString(for: total > 0 ? Double(value) / Double(total) : 0))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(UsageNumberFormatter.shortString(for: value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct UsageStackedComparisonBar: View {
    let summary: UsageSummary

    private var inputFraction: Double {
        guard summary.totalTokens > 0 else { return 0 }
        return min(max(Double(summary.inputTokens) / Double(summary.totalTokens), 0), 1)
    }

    private var outputFraction: Double {
        guard summary.totalTokens > 0 else { return 0 }
        return min(max(Double(summary.outputTokens) / Double(summary.totalTokens), 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let inputWidth = max(10, width * inputFraction)
            let outputWidth = max(summary.outputTokens > 0 ? 10 : 0, width * outputFraction)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.red.opacity(0.82))
                        .frame(width: inputWidth)

                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.yellow.opacity(0.82))
                        .frame(width: outputWidth)
                }
                .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
            }
        }
        .frame(height: 14)
    }
}

private struct UsageTopSessionRow: View {
    let rank: Int
    let session: UsageTopSession

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(rank)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(session.resolvedTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if session.resolvedTitle != session.id {
                    Text(session.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(UsageNumberFormatter.string(for: session.totalTokens))
                    .font(.headline)
                    .monospacedDigit()

                Text(L10n.string("tokens"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct UsageTopSessionPlaceholderRow: View {
    let rank: Int
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(rank)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.08), in: Circle())

            Text(L10n.string(title))
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text("-")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text(L10n.string("tokens"))
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        }
    }
}

private struct UsageTopModelRow: View {
    let rank: Int
    let model: UsageTopModel

    private var providerText: String {
        model.billingProvider ?? "-"
    }

    private var accessoryText: String? {
        if model.cacheAndReasoningTokens > 0 {
            return L10n.string("+%@ cache/reasoning", UsageNumberFormatter.shortString(for: model.cacheAndReasoningTokens))
        }
        return nil
    }

    private var metadataText: String {
        var parts = [
            providerText,
            L10n.string("%@ sessions", UsageNumberFormatter.string(for: model.sessionCount))
        ]
        if let accessoryText {
            parts.append(accessoryText)
        }
        return parts.joined(separator: " · ")
    }

    private var valueDetailText: String {
        L10n.string("tokens · %@", UsageNumberFormatter.usdString(for: model.estimatedCostUSD))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(rank)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(model.model)
                    .font(.headline)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.middle)

                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(UsageNumberFormatter.string(for: model.totalTokens))
                    .font(.headline)
                    .monospacedDigit()

                Text(valueDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct UsageTopModelPlaceholderRow: View {
    let rank: Int
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(rank)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(title))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("- · -")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text("-")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text(L10n.string("tokens · -"))
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        }
    }
}

private struct UsageChartLegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 16, height: 8)

            Text(L10n.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private enum UsageNumberFormatter {
    static let grouped: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static let percent: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func string<T: BinaryInteger>(for value: T) -> String {
        grouped.string(from: NSNumber(value: Int64(value))) ?? String(value)
    }

    static func percentString(for value: Double) -> String {
        percent.string(from: NSNumber(value: value)) ?? "\(Int((value * 100).rounded()))%"
    }

    static func usdString(for value: Double) -> String {
        let absolute = abs(value)
        let digits: Int

        switch absolute {
        case 0:
            digits = 2
        case 0..<0.01:
            digits = 6
        case 0..<1:
            digits = 4
        default:
            digits = 2
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func shortString(for value: Int64) -> String {
        let absValue = abs(Double(value))
        let sign = value < 0 ? "-" : ""

        switch absValue {
        case 1_000_000_000...:
            return "\(sign)\(compactDecimalString(absValue / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)\(compactDecimalString(absValue / 1_000_000))M"
        case 1_000...:
            return "\(sign)\(compactDecimalString(absValue / 1_000))K"
        default:
            return string(for: value)
        }
    }

    private static func compactDecimalString(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".0", with: "")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
