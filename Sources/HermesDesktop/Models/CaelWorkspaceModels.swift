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

struct CaelCommandCenterSectionEnvelope<Payload: Decodable>: Decodable {
    let ok: Bool
    let generatedAt: String
    let source: String
    let scope: String
    let data: Payload?
    let warnings: [String]
    let errors: [String]
}

struct CaelCommandCenterSectionsSnapshot {
    let actionGates: CaelCommandCenterSectionEnvelope<CaelCommandCenterActionGatesSection>?
    let agentRuns: CaelCommandCenterSectionEnvelope<CaelCommandCenterAgentRunsSection>?
    let automations: CaelCommandCenterSectionEnvelope<CaelCommandCenterAutomationSection>?
    let brain: CaelCommandCenterSectionEnvelope<CaelCommandCenterBrainSection>?
    let homebaseRecords: CaelCommandCenterSectionEnvelope<CaelCommandCenterHomebaseRecords>?
    let memoryArtifacts: CaelCommandCenterSectionEnvelope<CaelCommandCenterMemoryArtifactsSection>?
    let usageLimits: CaelCommandCenterSectionEnvelope<CaelCommandCenterUsage>?
    let vaultRefs: CaelCommandCenterSectionEnvelope<CaelCommandCenterVaultRefsSection>?

    var warningCount: Int {
        [
            actionGates?.warnings.count,
            agentRuns?.warnings.count,
            automations?.warnings.count,
            brain?.warnings.count,
            homebaseRecords?.warnings.count,
            memoryArtifacts?.warnings.count,
            usageLimits?.warnings.count,
            vaultRefs?.warnings.count
        ]
        .compactMap { $0 }
        .reduce(0, +)
    }
}

struct CaelCommandCenterActionGatesSection: Decodable {
    let total: Int
    let approvalRequired: Int
    let dryRun: Int
    let actions: [CaelCommandCenterActionGateDetail]
}

struct CaelCommandCenterActionGateDetail: Decodable, Identifiable {
    let id: String
    let label: String
    let source: String
    let status: String
    let riskLevel: String
    let approvalRequired: Bool
    let dryRunSupported: Bool
    let detail: String
    let ownerSystem: String
    let sideEffects: String
    let rollback: String
    let href: String?
}

struct CaelCommandCenterAgentRunsSection: Decodable {
    let runs: [CaelCommandCenterAgentRunDetail]
    let receipts: [CaelCommandCenterPromotionReceipt]
}

struct CaelCommandCenterAgentRunDetail: Decodable, Identifiable {
    let id: String
    let title: String
    let status: String
    let updatedAt: String
    let source: String
    let path: String?
    let receiptCount: Int?
    let verification: String
}

struct CaelCommandCenterPromotionReceipt: Decodable, Identifiable {
    var id: String { path }
    let title: String
    let path: String
    let updatedAt: String
    let instance: String
}

struct CaelCommandCenterAutomationSection: Decodable {
    let boundary: String
    let instances: [CaelCommandCenterAutomationInstance]
    let promotionReceipts: [CaelCommandCenterPromotionReceipt]
    let guardrails: [String]
}

struct CaelCommandCenterAutomationInstance: Decodable, Identifiable {
    let id: String
    let label: String
    let scope: String
    let access: String
    let boundary: String
    let health: CaelCommandCenterAutomationHealth
    let failures: [CaelCommandCenterAutomationFailure]
}

struct CaelCommandCenterAutomationHealth: Decodable {
    let ok: Bool
    let detail: String
    let checkedAt: String
    let latencyMs: Double?
}

struct CaelCommandCenterAutomationFailure: Decodable, Identifiable {
    var id: String { "\(instance)-\(workflowName)-\(lastSeen)" }
    let workflowName: String
    let status: String
    let lastSeen: String
    let count: Int
    let instance: String
}

struct CaelCommandCenterBrainSection: Decodable {
    let sources: [CaelCommandCenterBrainSource]
    let memoryArtifacts: CaelCommandCenterBrainMemoryArtifacts
    let policy: [String]
}

struct CaelCommandCenterBrainMemoryArtifacts: Decodable {
    let count: Int
    let rootConfigured: Bool
    let root: String?
}

struct CaelCommandCenterMemoryArtifactsSection: Decodable {
    let root: String
    let count: Int
    let artifacts: [CaelCommandCenterMemoryArtifact]
}

struct CaelCommandCenterMemoryArtifact: Decodable, Identifiable {
    let id: String
    let title: String
    let path: String
    let scope: String
    let tenant: String?
    let updatedAt: String?
    let sensitivity: String
    let tags: [String]
    let excerpt: String
}

struct CaelCommandCenterVaultRefsSection: Decodable {
    let warningCount: Int
    let refs: [CaelCommandCenterVaultRef]
    let policy: [String]
}

struct CaelCommandCenterVaultRef: Decodable, Identifiable {
    let id: String
    let displayName: String
    let scope: String
    let exists: Bool
    let lastVerifiedAt: String?
    let rotationDueAt: String?
    let linkedSystems: [String]
    let vaultHref: String?
    let secretValue: String?
}

