import Foundation
import Testing

@testable import HermesDesktop

@MainActor
struct AppStateConnectionTests {
    @Test
    func savingHostWithoutActiveConnectionSelectsAndPersistsIt() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = makeTestAppPaths(root: root)
        let appState = AppState(paths: paths)

        appState.saveConnection(
            ConnectionProfile(
                label: "Studio Mac",
                sshHost: "studio.local",
                sshUser: "alex"
            )
        )

        let savedConnection = try #require(appState.connectionStore.connections.first)
        #expect(appState.activeConnectionID == savedConnection.id)
        #expect(appState.connectionStore.lastConnectionID == savedConnection.id)
        #expect(appState.activeConnection?.label == "Studio Mac")

        let reloadedStore = ConnectionStore(paths: paths)
        #expect(reloadedStore.lastConnectionID == savedConnection.id)
    }

    @Test
    func savingAdditionalHostDoesNotSwitchActiveConnection() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appState = AppState(paths: makeTestAppPaths(root: root))
        let firstConnection = ConnectionProfile(
            label: "Studio Mac",
            sshHost: "studio.local",
            sshUser: "alex"
        )
        let secondConnection = ConnectionProfile(
            label: "Prod VPS",
            sshHost: "203.0.113.10",
            sshUser: "deploy"
        )

        appState.saveConnection(firstConnection)
        let activeConnectionID = try #require(appState.activeConnectionID)

        appState.saveConnection(secondConnection)

        #expect(appState.activeConnectionID == activeConnectionID)
        #expect(appState.connectionStore.lastConnectionID == activeConnectionID)
        #expect(appState.connectionStore.connections.count == 2)
    }

    @Test
    func startupSelectsSavedHostWhenLastConnectionPreferenceIsMissing() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = makeTestAppPaths(root: root)
        let store = ConnectionStore(paths: paths)
        let olderConnection = ConnectionProfile(
            label: "Older Host",
            sshHost: "older.local",
            lastConnectedAt: Date(timeIntervalSince1970: 100)
        )
        let newerConnection = ConnectionProfile(
            label: "Newer Host",
            sshHost: "newer.local",
            lastConnectedAt: Date(timeIntervalSince1970: 200)
        )
        store.upsert(olderConnection)
        store.upsert(newerConnection)
        #expect(store.lastConnectionID == nil)

        let appState = AppState(paths: paths)

        #expect(appState.activeConnectionID == newerConnection.id)
        #expect(appState.connectionStore.lastConnectionID == newerConnection.id)
    }

    @Test
    func startupIgnoresStaleLastConnectionPreference() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = makeTestAppPaths(root: root)
        let store = ConnectionStore(paths: paths)
        let savedConnection = ConnectionProfile(
            label: "Studio Mac",
            sshHost: "studio.local"
        )
        store.upsert(savedConnection)
        store.lastConnectionID = UUID()

        let appState = AppState(paths: paths)

        #expect(appState.activeConnectionID == savedConnection.id)
        #expect(appState.connectionStore.lastConnectionID == savedConnection.id)
    }
}
