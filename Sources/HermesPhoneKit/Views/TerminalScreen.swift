#if canImport(UIKit)
@preconcurrency import Citadel
import Crypto
import Foundation
import NIOCore
@preconcurrency import NIOSSH
import Security
import SwiftUI
import UIKit

struct TerminalScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @ObservedObject private var workspace: HermesTerminalWorkspaceStore
    @StateObject private var keyboard = KeyboardObserver()
    @AppStorage("hermesPhone.terminal.backgroundHex") private var terminalBackgroundHex = TerminalAppearance.default.backgroundHex
    @AppStorage("hermesPhone.terminal.foregroundHex") private var terminalForegroundHex = TerminalAppearance.default.foregroundHex
    @State private var isPresentingAppearanceSheet = false
    private let onOpenSettings: () -> Void

    init(
        workspace: HermesTerminalWorkspaceStore,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        _workspace = ObservedObject(wrappedValue: workspace)
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        ZStack {
            terminalAppearance.backgroundColor
                .ignoresSafeArea()

            terminalSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.bottom, keyboard.bottomInset)
        .animation(.easeOut(duration: 0.24), value: keyboard.bottomInset)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            terminalTopControls
        }
        .task(id: store.activeTerminalHostFingerprint) {
            await store.refreshOverview()
        }
        .task(id: keyboard.isVisible) {
            guard let session = workspace.selectedSession else { return }
            session.refreshLayout()
            if keyboard.isVisible {
                session.ensurePromptVisible()
            }
        }
        .task(id: workspace.selectedSessionID) {
            guard let session = workspace.selectedSession else { return }
            session.connectIfNeeded()
            await Task.yield()
            session.scrollToTop()
        }
        .sheet(isPresented: $isPresentingAppearanceSheet) {
            TerminalAppearanceSheet(
                backgroundHex: $terminalBackgroundHex,
                foregroundHex: $terminalForegroundHex
            )
            .presentationDetents([.medium])
        }
    }

    private var terminalAppearance: TerminalAppearance {
        TerminalAppearance(
            backgroundHex: terminalBackgroundHex,
            foregroundHex: terminalForegroundHex
        )
    }

    @ViewBuilder
    private var terminalSurface: some View {
        if let selectedSession = workspace.selectedSession {
            HermesTerminalRepresentable(
                session: selectedSession,
                appearance: terminalAppearance
            )
            .id(selectedSession.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(terminalAppearance.backgroundColor)
        } else {
            emptyTerminalLauncher
        }
    }

    private var emptyTerminalLauncher: some View {
        Button {
            store.openMonoTerminalSession()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 84, height: 84)
                .foregroundStyle(terminalAppearance.foregroundColor)
                .background(terminalAppearance.foregroundColor.opacity(0.10), in: Circle())
                .overlay(
                    Circle()
                        .stroke(terminalAppearance.foregroundColor.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(store.terminalConnection == nil)
        .opacity(store.terminalConnection == nil ? 0.45 : 1)
        .accessibilityLabel("Open terminal")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(terminalAppearance.backgroundColor)
    }

    @ViewBuilder
    private var terminalTopControls: some View {
        if let session = workspace.selectedSession {
            HStack(spacing: 8) {
                Menu {
                    terminalQuickKeyMenuContent
                } label: {
                    terminalIcon("command")
                }
                .accessibilityLabel("Terminal commands")

                Circle()
                    .fill(session.isConnected ? Color.green : (session.isConnecting ? Color.orange : terminalAppearance.foregroundColor.opacity(0.45)))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Spacer(minLength: 12)

                Menu {
                    terminalOptionsMenuContent(for: session)
                } label: {
                    terminalIcon("ellipsis.circle")
                }
                .accessibilityLabel("Terminal options")

                Button {
                    session.dismissKeyboard()
                } label: {
                    terminalIcon("keyboard.chevron.compact.down")
                }
                .buttonStyle(.plain)
                .disabled(!keyboard.isVisible)
                .opacity(keyboard.isVisible ? 1 : 0.45)
                .accessibilityLabel("Hide keyboard")

                Button {
                    workspace.closeAllSessions()
                } label: {
                    terminalIcon("xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close terminal")

                Button(action: onOpenSettings) {
                    terminalIcon("gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hermes settings")
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .background(terminalAppearance.backgroundColor.opacity(0.97))
        }
    }

    @ViewBuilder
    private func terminalOptionsMenuContent(for session: HermesTerminalSession) -> some View {
        Section {
            Label(session.connection.label, systemImage: "server.rack")
            Label(session.connection.displayDestination, systemImage: "network")
            Label(session.contextLabel, systemImage: "terminal")
        }

        Section("Session") {
            Button("Reconnect", systemImage: "arrow.clockwise") {
                session.requestReconnect()
            }
            Button("Appearance", systemImage: "paintpalette") {
                isPresentingAppearanceSheet = true
            }
        }
    }

    private func terminalIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 38, height: 38)
            .foregroundStyle(terminalAppearance.foregroundColor.opacity(0.92))
            .background(terminalAppearance.foregroundColor.opacity(0.10), in: Circle())
    }

    @ViewBuilder
    private var terminalQuickKeyMenuContent: some View {
        Section("Control") {
            ForEach([TerminalQuickKey.escape, .tab, .ctrlC, .ctrlD]) { key in
                Button(key.title) {
                    workspace.selectedSession?.sendQuickKey(key)
                }
            }
        }

        Section("Navigation") {
            ForEach([TerminalQuickKey.up, .down, .left, .right]) { key in
                Button(key.title) {
                    workspace.selectedSession?.sendQuickKey(key)
                }
            }
        }

        Section("Symbols") {
            ForEach([TerminalQuickKey.pipe, .slash, .dash]) { key in
                Button(key.title) {
                    workspace.selectedSession?.sendQuickKey(key)
                }
            }
        }
    }

}

struct TerminalAppearanceSheet: View {
    @Binding var backgroundHex: String
    @Binding var foregroundHex: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    ColorPicker("Background", selection: backgroundBinding, supportsOpacity: false)
                    ColorPicker("Text", selection: foregroundBinding, supportsOpacity: false)
                }

                Section("Preview") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("$ hermes --help")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(currentAppearance.foregroundColor)
                        Text("Terminal preview")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(currentAppearance.foregroundColor.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(currentAppearance.backgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Section {
                    Button("Reset Default Theme") {
                        backgroundHex = TerminalAppearance.default.backgroundHex
                        foregroundHex = TerminalAppearance.default.foregroundHex
                    }
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var currentAppearance: TerminalAppearance {
        TerminalAppearance(
            backgroundHex: backgroundHex,
            foregroundHex: foregroundHex
        )
    }

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { currentAppearance.backgroundColor },
            set: { newValue in
                backgroundHex = UIColor(newValue).terminalHexString ?? backgroundHex
            }
        )
    }

    private var foregroundBinding: Binding<Color> {
        Binding(
            get: { currentAppearance.foregroundColor },
            set: { newValue in
                foregroundHex = UIColor(newValue).terminalHexString ?? foregroundHex
            }
        )
    }
}

struct TerminalSessionChip: View {
    @ObservedObject var session: HermesTerminalSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(session.isConnected ? Color.green : (session.isConnecting ? Color.orange : Color.secondary.opacity(0.6)))
                            .frame(width: 6, height: 6)
                        Text(session.displayTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if session.isConnecting {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }

                    Text(session.chipSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 124, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Color.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    private var backgroundColor: Color {
        return isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.06)
    }

    private var borderColor: Color {
        return Color.white.opacity(isSelected ? 0.18 : 0.08)
    }
}

@MainActor
final class KeyboardObserver: ObservableObject {
    @Published var bottomInset: CGFloat = 0

    var isVisible: Bool { bottomInset > 0 }

    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            self?.handle(keyboardFrame: frame)
        })

        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bottomInset = 0
        })
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
    }

    @MainActor
    private func handle(keyboardFrame: CGRect?) {
        guard
            let keyboardFrame,
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: \.isKeyWindow)
        else {
            return
        }

        let overlap = max(0, window.bounds.maxY - keyboardFrame.minY - window.safeAreaInsets.bottom)
        bottomInset = overlap
    }
}

struct ActiveWorkspaceStrip: View {
    @EnvironmentObject private var store: HermesPhoneStore
    let compact: Bool
    let showsConnectionSummary: Bool
    let showsProfiles: Bool
    let showsDestination: Bool

    init(
        compact: Bool = false,
        showsConnectionSummary: Bool = true,
        showsProfiles: Bool = true,
        showsDestination: Bool = false
    ) {
        self.compact = compact
        self.showsConnectionSummary = showsConnectionSummary
        self.showsProfiles = showsProfiles
        self.showsDestination = showsDestination
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if showsProfiles {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.availableProfiles) { profile in
                            Button {
                                Task { await store.switchHermesProfile(to: profile.name) }
                            } label: {
                                HStack(spacing: 6) {
                                    if profile.name == store.activeConnection?.resolvedHermesProfileName {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                    }
                                    Text(profile.name)
                                        .lineLimit(1)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, compact ? 10 : 11)
                                .padding(.vertical, compact ? 6 : 7)
                                .background(profileBackground(for: profile), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isBusy || store.isLoadingOverview)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            if showsConnectionSummary, let connection = store.activeConnection {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(connection.label)
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                        .lineLimit(1)
                    Text(connection.resolvedHermesProfileName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if showsDestination {
                        Text(connection.displayDestination)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 9 : 12)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        )
    }

    private func profileBackground(for profile: RemoteHermesProfile) -> Color {
        if profile.name == store.activeConnection?.resolvedHermesProfileName {
            return Color(red: 0.18, green: 0.72, blue: 0.62).opacity(0.16)
        }
        return Color(.tertiarySystemFill)
    }
}

#endif
