import CryptoKit
import Foundation

struct CaelCommandCenterCachedSnapshot: Codable {
    let workspaceScopeFingerprint: String
    let workspaceBaseURL: String
    let cachedAt: Date
    let summaryEnvelope: CaelCommandCenterSummaryEnvelope?
    let sections: CaelCommandCenterSectionsSnapshot?
}

final class CaelCommandCenterSnapshotStore {
    private let fileManager: FileManager
    private let cacheDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(paths: AppPaths) {
        self.fileManager = paths.fileManager
        self.cacheDirectoryURL = paths.applicationSupportURL.appendingPathComponent(
            "CommandCenterSnapshots",
            isDirectory: true
        )
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    func load(for connection: ConnectionProfile) -> CaelCommandCenterCachedSnapshot? {
        let url = snapshotURL(for: connection)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = try? decoder.decode(CaelCommandCenterCachedSnapshot.self, from: data) else { return nil }
        guard snapshot.workspaceScopeFingerprint == connection.workspaceScopeFingerprint else { return nil }
        guard snapshot.workspaceBaseURL == connection.resolvedCaelWorkspaceBaseURL else { return nil }
        return snapshot
    }

    func save(
        summaryEnvelope: CaelCommandCenterSummaryEnvelope?,
        sections: CaelCommandCenterSectionsSnapshot?,
        for connection: ConnectionProfile
    ) throws {
        guard summaryEnvelope?.data != nil || sections?.hasAnyPayload == true else { return }
        try ensureCacheDirectory()

        let snapshot = CaelCommandCenterCachedSnapshot(
            workspaceScopeFingerprint: connection.workspaceScopeFingerprint,
            workspaceBaseURL: connection.resolvedCaelWorkspaceBaseURL,
            cachedAt: Date(),
            summaryEnvelope: summaryEnvelope,
            sections: sections?.sanitizedForLocalCache
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL(for: connection), options: [.atomic])
    }

    private func ensureCacheDirectory() throws {
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: NSNumber(value: Int16(0o700))
        ]
        try fileManager.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true,
            attributes: attributes
        )
        try? fileManager.setAttributes(attributes, ofItemAtPath: cacheDirectoryURL.path)
    }

    private func snapshotURL(for connection: ConnectionProfile) -> URL {
        let digest = SHA256.hash(data: Data(connection.commandCenterClientFingerprint.utf8))
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectoryURL.appendingPathComponent("\(hexDigest).json")
    }
}

extension CaelCommandCenterSectionsSnapshot {
    var hasAnyPayload: Bool {
        actionGates?.data != nil ||
            agentRuns?.data != nil ||
            automations?.data != nil ||
            brain?.data != nil ||
            homebaseRecords?.data != nil ||
            memoryArtifacts?.data != nil ||
            usageLimits?.data != nil ||
            vaultRefs?.data != nil
    }

    var sanitizedForLocalCache: CaelCommandCenterSectionsSnapshot {
        CaelCommandCenterSectionsSnapshot(
            actionGates: actionGates,
            agentRuns: agentRuns,
            automations: automations,
            brain: brain,
            homebaseRecords: homebaseRecords,
            memoryArtifacts: memoryArtifacts,
            usageLimits: usageLimits,
            vaultRefs: vaultRefs?.strippingSecretValues
        )
    }
}

private extension CaelCommandCenterSectionEnvelope where Payload == CaelCommandCenterVaultRefsSection {
    var strippingSecretValues: CaelCommandCenterSectionEnvelope<CaelCommandCenterVaultRefsSection> {
        guard let data else { return self }
        let sanitizedRefs = data.refs.map { ref in
            CaelCommandCenterVaultRef(
                id: ref.id,
                displayName: ref.displayName,
                scope: ref.scope,
                exists: ref.exists,
                lastVerifiedAt: ref.lastVerifiedAt,
                rotationDueAt: ref.rotationDueAt,
                linkedSystems: ref.linkedSystems,
                vaultHref: ref.vaultHref,
                secretValue: nil
            )
        }
        let strippedSecretCount = data.refs.filter { $0.secretValue != nil }.count
        let sanitizedWarnings: [String]
        if strippedSecretCount > 0 {
            sanitizedWarnings = warnings + ["Secret values were stripped before local cache storage."]
        } else {
            sanitizedWarnings = warnings
        }
        return CaelCommandCenterSectionEnvelope(
            ok: ok,
            generatedAt: generatedAt,
            source: source,
            scope: scope,
            data: CaelCommandCenterVaultRefsSection(
                warningCount: data.warningCount,
                refs: sanitizedRefs,
                policy: data.policy
            ),
            warnings: sanitizedWarnings,
            errors: errors
        )
    }
}
