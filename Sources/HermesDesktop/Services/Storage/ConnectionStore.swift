import Combine
import Foundation

@MainActor
final class ConnectionStore: ObservableObject {
    @Published private(set) var connections: [ConnectionProfile] = []
    @Published var lastConnectionID: UUID? {
        didSet {
            savePreferences()
        }
    }
    @Published var terminalTheme: TerminalThemePreference = .defaultValue {
        didSet {
            savePreferences()
        }
    }

    private let paths: AppPaths
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(paths: AppPaths) {
        self.paths = paths
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func upsert(_ connection: ConnectionProfile) {
        let normalized = connection.updated()
        if let index = connections.firstIndex(where: { $0.id == normalized.id }) {
            connections[index] = normalized
        } else {
            connections.append(normalized)
        }
        connections.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        saveConnections()
    }

    func delete(_ connection: ConnectionProfile) {
        connections.removeAll(where: { $0.id == connection.id })
        if lastConnectionID == connection.id {
            lastConnectionID = nil
        }
        saveConnections()
    }

    private func load() {
        if let data = try? Data(contentsOf: paths.connectionsURL),
           let decoded = try? decoder.decode([ConnectionProfile].self, from: data) {
            connections = decoded
        }

        if let data = try? Data(contentsOf: paths.preferencesURL),
           let decoded = try? decoder.decode(AppPreferences.self, from: data) {
            lastConnectionID = decoded.lastConnectionID
            terminalTheme = decoded.terminalTheme ?? .defaultValue
        }
    }

    private func saveConnections() {
        if let data = try? encoder.encode(connections) {
            try? data.write(to: paths.connectionsURL, options: [.atomic])
        }
        savePreferences()
    }

    private func savePreferences() {
        let preferences = AppPreferences(
            lastConnectionID: lastConnectionID,
            terminalTheme: terminalTheme
        )
        if let data = try? encoder.encode(preferences) {
            try? data.write(to: paths.preferencesURL, options: [.atomic])
        }
    }
}

private struct AppPreferences: Codable {
    var lastConnectionID: UUID?
    var terminalTheme: TerminalThemePreference?
}
