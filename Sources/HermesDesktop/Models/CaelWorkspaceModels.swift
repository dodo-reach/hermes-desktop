import Foundation

struct CaelWorkspaceStatus: Codable {
    let ok: Bool
    let generatedAt: String
    let host: String
    let posture: CaelWorkspacePosture
    let services: [CaelWorkspaceServiceCheck]
    let links: [CaelWorkspaceLink]
    let contextSurfaces: [CaelWorkspaceContextSurface]?
    let contract: CaelCommandCenterContract
}

struct CaelWorkspacePosture: Codable {
    let bind: String
    let remoteAccess: String
    let auth: String
    let publicInternet: String
}

struct CaelWorkspaceServiceCheck: Codable, Identifiable {
    let id: String
    let label: String
    let kind: String
    let target: String
    let ok: Bool
    let detail: String
    let latencyMs: Double?
    let lane: String?
    let owner: String?
    let description: String?
}

struct CaelWorkspaceLink: Codable, Identifiable {
    var id: String { href }
    let label: String
    let href: String
    let description: String
}

struct CaelWorkspaceContextSurface: Codable, Identifiable {
    var id: String { surface }
    let surface: String
    let owner: String
    let context: String
    let access: String
    let boundary: String
}

struct CaelCommandCenterContract: Codable {
    let id: String
    let version: String
    let generatedAt: String
    let principle: String
    let primarySurface: String
    let mirrorSurface: String
    let privateAccess: String
    let surfaces: [CaelCommandCenterSurface]
}

struct CaelCommandCenterSurface: Codable, Identifiable {
    let id: String
    let label: String
    let owner: String
    let desktop: String
    let web: String
    let source: String
    let status: String
    let description: String
}

struct CaelIntegrationStatus: Codable {
    let ok: Bool
    let generatedAt: String
    let integrations: [CaelIntegrationCheck]
    let policy: [String: String]
}

struct CaelIntegrationCheck: Codable, Identifiable {
    let id: String
    let label: String
    let status: String
    let detail: String
    let safeMode: String
}

struct CaelProviderUsageLimits: Codable {
    let ok: Bool
    let generatedAt: String
    let enabledProviders: [String]
    let providers: [CaelProviderUsageCard]
}

struct CaelProviderUsageCard: Codable, Identifiable {
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

struct CaelUsageWindow: Codable, Identifiable {
    let id: String
    let label: String
    let used: Double
    let limit: Double
    let unit: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: String?
}

struct CaelUsageBadge: Codable, Identifiable {
    var id: String { "\(label)-\(value)" }
    let label: String
    let value: String
    let color: String?
}

struct CaelTokenUsage: Codable {
    let sessionCostUSD: Double?
    let sessionTokens: Double?
    let last30DaysCostUSD: Double?
    let last30DaysTokens: Double?
}

struct CaelDailyUsage: Codable, Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let totalTokens: Double?
    let costUSD: Double?
}


struct CaelCommandCenterSummaryEnvelope: Codable {
    let ok: Bool
    let generatedAt: String
    let source: String
    let scope: String
    let data: CaelCommandCenterSummary?
    let warnings: [String]
    let errors: [String]
    let links: [CaelCommandCenterEnvelopeLink]?
}

struct CaelCommandCenterEnvelopeLink: Codable, Identifiable {
    var id: String { href }
    let label: String
    let href: String
    let kind: String
}

struct CaelCommandCenterSummary: Codable {
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

struct CaelCommandCenterPosture: Codable {
    let host: String
    let bind: String
    let remoteAccess: String
    let auth: String
    let publicInternet: String
}

struct CaelCommandCenterSystem: Codable, Identifiable {
    let id: String
    let label: String
    let ok: Bool
    let lane: String
    let owner: String
    let detail: String
    let latencyMs: Double?
}

struct CaelCommandCenterIntegration: Codable, Identifiable {
    let id: String
    let label: String
    let status: String
    let detail: String
    let safeMode: String
}

struct CaelCommandCenterUsage: Codable {
    let enabledProviders: [String]
    let providers: [CaelCommandCenterUsageProvider]
}

struct CaelCommandCenterUsageProvider: Codable, Identifiable {
    let id: String
    let label: String
    let status: String
    let confidence: String
    let monitorKind: String?
    let caelDefault: Bool
    let caelModel: String?
    let primary: CaelCommandCenterUsageWindow?
}

struct CaelCommandCenterUsageWindow: Codable {
    let label: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: String?
}

struct CaelCommandCenterAutomations: Codable {
    let boundary: String
    let instances: [CaelCommandCenterAutomation]
}

struct CaelCommandCenterAutomation: Codable, Identifiable {
    let id: String
    let label: String
    let ok: Bool
    let scope: String
    let boundary: String
    let failures: Int
}

struct CaelCommandCenterBrain: Codable {
    let sources: [CaelCommandCenterBrainSource]
}

struct CaelCommandCenterBrainSource: Codable, Identifiable {
    let id: String
    let label: String
    let category: String
    let status: String
    let writable: Bool
}

struct CaelCommandCenterActionGate: Codable, Identifiable {
    let id: String
    let label: String
    let source: String
    let status: String
    let riskLevel: String
    let approvalRequired: Bool
    let dryRunSupported: Bool
    let detail: String
}

struct CaelCommandCenterAgentRun: Codable, Identifiable {
    let id: String
    let title: String
    let status: String
    let updatedAt: String
    let source: String
    let path: String?
}

struct CaelCommandCenterNowNextItem: Codable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let tone: String
    let href: String?
}

struct CaelCommandCenterHomebaseRecords: Codable {
    let status: String
    let detail: String
    let records: [CaelCommandCenterHomebaseRecord]
}

struct CaelCommandCenterHomebaseRecord: Codable, Identifiable {
    let id: String
    let label: String
    let kind: String
    let updatedAt: String?
}

struct CaelCommandCenterSectionEnvelope<Payload: Codable>: Codable {
    let ok: Bool
    let generatedAt: String
    let source: String
    let scope: String
    let data: Payload?
    let warnings: [String]
    let errors: [String]
}

struct CaelCommandCenterSectionsSnapshot: Codable {
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

struct CaelCommandCenterActionGatesSection: Codable {
    let total: Int
    let approvalRequired: Int
    let dryRun: Int
    let actions: [CaelCommandCenterActionGateDetail]
}

struct CaelCommandCenterActionGateDetail: Codable, Identifiable {
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

struct CaelCommandCenterAgentRunsSection: Codable {
    let runs: [CaelCommandCenterAgentRunDetail]
    let receipts: [CaelCommandCenterPromotionReceipt]
}

struct CaelCommandCenterAgentRunDetail: Codable, Identifiable {
    let id: String
    let title: String
    let status: String
    let updatedAt: String
    let source: String
    let path: String?
    let receiptCount: Int?
    let verification: String
}

struct CaelCommandCenterPromotionReceipt: Codable, Identifiable {
    var id: String { path }
    let title: String
    let path: String
    let updatedAt: String
    let instance: String
}

struct CaelCommandCenterAutomationSection: Codable {
    let boundary: String
    let instances: [CaelCommandCenterAutomationInstance]
    let promotionReceipts: [CaelCommandCenterPromotionReceipt]
    let guardrails: [String]
}

struct CaelCommandCenterAutomationInstance: Codable, Identifiable {
    let id: String
    let label: String
    let scope: String
    let access: String
    let boundary: String
    let health: CaelCommandCenterAutomationHealth
    let failures: [CaelCommandCenterAutomationFailure]
}

struct CaelCommandCenterAutomationHealth: Codable {
    let ok: Bool
    let detail: String
    let checkedAt: String
    let latencyMs: Double?
}

struct CaelCommandCenterAutomationFailure: Codable, Identifiable {
    var id: String { "\(instance)-\(workflowName)-\(lastSeen)" }
    let workflowName: String
    let status: String
    let lastSeen: String
    let count: Int
    let instance: String
}

struct CaelN8nGovernanceStatus: Codable {
    let ok: Bool
    let generatedAt: String
    let boundary: String
    let instances: [CaelCommandCenterAutomationInstance]
    let promotionReceipts: [CaelCommandCenterPromotionReceipt]
    let safeWorkflowCommands: [CaelN8nSafeWorkflowCommand]
    let guardrails: [String]
}

struct CaelN8nSafeWorkflowCommand: Codable, Identifiable {
    let id: String
    let label: String
    let description: String
    let owningInstance: String
    let riskLevel: String
    let approvalRequired: Bool
    let dryRunSupported: Bool
    let sideEffects: String
    let rollback: String
    let status: String
}

struct CaelCommandCenterBrainSection: Codable {
    let sources: [CaelCommandCenterBrainSource]
    let memoryArtifacts: CaelCommandCenterBrainMemoryArtifacts
    let policy: [String]
}

struct CaelCommandCenterBrainMemoryArtifacts: Codable {
    let count: Int
    let rootConfigured: Bool
    let root: String?
}

struct CaelCommandCenterMemoryArtifactsSection: Codable {
    let root: String
    let count: Int
    let artifacts: [CaelCommandCenterMemoryArtifact]
}

struct CaelCommandCenterMemoryArtifact: Codable, Identifiable {
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

struct CaelCommandCenterVaultRefsSection: Codable {
    let warningCount: Int
    let refs: [CaelCommandCenterVaultRef]
    let policy: [String]
}

struct CaelCommandCenterVaultRef: Codable, Identifiable {
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

