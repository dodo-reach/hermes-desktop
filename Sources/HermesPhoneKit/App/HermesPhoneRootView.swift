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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = HermesPhoneStore()
    @StateObject private var notifications = HermesPhoneNotificationService.shared

    public init() {}

    public var body: some View {
        TabView(selection: $store.selectedRootTab) {
            NavigationStack(path: $store.chatNavigationPath) {
                NativeChatScreen(chatStore: store.nativeChatStore)
                    .navigationDestination(for: HermesPhoneChatRoute.self) { route in
                        switch route {
                        case .transcript(let session):
                            SessionTranscriptScreen(session: session)
                        }
                    }
            }
            .tag(HermesPhoneRootTab.chat)
            .tabItem {
                Label("Chats", systemImage: "bubble.left.and.bubble.right")
            }

            NavigationStack {
                TerminalScreen(workspace: store.terminalWorkspace)
            }
            .tag(HermesPhoneRootTab.terminal)
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }

            NavigationStack {
                FilesScreen()
            }
            .tag(HermesPhoneRootTab.files)
            .tabItem {
                Label("Files", systemImage: "doc.text")
            }

            NavigationStack {
                MoreScreen()
            }
            .tag(HermesPhoneRootTab.more)
            .tabItem {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .environmentObject(store)
        .tint(Color(red: 0.18, green: 0.72, blue: 0.62))
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
        .task {
            notifications.configure()
            notifications.updateScenePhase(scenePhase)
            await store.nativeChatStore.warmGatewayIfUseful()
        }
        .task(id: store.activeWorkspaceScopeFingerprint) {
            guard scenePhase == .active else { return }
            await store.nativeChatStore.warmGatewayIfUseful()
        }
        .onChange(of: scenePhase) { _, newPhase in
            notifications.updateScenePhase(newPhase)
            guard newPhase == .active else { return }
            Task { @MainActor in
                await store.nativeChatStore.warmGatewayIfUseful()
                await store.nativeChatStore.refreshCurrentConversationFromRemote()
            }
        }
        .onChange(of: notifications.pendingRoute) { _, route in
            guard let route else { return }
            store.openNotificationRoute(route)
            notifications.consumePendingRoute(route)
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
