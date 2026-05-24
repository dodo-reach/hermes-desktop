import Foundation

struct SessionListPage: Codable, Sendable {
    let ok: Bool
    let items: [SessionSummary]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case items
        case totalCount = "total_count"
    }
}

struct SessionSummary: Codable, Identifiable, Hashable, Sendable, TitleIdentifiable, OptionalModelDisplayable {
    let id: String
    let title: String?
    let model: String?
    let parentSessionID: String?
    let startedAt: SessionTimestamp?
    let lastActive: SessionTimestamp?
    let messageCount: Int?
    let preview: String?
    let searchMatch: SessionSearchMatch?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case model
        case parentSessionID = "parent_session_id"
        case startedAt = "started_at"
        case lastActive = "last_active"
        case messageCount = "message_count"
        case preview
        case searchMatch = "search_match"
    }

    init(
        id: String,
        title: String?,
        model: String?,
        parentSessionID: String? = nil,
        startedAt: SessionTimestamp?,
        lastActive: SessionTimestamp?,
        messageCount: Int?,
        preview: String?,
        searchMatch: SessionSearchMatch? = nil
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.parentSessionID = parentSessionID
        self.startedAt = startedAt
        self.lastActive = lastActive
        self.messageCount = messageCount
        self.preview = preview
        self.searchMatch = searchMatch
    }
}

struct SessionSearchMatch: Codable, Hashable, Sendable {
    let matchCount: Int
    let messageID: String?
    let role: SessionMessageRole?
    let timestamp: SessionTimestamp?
    let snippet: String?

    enum CodingKeys: String, CodingKey {
        case matchCount = "match_count"
        case messageID = "message_id"
        case role
        case timestamp
        case snippet
    }
}

struct PinnedSession: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let workspaceScopeFingerprint: String
    var title: String?
    var model: String?
    var parentSessionID: String?
    var startedAt: SessionTimestamp?
    var lastActive: SessionTimestamp?
    var messageCount: Int?
    var preview: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        session: SessionSummary,
        workspaceScopeFingerprint: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = session.id
        self.workspaceScopeFingerprint = workspaceScopeFingerprint
        self.title = session.title
        self.model = session.model
        self.parentSessionID = session.parentSessionID
        self.startedAt = session.startedAt
        self.lastActive = session.lastActive
        self.messageCount = session.messageCount
        self.preview = session.preview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var summary: SessionSummary {
        SessionSummary(
            id: id,
            title: title,
            model: model,
            parentSessionID: parentSessionID,
            startedAt: startedAt,
            lastActive: lastActive,
            messageCount: messageCount,
            preview: preview
        )
    }
}

struct SessionDetailResponse: Codable, Sendable {
    let ok: Bool
    let items: [SessionMessage]
}

struct SessionMessage: Codable, Identifiable, Hashable, Sendable {
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

    init(
        id: String,
        role: SessionMessageRole,
        content: String?,
        timestamp: SessionTimestamp? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
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

        var filtered = metadata.compactMapValues { $0.removingNulls }
        filtered.removeRedundantReasoningContent()
        return filtered.isEmpty ? nil : filtered
    }
}

struct SessionMessageDisplay: Identifiable, Hashable, Sendable {
    let id: String
    let role: SessionMessageRole
    let content: String?
    let timestampText: String?
    let metadataItems: [SessionMetadataDisplayItem]
    let toolSummary: SessionToolMessageSummary?
    let isStreaming: Bool

    init(
        id: String,
        role: SessionMessageRole,
        content: String?,
        timestampText: String? = nil,
        metadataItems: [SessionMetadataDisplayItem] = [],
        toolSummary: SessionToolMessageSummary? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestampText = timestampText
        self.metadataItems = metadataItems
        self.toolSummary = toolSummary
        self.isStreaming = isStreaming
    }

    init(message: SessionMessage) {
        id = message.id
        role = message.role
        content = message.content?.strippingTerminalControlArtifacts
        timestampText = message.timestamp?.dateValue.map(DateFormatters.shortDateTimeString(from:))

        let displayMetadata = message.displayMetadata ?? [:]
        metadataItems = displayMetadata.keys.sorted().compactMap { key in
            guard let value = displayMetadata[key] else { return nil }
            return SessionMetadataDisplayItem(key: key, value: value)
        }
        if message.role.isToolRole || SessionToolMessageSummary.isToolLikePayload(message.content) {
            toolSummary = SessionToolMessageSummary(content: message.content)
        } else {
            toolSummary = nil
        }
        isStreaming = false
    }

    var isToolMessage: Bool {
        toolSummary != nil
    }
}

private extension String {
    var strippingTerminalControlArtifacts: String {
        var cleaned = self
        let escape = "\u{001B}"
        let bell = "\u{0007}"
        cleaned = cleaned.replacingOccurrences(
            of: "\(escape)\\][^\(bell)\(escape)]*(?:\(bell)|\(escape)\\\\)",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "\(escape)\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "(?m)(^|\\s)(?:\\d{1,3}m;?){2,}(?:\\s+|(?=[.,:!?)]|$))",
            with: "$1",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "(?m)(^|\\s)(?:\\d{1,3};){1,8}\\d{1,3}m(?:\\s+|(?=[.,:!?)]|$))",
            with: "$1",
            options: .regularExpression
        )
        return cleaned
    }
}

struct SessionMetadataDisplayItem: Identifiable, Hashable, Sendable {
    let key: String
    let value: JSONValue

    var id: String {
        key
    }

    var displayValue: String {
        value.displayString
    }
}

enum SessionTimestamp: Codable, Hashable, Sendable {
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

struct SessionToolMessageSummary: Hashable, Sendable {
    let title: String
    let preview: String?
    let statusText: String?
    let statusKind: SessionToolStatusKind
    let sizeText: String?
    let isDetailPreviewTruncated: Bool

    private static let jsonParseByteLimit = 256 * 1024
    private static let collapsedPreviewCharacterLimit = 220
    static let detailPreviewCharacterLimit = 5_000

    init(
        title: String,
        preview: String?,
        statusText: String?,
        statusKind: SessionToolStatusKind,
        sizeText: String? = nil,
        isDetailPreviewTruncated: Bool = false
    ) {
        self.title = title
        self.preview = preview
        self.statusText = statusText
        self.statusKind = statusKind
        self.sizeText = sizeText
        self.isDetailPreviewTruncated = isDetailPreviewTruncated
    }

    init(content: String?) {
        let byteCount = content?.utf8.count ?? 0
        sizeText = byteCount > 0 ? Self.formattedByteCount(byteCount) : nil

        if let content, !content.isEmpty {
            isDetailPreviewTruncated = Self.isDetailPreviewTruncated(content)
        } else {
            isDetailPreviewTruncated = false
        }

        guard let content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            title = L10n.string("Tool turn")
            preview = nil
            statusText = nil
            statusKind = .neutral
            return
        }

        let payload = Self.jsonPayload(from: content)
        let toolCall = Self.toolCallPayload(from: Self.jsonObject(from: content))
        statusKind = Self.statusKind(from: payload)
        statusText = toolCall == nil ? Self.statusText(for: statusKind, payload: payload) : nil
        title = toolCall?.title ?? Self.title(from: payload) ?? L10n.string("Tool output")
        preview = toolCall?.preview ?? Self.preview(from: payload) ?? Self.snippet(from: content)
    }

    static func isToolLikePayload(_ content: String?) -> Bool {
        guard let content else { return false }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" || trimmed.first == "[" else { return false }
        guard trimmed.utf8.count <= jsonParseByteLimit else { return false }
        guard let object = Self.jsonObject(from: trimmed) else {
            return false
        }

        if Self.toolCallPayload(from: object) != nil {
            return true
        }

        guard let payload = object as? [String: Any] else { return false }
        return payload["output"] != nil ||
            payload["error"] != nil ||
            payload["diff"] != nil ||
            payload["exit_code"] != nil ||
            payload["success"] != nil ||
            payload["files_modified"] != nil
    }

    private static func jsonPayload(from content: String) -> [String: Any]? {
        guard let object = Self.jsonObject(from: content),
              let payload = object as? [String: Any] else {
            return nil
        }

        return payload
    }

    private static func jsonObject(from content: String) -> Any? {
        guard content.utf8.count <= jsonParseByteLimit,
              let data = content.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func toolCallPayload(from object: Any?) -> (title: String, preview: String?)? {
        if let payload = object as? [String: Any] {
            return Self.toolCallPayload(from: payload)
        }

        if let items = object as? [[String: Any]] {
            for item in items {
                if let result = Self.toolCallPayload(from: item) {
                    return result
                }
            }
        }

        return nil
    }

    private static func toolCallPayload(from payload: [String: Any]?) -> (title: String, preview: String?)? {
        guard let payload else { return nil }

        if let type = stringValue(payload["type"])?.lowercased(),
           type.contains("function"),
           let function = payload["function"] as? [String: Any] {
            let name = stringValue(function["name"]) ?? L10n.string("function")
            let arguments = stringValue(function["arguments"])
            return (
                L10n.string("Tool call: %@", name),
                arguments.flatMap(Self.snippet(from:))
            )
        }

        if let name = stringValue(payload["name"]),
           payload["arguments"] != nil || payload["parameters"] != nil {
            let rawArguments = stringValue(payload["arguments"]) ?? stringValue(payload["parameters"])
            return (
                L10n.string("Tool call: %@", name),
                rawArguments.flatMap(Self.snippet(from:))
            )
        }

        return nil
    }

    private static func statusKind(from payload: [String: Any]?) -> SessionToolStatusKind {
        guard let payload else { return .neutral }

        if let success = payload["success"] as? Bool {
            return success ? .success : .failure
        }

        if let exitCode = payload["exit_code"] as? Int {
            return exitCode == 0 ? .success : .failure
        }

        if let error = stringValue(payload["error"]), !error.isEmpty {
            return .failure
        }

        return .neutral
    }

    private static func statusText(for statusKind: SessionToolStatusKind, payload: [String: Any]?) -> String? {
        switch statusKind {
        case .success:
            return L10n.string("Succeeded")
        case .failure:
            return L10n.string("Failed")
        case .neutral:
            guard let payload,
                  let exitCode = payload["exit_code"] as? Int else {
                return nil
            }
            return L10n.string("Exit %@", "\(exitCode)")
        }
    }

    private static func title(from payload: [String: Any]?) -> String? {
        guard let payload else { return nil }

        if let files = payload["files_modified"] as? [String], !files.isEmpty {
            if files.count == 1, let fileName = files.first?.split(separator: "/").last {
                return L10n.string("Modified %@", String(fileName))
            }

            return L10n.string("Modified %@ files", "\(files.count)")
        }

        if let lint = payload["lint"] as? [String: Any],
           let status = stringValue(lint["status"]),
           !status.isEmpty {
            return L10n.string("Lint %@", status)
        }

        if let error = stringValue(payload["error"]), !error.isEmpty {
            return L10n.string("Tool error")
        }

        if let diff = stringValue(payload["diff"]), !diff.isEmpty {
            return L10n.string("Tool diff")
        }

        if let output = stringValue(payload["output"]), !output.isEmpty {
            return L10n.string("Tool output")
        }

        return nil
    }

    private static func preview(from payload: [String: Any]?) -> String? {
        guard let payload else { return nil }

        if let error = stringValue(payload["error"]), let snippet = snippet(from: error) {
            return snippet
        }

        if let output = stringValue(payload["output"]), let snippet = snippet(from: output) {
            return snippet
        }

        if let diff = stringValue(payload["diff"]), let snippet = snippet(from: diff) {
            return snippet
        }

        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        case .none:
            return nil
        default:
            return nil
        }
    }

    private static func snippet(from text: String) -> String? {
        let seed = String(text.prefix(collapsedPreviewCharacterLimit * 4))
        let normalized = seed
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        guard normalized.count > collapsedPreviewCharacterLimit else { return normalized }

        return String(normalized.prefix(collapsedPreviewCharacterLimit - 3)) + "..."
    }

    static func detailPreview(from content: String?) -> String? {
        guard let content, !content.isEmpty else { return nil }
        let endIndex = content.index(
            content.startIndex,
            offsetBy: detailPreviewCharacterLimit,
            limitedBy: content.endIndex
        ) ?? content.endIndex
        return String(content[..<endIndex])
    }

    private static func isDetailPreviewTruncated(_ content: String) -> Bool {
        guard let limitIndex = content.index(
            content.startIndex,
            offsetBy: detailPreviewCharacterLimit,
            limitedBy: content.endIndex
        ) else {
            return false
        }
        return limitIndex < content.endIndex
    }

    private static func formattedByteCount(_ byteCount: Int) -> String {
        if byteCount < 1_024 {
            return "\(byteCount) B"
        }

        if byteCount < 1_024 * 1_024 {
            return "\(formattedDecimal(Double(byteCount) / 1_024)) KB"
        }

        return "\(formattedDecimal(Double(byteCount) / Double(1_024 * 1_024))) MB"
    }

    private static func formattedDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        if tenths % 10 == 0 {
            return "\(tenths / 10)"
        }

        return "\(tenths / 10).\(tenths % 10)"
    }
}

enum SessionToolStatusKind: Hashable, Sendable {
    case success
    case failure
    case neutral
}

enum SessionMessageRole: Codable, Hashable, Sendable {
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
            return "Agent"
        case .user:
            return "User"
        case .system:
            return "System"
        case .event:
            return "Event"
        case .custom(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "Event" }
            return trimmed.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var isToolRole: Bool {
        switch self {
        case .custom(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return [
                "function",
                "function_call",
                "function_result",
                "tool",
                "tool_call",
                "tool_result"
            ].contains(normalized)
        case .assistant, .user, .system, .event:
            return false
        }
    }

    init(remoteValue: String) {
        self = Self(decodedValue: remoteValue)
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

enum JSONValue: Codable, Hashable, Sendable {
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

private extension Dictionary where Key == String, Value == JSONValue {
    mutating func removeRedundantReasoningContent() {
        guard let reasoning = self["reasoning"]?.normalizedMetadataText,
              let reasoningContent = self["reasoning_content"]?.normalizedMetadataText,
              reasoning == reasoningContent else {
            return
        }

        removeValue(forKey: "reasoning_content")
    }
}

private extension JSONValue {
    var normalizedMetadataText: String? {
        let trimmed = displayString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
