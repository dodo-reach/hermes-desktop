import Foundation

final class CaelWorkspaceAPIService: @unchecked Sendable {
    private let sshTransport: SSHTransport
    private let baseURL = "http://100.97.216.111:3077"

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func loadStatus(connection: ConnectionProfile) async throws -> CaelWorkspaceStatus {
        try await loadJSON(connection: connection, path: "/api/cael-status", responseType: CaelWorkspaceStatus.self)
    }

    func loadCommandCenterContract(connection: ConnectionProfile) async throws -> CaelCommandCenterContract {
        try await loadStatus(connection: connection).contract
    }

    func loadCommandCenterSummary(connection: ConnectionProfile) async throws -> CaelCommandCenterSummaryEnvelope {
        try await loadJSON(connection: connection, path: "/api/command-center/summary", responseType: CaelCommandCenterSummaryEnvelope.self)
    }

    func loadIntegrations(connection: ConnectionProfile) async throws -> CaelIntegrationStatus {
        try await loadJSON(connection: connection, path: "/api/integrations/status", responseType: CaelIntegrationStatus.self)
    }

    func loadProviderUsage(connection: ConnectionProfile, force: Bool = false) async throws -> CaelProviderUsageLimits {
        let path = force ? "/api/usage/limits?force=1" : "/api/usage/limits"
        return try await loadJSON(connection: connection, path: path, responseType: CaelProviderUsageLimits.self)
    }

    private func loadJSON<Response: Decodable>(
        connection: ConnectionProfile,
        path: String,
        responseType: Response.Type
    ) async throws -> Response {
        let payload = try JSONEncoder().encode(CaelWorkspaceAPIRequest(
            baseURL: baseURL,
            path: path,
            hermesHome: connection.remoteHermesHomePath
        ))
        let requestLiteral = String(data: payload, encoding: .utf8) ?? "{}"
        let script = """
        import json
        import os
        import pathlib
        import secrets
        import sys
        import time
        import urllib.error
        import urllib.request

        request = json.loads(\(String(reflecting: requestLiteral)))
        hermes_home = pathlib.Path.home() / ".hermes"
        store_path = hermes_home / "workspace-sessions.json"
        now_ms = int(time.time() * 1000)
        ttl_ms = 30 * 24 * 60 * 60 * 1000
        expiry = now_ms + ttl_ms
        token = secrets.token_hex(32)

        try:
            payload = json.loads(store_path.read_text()) if store_path.exists() else {"tokens": {}}
            tokens = payload.get("tokens", {})
            if not isinstance(tokens, dict):
                tokens = {}
        except Exception:
            tokens = {}

        tokens = {key: value for key, value in tokens.items() if isinstance(value, int) and value > now_ms}
        tokens[token] = expiry
        store_path.parent.mkdir(parents=True, exist_ok=True)
        store_path.write_text(json.dumps({"tokens": tokens}))
        try:
            store_path.chmod(0o600)
        except Exception:
            pass

        url = request["baseURL"].rstrip("/") + request["path"]
        http_request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/json",
                "Cookie": "claude-auth=" + token,
                "User-Agent": "CaelDesktop/1.0 native-api",
            },
        )

        try:
            with urllib.request.urlopen(http_request, timeout=12) as response:
                sys.stdout.write(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", "replace")
            print(json.dumps({"ok": False, "error": "HTTP %s: %s" % (error.code, body)}))
            sys.exit(1)
        """

        let result = try await sshTransport.execute(
            on: connection,
            remoteCommand: connection.remoteServiceCommand("python3 -"),
            standardInput: Data(script.utf8),
            allocateTTY: false
        )
        try sshTransport.validateSuccessfulExit(result, for: connection)

        guard let data = result.stdout.data(using: .utf8) else {
            throw SSHTransportError.invalidResponse("Workspace API output was not valid UTF-8.")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SSHTransportError.invalidResponse(
                "Workspace API returned JSON that Cael Desktop could not decode: \(error.localizedDescription)"
            )
        }
    }
}

private struct CaelWorkspaceAPIRequest: Encodable {
    let baseURL: String
    let path: String
    let hermesHome: String
}
