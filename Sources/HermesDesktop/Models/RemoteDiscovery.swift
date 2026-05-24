import Foundation

struct RemoteDiscovery: Codable {
    let ok: Bool
    let remoteHome: String
    let hermesHome: String
    let activeProfile: RemoteHermesProfile
    let availableProfiles: [RemoteHermesProfile]
    let paths: RemoteHermesPaths
    let exists: RemoteHermesPathExistence
    let sessionStore: RemoteSessionStore?
    let kanban: RemoteKanbanDiscovery?

    enum CodingKeys: String, CodingKey {
        case ok
        case remoteHome = "remote_home"
        case hermesHome = "hermes_home"
        case activeProfile = "active_profile"
        case availableProfiles = "available_profiles"
        case paths
        case exists
        case sessionStore = "session_store"
        case kanban
    }
}

struct RemoteHermesProfile: Codable, Identifiable {
    let name: String
    let path: String
    let isDefault: Bool
    let exists: Bool
    let displayName: String?

    var id: String { name }
    var displayTitle: String { displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? name }

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case isDefault = "is_default"
        case exists
        case displayName = "display_name"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct RemoteHermesPaths: Codable {
    let user: String
    let memory: String
    let soul: String
    let sessionsDir: String
    let cronJobs: String
    let kanbanDatabase: String?

    enum CodingKeys: String, CodingKey {
        case user
        case memory
        case soul
        case sessionsDir = "sessions_dir"
        case cronJobs = "cron_jobs"
        case kanbanDatabase = "kanban_database"
    }
}

struct RemoteHermesPathExistence: Codable {
    let user: Bool
    let memory: Bool
    let soul: Bool
    let sessionsDir: Bool
    let cronJobs: Bool
    let kanbanDatabase: Bool?

    enum CodingKeys: String, CodingKey {
        case user
        case memory
        case soul
        case sessionsDir = "sessions_dir"
        case cronJobs = "cron_jobs"
        case kanbanDatabase = "kanban_database"
    }
}

struct RemoteSessionStore: Codable {
    let kind: RemoteSessionStoreKind
    let path: String
    let sessionTable: String?
    let messageTable: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case path
        case sessionTable = "session_table"
        case messageTable = "message_table"
    }
}

struct RemoteKanbanDiscovery: Codable, Hashable {
    let databasePath: String
    let exists: Bool
    let hostWide: Bool
    let hasHermesCLI: Bool
    let hasKanbanModule: Bool
    let dispatcher: KanbanDispatcherStatus?

    enum CodingKeys: String, CodingKey {
        case databasePath = "database_path"
        case exists
        case hostWide = "host_wide"
        case hasHermesCLI = "has_hermes_cli"
        case hasKanbanModule = "has_kanban_module"
        case dispatcher
    }
}

enum RemoteSessionStoreKind: Codable, Hashable {
    case sqlite
    case other(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(decodedValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }

    var displayName: String {
        switch self {
        case .sqlite:
            return "SQLite"
        case .other(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "Unknown" }
            return trimmed.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private init(decodedValue: String) {
        let normalized = decodedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "sqlite":
            self = .sqlite
        default:
            self = .other(decodedValue)
        }
    }

    private var encodedValue: String {
        switch self {
        case .sqlite:
            return "sqlite"
        case .other(let value):
            return value
        }
    }
}
