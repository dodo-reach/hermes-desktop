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

enum CaelJSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: CaelJSONValue])
    case array([CaelJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CaelJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: CaelJSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct CaelProfilesListResponse: Codable {
    let profiles: [CaelProfileSummary]
    let activeProfile: String
}

struct CaelProfileSummary: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let path: String
    let active: Bool
    let exists: Bool
    let model: String?
    let provider: String?
    let description: String?
    let displayName: String?
    let skillCount: Int
    let sessionCount: Int
    let hasEnv: Bool
    let updatedAt: String?

    var resolvedDisplayName: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return name == "default" ? ConnectionProfile.defaultAgentDisplayName : name
    }
}

struct CaelProfileDetailResponse: Codable {
    let profile: CaelProfileDetail
}

struct CaelProfileMutationResponse: Codable {
    let ok: Bool?
    let profile: CaelProfileDetail?
    let error: String?
}

struct WorkspaceAgentStartResponse: Codable {
    let ok: Bool
    let message: String?
    let pid: Int?
    let error: String?

    var displayMessage: String {
        if ok {
            return message?.nilIfBlank ?? "Agent runtime accepted the start request."
        }
        return error?.nilIfBlank ?? "Agent runtime start failed."
    }
}

struct WorkspaceCrewStatusResponse: Codable {
    let crew: [WorkspaceCrewMember]
    let fetchedAt: Double?
}

struct WorkspaceCrewMember: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let humanLabel: String?
    let role: String
    let specialty: String?
    let mission: String?
    let skills: [String]?
    let capabilities: [String]?
    let profileFound: Bool
    let gatewayState: String
    let processAlive: Bool
    let model: String
    let provider: String
    let lastSessionTitle: String?
    let lastSessionAt: Double?
    let sessionCount: Int
    let messageCount: Int
    let toolCallCount: Int
    let totalTokens: Int
    let estimatedCostUsd: Double?
    let cronJobCount: Int
    let assignedTaskCount: Int
}

struct CaelProfileDetail: Codable {
    let name: String
    let path: String
    let active: Bool
    let config: [String: CaelJSONValue]
    let description: String
    let displayName: String?
    let envPath: String?
    let hasEnv: Bool
    let sessionsDir: String?
    let skillsDir: String?

    var resolvedDisplayName: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return name == "default" ? ConnectionProfile.defaultAgentDisplayName : name
    }
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
    let caelConfigured: Bool?
    let caelDefault: Bool?
    let caelModel: String?
    let caelModels: [String]?
    let monitorKind: String?
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

struct KnowledgeFabricHealthResponse: Decodable {
    let ok: Bool?
    let endpoint: String?
    let configured: Bool?
    let warning: String?
    let error: String?

    var statusLabel: String {
        if ok == true { return "Online" }
        if configured == false { return "Not configured" }
        return "Needs attention"
    }
}

struct KnowledgeFabricSearchResponse: Decodable {
    let ok: Bool?
    let endpoint: String?
    let memoryScope: String?
    let data: KnowledgeFabricPayload?
    let scopes: KnowledgeFabricScopedResults?
    let error: String?

    var scopedResults: [KnowledgeFabricScopedResult] {
        if let scopes {
            return [
                scopes.business?.withFallbackScope("business"),
                scopes.personal?.withFallbackScope("personal")
            ].compactMap { $0 }
        }
        return [KnowledgeFabricScopedResult(
            ok: ok,
            tool: nil,
            endpoint: endpoint,
            memoryScope: memoryScope,
            data: data,
            error: error,
            fallbackScope: memoryScope ?? "memory"
        )]
    }
}

struct KnowledgeFabricScopedResults: Decodable {
    let business: KnowledgeFabricScopedResult?
    let personal: KnowledgeFabricScopedResult?
}

struct KnowledgeFabricScopedResult: Decodable, Identifiable {
    let ok: Bool?
    let tool: String?
    let endpoint: String?
    let memoryScope: String?
    let data: KnowledgeFabricPayload?
    let error: String?
    private let fallbackScope: String?

    init(
        ok: Bool?,
        tool: String?,
        endpoint: String?,
        memoryScope: String?,
        data: KnowledgeFabricPayload?,
        error: String?,
        fallbackScope: String?
    ) {
        self.ok = ok
        self.tool = tool
        self.endpoint = endpoint
        self.memoryScope = memoryScope
        self.data = data
        self.error = error
        self.fallbackScope = fallbackScope
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case tool
        case endpoint
        case memoryScope
        case data
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        self.tool = try container.decodeIfPresent(String.self, forKey: .tool)
        self.endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        self.memoryScope = try container.decodeIfPresent(String.self, forKey: .memoryScope)
        self.data = try container.decodeIfPresent(KnowledgeFabricPayload.self, forKey: .data)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
        self.fallbackScope = nil
    }

    var id: String {
        "\(scopeKey)-\(data?.query ?? data?.document?.canonicalDocID ?? data?.document?.title ?? error ?? "result")"
    }

    var scopeKey: String {
        (memoryScope ?? fallbackScope ?? "memory").lowercased()
    }

    var displayScope: String {
        switch scopeKey {
        case "business": return "Business / Dev Server"
        case "personal": return "Personal / BigMac"
        default: return scopeKey.capitalized
        }
    }

    var summary: String {
        if let error, !error.isEmpty { return error }
        if let answer = data?.answer, !answer.isEmpty { return answer }
        if let document = data?.document {
            return document.summary?.nilIfBlank ?? document.title?.nilIfBlank ?? "Document record returned without a summary."
        }
        return data?.text?.nilIfBlank ?? "No structured Knowledge Fabric payload returned."
    }

    func withFallbackScope(_ scope: String) -> KnowledgeFabricScopedResult {
        KnowledgeFabricScopedResult(
            ok: ok,
            tool: tool,
            endpoint: endpoint,
            memoryScope: memoryScope,
            data: data,
            error: error,
            fallbackScope: scope
        )
    }
}

struct KnowledgeFabricPayload: Decodable {
    let status: String?
    let answer: String?
    let mode: String?
    let query: String?
    let workspace: String?
    let evidence: [KnowledgeFabricEvidence]
    let document: KnowledgeFabricDocument?
    let text: String?

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let text = try? container.decode(String.self) {
            self.status = nil
            self.answer = nil
            self.mode = nil
            self.query = nil
            self.workspace = nil
            self.evidence = []
            self.document = nil
            self.text = text
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.answer = try container.decodeIfPresent(String.self, forKey: .answer)
        self.mode = try container.decodeIfPresent(String.self, forKey: .mode)
        self.query = try container.decodeIfPresent(String.self, forKey: .query)
        self.workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        self.evidence = try container.decodeIfPresent([KnowledgeFabricEvidence].self, forKey: .evidence) ?? []
        self.document = try container.decodeIfPresent(KnowledgeFabricDocument.self, forKey: .document)
        self.text = nil
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case answer
        case mode
        case query
        case workspace
        case evidence
        case document
    }
}

struct KnowledgeFabricEvidence: Decodable, Identifiable {
    let docID: String?
    let canonicalDocID: String?
    let title: String?
    let workspace: String?
    let sourceTag: String?
    let capturedAt: String?
    let snippet: String?

    var id: String {
        docID ?? canonicalDocID ?? title ?? snippet ?? "evidence"
    }

    private enum CodingKeys: String, CodingKey {
        case docID = "doc_id"
        case canonicalDocID = "canonical_doc_id"
        case title
        case workspace
        case sourceTag = "source_tag"
        case capturedAt = "captured_at"
        case snippet
    }
}

struct KnowledgeFabricDocument: Decodable {
    let canonicalDocID: String?
    let title: String?
    let summary: String?
    let sourceSystem: String?

    private enum CodingKeys: String, CodingKey {
        case canonicalDocID = "canonical_doc_id"
        case title
        case summary
        case sourceSystem = "source_system"
    }
}


struct WorkspaceMemoryListResponse: Decodable {
    let files: [WorkspaceMemoryFile]
}

struct WorkspaceMemoryFile: Decodable, Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let size: Int
    let modified: String
}

struct WorkspaceMemoryReadResponse: Decodable {
    let path: String?
    let content: String?
}

struct WorkspaceMemorySearchResponse: Decodable {
    let results: [WorkspaceMemorySearchMatch]
}

struct WorkspaceMemorySearchMatch: Decodable, Identifiable {
    var id: String { "\(path):\(line):\(text)" }
    let path: String
    let line: Int
    let text: String
}

struct WorkspaceKnowledgeListResponse: Decodable {
    let pages: [WorkspaceKnowledgePage]
    let exists: Bool?
}

struct WorkspaceKnowledgePage: Decodable, Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let title: String
    let type: String?
    let domain: String?
    let status: String?
    let tags: [String]
    let summary: String?
    let created: String?
    let updated: String?
    let size: Int
    let modified: String
    let wikilinks: [String]
}

struct WorkspaceKnowledgeReadResponse: Decodable {
    let page: WorkspaceKnowledgePage?
    let content: String?
    let backlinks: [String]?
}

struct WorkspaceKnowledgeSearchResponse: Decodable {
    let results: [WorkspaceKnowledgeSearchMatch]
}

struct WorkspaceKnowledgeSearchMatch: Decodable, Identifiable {
    var id: String { "\(path):\(line):\(text)" }
    let path: String
    let title: String
    let line: Int
    let text: String
}

struct WorkspaceSecondBrainSourcesResponse: Decodable {
    let ok: Bool
    let sources: [WorkspaceSecondBrainSource]?
    let error: String?
}

struct WorkspaceSecondBrainSource: Decodable, Identifiable {
    let id: String
    let label: String
    let category: String
    let description: String
    let refPrefix: String
    let writable: Bool
    let exists: Bool
    let status: String
}

struct WorkspaceSecondBrainListResponse: Decodable {
    let ok: Bool
    let source: WorkspaceSecondBrainSource?
    let root: String?
    let entries: [WorkspaceSecondBrainEntry]?
    let error: String?
}

struct WorkspaceSecondBrainEntry: Decodable, Identifiable {
    var id: String { ref }
    let name: String
    let path: String
    let ref: String
    let type: String
    let size: Int?
    let modifiedAt: String?
}

struct WorkspaceSecondBrainReadResponse: Decodable {
    let ok: Bool
    let source: WorkspaceSecondBrainSource?
    let path: String?
    let ref: String?
    let content: String?
    let hash: String?
    let error: String?
}

struct WorkspaceSecondBrainWriteResponse: Decodable {
    let ok: Bool?
    let hash: String?
    let error: String?
}

struct WorkspaceSecondBrainDispatchResponse: Decodable {
    let ok: Bool
    let status: String?
    let operation: String?
    let idempotencyKey: String?
    let n8n: WorkspaceSecondBrainDispatchTarget?
    let error: String?
}

struct WorkspaceSecondBrainDispatchTarget: Decodable {
    let configured: Bool
    let endpointLabel: String
}


struct WorkspaceTerminalSessionsResponse: Decodable {
    let ok: Bool?
    let sessions: [WorkspaceTerminalSessionSummary]
    let error: String?
}

struct WorkspaceTerminalSessionSummary: Decodable, Identifiable, Hashable {
    let id: String
    let createdAt: Double
    let cwd: String?
    let command: [String]
    let cols: Int?
    let rows: Int?
    let idleTtlMs: Int?
}

struct WorkspaceSessionCreateResponse: Decodable {
    let ok: Bool?
    let sessionKey: String?
    let friendlyId: String?
    let error: String?
}

struct WorkspaceSessionSendResponse: Decodable {
    let ok: Bool
    let sessionKey: String?
    let queued: Bool?
    let serverSide: Bool?
    let error: String?
}

struct WorkspaceSessionHistoryResponse: Decodable {
    let ok: Bool?
    let messages: [SessionMessage]
    let sessionKey: String?
    let source: String?
    let error: String?
}

struct WorkspaceSessionActiveRunResponse: Decodable {
    let ok: Bool
    let run: WorkspaceSessionActiveRun?
    let error: String?
}

struct WorkspaceSessionActiveRun: Decodable, Equatable {
    let runId: String
    let sessionKey: String
    let friendlyId: String?
    let status: String
    let createdAt: Double?
    let updatedAt: Double?
    let lastEventAt: Double?
    let assistantText: String?
    let thinkingText: String?
    let toolCalls: [WorkspaceSessionRunToolCall]
    let lifecycleEvents: [WorkspaceSessionRunLifecycleEvent]
    let errorMessage: String?
}

struct WorkspaceSessionRunToolCall: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let phase: String
    let preview: String?
    let result: String?
}

struct WorkspaceSessionRunLifecycleEvent: Decodable, Equatable, Identifiable {
    let text: String
    let emoji: String?
    let timestamp: Double?
    let isError: Bool

    var id: String { "\(timestamp ?? 0)-\(text)" }
}


struct KnowledgeFabricSessionStateResponse: Decodable {
    let ok: Bool?
    let tool: String?
    let endpoint: String?
    let data: String?
    let error: String?
}

struct WorkspaceMCPListResponse: Decodable {
    let servers: [WorkspaceMCPServer]
    let total: Int
    let categories: [String]?
    let ok: Bool?
    let error: String?
}

struct WorkspaceMCPServer: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let enabled: Bool
    let transportType: String
    let url: String?
    let command: String?
    let args: [String]
    let authType: String
    let toolMode: String
    let includeTools: [String]
    let excludeTools: [String]
    let discoveredToolsCount: Int
    let status: String
    let lastError: String?
    let source: String
}

struct WorkspaceMCPTestResponse: Decodable {
    let ok: Bool
    let status: String
    let latencyMs: Double?
    let discoveredTools: [WorkspaceMCPTool]
    let error: String?
}

struct WorkspaceMCPMutationResponse: Decodable {
    let ok: Bool
    let server: WorkspaceMCPServer?
    let error: String?
}

struct WorkspaceMCPDiscoverResponse: Decodable {
    let ok: Bool
    let tools: [WorkspaceMCPTool]
    let error: String?
}

struct WorkspaceMCPHubSourcesResponse: Decodable {
    let ok: Bool?
    let sources: [WorkspaceMCPHubSource]
    let source: String?
    let error: String?
}

struct WorkspaceMCPHubSource: Decodable, Identifiable {
    let id: String
    let name: String
    let url: String
    let trust: String?
    let format: String?
    let enabled: Bool?
    let builtin: Bool?
}

struct WorkspaceMCPPresetsResponse: Decodable {
    let ok: Bool?
    let presets: [WorkspaceMCPPreset]
    let source: String?
    let error: String?
}

struct WorkspaceMCPPreset: Decodable, Identifiable {
    let id: String
    let name: String?
    let description: String?
    let category: String?
    let homepage: String?
    let tags: [String]?
    let template: WorkspaceMCPPresetTemplate?
}

struct WorkspaceMCPHubSearchResponse: Decodable {
    let ok: Bool?
    let results: [WorkspaceMCPHubEntry]
    let source: String?
    let total: Int?
    let warnings: [String]?
    let error: String?
}

struct WorkspaceMCPHubEntry: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let source: String?
    let homepage: String?
    let tags: [String]?
    let trust: String?
    let template: WorkspaceMCPPresetTemplate?
    let installCommand: String?
    let installed: Bool?
}

struct WorkspaceMCPPresetTemplate: Decodable {
    let name: String?
    let transportType: String?
    let command: String?
    let args: [String]?
    let url: String?
    let authType: String?
    let toolMode: String?
}

struct WorkspaceMCPTool: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let description: String?
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
