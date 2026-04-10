import SwiftUI

struct SessionsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Sessions",
                    subtitle: "Browse the recent Hermes conversations discovered on the active host."
                ) {
                    Button {
                        Task { await appState.loadSessions(reset: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isLoadingSessions)
                }

                sessionsPanel
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)

            SessionDetailView(
                session: selectedSession,
                messages: appState.sessionMessages,
                errorMessage: appState.sessionsError
            )
            .frame(minWidth: 420, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appState.activeConnectionID) {
            if appState.sessions.isEmpty {
                await appState.loadSessions(reset: true)
            }
        }
    }

    @ViewBuilder
    private var sessionsPanel: some View {
        if appState.isLoadingSessions && appState.sessions.isEmpty {
            HermesSurfacePanel {
                ProgressView("Loading sessions…")
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if let error = appState.sessionsError, appState.sessions.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load sessions",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if appState.sessions.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "No sessions found",
                    systemImage: "tray",
                    description: Text("No readable Hermes sessions were discovered yet for this SSH target.")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else {
            HermesSurfacePanel(
                title: "Stored Sessions (\(appState.totalSessionsCount))",
                subtitle: "Select a session to inspect its transcript, metadata and last activity."
            ) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(appState.sessions) { session in
                            SessionCardRow(
                                session: session,
                                isSelected: session.id == appState.selectedSessionID
                            ) {
                                Task {
                                    await appState.loadSessionDetail(sessionID: session.id)
                                }
                            }
                        }

                        if appState.hasMoreSessions {
                            Button("Load More") {
                                Task { await appState.loadSessions(reset: false) }
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingSessions && !appState.sessions.isEmpty {
                    ProgressView()
                        .padding(18)
                }
            }
        }
    }

    private var selectedSession: SessionSummary? {
        guard let selectedSessionID = appState.selectedSessionID else { return nil }
        return appState.sessions.first(where: { $0.id == selectedSessionID })
    }
}

private struct SessionCardRow: View {
    let session: SessionSummary
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.resolvedTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Text(session.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    if let count = session.messageCount {
                        HermesBadge(text: "\(count) messages", tint: .secondary)
                    }
                }

                if let preview = session.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        if let startedAt = session.startedAt?.dateValue {
                            metaLabel("Started \(DateFormatters.relativeFormatter().localizedString(for: startedAt, relativeTo: .now))")
                        }

                        if let lastActive = session.lastActive?.dateValue {
                            metaLabel("Active \(DateFormatters.relativeFormatter().localizedString(for: lastActive, relativeTo: .now))")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if let startedAt = session.startedAt?.dateValue {
                            metaLabel("Started \(DateFormatters.relativeFormatter().localizedString(for: startedAt, relativeTo: .now))")
                        }

                        if let lastActive = session.lastActive?.dateValue {
                            metaLabel("Active \(DateFormatters.relativeFormatter().localizedString(for: lastActive, relativeTo: .now))")
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.12 : 0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
