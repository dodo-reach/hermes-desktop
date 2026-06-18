#if canImport(UIKit)
@preconcurrency import Citadel
import Crypto
import Foundation
import NIOCore
@preconcurrency import NIOSSH
import Security
import SwiftUI
import UIKit

struct ConnectionsScreen: View {
    @EnvironmentObject private var store: HermesPhoneStore
    @State private var draft = ConnectionDraft()
    @State private var isPresentingEditor = false
    @State private var editingConnectionID: UUID?
    @State private var showsConnectionGuide = false

    var body: some View {
        List {
            Section {
                activeWorkspaceSummary
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            savedHostsSection
            connectionGuideSection
        }
        .navigationTitle("Connections")
        .toolbar {
            Button {
                editingConnectionID = nil
                draft = ConnectionDraft()
                isPresentingEditor = true
            } label: {
                Label("Add Host", systemImage: "plus")
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            NavigationStack {
                ConnectionEditorView(draft: $draft, editingConnectionID: editingConnectionID)
                    .environmentObject(store)
            }
            .hermesKeyboardDismissal()
        }
        .task(id: store.activeWorkspaceScopeFingerprint) {
            await store.refreshOverview()
        }
    }

    private var activeWorkspaceSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Active Host")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let connection = store.activeConnection {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.label)
                                .font(.title3.weight(.semibold))
                            Text(connection.displayDestination)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(connection.resolvedHermesProfileName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.16), in: Capsule())
                    }

                    if !store.availableProfiles.isEmpty {
                        profilePicker
                    }

                    if let overview = store.overview {
                        VStack(alignment: .leading, spacing: 8) {
                            workspaceMetric(label: "Hermes Home", value: overview.hermesHome)
                            workspaceMetric(label: "Mode", value: "SSH-first read-only companion")
                            workspaceMetric(label: "Session Store", value: overview.sessionStore?.path ?? "Not found")
                        }
                    } else {
                        Text("Add one SSH host. Hermes profiles on that host are discovered automatically.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ContentUnavailableView(
                    "No Active Host",
                    systemImage: "server.rack",
                    description: Text("Add one SSH host to inspect Sessions, Kanban, gateway state, profiles, and configuration.")
                )
            }
        }
    }

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovered Profiles")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.availableProfiles) { profile in
                        Button {
                            Task { await store.switchHermesProfile(to: profile.name) }
                        } label: {
                            HStack(spacing: 6) {
                                if profile.name == store.activeConnection?.resolvedHermesProfileName {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                Text(profile.name)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(profile.name == store.activeConnection?.resolvedHermesProfileName ? Color.green.opacity(0.16) : Color(.tertiarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isBusy || store.isLoadingOverview)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var savedHostsSection: some View {
        Section("Saved Hosts") {
            if store.connections.isEmpty {
                ContentUnavailableView(
                    "No Hosts",
                    systemImage: "server.rack",
                    description: Text("Add your Mac or server once. The app will discover default and named Hermes profiles over SSH.")
                )
            } else {
                ForEach(savedConnectionGroups) { group in
                    hostRow(group)
                        .swipeActions {
                            Button(role: .destructive) {
                                removeHost(group)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func hostRow(_ group: ConnectionHostGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.primaryConnection.label)
                        .font(.headline)
                    Text(group.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(group.isActive ? "Profiles are available above and throughout the app." : "Use this host to discover its Hermes profiles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if group.isActive {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
            }

            HStack(spacing: 10) {
                if !group.isActive {
                    Button("Use Host") {
                        store.activateHost(group.id)
                    }
                    .buttonStyle(.bordered)
                }

                Button("Edit") {
                    editingConnectionID = group.primaryConnection.id
                    draft = ConnectionDraft(
                        connection: group.primaryConnection,
                        credential: (try? store.credential(for: group.primaryConnection)) ?? SSHCredentialRecord()
                    )
                    isPresentingEditor = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }

    private func workspaceMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
        }
    }

    private var connectionGuideSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsConnectionGuide) {
                VStack(alignment: .leading, spacing: 12) {
                    ConnectionsGuideStep(title: "1. Add the SSH host", detail: "Host, port, user, and credentials are the only setup the app needs.")
                    ConnectionsGuideStep(title: "2. Let discovery run", detail: "Default and named Hermes profiles under ~/.hermes are found automatically.")
                    ConnectionsGuideStep(title: "3. Pick a profile", detail: "Use the profile chips here. All remote state remains scoped to that host and profile.")

                    Text("HermesPhone uses direct SSH. No mobile backend, dashboard process, or exposed gateway port is required.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } label: {
                Label("How profile discovery works", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var savedConnectionGroups: [ConnectionHostGroup] {
        let grouped = Dictionary(grouping: store.connections, by: \.hostConnectionFingerprint)
        return grouped.values.compactMap { connections in
            let sortedConnections = connections.sorted {
                if $0.usesDefaultHermesProfile != $1.usesDefaultHermesProfile {
                    return $0.usesDefaultHermesProfile
                }
                return $0.resolvedHermesProfileName.localizedCaseInsensitiveCompare($1.resolvedHermesProfileName) == .orderedAscending
            }
            guard let first = sortedConnections.first else { return nil }
            return ConnectionHostGroup(
                id: first.hostConnectionFingerprint,
                title: first.displayDestination,
                primaryConnection: first,
                connections: sortedConnections,
                isActive: store.activeHostFingerprint == first.hostConnectionFingerprint
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func removeHost(_ group: ConnectionHostGroup) {
        for connection in group.connections {
            store.removeConnection(connection)
        }
    }
}

private struct ConnectionsGuideStep: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.footnote.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectionHostGroup: Identifiable {
    let id: String
    let title: String
    let primaryConnection: ConnectionProfile
    let connections: [ConnectionProfile]
    let isActive: Bool
}

#endif
