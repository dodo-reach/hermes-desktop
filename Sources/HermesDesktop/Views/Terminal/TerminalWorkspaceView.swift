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
                        title: tab.session.terminalTitle,
                        isSelected: workspace.selectedTabID == tab.id,
                        onSelect: { workspace.selectedTabID = tab.id },
                        onClose: { workspace.closeTab(tab) }
                    )
                }

                if let activeConnection = appState.activeConnection {
                    Button {
                        workspace.addTab(for: activeConnection)
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

            if !workspace.tabs.isEmpty {
                ZStack {
                    ForEach(workspace.tabs) { tab in
                        let isActiveTerminal =
                            appState.selectedSection == .terminal &&
                            workspace.selectedTabID == tab.id

                        TerminalTabContainer(
                            session: tab.session,
                            appearance: terminalAppearance,
                            isActive: isActiveTerminal
                        )
                        .opacity(isActiveTerminal ? 1 : 0)
                        .allowsHitTesting(isActiveTerminal)
                        .zIndex(isActiveTerminal ? 1 : 0)
                    }
                }
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
}

private struct TerminalTabChip: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                Text(title)
                    .lineLimit(1)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
        .clipShape(Capsule())
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
