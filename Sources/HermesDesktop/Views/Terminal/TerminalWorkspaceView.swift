import AppKit
import SwiftUI

struct TerminalWorkspaceView: View {
    @ObservedObject var workspace: TerminalWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @State private var isShowingAppearanceEditor = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(workspace.tabs) { tab in
                    TerminalTabChip(
                        profileName: tab.session.connection.resolvedHermesProfileName,
                        hostLabel: tab.session.connection.label,
                        isSelected: workspace.selectedTabID == tab.id,
                        isCurrentWorkspace: isTabForActiveWorkspace(tab),
                        onSelect: { requestTabSelection(tab.id) },
                        onClose: { requestTabClose(tab) }
                    )
                }

                if let activeConnection = appState.activeConnection {
                    Button {
                        requestNewTab(for: activeConnection)
                    } label: {
                        Label("New Tab", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                TerminalAppearanceToolbarButton(
                    appearance: terminalAppearance,
                    isPresented: $isShowingAppearanceEditor,
                    themeBinding: terminalThemeBinding
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.thinMaterial)

            if let selectedTab = workspace.selectedTab {
                TerminalTabContainer(
                    session: selectedTab.session,
                    appearance: terminalAppearance,
                    isActive: appState.selectedSection == .terminal
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "No terminal tab",
                    systemImage: "terminal",
                    description: Text("Create a tab to start a real SSH shell for the active host.")
                )
            }
        }
        .task(id: appState.activeConnectionID) {
            if appState.selectedSection == .terminal {
                appState.ensureTerminalSession()
            }
        }
        .onChange(of: appState.selectedSection) { _, newValue in
            if newValue == .terminal {
                appState.ensureTerminalSession()
            }
        }
    }

    private var terminalAppearance: TerminalThemeAppearance {
        appState.connectionStore.terminalTheme.resolvedAppearance
    }

    private var terminalThemeBinding: Binding<TerminalThemePreference> {
        Binding {
            appState.connectionStore.terminalTheme
        } set: { newValue in
            appState.connectionStore.terminalTheme = newValue
        }
    }

    private func isTabForActiveWorkspace(_ tab: TerminalTabModel) -> Bool {
        guard let activeConnection = appState.activeConnection else { return true }
        return tab.workspaceScopeFingerprint == activeConnection.workspaceScopeFingerprint
    }

    private func requestNewTab(for connection: ConnectionProfile) {
        DispatchQueue.main.async {
            workspace.addTab(for: connection.updated())
        }
    }

    private func requestTabSelection(_ tabID: UUID) {
        DispatchQueue.main.async {
            workspace.selectTab(tabID)
        }
    }

    private func requestTabClose(_ tab: TerminalTabModel) {
        DispatchQueue.main.async {
            workspace.closeTab(tab)
        }
    }
}

private struct TerminalTabChip: View {
    let profileName: String
    let hostLabel: String
    let isSelected: Bool
    let isCurrentWorkspace: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(profileName)
                                .font(profileFont)
                                .lineLimit(1)

                            if !isCurrentWorkspace {
                                HermesBadge(text: "Other Profile", tint: .orange)
                            }
                        }

                        Text(hostLabel)
                            .font(hostFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: closeButtonReserveWidth)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Close tab")
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    private var backgroundColor: Color {
        if !isCurrentWorkspace {
            return isSelected ? Color.orange.opacity(0.20) : Color.orange.opacity(0.10)
        }

        return isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)
    }

    private var borderColor: Color {
        if !isCurrentWorkspace {
            return Color.orange.opacity(isSelected ? 0.40 : 0.18)
        }

        return Color.primary.opacity(isSelected ? 0.12 : 0.06)
    }

    private var profileFont: Font {
        isCurrentWorkspace ? .headline.weight(.semibold) : .subheadline.weight(.semibold)
    }

    private var hostFont: Font {
        isCurrentWorkspace ? .caption : .caption2
    }

    private var horizontalPadding: CGFloat {
        isCurrentWorkspace ? 12 : 9
    }

    private var verticalPadding: CGFloat {
        isCurrentWorkspace ? 7 : 5
    }

    private var closeButtonReserveWidth: CGFloat {
        24
    }
}

private struct TerminalAppearanceToolbarButton: View {
    let appearance: TerminalThemeAppearance
    @Binding var isPresented: Bool
    @Binding var themeBinding: TerminalThemePreference

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                ThemeSwatch(backgroundColor: appearance.backgroundColor.swiftUIColor, foregroundColor: appearance.foregroundColor.swiftUIColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Theme")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(appearance.name)
                        .font(.subheadline.weight(.semibold))
                }

                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            TerminalAppearanceEditor(themePreference: $themeBinding)
        }
        .help("Customize terminal colors")
    }
}

private struct TerminalAppearanceEditor: View {
    @Binding var themePreference: TerminalThemePreference

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        let appearance = themePreference.resolvedAppearance

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Terminal Theme")
                    .font(.title3.weight(.semibold))

                Text("Pick a preset for a coherent terminal look, then fine-tune background and text colors live if you want.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TerminalThemePreviewCard(appearance: appearance)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Quick Presets")
                        .font(.headline)

                    Spacer()

                    Button("Use System") {
                        themePreference = .defaultValue
                    }
                    .buttonStyle(.borderless)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TerminalThemePreference.quickPresets) { preset in
                        Button {
                            themePreference = themePreference.selectingPreset(preset.style)
                        } label: {
                            TerminalPresetCard(
                                preset: preset,
                                isSelected: themePreference.style == preset.style && !appearance.isCustom
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HermesInsetSurface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Custom Colors")
                            .font(.headline)

                        Spacer()

                        if appearance.isCustom {
                            Text("ANSI accents follow \(paletteName(for: appearance.paletteStyle)).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        TerminalColorControl(
                            label: "Background",
                            selection: backgroundBinding
                        )

                        TerminalColorControl(
                            label: "Text",
                            selection: foregroundBinding
                        )
                    }

                    Text("Custom colors update the running terminal immediately. Preset ANSI colors stay anchored so git output, prompts, and tools keep a readable palette.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(width: 430)
    }

    private var backgroundBinding: Binding<Color> {
        Binding {
            themePreference.resolvedAppearance.backgroundColor.swiftUIColor
        } set: { newValue in
            themePreference = themePreference.updatingBackgroundColor(TerminalThemeColor(nsColor: NSColor(newValue)))
        }
    }

    private var foregroundBinding: Binding<Color> {
        Binding {
            themePreference.resolvedAppearance.foregroundColor.swiftUIColor
        } set: { newValue in
            themePreference = themePreference.updatingForegroundColor(TerminalThemeColor(nsColor: NSColor(newValue)))
        }
    }

    private func paletteName(for style: TerminalThemeStyle) -> String {
        switch style {
        case .system:
            return "System"
        case .graphite:
            return "Graphite"
        case .evergreen:
            return "Evergreen"
        case .dusk:
            return "Dusk"
        case .paper:
            return "Paper"
        case .custom:
            return "Custom"
        }
    }
}

private struct TerminalThemePreviewCard: View {
    let appearance: TerminalThemeAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview")
                    .font(.headline)

                Spacer()

                ThemeSwatch(
                    backgroundColor: appearance.backgroundColor.swiftUIColor,
                    foregroundColor: appearance.foregroundColor.swiftUIColor
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("hermes@host:~/workspace$")
                    .foregroundStyle(appearance.foregroundColor.swiftUIColor.opacity(0.72))

                Text("git status")
                    .foregroundStyle(appearance.foregroundColor.swiftUIColor)

                HStack(spacing: 8) {
                    Text("main")
                        .foregroundStyle(appearance.ansiPalette[4].swiftUIColor)
                    Text("clean")
                        .foregroundStyle(appearance.ansiPalette[2].swiftUIColor)
                    Text("ssh")
                        .foregroundStyle(appearance.ansiPalette[6].swiftUIColor)
                }
                .font(.caption.weight(.semibold))
            }
            .font(.system(.body, design: .monospaced))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(appearance.backgroundColor.swiftUIColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(appearance.foregroundColor.swiftUIColor.opacity(0.12), lineWidth: 1)
            }
        }
    }
}

private struct TerminalPresetCard: View {
    let preset: TerminalThemePreset
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeSwatch(
                backgroundColor: preset.backgroundColor.swiftUIColor,
                foregroundColor: preset.foregroundColor.swiftUIColor
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(preset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
    }
}

private struct TerminalColorControl: View {
    let label: String
    @Binding var selection: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            ColorPicker(label, selection: $selection, supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selection)
                .frame(height: 24)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThemeSwatch: View {
    let backgroundColor: Color
    let foregroundColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)

            VStack(alignment: .leading, spacing: 3) {
                Capsule()
                    .fill(foregroundColor.opacity(0.85))
                    .frame(width: 18, height: 4)

                Capsule()
                    .fill(foregroundColor.opacity(0.55))
                    .frame(width: 12, height: 4)
            }
        }
        .frame(width: 32, height: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(foregroundColor.opacity(0.15), lineWidth: 1)
        }
    }
}
