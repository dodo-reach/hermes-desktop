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


struct CaelCommandCenterSummaryEnvelope: Decodable {
    let ok: Bool
    let generatedAt: String
    let source: String
    let scope: String
    let data: CaelCommandCenterSummary?
    let warnings: [String]
    let errors: [String]
    let links: [CaelCommandCenterEnvelopeLink]?
}

struct CaelCommandCenterEnvelopeLink: Decodable, Identifiable {
    var id: String { href }
    let label: String
    let href: String
    let kind: String
}

struct CaelCommandCenterSummary: Decodable {
    let version: String
    let generatedAt: String
    let contract: CaelCommandCenterContract?
    let posture: CaelCommandCenterPosture?
    let systems: [CaelCommandCenterSystem]
    let integrations: [CaelCommandCenterIntegration]
    let usage: CaelCommandCenterUsage?
    let automations: CaelCommandCenterAutomations?
    let brain: CaelCommandCenterBrain?
    let actionGates: [CaelCommandCenterActionGate]
    let agentRuns: [CaelCommandCenterAgentRun]
    let nowNext: [CaelCommandCenterNowNextItem]
    let homebaseRecords: CaelCommandCenterHomebaseRecords
}

struct CaelCommandCenterPosture: Decodable {
    let host: String
    let bind: String
    let remoteAccess: String
    let auth: String
    let publicInternet: String
}

struct CaelCommandCenterSystem: Decodable, Identifiable {
    let id: String
    let label: String
    let ok: Bool
    let lane: String
    let owner: String
    let detail: String
    let latencyMs: Double?
}

struct CaelCommandCenterIntegration: Decodable, Identifiable {
    let id: String
    let label: String
    let status: String
    let detail: String
    let safeMode: String
}

struct CaelCommandCenterUsage: Decodable {
    let enabledProviders: [String]
    let providers: [CaelCommandCenterUsageProvider]
}

struct CaelCommandCenterUsageProvider: Decodable, Identifiable {
    let id: String
    let label: String
    let status: String
    let confidence: String
    let monitorKind: String?
    let caelDefault: Bool
    let caelModel: String?
    let primary: CaelCommandCenterUsageWindow?
}

struct CaelCommandCenterUsageWindow: Decodable {
    let label: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: String?
}

struct CaelCommandCenterAutomations: Decodable {
    let boundary: String
    let instances: [CaelCommandCenterAutomation]
}

struct CaelCommandCenterAutomation: Decodable, Identifiable {
    let id: String
    let label: String
    let ok: Bool
    let scope: String
    let boundary: String
    let failures: Int
}

struct CaelCommandCenterBrain: Decodable {
    let sources: [CaelCommandCenterBrainSource]
}

struct CaelCommandCenterBrainSource: Decodable, Identifiable {
    let id: String
    let label: String
    let category: String
    let status: String
    let writable: Bool
}

struct CaelCommandCenterActionGate: Decodable, Identifiable {
    let id: String
    let label: String
    let source: String
    let status: String
    let riskLevel: String
    let approvalRequired: Bool
    let dryRunSupported: Bool
    let detail: String
}

struct CaelCommandCenterAgentRun: Decodable, Identifiable {
    let id: String
    let title: String
    let status: String
    let updatedAt: String
    let source: String
    let path: String?
}

struct CaelCommandCenterNowNextItem: Decodable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let tone: String
    let href: String?
}

struct CaelCommandCenterHomebaseRecords: Decodable {
    let status: String
    let detail: String
    let records: [CaelCommandCenterHomebaseRecord]
}

struct CaelCommandCenterHomebaseRecord: Decodable, Identifiable {
    let id: String
    let label: String
    let kind: String
    let updatedAt: String?
}
