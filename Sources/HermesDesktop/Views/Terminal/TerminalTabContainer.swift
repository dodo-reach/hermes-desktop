import SwiftUI

struct TerminalTabContainer: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var session: TerminalSession
    let appearance: TerminalThemeAppearance
    let isActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(session.connection.resolvedHermesProfileName)
                            .font(.headline)

                        if isDifferentFromActiveWorkspace {
                            HermesBadge(text: "Other Profile", tint: .orange)
                        }
                    }

                    Text(session.connection.displayDestination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let currentDirectory = session.currentDirectory {
                    Text(currentDirectory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let exitCode = session.exitCode {
                    Text(exitCode == 0 ? "Shell exited" : "Connection ended (\(exitCode))")
                        .font(.caption)
                        .foregroundStyle(exitCode == 0 ? Color.secondary : Color.orange)

                    Button("Reconnect") {
                        session.requestReconnect()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.08))

            SwiftTermTerminalView(session: session, appearance: appearance, isActive: isActive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appearance.backgroundColor.swiftUIColor)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isDifferentFromActiveWorkspace: Bool {
        guard let activeConnection = appState.activeConnection else { return false }
        return activeConnection.workspaceScopeFingerprint != session.connection.workspaceScopeFingerprint
    }
}
