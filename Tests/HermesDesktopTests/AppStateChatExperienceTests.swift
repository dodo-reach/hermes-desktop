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
}
