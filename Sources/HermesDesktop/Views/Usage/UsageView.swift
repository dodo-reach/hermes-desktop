import Charts
import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HermesPageHeader(
                    title: "Usage",
                    subtitle: "See the total input and output tokens consumed across the Hermes sessions stored on the active host."
                ) {
                    Button {
                        Task { await appState.loadUsage(forceRefresh: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isLoadingUsage)
                }

                usageContent
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task(id: appState.activeConnectionID) {
            await appState.loadUsage()
        }
    }

    @ViewBuilder
    private var usageContent: some View {
        if appState.isLoadingUsage && appState.usageSummary == nil {
            HermesSurfacePanel {
                ProgressView("Loading usage totals…")
                    .frame(maxWidth: .infinity, minHeight: 320)
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
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingUsage {
                    ProgressView()
                        .padding(18)
                }
            }
        } else {
            HermesSurfacePanel {
                ProgressView("Loading usage totals…")
                    .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
    }

    private func availableUsageView(summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
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

            usageHighlightsPanel(summary: summary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    topSessionsPanel(summary: summary)
                        .frame(maxWidth: .infinity, alignment: .top)

                    VStack(alignment: .leading, spacing: 16) {
                        recentSessionsChartPanel(summary: summary)
                        sourcePanel(summary: summary)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                VStack(alignment: .leading, spacing: 16) {
                    topSessionsPanel(summary: summary)
                    recentSessionsChartPanel(summary: summary)
                    sourcePanel(summary: summary)
                }
            }
        }
    }

    private func usageHighlightsPanel(summary: UsageSummary) -> some View {
        HermesSurfacePanel(
            title: "Highlights",
            subtitle: "A compact summary of stored session usage, with one visual comparison for input and output."
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
                        Text("Input vs Output")
                            .font(.headline)

                        Text("The visual balance between stored input and output token consumption.")
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
                ContentUnavailableView(
                    "No sessions available",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Top sessions will appear here once Hermes usage data is available.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(summary.topSessions.enumerated()), id: \.element.id) { index, session in
                        UsageTopSessionRow(
                            rank: index + 1,
                            session: session
                        )
                    }
                }
            }
        }
    }

    private func sourcePanel(summary: UsageSummary) -> some View {
        HermesSurfacePanel(
            title: "Source",
            subtitle: "Usage totals are queried live from the remote Hermes SQLite store."
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    HermesLabeledValue(
                        label: "Database path",
                        value: summary.databasePath ?? "Unavailable",
                        isMonospaced: true,
                        emphasizeValue: true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HermesLabeledValue(
                        label: "Sessions table",
                        value: summary.sessionTable ?? "Unavailable",
                        isMonospaced: true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HermesLabeledValue(
                        label: "Database path",
                        value: summary.databasePath ?? "Unavailable",
                        isMonospaced: true,
                        emphasizeValue: true
                    )

                    HermesLabeledValue(
                        label: "Sessions table",
                        value: summary.sessionTable ?? "Unavailable",
                        isMonospaced: true
                    )
                }
            }

            if !summary.missingColumns.isEmpty || summary.message != nil {
                HermesInsetSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.orange)

                            Text(summary.message ?? "Missing token columns are treated as 0.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if !summary.missingColumns.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(summary.missingColumns, id: \.self) { column in
                                    HermesBadge(text: column, tint: .orange, isMonospaced: true)
                                }
                            }
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
                    .accessibilityValue("\(UsageNumberFormatter.string(for: session.totalTokens)) total tokens")
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
                .chartXAxisLabel("Recent sessions", alignment: .trailing)
                .chartYAxisLabel("Tokens", position: .leading)
                .chartLegend(.hidden)
                .frame(height: 220)

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

                        Text("Older on the left, newer on the right")
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

private struct UsageMiniStat: View {
    let title: String
    let valueText: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
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
            Text(title)
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

                Text("tokens")
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
}

private struct UsageChartLegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 16, height: 8)

            Text(title)
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
