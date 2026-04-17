import Foundation

struct UsageSummary: Codable {
    let ok: Bool
    let state: UsageSummaryState
    let sessionCount: Int
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let cacheWriteTokens: Int64
    let reasoningTokens: Int64
    let topSessions: [UsageTopSession]
    let topModels: [UsageTopModel]
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
        case cacheReadTokens = "cache_read_tokens"
        case cacheWriteTokens = "cache_write_tokens"
        case reasoningTokens = "reasoning_tokens"
        case topSessions = "top_sessions"
        case topModels = "top_models"
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

struct UsageTopModel: Codable, Identifiable, Hashable {
    let model: String
    let billingProvider: String?
    let sessionCount: Int
    let totalTokens: Int64
    let cacheAndReasoningTokens: Int64
    let estimatedCostUSD: Double

    var id: String { model }

    enum CodingKeys: String, CodingKey {
        case model
        case billingProvider = "billing_provider"
        case sessionCount = "session_count"
        case totalTokens = "total_tokens"
        case cacheAndReasoningTokens = "cache_reasoning_tokens"
        case estimatedCostUSD = "estimated_cost_usd"
    }
}

enum UsageSummaryState: String, Codable {
    case available
    case unavailable
}

struct UsageProfileBreakdown: Hashable {
    let profiles: [UsageProfileSlice]

    var readableProfiles: [UsageProfileSlice] {
        profiles.filter { $0.state == .available }
    }

    var chartProfiles: [UsageProfileSlice] {
        readableProfiles.filter { $0.allTokenCategoriesTotal > 0 }
    }

    var hostWideAllTokenCategoriesTotal: Int64 {
        readableProfiles.reduce(into: 0) { partialResult, profile in
            partialResult += profile.allTokenCategoriesTotal
        }
    }

    var hostWideInputTokens: Int64 {
        readableProfiles.reduce(into: 0) { $0 += $1.inputTokens }
    }

    var hostWideOutputTokens: Int64 {
        readableProfiles.reduce(into: 0) { $0 += $1.outputTokens }
    }

    var hostWideCacheTokens: Int64 {
        readableProfiles.reduce(into: 0) { $0 += $1.cacheTokensTotal }
    }

    var hostWideReasoningTokens: Int64 {
        readableProfiles.reduce(into: 0) { $0 += $1.reasoningTokens }
    }

    var unavailableProfiles: [UsageProfileSlice] {
        profiles.filter { $0.state == .unavailable }
    }
}

struct UsageProfileSlice: Identifiable, Hashable {
    let profileName: String
    let hermesHomePath: String
    let state: UsageSummaryState
    let sessionCount: Int
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let cacheWriteTokens: Int64
    let reasoningTokens: Int64
    let databasePath: String?
    let message: String?
    let isActiveProfile: Bool

    var id: String { profileName }

    var cacheTokensTotal: Int64 {
        cacheReadTokens + cacheWriteTokens
    }

    var allTokenCategoriesTotal: Int64 {
        inputTokens + outputTokens + cacheTokensTotal + reasoningTokens
    }
}

extension UsageSummary {
    var totalTokens: Int64 {
        inputTokens + outputTokens
    }

    var cacheTokensTotal: Int64 {
        cacheReadTokens + cacheWriteTokens
    }

    var allTokenCategoriesTotal: Int64 {
        totalTokens + cacheTokensTotal + reasoningTokens
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
