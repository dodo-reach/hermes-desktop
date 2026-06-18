#if canImport(UIKit)
@preconcurrency import Citadel
import Crypto
import Foundation
import NIOCore
@preconcurrency import NIOSSH
import Security
import SwiftUI
import UIKit

public struct HermesPhoneRootView: View {
    @StateObject private var store = HermesPhoneStore()
    @State private var isPresentingSettings = false

    public init() {}

    public var body: some View {
        TabView(selection: $store.selectedRootTab) {
            NavigationStack(path: $store.sessionNavigationPath) {
                SessionsScreen()
                    .navigationDestination(for: HermesPhoneSessionRoute.self) { route in
                        switch route {
                        case .transcript(let session):
                            SessionTranscriptScreen(session: session)
                        }
                    }
            }
            .tag(HermesPhoneRootTab.sessions)
            .tabItem {
                Label("Sessions", systemImage: "text.bubble")
            }

            NavigationStack {
                KanbanScreen()
            }
            .tag(HermesPhoneRootTab.kanban)
            .tabItem {
                Label("Kanban", systemImage: "rectangle.3.group")
            }

            NavigationStack {
                CronJobsScreen()
            }
            .tag(HermesPhoneRootTab.cron)
            .tabItem {
                Label("Cron", systemImage: "calendar.badge.clock")
            }

            NavigationStack {
                FilesScreen()
            }
            .tag(HermesPhoneRootTab.files)
            .tabItem {
                Label("Files", systemImage: "folder")
            }

            NavigationStack {
                SkillsScreen()
            }
            .tag(HermesPhoneRootTab.skills)
            .tabItem {
                Label("Skills", systemImage: "book.closed")
            }

            NavigationStack {
                TerminalScreen(
                    workspace: store.terminalWorkspace,
                    onOpenSettings: { isPresentingSettings = true }
                )
            }
            .tag(HermesPhoneRootTab.terminal)
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HermesQuickAccessBar(selection: $store.selectedRootTab)
        }
        .overlay {
            if store.selectedRootTab != .terminal {
                GeometryReader { geometry in
                    Button {
                        isPresentingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Hermes settings")
                    .position(
                        x: geometry.size.width - 30,
                        y: geometry.safeAreaInsets.top + 27
                    )
                }
            }
        }
        .environmentObject(store)
        .tint(Color(red: 0.18, green: 0.72, blue: 0.62))
        .hermesKeyboardDismissal()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .alert("HermesPhone", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { newValue in
                if !newValue { store.dismissAlert() }
            }
        )) {
            Button("OK", role: .cancel) {
                store.dismissAlert()
            }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .alert(
            store.hostKeyPrompt?.title ?? "SSH Host Key",
            isPresented: Binding(
                get: { store.hostKeyPrompt != nil },
                set: { newValue in
                    if !newValue { store.dismissHostKeyPrompt() }
                }
            )
        ) {
            if store.hostKeyPrompt?.allowsTrust == true {
                Button("Trust") {
                    store.acceptHostKeyPrompt()
                }
                Button("Cancel", role: .cancel) {
                    store.dismissHostKeyPrompt()
                }
            } else {
                Button("OK", role: .cancel) {
                    store.dismissHostKeyPrompt()
                }
            }
        } message: {
            Text(store.hostKeyPrompt?.message ?? "")
        }
        .sheet(item: $store.fileEditor) { draft in
            FileEditorSheet(draft: draft)
                .environmentObject(store)
        }
        .sheet(isPresented: $isPresentingSettings) {
            NavigationStack {
                HermesSettingsScreen()
            }
            .environmentObject(store)
            .hermesKeyboardDismissal()
        }
    }
}

private struct HermesQuickAccessBar: View {
    @Binding var selection: HermesPhoneRootTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HermesPhoneRootTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: selection == tab ? .semibold : .regular))
                            .symbolVariant(selection == tab ? .fill : .none)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selection == tab ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

extension View {
    func hermesKeyboardDismissal() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                    .accessibilityLabel("Hide keyboard")
                }
            }
    }
}

struct ConnectionHeader: View {
    let connection: ConnectionProfile?

    var body: some View {
        if let connection {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.18, green: 0.72, blue: 0.62))

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.label)
                        .font(.headline)
                        .lineLimit(1)
                    Text(connection.resolvedHermesProfileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

#endif
