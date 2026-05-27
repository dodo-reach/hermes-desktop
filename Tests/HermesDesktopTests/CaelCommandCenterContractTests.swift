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

    @Test
    func decodesCommandCenterSummaryEnvelope() throws {
        let json = #"""
        {
          "ok": true,
          "generatedAt": "2026-05-24T00:00:00.000Z",
          "source": "cael-workspace:3077",
          "scope": "mixed",
          "warnings": [],
          "errors": [],
          "links": [{ "label": "Usage", "href": "/usage", "kind": "local" }],
          "data": {
            "version": "2026-05-24.phase1",
            "generatedAt": "2026-05-24T00:00:00.000Z",
            "contract": null,
            "posture": {
              "host": "BigMac",
              "bind": "100.97.216.111:3077",
              "remoteAccess": "Tailscale-only",
              "auth": "enabled",
              "publicInternet": "disabled"
            },
            "systems": [{
              "id": "workspace",
              "label": "Workspace",
              "ok": true,
              "lane": "personal",
              "owner": "Cael",
              "detail": "HTTP 200",
              "latencyMs": 12
            }],
            "integrations": [],
            "usage": {
              "enabledProviders": ["codex"],
              "providers": [{
                "id": "codex",
                "label": "Codex",
                "status": "ok",
                "confidence": "live",
                "monitorKind": "cael",
                "caelDefault": true,
                "caelModel": "gpt-5.5",
                "primary": {
                  "label": "weekly",
                  "usedPercent": 25,
                  "remainingPercent": 75,
                  "resetsAt": null
                }
              }]
            },
            "automations": {
              "boundary": "separate lanes",
              "instances": [{
                "id": "personal-bigmac",
                "label": "Personal n8n",
                "ok": true,
                "scope": "personal",
                "boundary": "personal only",
                "failures": 0
              }]
            },
            "brain": {
              "sources": [{
                "id": "personal-kv",
                "label": "Personal Knowledge Vault",
                "category": "personal",
                "status": "available",
                "writable": false
              }]
            },
            "actionGates": [{
              "id": "business-dry-run-smoke",
              "label": "Business dry run",
              "source": "n8n-governance",
              "status": "approval_gated",
              "riskLevel": "production_mutation",
              "approvalRequired": true,
              "dryRunSupported": true,
              "detail": "requires approval"
            }],
            "agentRuns": [{
              "id": "/Users/cderamos/.hermes/receipts/chat.md",
              "title": "chat recovery receipt",
              "status": "personal-bigmac",
              "updatedAt": "2026-05-24T01:00:00.000Z",
              "source": "receipt",
              "path": "/Users/cderamos/.hermes/receipts/chat.md"
            }],
            "nowNext": [{
              "id": "runtime-posture",
              "label": "Runtime ready",
              "detail": "Core checks are online.",
              "tone": "success",
              "href": "/cael-home"
            }],
            "homebaseRecords": {
              "status": "planned",
              "detail": "Twenty remains legacy.",
              "records": []
            }
          }
        }
        """#

        let envelope = try JSONDecoder().decode(CaelCommandCenterSummaryEnvelope.self, from: Data(json.utf8))

        #expect(envelope.ok)
        #expect(envelope.source == "cael-workspace:3077")
        #expect(envelope.data?.posture?.host == "BigMac")
        #expect(envelope.data?.usage?.enabledProviders == ["codex"])
        #expect(envelope.data?.actionGates.first?.approvalRequired == true)
        #expect(envelope.data?.brain?.sources.first?.status == "available")
        #expect(envelope.links?.first?.kind == "local")
    }

}
