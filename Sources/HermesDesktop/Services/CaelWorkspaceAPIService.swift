import Foundation

final class CaelWorkspaceAPIService: @unchecked Sendable {
    private let sshTransport: SSHTransport

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

    func loadCommandCenterSections(connection: ConnectionProfile) async -> CaelCommandCenterSectionsSnapshot {
        async let actionGates: CaelCommandCenterSectionEnvelope<CaelCommandCenterActionGatesSection>? = try? await loadJSON(
            connection: connection,
            path: "/api/command-center/action-gates",
            responseType: CaelCommandCenterSectionEnvelope<CaelCommandCenterActionGatesSection>.self
        )
        async let agentRuns: CaelCommandCenterSectionEnvelope<CaelCommandCenterAgentRunsSection>? = try? await loadJSON(
            connection: connection,
            path: "/api/command-center/agent-runs",
            responseType: CaelCommandCenterSectionEnvelope<CaelCommandCenterAgentRunsSection>.self
        )
        async let automations: CaelCommandCenterSectionEnvelope<CaelCommandCenterAutomationSection>? = try? await loadJSON(
            connection: connection,
            path: "/api/command-center/automations",
            responseType: CaelCommandCenterSectionEnvelope<CaelCommandCenterAutomationSection>.self
        )
        async let brain: CaelCommandCenterSectionEnvelope<CaelCommandCenterBrainSection>? = try? await loadJSON(
            connection: connection,
            path: "/api/command-center/brain",
            responseType: CaelCommandCenterSectionEnvelope<CaelCommandCenterBrainSection>.self
        )
        async let homebaseRecords: CaelCommandCenterSectionEnvelope<CaelCommandCenterHomebaseRecords>? = try? await loadJSON(
            connection: connection,
            path: "/api/command-center/homebase-records",
            responseType: CaelCommandCenterSectionEnvelope<CaelCommandCenterHomebaseRecords>.self
        )
        async let memoryArtifacts: CaelCommandCenterSectionEnvelope<CaelCommandCenterMemoryArtifactsSection>? = try? await loadJSON(
            connection: connection,
            path: "/api/command-center/memory-artifacts",
            responseType: CaelCommandCenterSectionEnvelope<CaelCommandCenterMemoryArtifactsSection>.self
        )
        async let usageLimits: CaelCommandCenterSectionEnvelope<CaelCommandCenterUsage>? = try? await loadJSON(
            connection: connection,
            path: "/api/command-center/usage-limits",
            responseType: CaelCommandCenterSectionEnvelope<CaelCommandCenterUsage>.self
        )
        async let vaultRefs: CaelCommandCenterSectionEnvelope<CaelCommandCenterVaultRefsSection>? = try? await loadJSON(
            connection: connection,
            path: "/api/command-center/vault-refs",
            responseType: CaelCommandCenterSectionEnvelope<CaelCommandCenterVaultRefsSection>.self
        )

        return await CaelCommandCenterSectionsSnapshot(
            actionGates: actionGates,
            agentRuns: agentRuns,
            automations: automations,
            brain: brain,
            homebaseRecords: homebaseRecords,
            memoryArtifacts: memoryArtifacts,
            usageLimits: usageLimits,
            vaultRefs: vaultRefs
        )
    }

    func loadN8nGovernance(connection: ConnectionProfile) async throws -> CaelN8nGovernanceStatus {
        try await loadJSON(connection: connection, path: "/api/cael-n8n-governance", responseType: CaelN8nGovernanceStatus.self)
    }

    func loadIntegrations(connection: ConnectionProfile) async throws -> CaelIntegrationStatus {
        try await loadJSON(connection: connection, path: "/api/integrations/status", responseType: CaelIntegrationStatus.self)
    }

    func loadProviderUsage(connection: ConnectionProfile, force: Bool = false) async throws -> CaelProviderUsageLimits {
        let path = force ? "/api/usage/limits?force=1" : "/api/usage/limits"
        return try await loadJSON(connection: connection, path: path, responseType: CaelProviderUsageLimits.self)
    }

    func loadProfiles(connection: ConnectionProfile) async throws -> CaelProfilesListResponse {
        try await loadJSON(connection: connection, path: "/api/profiles/list", responseType: CaelProfilesListResponse.self)
    }

    func readProfile(connection: ConnectionProfile, name: String) async throws -> CaelProfileDetail {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let response = try await loadJSON(
            connection: connection,
            path: "/api/profiles/read?name=\(encodedName)",
            responseType: CaelProfileDetailResponse.self
        )
        return response.profile
    }

    @discardableResult
    func createProfile(
        connection: ConnectionProfile,
        name: String,
        cloneFrom: String? = nil,
        provider: String? = nil,
        model: String? = nil
    ) async throws -> CaelProfileMutationResponse {
        try await postJSON(
            connection: connection,
            path: "/api/profiles/create",
            body: CaelProfileCreateRequest(
                name: name,
                cloneFrom: cloneFrom?.nilIfBlank,
                model: model?.nilIfBlank,
                provider: provider?.nilIfBlank
            ),
            responseType: CaelProfileMutationResponse.self
        )
    }

    @discardableResult
    func activateProfile(connection: ConnectionProfile, name: String) async throws -> CaelProfileMutationResponse {
        try await postJSON(
            connection: connection,
            path: "/api/profiles/activate",
            body: CaelProfileNameRequest(name: name),
            responseType: CaelProfileMutationResponse.self
        )
    }

    @discardableResult
    func renameProfile(connection: ConnectionProfile, oldName: String, newName: String) async throws -> CaelProfileMutationResponse {
        try await postJSON(
            connection: connection,
            path: "/api/profiles/rename",
            body: CaelProfileRenameRequest(oldName: oldName, newName: newName),
            responseType: CaelProfileMutationResponse.self
        )
    }

    @discardableResult
    func deleteProfile(connection: ConnectionProfile, name: String) async throws -> CaelProfileMutationResponse {
        try await postJSON(
            connection: connection,
            path: "/api/profiles/delete",
            body: CaelProfileNameRequest(name: name),
            responseType: CaelProfileMutationResponse.self
        )
    }

    @discardableResult
    func updateProfileDescription(connection: ConnectionProfile, name: String, description: String) async throws -> CaelProfileMutationResponse {
        try await postJSON(
            connection: connection,
            path: "/api/profiles/update",
            body: CaelProfileDescriptionUpdateRequest(
                name: name,
                patch: CaelProfileDescriptionPatch(description: description)
            ),
            responseType: CaelProfileMutationResponse.self
        )
    }

    private func loadJSON<Response: Decodable>(
        connection: ConnectionProfile,
        path: String,
        responseType: Response.Type
    ) async throws -> Response {
        try await requestJSON(connection: connection, path: path, method: "GET", body: nil, responseType: responseType)
    }

    private func postJSON<Body: Encodable, Response: Decodable>(
        connection: ConnectionProfile,
        path: String,
        body: Body,
        responseType: Response.Type
    ) async throws -> Response {
        let bodyData = try JSONEncoder().encode(body)
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            throw SSHTransportError.invalidResponse("Workspace API request body was not valid UTF-8.")
        }
        return try await requestJSON(
            connection: connection,
            path: path,
            method: "POST",
            body: bodyString,
            responseType: responseType
        )
    }

    private func requestJSON<Response: Decodable>(
        connection: ConnectionProfile,
        path: String,
        method: String,
        body: String?,
        responseType: Response.Type
    ) async throws -> Response {
        let payload = try JSONEncoder().encode(CaelWorkspaceAPIRequest(
            baseURL: connection.resolvedCaelWorkspaceBaseURL,
            path: path,
            hermesHome: connection.remoteHermesHomePath,
            method: method,
            body: body
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
        method = str(request.get("method") or "GET").upper()
        body = request.get("body")
        data = body.encode("utf-8") if isinstance(body, str) else None
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
        headers = {
            "Accept": "application/json",
            "Cookie": "claude-auth=" + token,
            "User-Agent": "CaelDesktop/1.0 native-api",
        }
        if data is not None:
            headers["Content-Type"] = "application/json"
        http_request = urllib.request.Request(
            url,
            data=data,
            headers=headers,
            method=method,
        )

        try:
            with urllib.request.urlopen(http_request, timeout=6) as response:
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
    let method: String
    let body: String?
}

private struct CaelProfileNameRequest: Encodable {
    let name: String
}

private struct CaelProfileCreateRequest: Encodable {
    let name: String
    let cloneFrom: String?
    let model: String?
    let provider: String?
}

private struct CaelProfileRenameRequest: Encodable {
    let oldName: String
    let newName: String
}

private struct CaelProfileDescriptionPatch: Encodable {
    let description: String
}

private struct CaelProfileDescriptionUpdateRequest: Encodable {
    let name: String
    let patch: CaelProfileDescriptionPatch
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
