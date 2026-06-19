import Foundation
import Testing
@testable import HermesPhoneKit

@Suite("Mobile companion contracts")
struct MobileCompanionContractsTests {
    @Test
    func gatewaySnapshotDecodesWithoutSecrets() throws {
        let data = Data(#"{"profile_name":"work","cli_available":true,"lifecycle_available":true,"running":true,"state":"running","process_id":42,"manager":"systemd","service_status":"running","last_error":null,"updated_at":"2026-06-19T10:00:00Z","channels":[{"id":"telegram","name":"Telegram","description":"Telegram bot","enabled":true,"configured":true,"state":"connected","error_message":null,"updated_at":"2026-06-19T10:00:00Z","credentials":[{"key":"TELEGRAM_BOT_TOKEN","prompt":"Bot token","description":null,"required":true,"is_set":true,"is_password":true,"advanced":false}]}]}"#.utf8)
        let snapshot = try JSONDecoder().decode(GatewaySnapshot.self, from: data)
        #expect(snapshot.profileName == "work")
        #expect(snapshot.processID == 42)
        #expect(snapshot.channels.first?.state == "connected")
        #expect(snapshot.channels.first?.configured == true)
        #expect(snapshot.channels.first?.credentials.first?.isSet == true)
        #expect(!String(data: data, encoding: .utf8)!.contains(#""value""#))
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
        #expect(script.contains("hermes = find_hermes_binary(payload)"))
        #expect(!script.contains(#"hermes = shutil.which("hermes")"#))
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
        #expect(script.contains("profiles_module.delete_profile(name, yes=True)"))
        #expect(!script.contains("noninteractive_delete_flag"))
    }

    @Test
    func agentManagementUsesInstalledHermesProfileContracts() {
        let script = MobileCompanionService.remoteScript
        #expect(script.contains("profiles_module.list_profiles()"))
        #expect(script.contains("profiles_module.create_profile("))
        #expect(script.contains("profiles_module.rename_profile(name, new_name)"))
        #expect(script.contains("profiles_module.write_profile_meta("))
        #expect(script.contains("profiles_module.seed_profile_skills(profile_dir, quiet=True)"))
        #expect(script.contains(#"soul_path = profile_dir / "SOUL.md""#))
        #expect(script.contains("Switch to this agent before editing its SOUL.md."))
    }

    @Test
    func gatewayStatusUsesRuntimeHealthAndDashboardChannelMetadata() {
        let script = MobileCompanionService.remoteScript
        #expect(script.contains("from gateway.status import get_running_pid"))
        #expect(script.contains("_messaging_platform_catalog"))
        #expect(script.contains("_messaging_platform_payload"))
        #expect(script.contains("_write_platform_enabled"))
        #expect(script.contains("save_env_value(key, text)"))
        #expect(!script.contains(#"not any(token in lower"#))
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
    func installedHermesExecutesAgentAndGatewaySnapshotsWhenAvailable() throws {
        let python = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/hermes-agent/venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return }

        let profilesRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/profiles")
        let namedProfile = (try? FileManager.default.contentsOfDirectory(
            at: profilesRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).first { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }?.lastPathComponent)

        for operation in ["profile_snapshot", "gateway_snapshot", "config_snapshot", "env_snapshot"] {
            var arguments: [String: JSONValue] = [
                "operation": .string(operation),
                "hermes_home": .string(
                    FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".hermes")
                        .path
                ),
            ]
            if operation == "profile_snapshot", let namedProfile {
                arguments["profile_name"] = .string(namedProfile)
                arguments["hermes_home"] = .string(
                    profilesRoot.appendingPathComponent(namedProfile).path
                )
            }
            let payload: JSONValue = .object([
                "operation": arguments["operation"]!,
                "hermes_home": arguments["hermes_home"]!,
                "profile_name": arguments["profile_name"] ?? .string(""),
            ])
            let script = try RemotePythonScript.wrap(payload, body: MobileCompanionService.remoteScript)
            let process = Process()
            process.executableURL = python
            process.arguments = ["-c", script]
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("hermes-mobile-contract-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: outputURL)
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            try output.close()
            let data = try Data(contentsOf: outputURL)
            try? FileManager.default.removeItem(at: outputURL)

            #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: data, as: UTF8.self)))
            if operation == "profile_snapshot" {
                let snapshot = try JSONDecoder().decode(ProfileManagementSnapshot.self, from: data)
                #expect(!snapshot.agents.isEmpty)
                if let namedProfile {
                    #expect(snapshot.activeProfileName == namedProfile)
                    #expect(snapshot.agents.contains { $0.name == namedProfile && $0.isActive })
                }
            } else if operation == "gateway_snapshot" {
                let snapshot = try JSONDecoder().decode(GatewaySnapshot.self, from: data)
                #expect(!snapshot.channels.isEmpty)
            } else if operation == "config_snapshot" {
                let snapshot = try JSONDecoder().decode(ConfigSnapshot.self, from: data)
                #expect(!snapshot.fields.isEmpty)
                #expect(snapshot.fields.contains { $0.path == "model" || $0.path.hasPrefix("model.") })
            } else {
                let snapshot = try JSONDecoder().decode(EnvironmentSnapshot.self, from: data)
                #expect(!snapshot.variables.isEmpty)
            }
        }
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
