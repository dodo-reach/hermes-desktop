import Foundation

struct SessionListPage: Codable {
    let ok: Bool
    let items: [SessionSummary]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case items
        case totalCount = "total_count"
    }
}

struct SessionSummary: Codable, Identifiable, Hashable, TitleIdentifiable, OptionalModelDisplayable {
    let id: String
    let title: String?
    let model: String?
    let startedAt: SessionTimestamp?
    let lastActive: SessionTimestamp?
    let messageCount: Int?
    let preview: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case model
        case startedAt = "started_at"
        case lastActive = "last_active"
        case messageCount = "message_count"
        case preview
    }
}

struct SessionDetailResponse: Codable {
    let ok: Bool
    let items: [SessionMessage]
}

struct SessionMessage: Codable, Identifiable, Hashable {
    let id: String
    let role: SessionMessageRole
    let content: String?
    let timestamp: SessionTimestamp?
    let metadata: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case timestamp
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decodeIfPresent(SessionMessageRole.self, forKey: .role) ?? .event
        content = try container.decodeIfPresent(String.self, forKey: .content)
        timestamp = try container.decodeIfPresent(SessionTimestamp.self, forKey: .timestamp)
        metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata)
    }

    var displayMetadata: [String: JSONValue]? {
        guard let metadata else {
            return nil
        }

        let filtered = metadata.compactMapValues { $0.removingNulls }
        return filtered.isEmpty ? nil : filtered
    }
}

enum SessionTimestamp: Codable, Hashable {
    case unixSeconds(Double)
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(Int.self) {
            self = .unixSeconds(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .unixSeconds(value)
        } else if let value = try? container.decode(String.self) {
            self = .text(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported timestamp value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .unixSeconds(let value):
            try container.encode(value)
        case .text(let value):
            try container.encode(value)
        }
    }

    var dateValue: Date? {
        switch self {
        case .unixSeconds(let value):
            return Date(timeIntervalSince1970: value)
        case .text(let value):
            if let double = Double(value) {
                return Date(timeIntervalSince1970: double)
            }
            return ISO8601DateFormatter.fractionalSecondsFormatter().date(from: value) ??
                ISO8601DateFormatter().date(from: value)
        }
    }
}

enum SessionMessageRole: Codable, Hashable {
    case assistant
    case user
    case system
    case event
    case custom(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(decodedValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }

    var displayTitle: String {
        switch self {
        case .assistant:
            return NSLocalizedString("role.assistant", comment: "Assistant message role")
        case .user:
            return NSLocalizedString("role.user", comment: "User message role")
        case .system:
            return NSLocalizedString("role.system", comment: "System message role")
        case .event:
            return NSLocalizedString("role.event", comment: "Event message role")
        case .custom(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return NSLocalizedString("role.event", comment: "Event message role")
            }
            return trimmed.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private init(decodedValue: String) {
        let normalized = decodedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "assistant":
            self = .assistant
        case "user":
            self = .user
        case "system":
            self = .system
        case "", "event":
            self = .event
        default:
            self = .custom(decodedValue)
        }
    }

    private var encodedValue: String {
        switch self {
        case .assistant:
            return "assistant"
        case .user:
            return "user"
        case .system:
            return "system"
        case .event:
            return "event"
        case .custom(let value):
            return value
        }
    }
}

enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case int(Int)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            String(value)
        case .int(let value):
            String(value)
        case .bool(let value):
            String(value)
        case .null:
            nil
        case .object, .array:
            nil
        }
    }

    var dateValue: Date? {
        switch self {
        case .number(let value):
            return Date(timeIntervalSince1970: value)
        case .int(let value):
            return Date(timeIntervalSince1970: Double(value))
        case .string(let value):
            if let double = Double(value) {
                return Date(timeIntervalSince1970: double)
            }
            return ISO8601DateFormatter.fractionalSecondsFormatter().date(from: value) ??
                ISO8601DateFormatter().date(from: value)
        default:
            return nil
        }
    }

    var displayString: String {
        switch self {
        case .object, .array:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(self),
                  let string = String(data: data, encoding: .utf8) else {
                return String(describing: self)
            }
            return string
        case .null:
            return "null"
        default:
            return stringValue ?? "null"
        }
    }

    var removingNulls: JSONValue? {
        switch self {
        case .null:
            return nil
        case .object(let value):
            let filtered = value.compactMapValues { $0.removingNulls }
            return filtered.isEmpty ? nil : .object(filtered)
        case .array(let value):
            let filtered = value.compactMap { $0.removingNulls }
            return filtered.isEmpty ? nil : .array(filtered)
        default:
            return self
        }
    }
}
