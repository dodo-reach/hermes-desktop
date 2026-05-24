import Foundation
import Testing
@testable import HermesDesktop

@MainActor
struct AppStateChatExperienceTests {
    @Test
    func chatModeDoesNotLaunchEmbeddedTUIForNewSession() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(paths: makeTestAppPaths(root: root))
        let connection = ConnectionProfile(label: "Host", sshHost: "example.local").updated()
        state.connectionStore.upsert(connection)
        state.activeConnectionID = connection.id

        state.startNewSessionChat()

        #expect(state.selectedSessionDetailMode == .chat)
        #expect(state.selectedSessionID == nil)
        #expect(state.sessionTUITerminal == nil)
    }

    @Test
    func chatModeDoesNotLaunchEmbeddedTUIForExistingSession() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(paths: makeTestAppPaths(root: root))
        let connection = ConnectionProfile(label: "Host", sshHost: "example.local").updated()
        state.connectionStore.upsert(connection)
        state.activeConnectionID = connection.id
        state.selectedSessionID = "session-123"

        state.setSessionDetailMode(.chat)

        #expect(state.selectedSessionDetailMode == .chat)
        #expect(state.selectedSessionID == "session-123")
        #expect(state.sessionTUITerminal == nil)
    }

    @Test
    func startingNewChatClearsPreviousNativeTurnCards() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(paths: makeTestAppPaths(root: root))
        let connection = ConnectionProfile(label: "Host", sshHost: "example.local").updated()
        state.connectionStore.upsert(connection)
        state.activeConnectionID = connection.id
        state.selectedSessionID = "session-123"
        state.liveSessionMessageDisplays = [
            SessionMessageDisplay(id: "live-user", role: .user, content: "hello")
        ]
        state.liveToolActivityCards = [
            HermesToolActivityCard(
                id: "tool-1",
                title: "terminal",
                status: "running",
                detail: "swift build",
                isRunning: true,
                updatedAt: Date(timeIntervalSince1970: 0)
            )
        ]
        state.sessionPromptCards = [
            HermesPromptCard(
                id: "approval-1",
                sessionID: "session-123",
                requestID: "approval-1",
                kind: .approval,
                title: "Approve command",
                message: "Run swift build?",
                choices: ["Approve", "Deny"]
            )
        ]

        state.startNewSessionChat()

        #expect(state.selectedSessionDetailMode == .chat)
        #expect(state.selectedSessionID == nil)
        #expect(state.liveSessionMessageDisplays.isEmpty)
        #expect(state.liveToolActivityCards.isEmpty)
        #expect(state.sessionPromptCards.isEmpty)
        #expect(state.sessionTUITerminal == nil)
    }
}
