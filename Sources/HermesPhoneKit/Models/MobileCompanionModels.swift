import Foundation

struct GatewaySnapshot: Codable, Hashable, Sendable {
    let profileName: String
    let cliAvailable: Bool
    let lifecycleAvailable: Bool
    let running: Bool?
    let state: String?
    let processID: Int?
    let manager: String?
    let serviceStatus: String?
    let lastError: String?
    let updatedAt: String?
    let channels: [GatewayChannel]

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case cliAvailable = "cli_available"
        case lifecycleAvailable = "lifecycle_available"
        case running
        case state
        case processID = "process_id"
        case manager
        case serviceStatus = "service_status"
        case lastError = "last_error"
        case updatedAt = "updated_at"
        case channels
    }
}

struct GatewayChannel: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?
    let enabled: Bool
    let configured: Bool
    let state: String
    let errorMessage: String?
    let updatedAt: String?
    let credentials: [GatewayChannelCredential]

    enum CodingKeys: String, CodingKey {
        case id, name, description, enabled, configured, state
        case errorMessage = "error_message"
        case updatedAt = "updated_at"
        case credentials
    }
}

struct GatewayChannelCredential: Codable, Identifiable, Hashable, Sendable {
    let key: String
    let prompt: String
    let description: String?
    let required: Bool
    let isSet: Bool
    let isPassword: Bool
    let isAdvanced: Bool

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, prompt, description, required
        case isSet = "is_set"
        case isPassword = "is_password"
        case isAdvanced = "advanced"
    }
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
    let agents: [HermesAgentSummary]
    let activeProfileName: String
    let canCreate: Bool
    let canRename: Bool
    let canDelete: Bool

    enum CodingKeys: String, CodingKey {
        case agents
        case activeProfileName = "active_profile_name"
        case canCreate = "can_create"
        case canRename = "can_rename"
        case canDelete = "can_delete"
    }
}

struct HermesAgentSummary: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let path: String
    let isDefault: Bool
    let isActive: Bool
    let gatewayRunning: Bool
    let model: String?
    let provider: String?
    let hasEnvironment: Bool
    let skillCount: Int
    let description: String?
    let descriptionIsAutomatic: Bool
    let soul: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, path, model, provider, description, soul
        case isDefault = "is_default"
        case isActive = "is_active"
        case gatewayRunning = "gateway_running"
        case hasEnvironment = "has_environment"
        case skillCount = "skill_count"
        case descriptionIsAutomatic = "description_is_automatic"
    }
}

enum AgentCreationMode: String, CaseIterable, Identifiable, Sendable {
    case fresh
    case cloneCurrent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fresh: "Fresh Agent"
        case .cloneCurrent: "Clone Current"
        }
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
