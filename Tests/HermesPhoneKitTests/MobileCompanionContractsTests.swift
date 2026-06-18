import Foundation
import Testing
@testable import HermesPhoneKit

@Suite("Mobile companion contracts")
struct MobileCompanionContractsTests {
    @Test
    func gatewaySnapshotDecodesWithoutSecrets() throws {
        let data = Data(#"{"profile_name":"work","cli_available":true,"lifecycle_available":true,"running":true,"manager":"systemd","service_status":"running","last_error":null,"channels":[{"id":"telegram","name":"Telegram","enabled":true,"configured":true}]}"#.utf8)
        let snapshot = try JSONDecoder().decode(GatewaySnapshot.self, from: data)
        #expect(snapshot.profileName == "work")
        #expect(snapshot.channels.first?.configured == true)
    }

    @Test
    func configFieldsPreserveNestedJSONTypes() throws {
        let data = Data(#"{"path":"tools.groups","title":"Groups","category":"Tools","description":null,"kind":"list","enum_values":[],"value":[{"name":"safe","enabled":true,"limit":3}],"default_value":[]}"#.utf8)
        let field = try JSONDecoder().decode(ConfigField.self, from: data)
        guard case .array(let values) = field.value,
              case .object(let item) = values.first else {
            Issue.record("Expected a typed list-of-object value")
            return
        }
        #expect(item["enabled"] == .bool(true))
        #expect(item["limit"] == .int(3))
    }

    @Test
    func environmentContractContainsStatusOnly() throws {
        let data = Data(#"{"variables":[{"name":"OPENAI_API_KEY","category":"Models","description":"OpenAI API key","is_set":true}]}"#.utf8)
        let snapshot = try JSONDecoder().decode(EnvironmentSnapshot.self, from: data)
        #expect(snapshot.variables.first?.isSet == true)
        #expect(!String(data: data, encoding: .utf8)!.contains(#""value""#))
    }

    @Test
    func remoteScriptUsesHermesLifecycleAndAtomicSecretWrites() {
        let script = MobileCompanionService.remoteScript
        #expect(script.contains(#"run("gateway", action"#))
        #expect(script.contains("os.replace(temporary, path)"))
        #expect(script.contains("os.chmod(path, mode)"))
        #expect(!script.contains("systemctl"))
        #expect(!script.contains("launchctl"))
        #expect(!script.contains("s6-svc"))
        #expect(!script.contains("os.kill"))
    }

    @Test
    func profileDeletionGuardsDefaultAndActiveProfiles() {
        let script = MobileCompanionService.remoteScript
        #expect(script.contains(#"name in ("", "default", profile_name)"#))
        #expect(script.contains("noninteractive_delete_flag"))
    }

    @Test
    func kanbanSnapshotCarriesLatestEventID() throws {
        let data = Data(#"{"available":true,"database_path":"~/.hermes/kanban.db","board_slug":"default","boards":[{"slug":"default","name":"Default"}],"tasks":[],"latest_event_id":42,"warning":null}"#.utf8)
        let snapshot = try JSONDecoder().decode(KanbanMobileSnapshot.self, from: data)
        #expect(snapshot.latestEventID == 42)
    }

    @Test
    func kanbanReaderFeatureDetectsSortAndUpstreamTables() {
        let script = MobileCompanionService.remoteScript
        #expect(script.contains(#"if "updated_at" in columns"#))
        #expect(script.contains(#"elif "created_at" in columns"#))
        #expect(script.contains(#"("task_comments", "comments")"#))
        #expect(script.contains(#"("task_events", "events")"#))
        #expect(!script.contains("coalesce(updated_at, created_at, 0)"))
        #expect(script.contains(#""kanban" / "boards" / board / "kanban.db""#))
    }

    @Test
    func settingsUseInstalledHermesMetadataWhenAvailable() {
        let script = MobileCompanionService.remoteScript
        #expect(script.contains("CONFIG_SCHEMA"))
        #expect(script.contains("OPTIONAL_ENV_VARS"))
        #expect(script.contains(#""category_order": category_order"#))
    }

    @Test
    func durableSessionIdentityStillUsesLineageRoot() {
        let session = SessionSummary(
            id: "live-tip",
            title: "Session",
            model: nil,
            parentSessionID: "parent",
            lineageRootID: "durable-root",
            startedAt: nil,
            lastActive: nil,
            messageCount: 1,
            preview: nil
        )
        #expect(session.durableSessionID == "durable-root")
        #expect(session.matchesSessionIdentity("durable-root"))
    }
}
