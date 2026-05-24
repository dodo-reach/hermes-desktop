import Foundation

struct CaelWorkspaceStatus: Decodable {
    let ok: Bool
    let generatedAt: String
    let host: String
    let posture: CaelWorkspacePosture
    let services: [CaelWorkspaceServiceCheck]
    let links: [CaelWorkspaceLink]
    let contract: CaelCommandCenterContract
}

struct CaelWorkspacePosture: Decodable {
    let bind: String
    let remoteAccess: String
    let auth: String
    let publicInternet: String
}

struct CaelWorkspaceServiceCheck: Decodable, Identifiable {
    let id: String
    let label: String
    let kind: String
    let target: String
    let ok: Bool
    let detail: String
    let latencyMs: Double?
}

struct CaelWorkspaceLink: Decodable, Identifiable {
    var id: String { href }
    let label: String
    let href: String
    let description: String
}

struct CaelCommandCenterContract: Decodable {
    let id: String
    let version: String
    let generatedAt: String
    let principle: String
    let primarySurface: String
    let mirrorSurface: String
    let privateAccess: String
    let surfaces: [CaelCommandCenterSurface]
}

struct CaelCommandCenterSurface: Decodable, Identifiable {
    let id: String
    let label: String
    let owner: String
    let desktop: String
    let web: String
    let source: String
    let status: String
    let description: String
}

struct CaelIntegrationStatus: Decodable {
    let ok: Bool
    let generatedAt: String
    let integrations: [CaelIntegrationCheck]
    let policy: [String: String]
}

struct CaelIntegrationCheck: Decodable, Identifiable {
    let id: String
    let label: String
    let status: String
    let detail: String
    let safeMode: String
}

struct CaelProviderUsageLimits: Decodable {
    let ok: Bool
    let generatedAt: String
    let enabledProviders: [String]
    let providers: [CaelProviderUsageCard]
}

struct CaelProviderUsageCard: Decodable, Identifiable {
    let id: String
    let label: String
    let status: String
    let plan: String?
    let message: String?
    let updatedAt: String
    let source: String
    let confidence: String
    let primary: CaelUsageWindow?
    let secondary: CaelUsageWindow?
    let tertiary: CaelUsageWindow?
    let usageRows: [CaelUsageWindow]
    let badges: [CaelUsageBadge]
    let creditsRemaining: Double?
    let codeReviewRemainingPercent: Double?
    let tokenUsage: CaelTokenUsage
    let dailyUsage: [CaelDailyUsage]
}

struct CaelUsageWindow: Decodable, Identifiable {
    let id: String
    let label: String
    let used: Double
    let limit: Double
    let unit: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: String?
}

struct CaelUsageBadge: Decodable, Identifiable {
    var id: String { "\(label)-\(value)" }
    let label: String
    let value: String
    let color: String?
}

struct CaelTokenUsage: Decodable {
    let sessionCostUSD: Double?
    let sessionTokens: Double?
    let last30DaysCostUSD: Double?
    let last30DaysTokens: Double?
}

struct CaelDailyUsage: Decodable, Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let totalTokens: Double?
    let costUSD: Double?
}
