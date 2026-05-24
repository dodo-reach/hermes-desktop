import SwiftUI

struct CaelProviderLimitsWebPanel: View {
    @EnvironmentObject private var appState: AppState

    private let usageURL = URL(string: "http://100.97.216.111:3077/usage")!

    var body: some View {
        HermesSurfacePanel(
            title: "Provider Remaining Limits",
            subtitle: "Native provider limit cards sourced from the Cael Workspace usage API."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label("Shared Usage Snapshot", systemImage: "gauge.with.dots.needle.bottom.50percent")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    HermesRefreshButton(isRefreshing: appState.isRefreshingCaelProviderUsage) {
                        Task { await appState.refreshCaelProviderUsage() }
                    }
                    Link(destination: usageURL) {
                        Label("Open Web Usage", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }

                content
            }
        }
        .task(id: appState.activeConnectionID) {
            await appState.loadCaelProviderUsage()
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.isLoadingCaelProviderUsage,
           appState.caelProviderUsageLimits == nil {
            HermesLoadingState(label: "Loading provider usage limits…", minHeight: 220)
        } else if let error = appState.caelProviderUsageError,
                  appState.caelProviderUsageLimits == nil {
            ContentUnavailableView(
                "Provider limits unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if let limits = appState.caelProviderUsageLimits {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(limits.providers) { provider in
                    CaelProviderUsageNativeCard(provider: provider)
                }
            }
        }
    }
}

private struct CaelProviderUsageNativeCard: View {
    let provider: CaelProviderUsageCard

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.label)
                            .font(.headline)
                        if let plan = provider.plan {
                            Text(plan)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                    CaelProviderBadge(label: badgeLabel, tint: badgeTint)
                }

                if let message = provider.message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(displayRows) { row in
                    CaelProviderUsageRow(row: row)
                }

                if !provider.badges.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(provider.badges) { badge in
                            Text("\(badge.label): \(badge.value)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.secondary.opacity(0.10), in: Capsule())
                        }
                    }
                }

                Text(provider.source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var displayRows: [CaelUsageWindow] {
        Array(provider.usageRows.prefix(3))
    }

    private var badgeLabel: String {
        switch provider.confidence {
        case "live": "Live"
        case "configured": "Configured"
        case "missing": "Setup needed"
        case "error": "Error"
        default: provider.status.capitalized
        }
    }

    private var badgeTint: Color {
        switch provider.confidence {
        case "live": .green
        case "configured": .blue
        case "missing": .orange
        case "error": .red
        default: .secondary
        }
    }
}

private struct CaelProviderUsageRow: View {
    let row: CaelUsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.label)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(format(row.used, unit: row.unit)) / \(format(row.limit, unit: row.unit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: max(0, min(100, row.usedPercent)), total: 100)
                .tint(row.usedPercent > 85 ? .orange : .green)

            if let resetsAt = row.resetsAt {
                Text("Resets \(resetsAt)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func format(_ value: Double, unit: String) -> String {
        switch unit {
        case "dollars":
            value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
        case "percent":
            "\(Int(value.rounded()))%"
        case "tokens":
            value.formatted(.number.notation(.compactName))
        default:
            value.formatted(.number.notation(.compactName))
        }
    }
}

private struct CaelProviderBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        var position = CGPoint.zero
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if position.x > 0, position.x + size.width > width {
                position.x = 0
                position.y += rowHeight + spacing
                rowHeight = 0
            }
            position.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: position.y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var position = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if position.x > bounds.minX, position.x + size.width > bounds.maxX {
                position.x = bounds.minX
                position.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: position, proposal: ProposedViewSize(size))
            position.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
