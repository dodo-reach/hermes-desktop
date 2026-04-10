import Foundation

struct UsageSummary: Codable {
    let ok: Bool
    let state: UsageSummaryState
    let sessionCount: Int
    let inputTokens: Int64
    let outputTokens: Int64
    let topSessions: [UsageTopSession]
    let recentSessions: [UsageRecentSession]
    let databasePath: String?
    let sessionTable: String?
    let message: String?
    let missingColumns: [String]

    enum CodingKeys: String, CodingKey {
        case ok
        case state
        case sessionCount = "session_count"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case topSessions = "top_sessions"
        case recentSessions = "recent_sessions"
        case databasePath = "database_path"
        case sessionTable = "session_table"
        case message
        case missingColumns = "missing_columns"
    }
}

struct UsageRecentSession: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let inputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

struct UsageTopSession: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let inputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }

    var resolvedTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return id
    }
}

enum UsageSummaryState: String, Codable {
    case available
    case unavailable
}

extension UsageSummary {
    var totalTokens: Int64 {
        inputTokens + outputTokens
    }

    var averageTokensPerSession: Int64 {
        guard sessionCount > 0 else { return 0 }
        return Int64((Double(totalTokens) / Double(sessionCount)).rounded())
    }

    var averageInputTokensPerSession: Int64 {
        guard sessionCount > 0 else { return 0 }
        return Int64((Double(inputTokens) / Double(sessionCount)).rounded())
    }

    var averageOutputTokensPerSession: Int64 {
        guard sessionCount > 0 else { return 0 }
        return Int64((Double(outputTokens) / Double(sessionCount)).rounded())
    }
}
