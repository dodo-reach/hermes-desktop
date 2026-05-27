import Foundation
import Testing

@testable import HermesDesktop

struct CaelCommandCenterSnapshotStoreTests {
    @Test
    func cacheIsScopedByWorkspaceURLAndStripsVaultSecretValues() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            "HermesDesktopCacheTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: rootURL) }

        let paths = AppPaths(
            fileManager: fileManager,
            applicationSupportURL: rootURL.appendingPathComponent("Support", isDirectory: true),
            controlSocketDirectoryURL: rootURL.appendingPathComponent("Sockets", isDirectory: true)
        )
        let store = CaelCommandCenterSnapshotStore(paths: paths)
        let profile = ConnectionProfile(
            label: "BigMac",
            sshAlias: "bigmac-home"
        ).updated()
        let alternateURLProfile = ConnectionProfile(
            label: "BigMac",
            sshAlias: "bigmac-home",
            caelWorkspaceBaseURL: "http://127.0.0.1:3078"
        ).updated()

        let sections = CaelCommandCenterSectionsSnapshot(
            actionGates: nil,
            agentRuns: nil,
            automations: nil,
            brain: nil,
            homebaseRecords: nil,
            memoryArtifacts: nil,
            usageLimits: nil,
            vaultRefs: CaelCommandCenterSectionEnvelope(
                ok: true,
                generatedAt: "2026-05-24T00:00:00.000Z",
                source: "test",
                scope: "personal",
                data: CaelCommandCenterVaultRefsSection(
                    warningCount: 0,
                    refs: [
                        CaelCommandCenterVaultRef(
                            id: "claude-token",
                            displayName: "Claude token",
                            scope: "personal",
                            exists: true,
                            lastVerifiedAt: nil,
                            rotationDueAt: nil,
                            linkedSystems: ["cael"],
                            vaultHref: "vaultwarden://item/claude-token",
                            secretValue: "do-not-store"
                        )
                    ],
                    policy: ["refs only"]
                ),
                warnings: [],
                errors: []
            )
        )

        try store.save(summaryEnvelope: nil, sections: sections, for: profile)

        let loaded = store.load(for: profile)
        #expect(loaded?.workspaceBaseURL == ConnectionProfile.defaultCaelWorkspaceBaseURL)
        #expect(loaded?.sections?.vaultRefs?.data?.refs.first?.secretValue == nil)
        #expect(loaded?.sections?.vaultRefs?.warnings.contains("Secret values were stripped before local cache storage.") == true)
        #expect(store.load(for: alternateURLProfile)?.workspaceBaseURL == nil)
    }
}
