import Foundation
import Testing

@testable import HermesDesktop

struct CaelCommandCenterContractTests {
    @Test
    func statusDecodesSharedCommandCenterContract() throws {
        let json = #"""
        {
          "ok": true,
          "generatedAt": "2026-05-24T00:00:00.000Z",
          "host": "BigMac",
          "posture": {
            "bind": "100.97.216.111:3077",
            "remoteAccess": "Tailscale-only browser/PWA access",
            "auth": "enabled",
            "publicInternet": "disabled"
          },
          "services": [],
          "links": [],
          "contract": {
            "id": "cael-command-center",
            "version": "2026-05-24.si-004",
            "generatedAt": "2026-05-24T00:00:00.000Z",
            "principle": "The shared Cael Workspace API contract owns business logic and state; Swift/Desktop and Web/PWA are clients, not separate sources of truth.",
            "primarySurface": "Cael Desktop native macOS command center",
            "mirrorSurface": "Cael Workspace :3077 responsive web/PWA mirror for iPhone/iPad and browsers",
            "privateAccess": "Tailscale-only/private mesh; no public internet exposure by default.",
            "surfaces": [
              {
                "id": "kb-brain-dashboard",
                "label": "KB Brain Dashboard",
                "owner": "legacy",
                "desktop": "planned",
                "web": "retired",
                "source": "/Users/cderamos/projects/KB_Brain_Dashboard",
                "status": "migration-only",
                "description": "Absorb useful surfaces into Cael."
              }
            ]
          }
        }
        """#

        let status = try JSONDecoder().decode(CaelWorkspaceStatus.self, from: Data(json.utf8))

        #expect(status.contract.id == "cael-command-center")
        #expect(status.contract.primarySurface.contains("Desktop"))
        #expect(status.contract.mirrorSurface.contains(":3077"))
        #expect(status.contract.privateAccess.contains("Tailscale-only"))
        #expect(status.contract.surfaces.first?.id == "kb-brain-dashboard")
        #expect(status.contract.surfaces.first?.status == "migration-only")
        #expect(status.contract.surfaces.first?.owner == "legacy")
    }
}
