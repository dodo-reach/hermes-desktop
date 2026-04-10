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

struct SessionSummary: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let startedAt: JSONValue?
    let lastActive: JSONValue?
    let messageCount: Int?
    let preview: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startedAt = "started_at"
        case lastActive = "last_active"
        case messageCount = "message_count"
        case preview
    }

    var resolvedTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return id
    }
}

struct SessionDetailResponse: Codable {
    let ok: Bool
    let items: [SessionMessage]
}

struct SessionMessage: Codable, Identifiable, Hashable {
    let id: String
    let role: String?
    let content: String?
    let timestamp: JSONValue?
    let metadata: [String: JSONValue]?
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
}
