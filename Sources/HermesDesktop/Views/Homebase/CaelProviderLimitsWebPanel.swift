import SwiftUI

struct CaelProviderLimitsWebPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HermesSurfacePanel(
            title: "Cael Model Usage Limits",
            subtitle: "Active Cael model providers are shown first; external monitors remain secondary."
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

    private var usageURL: URL {
        appState.activeConnection?.caelWorkspaceURL(path: "/usage") ?? ConnectionProfile().caelWorkspaceURL(path: "/usage")
    }

    private func sortedProviders(_ providers: [CaelProviderUsageCard]) -> [CaelProviderUsageCard] {
        providers.sorted { left, right in
            let leftRank = providerRank(left)
            let rightRank = providerRank(right)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
        }
    }

    private func providerRank(_ provider: CaelProviderUsageCard) -> Int {
        if provider.caelDefault == true { return 0 }
        if provider.caelConfigured == true { return 1 }
        if provider.monitorKind == "cael" { return 2 }
        return 3
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
            VStack(alignment: .leading, spacing: 14) {
                CaelModelRosterStrip(providers: sortedProviders(limits.providers))
                CaelModelConfigControl()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(sortedProviders(limits.providers)) { provider in
                        CaelProviderUsageNativeCard(provider: provider)
                    }
                }
            }
        }
    }
}


private struct CaelModelRosterStrip: View {
    let providers: [CaelProviderUsageCard]

    private var caelProviders: [CaelProviderUsageCard] {
        providers.filter { $0.caelConfigured == true || $0.monitorKind == "cael" }
    }

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("Active Cael model roster", systemImage: "cpu")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    HermesBadge(text: "\(caelProviders.count) Cael monitors", tint: .accentColor)
                }

                if caelProviders.isEmpty {
                    Text("No Cael-configured model providers were reported by /api/usage/limits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(caelProviders) { provider in
                            Text(rosterLabel(for: provider))
                                .font(.caption.weight(provider.caelDefault == true ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background((provider.caelDefault == true ? Color.accentColor : Color.secondary).opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func rosterLabel(for provider: CaelProviderUsageCard) -> String {
        let model = provider.caelModel ?? provider.caelModels?.first ?? "configured"
        if provider.caelDefault == true {
            return "Default: \(provider.label) / \(model)"
        }
        return "\(provider.label) / \(model)"
    }
}


private struct CaelModelConfigControl: View {
    @EnvironmentObject private var appState: AppState
    @State private var config: WorkspaceHermesConfigResponse?
    @State private var catalog: WorkspaceModelCatalogResponse?
    @State private var providerID = ""
    @State private var modelID = ""
    @State private var notice: String?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var useManualEntry = false

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("Active Cael model config", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(isLoading ? "Loading..." : "Reload") {
                        Task { await loadConfig() }
                    }
                    .disabled(isLoading || isSaving)
                }

                Text(currentConfigLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if useManualEntry || providerOptions.isEmpty {
                    HStack(spacing: 8) {
                        TextField("provider", text: $providerID)
                            .textFieldStyle(.roundedBorder)
                        TextField("model", text: $modelID)
                            .textFieldStyle(.roundedBorder)
                        applyButton
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Picker("Provider", selection: $providerID) {
                                ForEach(providerOptions, id: \.self) { provider in
                                    Text(providerDisplayName(provider)).tag(provider)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                            .onChange(of: providerID) { _, _ in
                                alignSelectedModelWithProvider()
                            }

                            Picker("Model", selection: $modelID) {
                                ForEach(modelOptions, id: \.self) { model in
                                    Text(modelDisplayName(model)).tag(model)
                                }
                            }
                            .labelsHidden()
                            .frame(minWidth: 260, maxWidth: .infinity)

                            applyButton
                        }

                        Text(catalogLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Toggle("Manual provider/model override", isOn: $useManualEntry)
                    .font(.caption)
                    .toggleStyle(.checkbox)

                if let notice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let providers = config?.providers?.filter({ $0.configured == true || $0.isDefault == true }), !providers.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(providers) { provider in
                            Button(providerChipLabel(provider)) {
                                providerID = provider.id
                                modelID = provider.isDefault == true
                                    ? (config?.activeModel ?? provider.models?.first?.id ?? modelID)
                                    : (provider.models?.first?.id ?? modelID)
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((provider.isDefault == true ? Color.accentColor : Color.secondary).opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await loadConfig()
        }
    }

    private var applyButton: some View {
        Button(isSaving ? "Applying..." : "Apply") {
            Task { await applyModelConfig() }
        }
        .disabled(isSaving || providerID.nilIfBlank == nil || modelID.nilIfBlank == nil)
    }

    private var currentConfigLabel: String {
        let provider = config?.activeProvider?.nilIfBlank ?? "unknown provider"
        let model = config?.activeModel?.nilIfBlank ?? "unknown model"
        return "Shared active model: \(provider) / \(model). The picker is hydrated from /api/models and applies through /api/hermes-config."
    }

    private var catalogModels: [WorkspaceModelCatalogEntry] {
        catalog?.catalogModels ?? []
    }

    private var providerOptions: [String] {
        let catalogProviders = catalogModels.compactMap { $0.provider?.nilIfBlank }
        let configProviders = config?.providers?.compactMap { provider -> String? in
            if provider.isDefault == true || provider.configured == true || provider.models?.isEmpty == false {
                return provider.id.nilIfBlank
            }
            return nil
        } ?? []
        let configuredProviders = catalog?.configuredProviders?.compactMap(\.nilIfBlank) ?? []
        let activeProvider = (config?.activeProvider)?.nilIfBlank.map { [$0] } ?? []
        return Array(Set(catalogProviders + configProviders + configuredProviders + activeProvider)).sorted()
    }

    private var modelOptions: [String] {
        guard let provider = providerID.nilIfBlank else { return [] }
        let catalogMatches = catalogModels
            .filter { ($0.provider?.nilIfBlank ?? "unknown") == provider }
            .compactMap { $0.id.nilIfBlank }
        let configMatches = config?.providers?
            .first(where: { $0.id == provider })?
            .models?
            .compactMap { $0.id.nilIfBlank } ?? []
        let activeModel = config?.activeProvider == provider ? ((config?.activeModel)?.nilIfBlank.map { [$0] } ?? []) : []
        return Array(Set(catalogMatches + configMatches + activeModel)).sorted()
    }

    private var catalogLabel: String {
        let count = catalogModels.count
        let source = catalog?.source?.nilIfBlank ?? "unknown source"
        let providers = providerOptions.count
        return "\(count) models across \(providers) providers from \(source). Raw credentials stay server-side."
    }

    private func providerChipLabel(_ provider: WorkspaceHermesProviderState) -> String {
        let name = provider.name.nilIfBlank ?? provider.id
        if provider.isDefault == true { return "Default: \(name)" }
        return name
    }

    private func providerDisplayName(_ provider: String) -> String {
        let name = config?.providers?.first(where: { $0.id == provider })?.name.nilIfBlank ?? provider
        if provider == config?.activeProvider { return "Default: \(name)" }
        return name
    }

    private func modelDisplayName(_ model: String) -> String {
        catalogModels.first(where: { $0.id == model })?.name?.nilIfBlank ?? model
    }

    private func alignSelectedModelWithProvider() {
        if !modelOptions.contains(modelID), let first = modelOptions.first {
            modelID = first
        }
    }

    private func loadConfig() async {
        guard let connection = appState.activeConnection else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await appState.caelWorkspaceAPIService.loadHermesConfig(connection: connection)
            config = next
            providerID = next.activeProvider?.nilIfBlank ?? providerID
            modelID = next.activeModel?.nilIfBlank ?? modelID
            notice = next.ok == false ? (next.error?.nilIfBlank ?? "Hermes config is unavailable.") : nil
        } catch {
            notice = "Unable to load Hermes config: \(error.localizedDescription)"
        }
        do {
            let nextCatalog = try await appState.caelWorkspaceAPIService.loadWorkspaceModels(connection: connection)
            catalog = nextCatalog
            if providerID.nilIfBlank == nil {
                providerID = providerOptions.first ?? ""
            }
            alignSelectedModelWithProvider()
            if nextCatalog.ok == false {
                notice = nextCatalog.error?.nilIfBlank ?? "Model catalog is unavailable."
            }
        } catch {
            catalog = nil
            useManualEntry = true
            if notice == nil {
                notice = "Unable to load model catalog: \(error.localizedDescription)"
            }
        }
    }

    private func applyModelConfig() async {
        guard let connection = appState.activeConnection,
              let provider = providerID.nilIfBlank,
              let model = modelID.nilIfBlank else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let result = try await appState.caelWorkspaceAPIService.setDefaultHermesModel(
                connection: connection,
                providerID: provider,
                modelID: model
            )
            notice = result.message?.nilIfBlank ?? "Default model updated."
            await loadConfig()
            await appState.loadCaelProviderUsage(forceRefresh: true)
        } catch {
            notice = "Unable to update default model: \(error.localizedDescription)"
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

                FlowLayout(spacing: 6) {
                    if provider.caelDefault == true {
                        CaelProviderBadge(label: "Cael default", tint: .accentColor)
                    } else if provider.caelConfigured == true || provider.monitorKind == "cael" {
                        CaelProviderBadge(label: "Cael model", tint: .blue)
                    }

                    if let caelModel = provider.caelModel {
                        Text(caelModel)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.10), in: Capsule())
                    }

                    ForEach(provider.badges) { badge in
                        Text("\(badge.label): \(badge.value)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.10), in: Capsule())
                    }
                }

                if let models = provider.caelModels, models.count > 1 {
                    Text("Cael models: \(models.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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


private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
