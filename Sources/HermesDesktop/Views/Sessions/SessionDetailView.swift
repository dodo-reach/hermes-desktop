import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject private var appState: AppState

    let session: SessionSummary?
    let messages: [SessionMessage]
    let errorMessage: String?

    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let session {
                    HermesSurfacePanel {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(session.resolvedTitle)
                                        .font(.title2)
                                        .fontWeight(.semibold)

                                    Text(session.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                Spacer(minLength: 12)

                                HStack(spacing: 8) {
                                    if let model = session.displayModel {
                                        HermesBadge(text: model, tint: .orange)
                                    }

                                    if let count = session.messageCount {
                                        HermesBadge(text: L10n.string("%@ messages", "\(count)"), tint: .accentColor)
                                    }

                                    Button {
                                        showDeleteConfirmation = true
                                    } label: {
                                        Group {
                                            if appState.isDeletingSession && appState.selectedSessionID == session.id {
                                                ProgressView()
                                                    .controlSize(.small)
                                            } else {
                                                Image(systemName: "trash")
                                                    .font(.caption.weight(.semibold))
                                            }
                                        }
                                        .foregroundStyle(.red)
                                        .frame(minWidth: 14, minHeight: 14)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(Color.red.opacity(0.12), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .help(L10n.string("Delete session"))
                                    .accessibilityLabel(L10n.string("Delete session"))
                                    .disabled(appState.isDeletingSession)
                                }
                            }

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 18) {
                                    if let startedAt = session.startedAt?.dateValue {
                                        HermesLabeledValue(
                                            label: "Started",
                                            value: DateFormatters.shortDateTimeFormatter().string(from: startedAt)
                                        )
                                    }

                                    if let lastActive = session.lastActive?.dateValue {
                                        HermesLabeledValue(
                                            label: "Last active",
                                            value: DateFormatters.shortDateTimeFormatter().string(from: lastActive)
                                        )
                                    }
                                }

                                VStack(alignment: .leading, spacing: 12) {
                                    if let startedAt = session.startedAt?.dateValue {
                                        HermesLabeledValue(
                                            label: "Started",
                                            value: DateFormatters.shortDateTimeFormatter().string(from: startedAt)
                                        )
                                    }

                                    if let lastActive = session.lastActive?.dateValue {
                                        HermesLabeledValue(
                                            label: "Last active",
                                            value: DateFormatters.shortDateTimeFormatter().string(from: lastActive)
                                        )
                                    }
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        HermesSurfacePanel {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }

                    if messages.isEmpty {
                        HermesSurfacePanel {
                            ContentUnavailableView(
                                "No transcript entries",
                                systemImage: "text.bubble",
                                description: Text("This session has no readable message rows yet.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 280)
                        }
                    } else {
                        HermesSurfacePanel(
                            title: "Transcript",
                            subtitle: "Messages are shown in the order Hermes stored them for this session."
                        ) {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(messages) { message in
                                    MessageCard(message: message)
                                }
                            }
                        }
                    }
                } else {
                    HermesSurfacePanel {
                        ContentUnavailableView(
                            "Select a session",
                            systemImage: "rectangle.stack.person.crop",
                            description: Text("Choose a Hermes session from the active host to inspect its transcript.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .alert("Delete this session?", isPresented: $showDeleteConfirmation, presenting: session) { session in
            Button("Delete", role: .destructive) {
                Task {
                    await appState.deleteSession(session)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text(L10n.string(
                "“%@” will be removed from Hermes Desktop and deleted on the remote Hermes host as well. This action cannot be undone.",
                session.resolvedTitle
            ))
        }
    }
}

private struct MessageCard: View {
    let message: SessionMessage

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    HermesBadge(
                        text: displayRole,
                        tint: roleTint,
                        isMonospaced: false
                    )

                    Spacer()

                    if let timestamp = message.timestamp?.dateValue {
                        Text(DateFormatters.shortDateTimeFormatter().string(from: timestamp))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let content = message.content, !content.isEmpty {
                    Text(content)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(L10n.string("No text payload"))
                        .foregroundStyle(.secondary)
                        .italic()
                }

                if let metadata = message.displayMetadata, !metadata.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("Metadata"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(metadata.keys.sorted(), id: \.self) { key in
                            if let value = metadata[key] {
                                HermesInsetSurface {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(key)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)

                                        Text(value.displayString)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var displayRole: String {
        message.role.displayTitle
    }

    private var roleTint: Color {
        switch message.role {
        case .assistant:
            return .blue
        case .user:
            return .green
        case .system:
            return .orange
        case .event, .custom:
            return .secondary
        }
    }
}
