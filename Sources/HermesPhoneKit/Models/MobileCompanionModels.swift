import Foundation

struct GatewaySnapshot: Codable, Hashable, Sendable {
    let profileName: String
    let cliAvailable: Bool
    let lifecycleAvailable: Bool
    let running: Bool?
    let manager: String?
    let serviceStatus: String?
    let lastError: String?
    let channels: [GatewayChannel]

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case cliAvailable = "cli_available"
        case lifecycleAvailable = "lifecycle_available"
        case running
        case manager
        case serviceStatus = "service_status"
        case lastError = "last_error"
        case channels
    }
}

struct GatewayChannel: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let enabled: Bool?
    let configured: Bool
}

enum GatewayLifecycleAction: String, CaseIterable, Identifiable, Sendable {
    case start
    case stop
    case restart

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var isDestructive: Bool { self != .start }
}

struct ProfileManagementSnapshot: Codable, Sendable {
    let profiles: [RemoteHermesProfile]
    let deleteCommandAvailable: Bool
    let noninteractiveDeleteFlag: String?

    enum CodingKeys: String, CodingKey {
        case profiles
        case deleteCommandAvailable = "delete_command_available"
        case noninteractiveDeleteFlag = "noninteractive_delete_flag"
    }
}

struct KanbanMobileSnapshot: Codable, Hashable, Sendable {
    let available: Bool
    let databasePath: String
    let boardSlug: String
    let boards: [KanbanMobileBoard]
    let tasks: [KanbanMobileTask]
    let latestEventID: Int?
    let warning: String?

    enum CodingKeys: String, CodingKey {
        case available
        case databasePath = "database_path"
        case boardSlug = "board_slug"
        case boards
        case tasks
        case latestEventID = "latest_event_id"
        case warning
    }
}

struct KanbanMobileBoard: Codable, Identifiable, Hashable, Sendable {
    let slug: String
    let name: String
    var id: String { slug }
}

struct KanbanMobileTask: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String?
    let status: String
    let assignee: String?
    let priority: Int
    let commentCount: Int
    let comments: [KanbanMobileComment]

    enum CodingKeys: String, CodingKey {
        case id, title, body, status, assignee, priority, comments
        case commentCount = "comment_count"
    }
}

struct KanbanMobileComment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let author: String?
    let body: String
    let createdAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, author, body
        case createdAt = "created_at"
    }
}

struct ConfigSnapshot: Codable, Hashable, Sendable {
    let contentHash: String
    let fields: [ConfigField]
    let categoryOrder: [String]
    let unknownJSON: String
    let validationAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case contentHash = "content_hash"
        case fields
        case categoryOrder = "category_order"
        case unknownJSON = "unknown_json"
        case validationAvailable = "validation_available"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        fields = try container.decode([ConfigField].self, forKey: .fields)
        categoryOrder = try container.decodeIfPresent([String].self, forKey: .categoryOrder) ?? []
        unknownJSON = try container.decode(String.self, forKey: .unknownJSON)
        validationAvailable = try container.decode(Bool.self, forKey: .validationAvailable)
    }
}

struct ConfigField: Codable, Identifiable, Hashable, Sendable {
    let path: String
    let title: String
    let category: String
    let description: String?
    let kind: String
    let enumValues: [String]
    let value: JSONValue
    let defaultValue: JSONValue?

    enum CodingKeys: String, CodingKey {
        case path, title, category, description, kind, value
        case enumValues = "enum_values"
        case defaultValue = "default_value"
    }

    var id: String { path }
}

struct EnvironmentSnapshot: Codable, Hashable, Sendable {
    let variables: [EnvironmentVariableStatus]
}

struct EnvironmentVariableStatus: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let category: String
    let description: String?
    let isSet: Bool
    let url: String?
    let tools: [String]
    let isAdvanced: Bool
    let isPassword: Bool

    enum CodingKeys: String, CodingKey {
        case name, category, description
        case isSet = "is_set"
        case url, tools
        case isAdvanced = "advanced"
        case isPassword = "is_password"
    }

    var id: String { name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "other"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isSet = try container.decode(Bool.self, forKey: .isSet)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        tools = try container.decodeIfPresent([String].self, forKey: .tools) ?? []
        isAdvanced = try container.decodeIfPresent(Bool.self, forKey: .isAdvanced) ?? false
        isPassword = try container.decodeIfPresent(Bool.self, forKey: .isPassword) ?? true
    }
}

enum MobileCompanionError: LocalizedError {
    case staleResponse
    case unsafeOperation(String)

    var errorDescription: String? {
        switch self {
        case .staleResponse:
            "The active host or profile changed before the request completed."
        case .unsafeOperation(let message):
            message
        }
    }
}
