import Foundation
import Testing

@testable import HermesPhoneKit

actor CapturedGatewayLines {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func firstLine() -> String? {
        lines.first
    }
}

struct HermesGatewayCoreTests {
    @Test
    func rpcRequestMatchesResponseByID() async throws {
        let client = HermesGatewayRPCClient()
        let capturedLines = CapturedGatewayLines()
        await client.attachSender { line in
            await capturedLines.append(line)
        }

        let requestTask = Task {
            try await client.request(method: "session.create", params: ["client": .string("test")], timeout: 2)
        }

        var requestID: Int?
        for _ in 0..<20 {
            if let line = await capturedLines.firstLine(),
               let data = line.data(using: .utf8),
               let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                requestID = object["id"] as? Int
                #expect(object["method"] as? String == "session.create")
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let id = try #require(requestID)
        await client.handleStdoutLine("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"result\":{\"session_id\":\"session-1\"}}")

        let result = try await requestTask.value
        #expect(result?.objectValue?["session_id"]?.stringValue == "session-1")
    }

    @Test
    func rpcDecodesGatewayEventsFromJsonLines() async throws {
        let client = HermesGatewayRPCClient()
        let events = client.events
        let eventTask = Task {
            var iterator = events.makeAsyncIterator()
            return await iterator.next()
        }

        await client.handleStdoutLine("{\"jsonrpc\":\"2.0\",\"method\":\"event\",\"params\":{\"type\":\"message.delta\",\"session_id\":\"session-1\",\"payload\":{\"delta\":\"hello\"}}}")

        let event = try #require(await eventTask.value)
        #expect(event.type == "message.delta")
        #expect(event.sessionID == "session-1")
        #expect(event.payload["delta"]?.stringValue == "hello")
    }

    @Test
    func rpcReportsInvalidFramesAsParseEvents() async throws {
        let client = HermesGatewayRPCClient()
        let events = client.events
        let eventTask = Task {
            var iterator = events.makeAsyncIterator()
            return await iterator.next()
        }

        await client.handleStdoutLine("not json")

        let event = try #require(await eventTask.value)
        #expect(event.type == "gateway.parse_error")
        #expect(event.payload["line"]?.stringValue == "not json")
    }

    @Test
    func commandDispatchResultsMapToPrimaryActions() {
        let skill = HermesGatewayCommandResult(.object([
            "type": .string("skill"),
            "message": .string("Use the selected skill")
        ]))
        #expect(skill.primaryAction == .submit("Use the selected skill"))

        let exec = HermesGatewayCommandResult(.object([
            "type": .string("exec"),
            "output": .string("Model switched")
        ]))
        #expect(exec.primaryAction == .render("Model switched"))

        let alias = HermesGatewayCommandResult(.object([
            "type": .string("alias"),
            "target": .string("/model")
        ]))
        #expect(alias.primaryAction == .alias("/model"))
    }

    @Test
    func gatewayTextSanitizerRemovesAnsiEscapes() {
        let dirty = "\u{1B}[1;3mUnknown command\u{1B}[0m: /creative/test\n\u{1B}[2mHint\u{1B}[0m"
        #expect(HermesGatewayTextSanitizer.sanitize(dirty) == "Unknown command: /creative/test\nHint")

        let osc = "before\u{1B}]0;title\u{07}after"
        #expect(HermesGatewayTextSanitizer.sanitize(osc) == "beforeafter")
    }

    @Test
    func slashCommandCatalogParserHandlesNestedGatewayCatalogs() {
        let catalog = JSONValue.object([
            "sections": .array([
                .object([
                    "title": .string("Session"),
                    "commands": .array([
                        .object([
                            "command": .string("/status"),
                            "description": .string("Show session info")
                        ]),
                        .object([
                            "usage": .string("/goal <text>"),
                            "summary": .string("Set a standing goal")
                        ])
                    ])
                ]),
                .object([
                    "title": .string("Skills"),
                    "items": .array([
                        .object([
                            "name": .string("/gif-search"),
                            "type": .string("skill"),
                            "help": .string("Search GIFs")
                        ])
                    ])
                ])
            ])
        ])

        let entries = HermesSlashCommandCatalogParser.parse(catalog)
        #expect(entries.map(\.name).contains("/status"))
        #expect(entries.map(\.name).contains("/goal"))
        #expect(entries.map(\.name).contains("/gif-search"))
        #expect(entries.first { $0.name == "/goal" }?.usage == "/goal <text>")
        #expect(entries.first { $0.name == "/gif-search" }?.isSkill == true)
    }

    @Test
    func slashCommandCatalogParserHandlesUpstreamPairsCatalogs() {
        let catalog = JSONValue.object([
            "categories": .array([
                .object([
                    "name": .string("Session"),
                    "pairs": .array([
                        .array([.string("/status"), .string("Show session info")]),
                        .array([.string("/compress <focus>"), .string("Compress context")])
                    ])
                ])
            ])
        ])

        let entries = HermesSlashCommandCatalogParser.parse(catalog)
        #expect(entries.first { $0.name == "/status" }?.description == "Show session info")
        #expect(entries.first { $0.name == "/compress" }?.usage == "/compress <focus>")
        #expect(entries.first { $0.name == "/compress" }?.category == "Session")
    }

    @Test
    func sessionSummaryMatchesLineageRootIdentity() throws {
        let data = """
        {
          "id": "tip-5",
          "_lineage_root_id": "root-1",
          "parent_session_id": "tip-4",
          "title": "Compacted chat"
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(SessionSummary.self, from: data)
        #expect(summary.durableSessionID == "root-1")
        #expect(summary.lineageMatchID == "root-1")
        #expect(summary.matchesSessionIdentity("tip-5"))
        #expect(summary.matchesSessionIdentity("tip-4"))
        #expect(summary.matchesSessionIdentity("root-1"))
    }

    @Test
    func capabilityProbeParsesBooleansAndReasons() {
        #expect(HermesNativeChatCapabilityProbe.bool(from: "1\n"))
        #expect(HermesNativeChatCapabilityProbe.bool(from: "true"))
        #expect(!HermesNativeChatCapabilityProbe.bool(from: "0"))

        var missingPython = HermesChatBootstrapStatus(sshConnected: true)
        #expect(HermesNativeChatCapabilityProbe.fallbackReason(for: missingPython) == "python3 is not available on the remote host.")

        let missingGateway = HermesChatBootstrapStatus(
            sshConnected: true,
            pythonAvailable: true,
            hermesCLIAvailable: true,
            tuiGatewayAvailable: false
        )
        #expect(HermesNativeChatCapabilityProbe.fallbackReason(for: missingGateway) == "tui_gateway.entry is not importable on this host.")

        missingPython.pythonAvailable = true
        missingPython.hermesCLIAvailable = false
        #expect(HermesNativeChatCapabilityProbe.fallbackReason(for: missingPython) == "Hermes CLI is not available on the remote host.")
    }
}
