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

    func loadHermesConfig(connection: ConnectionProfile) async throws -> WorkspaceHermesConfigResponse {
        try await loadJSON(connection: connection, path: "/api/hermes-config", responseType: WorkspaceHermesConfigResponse.self)
    }

    func loadWorkspaceModels(connection: ConnectionProfile) async throws -> WorkspaceModelCatalogResponse {
        try await loadJSON(connection: connection, path: "/api/models", responseType: WorkspaceModelCatalogResponse.self)
    }

    func loadWorkspaceModelInfo(connection: ConnectionProfile) async throws -> WorkspaceModelInfoResponse {
        try await loadJSON(connection: connection, path: "/api/model/info", responseType: WorkspaceModelInfoResponse.self)
    }

    func loadWorkspaceContextUsage(
        connection: ConnectionProfile,
        sessionID: String? = nil
    ) async throws -> WorkspaceContextUsageResponse {
        let normalizedSessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let path = apiPath(
            "/api/context-usage",
            queryItems: normalizedSessionID.isEmpty ? [] : [
                URLQueryItem(name: "sessionId", value: normalizedSessionID)
            ]
        )
        return try await loadJSON(connection: connection, path: path, responseType: WorkspaceContextUsageResponse.self)
    }

    @discardableResult
    func setDefaultHermesModel(connection: ConnectionProfile, providerID: String, modelID: String) async throws -> WorkspaceHermesConfigPatchResponse {
        let response = try await patchJSON(
            connection: connection,
            path: "/api/hermes-config",
            body: WorkspaceHermesSetDefaultModelRequest(
                action: "set-default-model",
                providerID: providerID,
                modelID: modelID
            ),
            responseType: WorkspaceHermesConfigPatchResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "Hermes model config update failed.")
        }
        return response
    }

    func loadProviderUsage(connection: ConnectionProfile, force: Bool = false) async throws -> CaelProviderUsageLimits {
        let path = force ? "/api/usage/limits?force=1" : "/api/usage/limits"
        return try await loadJSON(connection: connection, path: path, responseType: CaelProviderUsageLimits.self)
    }

    func loadWorkspaceTerminalSessions(connection: ConnectionProfile) async throws -> WorkspaceTerminalSessionsResponse {
        try await loadJSON(connection: connection, path: "/api/terminal-sessions", responseType: WorkspaceTerminalSessionsResponse.self)
    }

    @discardableResult
    func renameWorkspaceTerminalSession(
        connection: ConnectionProfile,
        sessionID: String,
        label: String
    ) async throws -> WorkspaceTerminalSessionActionResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/terminal-sessions",
            body: WorkspaceTerminalSessionRenameRequest(
                action: "rename",
                sessionId: sessionID,
                label: label
            ),
            responseType: WorkspaceTerminalSessionActionResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace terminal rename failed.")
        }
        return response
    }

    func loadWorkspaceSkills(
        connection: ConnectionProfile,
        tab: String = "installed",
        search: String = "",
        limit: Int = 30
    ) async throws -> WorkspaceSkillCatalogResponse {
        let path = apiPath(
            "/api/skills",
            queryItems: [
                URLQueryItem(name: "tab", value: tab),
                URLQueryItem(name: "search", value: search),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "sort", value: "name")
            ]
        )
        return try await loadJSON(connection: connection, path: path, responseType: WorkspaceSkillCatalogResponse.self)
    }

    func searchWorkspaceSkillsHub(
        connection: ConnectionProfile,
        query: String,
        limit: Int = 20
    ) async throws -> WorkspaceSkillHubSearchResponse {
        let path = apiPath(
            "/api/skills/hub-search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "source", value: "all"),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        return try await loadJSON(connection: connection, path: path, responseType: WorkspaceSkillHubSearchResponse.self)
    }

    @discardableResult
    func runWorkspaceSkillAction(
        connection: ConnectionProfile,
        action: String,
        identifier: String,
        enabled: Bool? = nil,
        category: String? = nil
    ) async throws -> WorkspaceSkillActionResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/skills",
            body: WorkspaceSkillActionRequest(
                action: action,
                identifier: identifier,
                name: identifier,
                category: category?.nilIfBlank,
                force: false,
                enabled: enabled
            ),
            responseType: WorkspaceSkillActionResponse.self
        )
        if let ok = response.ok, ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace skills action failed.")
        }
        return response
    }

    func loadProfiles(connection: ConnectionProfile) async throws -> CaelProfilesListResponse {
        try await loadJSON(connection: connection, path: "/api/profiles/list", responseType: CaelProfilesListResponse.self)
    }

    func loadCrewStatus(connection: ConnectionProfile) async throws -> WorkspaceCrewStatusResponse {
        try await loadJSON(connection: connection, path: "/api/crew-status", responseType: WorkspaceCrewStatusResponse.self)
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
    func startWorkspaceAgentRuntime(connection: ConnectionProfile) async throws -> WorkspaceAgentStartResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/start-agent",
            body: EmptyWorkspaceAPIRequest(),
            responseType: WorkspaceAgentStartResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not start the agent runtime.")
        }
        return response
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


    func createWorkspaceChatSession(connection: ConnectionProfile, label: String? = nil, model: String? = nil) async throws -> WorkspaceSessionCreateResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/sessions",
            body: WorkspaceSessionCreateRequest(
                label: label?.nilIfBlank,
                model: model?.nilIfBlank
            ),
            responseType: WorkspaceSessionCreateResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not create a chat session.")
        }
        guard response.sessionKey?.isEmpty == false || response.friendlyId?.isEmpty == false else {
            throw SSHTransportError.invalidResponse("Workspace API did not return a session key for the new chat session.")
        }
        return response
    }

    @discardableResult
    func sendWorkspaceSessionMessage(
        connection: ConnectionProfile,
        sessionKey: String,
        message: String,
        autoApproveCommands: Bool
    ) async throws -> WorkspaceSessionSendResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/session-send",
            body: WorkspaceSessionSendRequest(
                sessionKey: sessionKey,
                message: message,
                serverSide: true,
                autoApproveCommands: autoApproveCommands,
                idempotencyKey: UUID().uuidString
            ),
            responseType: WorkspaceSessionSendResponse.self
        )
        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API did not accept the chat message.")
        }
        return response
    }

    func loadWorkspaceSessionHistory(
        connection: ConnectionProfile,
        sessionKey: String,
        limit: Int = 200
    ) async throws -> WorkspaceSessionHistoryResponse {
        let path = apiPath(
            "/api/session-history",
            queryItems: [
                URLQueryItem(name: "key", value: sessionKey),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "includeTools", value: "true")
            ]
        )
        let response = try await loadJSON(
            connection: connection,
            path: path,
            responseType: WorkspaceSessionHistoryResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not load chat history.")
        }
        return response
    }

    func loadWorkspaceSessionActiveRun(
        connection: ConnectionProfile,
        sessionKey: String
    ) async throws -> WorkspaceSessionActiveRunResponse {
        let encodedSession = Self.pathSegment(sessionKey)
        let response = try await loadJSON(
            connection: connection,
            path: "/api/sessions/\(encodedSession)/active-run",
            responseType: WorkspaceSessionActiveRunResponse.self
        )
        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not load active run state.")
        }
        return response
    }

    func tailWorkspaceChatEvents(
        connection: ConnectionProfile,
        sessionKey: String,
        timeoutSeconds: Int = 8,
        maxEvents: Int = 80
    ) async throws -> WorkspaceChatEventsResponse {
        let path = apiPath(
            "/api/chat-events",
            queryItems: [URLQueryItem(name: "sessionKey", value: sessionKey)]
        )
        return try await requestChatEventTail(
            connection: connection,
            path: path,
            timeoutSeconds: timeoutSeconds,
            maxEvents: maxEvents
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

    @discardableResult
    func updateProfileOperationsConfig(
        connection: ConnectionProfile,
        name: String,
        model: String?,
        provider: String?,
        systemPrompt: String?,
        description: String?
    ) async throws -> CaelProfileMutationResponse {
        try await postJSON(
            connection: connection,
            path: "/api/profiles/update",
            body: CaelProfileOperationsUpdateRequest(
                name: name,
                patch: CaelProfileOperationsPatch(
                    model: model?.nilIfBlank,
                    provider: provider?.nilIfBlank,
                    systemPrompt: systemPrompt?.nilIfBlank,
                    description: description?.nilIfBlank
                )
            ),
            responseType: CaelProfileMutationResponse.self
        )
    }

    func listWorkspaceFiles(
        connection: ConnectionProfile,
        path filePath: String,
        maxDepth: Int = 0,
        maxEntries: Int = 500
    ) async throws -> RemoteDirectoryListing {
        let response = try await loadJSON(
            connection: connection,
            path: filesAPIPath(action: "list", path: filePath, maxDepth: maxDepth, maxEntries: maxEntries),
            responseType: CaelWorkspaceFilesListResponse.self
        )
        return response.remoteDirectoryListing(requestedPath: filePath)
    }

    func readWorkspaceFile(connection: ConnectionProfile, path filePath: String) async throws -> FileSnapshot {
        let response = try await loadJSON(
            connection: connection,
            path: filesAPIPath(action: "read", path: filePath),
            responseType: CaelWorkspaceFileReadResponse.self
        )
        guard response.type == "text" else {
            throw SSHTransportError.invalidResponse("Workspace API returned a non-text file. Open images and binary artifacts from the web fallback for now.")
        }
        guard let contentHash = response.contentHash, !contentHash.isEmpty else {
            throw SSHTransportError.invalidResponse("Workspace API did not return a content hash for \(filePath).")
        }
        return FileSnapshot(content: response.content, contentHash: contentHash)
    }

    @discardableResult
    func writeWorkspaceFile(
        connection: ConnectionProfile,
        path filePath: String,
        content: String,
        expectedContentHash: String?
    ) async throws -> FileSaveResult {
        let response = try await postJSON(
            connection: connection,
            path: "/api/files",
            body: CaelWorkspaceFileWriteRequest(
                action: "write",
                path: filePath,
                content: content,
                expectedContentHash: expectedContentHash
            ),
            responseType: CaelWorkspaceFileWriteResponse.self
        )
        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not save \(filePath).")
        }
        guard let contentHash = response.contentHash, !contentHash.isEmpty else {
            throw SSHTransportError.invalidResponse("Workspace API did not return a saved content hash for \(filePath).")
        }
        return FileSaveResult(path: response.path ?? filePath, contentHash: contentHash)
    }

    @discardableResult
    func makeWorkspaceDirectory(connection: ConnectionProfile, path directoryPath: String) async throws -> String {
        let response = try await postJSON(
            connection: connection,
            path: "/api/files",
            body: CaelWorkspaceFileMutationRequest(
                action: "mkdir",
                path: directoryPath,
                from: nil,
                to: nil
            ),
            responseType: CaelWorkspaceFileMutationResponse.self
        )
        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not create \(directoryPath).")
        }
        return response.path ?? directoryPath
    }

    @discardableResult
    func renameWorkspacePath(connection: ConnectionProfile, from sourcePath: String, to destinationPath: String) async throws -> String {
        let response = try await postJSON(
            connection: connection,
            path: "/api/files",
            body: CaelWorkspaceFileMutationRequest(
                action: "rename",
                path: nil,
                from: sourcePath,
                to: destinationPath
            ),
            responseType: CaelWorkspaceFileMutationResponse.self
        )
        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not rename \(sourcePath).")
        }
        return response.path ?? destinationPath
    }

    func deleteWorkspacePath(connection: ConnectionProfile, path targetPath: String) async throws {
        let response = try await postJSON(
            connection: connection,
            path: "/api/files",
            body: CaelWorkspaceFileMutationRequest(
                action: "delete",
                path: targetPath,
                from: nil,
                to: nil
            ),
            responseType: CaelWorkspaceFileMutationResponse.self
        )
        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not delete \(targetPath).")
        }
    }

    @discardableResult
    func uploadWorkspaceFile(
        connection: ConnectionProfile,
        targetPath: String,
        fileName: String,
        contentBase64: String
    ) async throws -> WorkspaceFileUploadResult {
        let response = try await postJSON(
            connection: connection,
            path: "/api/files",
            body: CaelWorkspaceFileUploadRequest(
                action: "uploadBase64",
                path: targetPath,
                fileName: fileName,
                contentBase64: contentBase64
            ),
            responseType: WorkspaceFileUploadResult.self
        )
        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not upload \(fileName).")
        }
        return response
    }

    func loadPreviewFile(connection: ConnectionProfile, path filePath: String) async throws -> WorkspacePreviewFile {
        let response = try await loadJSON(
            connection: connection,
            path: previewFileAPIPath(path: filePath),
            responseType: WorkspacePreviewFile.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse("Workspace API could not preview \(filePath).")
        }
        return response
    }

    func loadToolArtifacts(connection: ConnectionProfile, sessionId: String? = nil, limit: Int = 100) async throws -> [ToolArtifactSummary] {
        let response = try await loadJSON(
            connection: connection,
            path: artifactsAPIPath(sessionId: sessionId, limit: limit),
            responseType: ToolArtifactsListResponse.self
        )
        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not load tool artifacts.")
        }
        return response.artifacts
    }

    func loadToolArtifact(connection: ConnectionProfile, id artifactId: String) async throws -> ToolArtifactDetail {
        let encodedId = artifactId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? artifactId
        let response = try await loadJSON(
            connection: connection,
            path: "/api/artifacts/\(encodedId)",
            responseType: ToolArtifactDetailResponse.self
        )
        guard response.ok, let artifact = response.artifact else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not load artifact \(artifactId).")
        }
        return artifact
    }

    func loadWorkspaceTasks(connection: ConnectionProfile, includeDone: Bool = false) async throws -> [WorkspaceTask] {
        let includeDoneValue = includeDone ? "true" : "false"
        let response = try await loadJSON(
            connection: connection,
            path: "/api/hermes-tasks?include_done=\(includeDoneValue)",
            responseType: WorkspaceTasksResponse.self
        )
        return response.tasks
    }

    @discardableResult
    func createWorkspaceTask(connection: ConnectionProfile, draft: KanbanTaskDraft) async throws -> WorkspaceTask {
        let response = try await postJSON(
            connection: connection,
            path: "/api/hermes-tasks",
            body: WorkspaceTaskCreateRequest(
                title: draft.normalizedTitle,
                description: draft.normalizedBody ?? "",
                column: draft.startsInTriage ? .backlog : .todo,
                priority: WorkspaceTaskPriority.fromKanbanPriority(draft.priority),
                assignee: draft.normalizedAssignee,
                tags: draft.skills,
                dueDate: nil,
                createdBy: connection.resolvedHermesProfileName
            ),
            responseType: WorkspaceTaskMutationResponse.self
        )
        guard let task = response.task else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API did not return a created task.")
        }
        return task
    }

    @discardableResult
    func updateWorkspaceTask(
        connection: ConnectionProfile,
        taskID: String,
        title: String? = nil,
        description: String? = nil,
        column: WorkspaceTaskColumn? = nil,
        priority: WorkspaceTaskPriority? = nil,
        assignee: String? = nil,
        tags: [String]? = nil
    ) async throws -> WorkspaceTask {
        let response = try await patchJSON(
            connection: connection,
            path: "/api/hermes-tasks/\(taskID)",
            body: WorkspaceTaskUpdateRequest(
                title: title,
                description: description,
                column: column,
                priority: priority,
                assignee: assignee,
                tags: tags
            ),
            responseType: WorkspaceTaskMutationResponse.self
        )
        guard let task = response.task else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API did not return an updated task.")
        }
        return task
    }

    @discardableResult
    func moveWorkspaceTask(connection: ConnectionProfile, taskID: String, column: WorkspaceTaskColumn) async throws -> WorkspaceTask {
        let response = try await postJSON(
            connection: connection,
            path: "/api/hermes-tasks/\(taskID)?action=move",
            body: WorkspaceTaskMoveRequest(column: column, movedBy: "cael-desktop"),
            responseType: WorkspaceTaskMutationResponse.self
        )
        guard let task = response.task else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API did not return a moved task.")
        }
        return task
    }

    @discardableResult
    func linkWorkspaceTaskSession(connection: ConnectionProfile, taskID: String, sessionID: String?) async throws -> WorkspaceTask {
        let response = try await patchJSON(
            connection: connection,
            path: "/api/hermes-tasks/\(taskID)",
            body: WorkspaceTaskSessionLinkRequest(sessionID: sessionID),
            responseType: WorkspaceTaskMutationResponse.self
        )
        guard let task = response.task else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API did not return a linked task.")
        }
        return task
    }

    @discardableResult
    func launchWorkspaceTaskSession(connection: ConnectionProfile, taskID: String) async throws -> WorkspaceTaskLaunchResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/hermes-tasks/\(taskID)?action=launch",
            body: WorkspaceEmptyRequest(),
            responseType: WorkspaceTaskLaunchResponse.self
        )
        guard response.error == nil else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not launch this task.")
        }
        guard response.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw SSHTransportError.invalidResponse("Workspace API did not return a task session id.")
        }
        return response
    }

    func deleteWorkspaceTask(connection: ConnectionProfile, taskID: String) async throws {
        let response = try await deleteJSON(
            connection: connection,
            path: "/api/hermes-tasks/\(taskID)",
            responseType: WorkspaceTaskDeleteResponse.self
        )
        guard response.ok == true else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API does not support deleting this shared task.")
        }
    }

    func loadWorkspaceCronJobs(connection: ConnectionProfile) async throws -> [CronJob] {
        let response = try await loadJSON(
            connection: connection,
            path: "/api/claude-jobs?include_disabled=true&profiles=all",
            responseType: CronJobListResponse.self
        )
        return response.jobs
    }

    @discardableResult
    func createWorkspaceCronJob(connection: ConnectionProfile, draft: CronJobDraft) async throws -> CronJobMutationResult {
        let response = try await postJSON(
            connection: connection,
            path: "/api/claude-jobs",
            body: WorkspaceCronJobMutationRequest(connection: connection, draft: draft),
            responseType: WorkspaceCronJobMutationResponse.self
        )
        guard response.ok != false else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not create the cron job.")
        }
        return CronJobMutationResult(jobID: response.jobID ?? response.job?.id, job: response.job)
    }

    @discardableResult
    func updateWorkspaceCronJob(connection: ConnectionProfile, jobID: String, draft: CronJobDraft) async throws -> CronJobMutationResult {
        let response = try await patchJSON(
            connection: connection,
            path: "/api/claude-jobs/\(Self.pathSegment(jobID))",
            body: WorkspaceCronJobMutationRequest(connection: connection, draft: draft),
            responseType: WorkspaceCronJobMutationResponse.self
        )
        guard response.ok != false else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not update the cron job.")
        }
        return CronJobMutationResult(jobID: response.jobID ?? response.job?.id ?? jobID, job: response.job)
    }

    func pauseWorkspaceCronJob(connection: ConnectionProfile, jobID: String) async throws {
        try await runWorkspaceCronJobAction(connection: connection, jobID: jobID, action: "pause")
    }

    func resumeWorkspaceCronJob(connection: ConnectionProfile, jobID: String) async throws {
        try await runWorkspaceCronJobAction(connection: connection, jobID: jobID, action: "resume")
    }

    func triggerWorkspaceCronJob(connection: ConnectionProfile, jobID: String) async throws {
        try await runWorkspaceCronJobAction(connection: connection, jobID: jobID, action: "run")
    }

    func deleteWorkspaceCronJob(connection: ConnectionProfile, jobID: String) async throws {
        let response = try await deleteJSON(
            connection: connection,
            path: "/api/claude-jobs/\(Self.pathSegment(jobID))",
            responseType: WorkspaceCronJobMutationResponse.self
        )
        guard response.ok != false else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not remove the cron job.")
        }
    }

    func loadWorkspaceCronJobOutputs(connection: ConnectionProfile, jobID: String, limit: Int = 10) async throws -> [CronJobOutput] {
        let boundedLimit = max(1, min(limit, 50))
        let response = try await loadJSON(
            connection: connection,
            path: "/api/claude-jobs/\(Self.pathSegment(jobID))?action=output&limit=\(boundedLimit)",
            responseType: CronJobOutputResponse.self
        )
        guard response.ok != false else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not load cron job output.")
        }
        return response.outputs
    }

    private func runWorkspaceCronJobAction(connection: ConnectionProfile, jobID: String, action: String) async throws {
        let response = try await postJSON(
            connection: connection,
            path: "/api/claude-jobs/\(Self.pathSegment(jobID))?action=\(action)",
            body: WorkspaceEmptyRequest(),
            responseType: WorkspaceCronJobMutationResponse.self
        )
        guard response.ok != false else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API could not run cron action \(action).")
        }
    }

    func loadKnowledgeFabricHealth(connection: ConnectionProfile) async throws -> KnowledgeFabricHealthResponse {
        try await loadJSON(
            connection: connection,
            path: "/api/knowledge/fabric/health",
            responseType: KnowledgeFabricHealthResponse.self
        )
    }

    func searchKnowledgeFabric(
        connection: ConnectionProfile,
        query: String,
        scope: String,
        mode: String,
        agentSource: String? = nil
    ) async throws -> KnowledgeFabricSearchResponse {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            throw SSHTransportError.invalidResponse("Knowledge Fabric search query is required.")
        }

        if scope == "both" {
            async let business: KnowledgeFabricScopedResult? = try? await searchKnowledgeFabricScope(
                connection: connection,
                query: normalizedQuery,
                scope: "business",
                mode: mode,
                agentSource: agentSource
            ).scopedResults.first?.withFallbackScope("business")
            async let personal: KnowledgeFabricScopedResult? = try? await searchKnowledgeFabricScope(
                connection: connection,
                query: normalizedQuery,
                scope: "personal",
                mode: mode,
                agentSource: agentSource
            ).scopedResults.first?.withFallbackScope("personal")

            let results = await (business, personal)
            return KnowledgeFabricSearchResponse(
                ok: results.0 != nil || results.1 != nil,
                endpoint: nil,
                memoryScope: nil,
                data: nil,
                scopes: KnowledgeFabricScopedResults(business: results.0, personal: results.1),
                error: results.0 == nil && results.1 == nil ? "Both Knowledge Fabric scopes failed." : nil
            )
        }

        return try await searchKnowledgeFabricScope(
            connection: connection,
            query: normalizedQuery,
            scope: scope,
            mode: mode,
            agentSource: agentSource
        )
    }

    func lookupKnowledgeFabricDocument(
        connection: ConnectionProfile,
        docID: String,
        scope: String
    ) async throws -> KnowledgeFabricSearchResponse {
        let normalizedDocID = docID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDocID.isEmpty else {
            throw SSHTransportError.invalidResponse("Knowledge Fabric document id is required.")
        }

        if scope == "both" {
            async let business: KnowledgeFabricScopedResult? = try? await lookupKnowledgeFabricDocumentScope(
                connection: connection,
                docID: normalizedDocID,
                scope: "business"
            ).scopedResults.first?.withFallbackScope("business")
            async let personal: KnowledgeFabricScopedResult? = try? await lookupKnowledgeFabricDocumentScope(
                connection: connection,
                docID: normalizedDocID,
                scope: "personal"
            ).scopedResults.first?.withFallbackScope("personal")

            let results = await (business, personal)
            return KnowledgeFabricSearchResponse(
                ok: results.0 != nil || results.1 != nil,
                endpoint: nil,
                memoryScope: nil,
                data: nil,
                scopes: KnowledgeFabricScopedResults(business: results.0, personal: results.1),
                error: results.0 == nil && results.1 == nil ? "Both Knowledge Fabric document lookups failed." : nil
            )
        }

        return try await lookupKnowledgeFabricDocumentScope(
            connection: connection,
            docID: normalizedDocID,
            scope: scope
        )
    }

    func recordKnowledgeFabricSessionState(
        connection: ConnectionProfile,
        summary: String,
        memoryScope: String,
        agentSource: String?,
        sessionId: String?,
        project: String?
    ) async throws -> KnowledgeFabricSessionStateResponse {
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSummary.isEmpty else {
            throw SSHTransportError.invalidResponse("Knowledge Fabric session-state summary is required.")
        }
        let response = try await postJSON(
            connection: connection,
            path: "/api/knowledge/fabric/session-state",
            body: KnowledgeFabricSessionStateRequest(
                summary: normalizedSummary,
                memoryScope: memoryScope,
                agentSource: agentSource?.nilIfBlank,
                sessionId: sessionId?.nilIfBlank,
                project: project?.nilIfBlank,
                metadata: [
                    "client": "Cael Desktop",
                    "surface": "native-knowledge-fabric-panel"
                ]
            ),
            responseType: KnowledgeFabricSessionStateResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "Knowledge Fabric session-state write failed.")
        }
        return response
    }


    func listMemoryFiles(connection: ConnectionProfile) async throws -> WorkspaceMemoryListResponse {
        try await loadJSON(connection: connection, path: "/api/memory/list", responseType: WorkspaceMemoryListResponse.self)
    }

    func readMemoryFile(connection: ConnectionProfile, path filePath: String) async throws -> WorkspaceMemoryReadResponse {
        try await loadJSON(
            connection: connection,
            path: apiPath("/api/memory/read", queryItems: [URLQueryItem(name: "path", value: filePath)]),
            responseType: WorkspaceMemoryReadResponse.self
        )
    }

    func searchMemoryFiles(connection: ConnectionProfile, query: String) async throws -> WorkspaceMemorySearchResponse {
        try await loadJSON(
            connection: connection,
            path: apiPath("/api/memory/search", queryItems: [URLQueryItem(name: "q", value: query)]),
            responseType: WorkspaceMemorySearchResponse.self
        )
    }

    func listKnowledgePages(connection: ConnectionProfile) async throws -> WorkspaceKnowledgeListResponse {
        try await loadJSON(connection: connection, path: "/api/knowledge/list", responseType: WorkspaceKnowledgeListResponse.self)
    }

    func readKnowledgePage(connection: ConnectionProfile, path pagePath: String) async throws -> WorkspaceKnowledgeReadResponse {
        try await loadJSON(
            connection: connection,
            path: apiPath("/api/knowledge/read", queryItems: [URLQueryItem(name: "path", value: pagePath)]),
            responseType: WorkspaceKnowledgeReadResponse.self
        )
    }

    func searchKnowledgePages(connection: ConnectionProfile, query: String) async throws -> WorkspaceKnowledgeSearchResponse {
        try await loadJSON(
            connection: connection,
            path: apiPath("/api/knowledge/search", queryItems: [URLQueryItem(name: "q", value: query)]),
            responseType: WorkspaceKnowledgeSearchResponse.self
        )
    }

    func listSecondBrainSources(connection: ConnectionProfile) async throws -> WorkspaceSecondBrainSourcesResponse {
        try await loadJSON(connection: connection, path: "/api/second-brain/sources", responseType: WorkspaceSecondBrainSourcesResponse.self)
    }

    func listSecondBrainEntries(connection: ConnectionProfile, source: String, path folderPath: String) async throws -> WorkspaceSecondBrainListResponse {
        try await loadJSON(
            connection: connection,
            path: apiPath(
                "/api/second-brain/list",
                queryItems: [
                    URLQueryItem(name: "source", value: source),
                    URLQueryItem(name: "path", value: folderPath)
                ]
            ),
            responseType: WorkspaceSecondBrainListResponse.self
        )
    }

    func readSecondBrainFile(connection: ConnectionProfile, source: String, path filePath: String) async throws -> WorkspaceSecondBrainReadResponse {
        try await loadJSON(
            connection: connection,
            path: apiPath(
                "/api/second-brain/read",
                queryItems: [
                    URLQueryItem(name: "source", value: source),
                    URLQueryItem(name: "path", value: filePath)
                ]
            ),
            responseType: WorkspaceSecondBrainReadResponse.self
        )
    }

    @discardableResult
    func writeSecondBrainFile(
        connection: ConnectionProfile,
        source: String,
        path filePath: String,
        content: String,
        expectedHash: String
    ) async throws -> WorkspaceSecondBrainWriteResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/second-brain/write",
            body: WorkspaceSecondBrainWriteRequest(
                source: source,
                path: filePath,
                content: content,
                expectedHash: expectedHash
            ),
            responseType: WorkspaceSecondBrainWriteResponse.self
        )
        guard response.ok != false else {
            throw SSHTransportError.invalidResponse(response.error ?? "Second Brain write failed.")
        }
        return response
    }

    @discardableResult
    func dispatchSecondBrainWorkflow(
        connection: ConnectionProfile,
        source: String,
        path filePath: String?,
        operation: String,
        hash: String?
    ) async throws -> WorkspaceSecondBrainDispatchResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/second-brain/dispatch",
            body: WorkspaceSecondBrainDispatchRequest(
                source: source,
                path: filePath,
                operation: operation,
                hash: hash
            ),
            responseType: WorkspaceSecondBrainDispatchResponse.self
        )
        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.error ?? "Second Brain dispatch failed.")
        }
        return response
    }

    private func searchKnowledgeFabricScope(
        connection: ConnectionProfile,
        query: String,
        scope: String,
        mode: String,
        agentSource: String?
    ) async throws -> KnowledgeFabricSearchResponse {
        let endpoint = mode == "agent" ? "/api/knowledge/fabric/agent-search" : "/api/knowledge/fabric/search"
        return try await postJSON(
            connection: connection,
            path: endpoint,
            body: KnowledgeFabricSearchRequest(
                query: query,
                memoryScope: scope,
                mode: mode == "agent" ? nil : "local",
                maxResults: 8,
                agentSource: agentSource?.nilIfBlank
            ),
            responseType: KnowledgeFabricSearchResponse.self
        )
    }

    private func lookupKnowledgeFabricDocumentScope(
        connection: ConnectionProfile,
        docID: String,
        scope: String
    ) async throws -> KnowledgeFabricSearchResponse {
        try await postJSON(
            connection: connection,
            path: "/api/knowledge/fabric/document-record",
            body: KnowledgeFabricDocumentRequest(docId: docID, memoryScope: scope),
            responseType: KnowledgeFabricSearchResponse.self
        )
    }


    private func apiPath(_ path: String, queryItems: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.string ?? path
    }

    func loadSwarmHealth(connection: ConnectionProfile) async throws -> WorkspaceSwarmHealthResponse {
        try await loadJSON(connection: connection, path: "/api/swarm-health", responseType: WorkspaceSwarmHealthResponse.self)
    }

    func loadSwarmRuntime(connection: ConnectionProfile) async throws -> WorkspaceSwarmRuntimeResponse {
        try await loadJSON(connection: connection, path: "/api/swarm-runtime", responseType: WorkspaceSwarmRuntimeResponse.self)
    }

    func loadSwarmMissions(connection: ConnectionProfile, limit: Int = 8) async throws -> WorkspaceSwarmMissionsResponse {
        try await loadJSON(
            connection: connection,
            path: apiPath("/api/swarm-missions", queryItems: [URLQueryItem(name: "limit", value: String(limit))]),
            responseType: WorkspaceSwarmMissionsResponse.self
        )
    }

    @discardableResult
    func startSwarmWorkerTmux(connection: ConnectionProfile, workerID: String) async throws -> WorkspaceSwarmWorkerMutationResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/swarm-tmux-start",
            body: WorkspaceSwarmWorkerRequest(workerId: workerID),
            responseType: WorkspaceSwarmWorkerMutationResponse.self
        )
        if let error = response.error?.nilIfBlank {
            throw SSHTransportError.invalidResponse(error)
        }
        return response
    }

    @discardableResult
    func stopSwarmWorkerTmux(connection: ConnectionProfile, workerID: String) async throws -> WorkspaceSwarmWorkerMutationResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/swarm-tmux-stop",
            body: WorkspaceSwarmWorkerRequest(workerId: workerID),
            responseType: WorkspaceSwarmWorkerMutationResponse.self
        )
        if let error = response.error?.nilIfBlank {
            throw SSHTransportError.invalidResponse(error)
        }
        return response
    }

    @discardableResult
    func dispatchSwarmPrompt(
        connection: ConnectionProfile,
        workerID: String,
        prompt: String,
        timeoutSeconds: Int = 60,
        allowAsync: Bool = false
    ) async throws -> WorkspaceSwarmDispatchResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/swarm-dispatch",
            body: WorkspaceSwarmDispatchRequest(
                workerIds: [workerID],
                prompt: prompt,
                timeoutSeconds: timeoutSeconds,
                allowAsync: allowAsync
            ),
            responseType: WorkspaceSwarmDispatchResponse.self
        )
        if let error = response.error?.nilIfBlank {
            throw SSHTransportError.invalidResponse(error)
        }
        return response
    }

    @discardableResult
    func spawnConductorMission(
        connection: ConnectionProfile,
        goal: String,
        orchestratorModel: String? = nil,
        workerModel: String? = nil,
        projectsDir: String? = nil,
        maxParallel: Int = 1,
        supervised: Bool = false
    ) async throws -> WorkspaceConductorSpawnResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/conductor-spawn",
            body: WorkspaceConductorSpawnRequest(
                goal: goal,
                orchestratorModel: orchestratorModel?.nilIfBlank,
                workerModel: workerModel?.nilIfBlank,
                projectsDir: projectsDir?.nilIfBlank,
                maxParallel: maxParallel,
                supervised: supervised
            ),
            responseType: WorkspaceConductorSpawnResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "Conductor mission launch failed.")
        }
        return response
    }

    func loadConductorMission(connection: ConnectionProfile, missionID: String, lines: Int = 400) async throws -> WorkspaceConductorMissionResponse {
        let response = try await loadJSON(
            connection: connection,
            path: apiPath("/api/conductor-spawn", queryItems: [
                URLQueryItem(name: "missionId", value: missionID),
                URLQueryItem(name: "lines", value: String(lines))
            ]),
            responseType: WorkspaceConductorMissionResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "Conductor mission status unavailable.")
        }
        return response
    }

    @discardableResult
    func stopConductorMission(
        connection: ConnectionProfile,
        missionIDs: [String],
        sessionKeys: [String] = []
    ) async throws -> WorkspaceConductorStopResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/conductor-stop",
            body: WorkspaceConductorStopRequest(sessionKeys: sessionKeys, missionIds: missionIDs),
            responseType: WorkspaceConductorStopResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "Conductor stop failed.")
        }
        return response
    }


    func listMCPServers(connection: ConnectionProfile, search: String = "", category: String = "All") async throws -> WorkspaceMCPListResponse {
        var queryItems: [URLQueryItem] = []
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if category != "All" {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        let path = queryItems.isEmpty ? "/api/mcp" : apiPath("/api/mcp", queryItems: queryItems)
        return try await loadJSON(connection: connection, path: path, responseType: WorkspaceMCPListResponse.self)
    }

    func testMCPServer(connection: ConnectionProfile, name: String) async throws -> WorkspaceMCPTestResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/mcp/test",
            body: WorkspaceMCPTestRequest(name: name),
            responseType: WorkspaceMCPTestResponse.self
        )
        guard response.ok || !response.status.isEmpty else {
            throw SSHTransportError.invalidResponse(response.error ?? "MCP test failed.")
        }
        return response
    }

    func discoverMCPServer(connection: ConnectionProfile, server: WorkspaceMCPServer) async throws -> WorkspaceMCPDiscoverResponse {
        guard let command = server.command?.nilIfBlank else {
            throw SSHTransportError.invalidResponse("MCP discovery currently supports command-backed servers only.")
        }
        let response = try await postJSON(
            connection: connection,
            path: "/api/mcp/discover",
            body: WorkspaceMCPCreateRequest(
                name: server.name,
                enabled: server.enabled,
                transportType: server.transportType,
                command: command,
                args: server.args,
                authType: server.authType,
                toolMode: server.toolMode
            ),
            responseType: WorkspaceMCPDiscoverResponse.self
        )
        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.error ?? "MCP discover failed.")
        }
        return response
    }

    func loadMCPServerLogs(connection: ConnectionProfile, name: String, maxLines: Int = 80) async throws -> WorkspaceMCPLogsResponse {
        let encodedName = Self.pathSegment(name)
        return try await requestMCPLogTail(
            connection: connection,
            path: "/api/mcp/\(encodedName)/logs",
            maxLines: max(1, min(maxLines, 200))
        )
    }

    func loadMCPHubSources(connection: ConnectionProfile) async throws -> WorkspaceMCPHubSourcesResponse {
        try await loadJSON(connection: connection, path: "/api/mcp/hub-sources", responseType: WorkspaceMCPHubSourcesResponse.self)
    }

    func loadMCPPresets(connection: ConnectionProfile) async throws -> WorkspaceMCPPresetsResponse {
        try await loadJSON(connection: connection, path: "/api/mcp/presets", responseType: WorkspaceMCPPresetsResponse.self)
    }

    func searchMCPHub(connection: ConnectionProfile, query: String, limit: Int = 12) async throws -> WorkspaceMCPHubSearchResponse {
        let queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "source", value: "all"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await loadJSON(
            connection: connection,
            path: apiPath("/api/mcp/hub-search", queryItems: queryItems),
            responseType: WorkspaceMCPHubSearchResponse.self
        )
    }

    @discardableResult
    func createMCPCommandServer(
        connection: ConnectionProfile,
        name: String,
        command: String,
        args: [String],
        enabled: Bool
    ) async throws -> WorkspaceMCPMutationResponse {
        let response = try await postJSON(
            connection: connection,
            path: "/api/mcp",
            body: WorkspaceMCPCreateRequest(
                name: name,
                enabled: enabled,
                transportType: "stdio",
                command: command,
                args: args,
                authType: "none",
                toolMode: "all"
            ),
            responseType: WorkspaceMCPMutationResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "MCP create failed.")
        }
        return response
    }

    @discardableResult
    func configureMCPServer(
        connection: ConnectionProfile,
        name: String,
        enabled: Bool? = nil,
        toolMode: String? = nil,
        includeTools: [String]? = nil,
        excludeTools: [String]? = nil
    ) async throws -> WorkspaceMCPMutationResponse {
        let response = try await putJSON(
            connection: connection,
            path: "/api/mcp/configure",
            body: WorkspaceMCPConfigureRequest(
                name: name,
                enabled: enabled,
                toolMode: toolMode,
                includeTools: includeTools,
                excludeTools: excludeTools
            ),
            responseType: WorkspaceMCPMutationResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "MCP configure failed.")
        }
        return response
    }

    @discardableResult
    func deleteMCPServer(connection: ConnectionProfile, name: String) async throws -> WorkspaceMCPMutationResponse {
        let encodedName = Self.pathSegment(name)
        let response = try await deleteJSON(
            connection: connection,
            path: "/api/mcp/\(encodedName)",
            responseType: WorkspaceMCPMutationResponse.self
        )
        if response.ok == false {
            throw SSHTransportError.invalidResponse(response.error ?? "MCP delete failed.")
        }
        return response
    }

    private func filesAPIPath(action: String, path filePath: String, maxDepth: Int? = nil, maxEntries: Int? = nil) -> String {
        var components = URLComponents()
        components.path = "/api/files"
        var queryItems = [
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "path", value: filePath)
        ]
        if let maxDepth {
            queryItems.append(URLQueryItem(name: "maxDepth", value: String(maxDepth)))
        }
        if let maxEntries {
            queryItems.append(URLQueryItem(name: "maxEntries", value: String(maxEntries)))
        }
        components.queryItems = queryItems
        return components.string ?? "/api/files"
    }

    private func artifactsAPIPath(sessionId: String?, limit: Int) -> String {
        var components = URLComponents()
        components.path = "/api/artifacts"
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let sessionId, !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "sessionId", value: sessionId))
        }
        components.queryItems = queryItems
        return components.string ?? "/api/artifacts"
    }

    private func previewFileAPIPath(path filePath: String) -> String {
        var components = URLComponents()
        components.path = "/api/preview-file"
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "path", value: filePath)
        ]
        return components.string ?? "/api/preview-file"
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

    private func patchJSON<Body: Encodable, Response: Decodable>(
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
            method: "PATCH",
            body: bodyString,
            responseType: responseType
        )
    }

    private func putJSON<Body: Encodable, Response: Decodable>(
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
            method: "PUT",
            body: bodyString,
            responseType: responseType
        )
    }

    private func deleteJSON<Response: Decodable>(
        connection: ConnectionProfile,
        path: String,
        responseType: Response.Type
    ) async throws -> Response {
        try await requestJSON(connection: connection, path: path, method: "DELETE", body: nil, responseType: responseType)
    }

    private func requestMCPLogTail(
        connection: ConnectionProfile,
        path: String,
        maxLines: Int
    ) async throws -> WorkspaceMCPLogsResponse {
        let payload = try JSONEncoder().encode(CaelWorkspaceMCPLogRequest(
            baseURL: connection.resolvedCaelWorkspaceBaseURL,
            path: path,
            hermesHome: connection.remoteHermesHomePath,
            maxLines: maxLines,
            timeoutSeconds: 6
        ))
        let requestLiteral = String(data: payload, encoding: .utf8) ?? "{}"
        let script = """
        import json
        import pathlib
        import secrets
        import socket
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
        headers = {
            "Accept": "text/event-stream, application/json",
            "Cookie": "claude-auth=" + token,
            "User-Agent": "CaelDesktop/1.0 native-api",
        }
        http_request = urllib.request.Request(url, headers=headers, method="GET")
        max_lines = int(request.get("maxLines") or 80)
        timeout_seconds = float(request.get("timeoutSeconds") or 6)
        deadline = time.time() + timeout_seconds
        lines = []
        event_name = None

        try:
            with urllib.request.urlopen(http_request, timeout=timeout_seconds) as response:
                content_type = response.headers.get("content-type", "")
                if "application/json" in content_type:
                    body = response.read().decode("utf-8", "replace")
                    data = json.loads(body) if body.strip() else {}
                    data.setdefault("lines", [])
                    print(json.dumps(data))
                    sys.exit(0)

                while len(lines) < max_lines and time.time() < deadline:
                    try:
                        raw = response.readline()
                    except socket.timeout:
                        break
                    if not raw:
                        break
                    line = raw.decode("utf-8", "replace").rstrip("\\r\\n")
                    if line.startswith("event:"):
                        event_name = line.split(":", 1)[1].strip()
                        continue
                    if line.startswith("data:"):
                        payload_text = line.split(":", 1)[1].strip()
                        try:
                            payload = json.loads(payload_text)
                        except Exception:
                            payload = {"line": payload_text}
                        if event_name == "log":
                            log_line = str(payload.get("line", "")).strip()
                            if log_line:
                                lines.append(log_line)
                        elif event_name == "error":
                            error_message = payload.get("message") or payload_text
                            print(json.dumps({"ok": False, "lines": lines, "error": str(error_message)}))
                            sys.exit(0)
                print(json.dumps({"ok": True, "lines": lines}))
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", "replace")
            try:
                payload = json.loads(body)
            except Exception:
                payload = {"error": body}
            print(json.dumps({
                "ok": False,
                "lines": [],
                "error": "HTTP %s: %s" % (error.code, payload.get("error") or body),
            }))
        except Exception as error:
            print(json.dumps({"ok": False, "lines": lines, "error": str(error)}))
        """

        let result = try await sshTransport.execute(
            on: connection,
            remoteCommand: connection.remoteServiceCommand("python3 -"),
            standardInput: Data(script.utf8),
            allocateTTY: false
        )
        try sshTransport.validateSuccessfulExit(result, for: connection)

        guard let data = result.stdout.data(using: .utf8) else {
            throw SSHTransportError.invalidResponse("Workspace MCP logs output was not valid UTF-8.")
        }

        do {
            return try Self.makeDecoder().decode(WorkspaceMCPLogsResponse.self, from: data)
        } catch {
            throw SSHTransportError.invalidResponse(
                "Workspace MCP logs returned JSON that Cael Desktop could not decode: \(error.localizedDescription)"
            )
        }
    }

    private func requestChatEventTail(
        connection: ConnectionProfile,
        path: String,
        timeoutSeconds: Int,
        maxEvents: Int
    ) async throws -> WorkspaceChatEventsResponse {
        let payload = try JSONEncoder().encode(CaelWorkspaceChatEventsRequest(
            baseURL: connection.resolvedCaelWorkspaceBaseURL,
            path: path,
            hermesHome: connection.remoteHermesHomePath,
            timeoutSeconds: max(1, timeoutSeconds),
            maxEvents: max(1, maxEvents)
        ))
        let requestLiteral = String(data: payload, encoding: .utf8) ?? "{}"
        let script = """
        import json
        import pathlib
        import secrets
        import socket
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
        headers = {
            "Accept": "text/event-stream, application/json",
            "Cookie": "claude-auth=" + token,
            "User-Agent": "CaelDesktop/1.0 native-api",
        }
        http_request = urllib.request.Request(url, headers=headers, method="GET")
        max_events = int(request.get("maxEvents") or 80)
        timeout_seconds = float(request.get("timeoutSeconds") or 8)
        deadline = time.time() + timeout_seconds
        events = []
        event_name = None
        data_lines = []

        def flush_event():
            global event_name, data_lines
            if not event_name:
                data_lines = []
                return
            payload_text = "\\n".join(data_lines).strip()
            data_lines = []
            name = event_name
            event_name = None
            if not payload_text:
                return
            try:
                payload = json.loads(payload_text)
            except Exception:
                payload = {"raw": payload_text}
            if name == "heartbeat":
                return
            events.append({"event": name, "data": payload if isinstance(payload, dict) else {"value": payload}})

        try:
            with urllib.request.urlopen(http_request, timeout=timeout_seconds) as response:
                content_type = response.headers.get("content-type", "")
                if "application/json" in content_type:
                    body = response.read().decode("utf-8", "replace")
                    data = json.loads(body) if body.strip() else {}
                    data.setdefault("events", [])
                    print(json.dumps(data))
                    sys.exit(0)

                while len(events) < max_events and time.time() < deadline:
                    try:
                        raw = response.readline()
                    except socket.timeout:
                        break
                    if not raw:
                        break
                    line = raw.decode("utf-8", "replace").rstrip("\\r\\n")
                    if line == "":
                        flush_event()
                        continue
                    if line.startswith(":"):
                        continue
                    if line.startswith("event:"):
                        event_name = line.split(":", 1)[1].strip()
                        continue
                    if line.startswith("data:"):
                        data_lines.append(line.split(":", 1)[1].strip())
                flush_event()
                print(json.dumps({"ok": True, "events": events}))
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", "replace")
            try:
                payload = json.loads(body)
            except Exception:
                payload = {"error": body}
            print(json.dumps({
                "ok": False,
                "events": events,
                "error": "HTTP %s: %s" % (error.code, payload.get("error") or body),
            }))
        except Exception as error:
            print(json.dumps({"ok": False, "events": events, "error": str(error)}))
        """

        let result = try await sshTransport.execute(
            on: connection,
            remoteCommand: connection.remoteServiceCommand("python3 -"),
            standardInput: Data(script.utf8),
            allocateTTY: false
        )
        try sshTransport.validateSuccessfulExit(result, for: connection)

        guard let data = result.stdout.data(using: .utf8) else {
            throw SSHTransportError.invalidResponse("Workspace chat events output was not valid UTF-8.")
        }

        do {
            return try Self.makeDecoder().decode(WorkspaceChatEventsResponse.self, from: data)
        } catch {
            throw SSHTransportError.invalidResponse(
                "Workspace chat events returned JSON that Cael Desktop could not decode: \(error.localizedDescription)"
            )
        }
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
            with urllib.request.urlopen(http_request, timeout=20) as response:
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
            return try Self.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw SSHTransportError.invalidResponse(
                "Workspace API returned JSON that Cael Desktop could not decode: \(error.localizedDescription)"
            )
        }
    }

    private static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.fractionalSecondsFormatter().date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }
}

private struct CaelWorkspaceAPIRequest: Encodable {
    let baseURL: String
    let path: String
    let hermesHome: String
    let method: String
    let body: String?
}

private struct CaelWorkspaceMCPLogRequest: Encodable {
    let baseURL: String
    let path: String
    let hermesHome: String
    let maxLines: Int
    let timeoutSeconds: Int
}

private struct CaelWorkspaceChatEventsRequest: Encodable {
    let baseURL: String
    let path: String
    let hermesHome: String
    let timeoutSeconds: Int
    let maxEvents: Int
}

private struct WorkspaceSkillActionRequest: Encodable {
    let action: String
    let identifier: String
    let name: String
    let category: String?
    let force: Bool
    let enabled: Bool?
}

private struct EmptyWorkspaceAPIRequest: Encodable {}

private struct WorkspaceHermesSetDefaultModelRequest: Encodable {
    let action: String
    let providerID: String
    let modelID: String

    enum CodingKeys: String, CodingKey {
        case action
        case providerID = "providerId"
        case modelID = "modelId"
    }
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

private struct CaelProfileOperationsPatch: Encodable {
    let model: String?
    let provider: String?
    let systemPrompt: String?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case model
        case provider
        case systemPrompt = "system_prompt"
        case description
    }
}

private struct CaelProfileOperationsUpdateRequest: Encodable {
    let name: String
    let patch: CaelProfileOperationsPatch
}


private struct WorkspaceSessionCreateRequest: Encodable {
    let label: String?
    let model: String?
}

private struct WorkspaceSessionSendRequest: Encodable {
    let sessionKey: String
    let message: String
    let serverSide: Bool
    let autoApproveCommands: Bool
    let idempotencyKey: String
}

private struct KnowledgeFabricSearchRequest: Encodable {
    let query: String
    let memoryScope: String
    let mode: String?
    let maxResults: Int
    let agentSource: String?
}

private struct KnowledgeFabricDocumentRequest: Encodable {
    let docId: String
    let memoryScope: String
}

private struct KnowledgeFabricSessionStateRequest: Encodable {
    let summary: String
    let memoryScope: String
    let agentSource: String?
    let sessionId: String?
    let project: String?
    let metadata: [String: String]
}



private struct WorkspaceMCPTestRequest: Encodable {
    let name: String
}

private struct WorkspaceMCPCreateRequest: Encodable {
    let name: String
    let enabled: Bool
    let transportType: String
    let command: String
    let args: [String]
    let authType: String
    let toolMode: String
}

private struct WorkspaceMCPConfigureRequest: Encodable {
    let name: String
    let enabled: Bool?
    let toolMode: String?
    let includeTools: [String]?
    let excludeTools: [String]?
}

private struct WorkspaceSwarmWorkerRequest: Encodable {
    let workerId: String
}

private struct WorkspaceSwarmDispatchRequest: Encodable {
    let workerIds: [String]
    let prompt: String
    let timeoutSeconds: Int
    let allowAsync: Bool
}

private struct WorkspaceConductorSpawnRequest: Encodable {
    let goal: String
    let orchestratorModel: String?
    let workerModel: String?
    let projectsDir: String?
    let maxParallel: Int
    let supervised: Bool
}

private struct WorkspaceConductorStopRequest: Encodable {
    let sessionKeys: [String]
    let missionIds: [String]
}

private struct WorkspaceSecondBrainWriteRequest: Encodable {
    let source: String
    let path: String
    let content: String
    let expectedHash: String
}

private struct WorkspaceSecondBrainDispatchRequest: Encodable {
    let source: String
    let path: String?
    let operation: String
    let hash: String?
}

private struct CaelWorkspaceFilesListResponse: Decodable {
    let root: String?
    let base: String?
    let entries: [CaelWorkspaceFileEntry]

    func remoteDirectoryListing(requestedPath: String) -> RemoteDirectoryListing {
        let resolvedPath = Self.absolutePath(base: base, path: root ?? requestedPath)
        let parent = Self.parentPath(for: resolvedPath, base: base)
        let mappedEntries = entries.map { $0.remoteDirectoryEntry(base: base) }

        return RemoteDirectoryListing(
            requestedPath: requestedPath,
            resolvedPath: resolvedPath,
            displayPath: resolvedPath,
            parentPath: parent,
            parentDisplayPath: parent,
            entries: mappedEntries,
            totalEntryCount: mappedEntries.count,
            isTruncated: false
        )
    }

    static func absolutePath(base: String?, path candidate: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return trimmed
        }
        guard let base = base?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty else {
            return trimmed.isEmpty ? "." : trimmed
        }
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard !trimmed.isEmpty else { return normalizedBase }
        return "\(normalizedBase)/\(trimmed)"
    }

    static func parentPath(for resolvedPath: String, base: String?) -> String? {
        let normalizedBase = base?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingTrailingSlash
        let normalizedPath = resolvedPath.trimmingTrailingSlash
        if let normalizedBase, normalizedPath == normalizedBase {
            return nil
        }
        let parent = (normalizedPath as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != normalizedPath else { return nil }
        return parent
    }
}

private struct CaelWorkspaceFileEntry: Decodable {
    let name: String
    let path: String
    let type: String
    let size: Int64?
    let modifiedAt: String?

    func remoteDirectoryEntry(base: String?) -> RemoteDirectoryEntry {
        let absolutePath = CaelWorkspaceFilesListResponse.absolutePath(base: base, path: path)
        return RemoteDirectoryEntry(
            name: name,
            path: absolutePath,
            displayPath: absolutePath,
            kind: type == "folder" ? .directory : .file,
            size: size,
            modifiedAt: Self.modifiedTimestamp(from: modifiedAt),
            isReadable: true,
            isWritable: true,
            isSymlink: false
        )
    }

    private static func modifiedTimestamp(from value: String?) -> Double? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)?.timeIntervalSince1970
    }
}

private struct WorkspaceTaskCreateRequest: Encodable {
    let title: String
    let description: String
    let column: WorkspaceTaskColumn
    let priority: WorkspaceTaskPriority
    let assignee: String?
    let tags: [String]
    let dueDate: String?
    let createdBy: String

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case column
        case priority
        case assignee
        case tags
        case dueDate = "due_date"
        case createdBy = "created_by"
    }
}

private struct WorkspaceTaskUpdateRequest: Encodable {
    let title: String?
    let description: String?
    let column: WorkspaceTaskColumn?
    let priority: WorkspaceTaskPriority?
    let assignee: String?
    let tags: [String]?
}

private struct WorkspaceTaskSessionLinkRequest: Encodable {
    let sessionID: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let sessionID {
            try container.encode(sessionID, forKey: .sessionID)
        } else {
            try container.encodeNil(forKey: .sessionID)
        }
    }
}

private struct WorkspaceTaskMoveRequest: Encodable {
    let column: WorkspaceTaskColumn
    let movedBy: String

    enum CodingKeys: String, CodingKey {
        case column
        case movedBy = "moved_by"
    }
}

struct CronJobMutationResult {
    let jobID: String?
    let job: CronJob?
}

private struct WorkspaceEmptyRequest: Encodable {}

private struct WorkspaceCronJobMutationRequest: Encodable {
    let profile: String
    let name: String
    let prompt: String
    let input: String
    let schedule: String
    let deliver: [String]
    let skills: [String]
    let model: String?
    let provider: String?
    let baseURL: String?
    let timezone: String?
    let script: String?
    let workdir: String?
    let noAgent: Bool

    enum CodingKeys: String, CodingKey {
        case profile
        case name
        case prompt
        case input
        case schedule
        case deliver
        case skills
        case model
        case provider
        case baseURL = "base_url"
        case timezone
        case script
        case workdir
        case noAgent = "no_agent"
    }

    init(connection: ConnectionProfile, draft: CronJobDraft) {
        let prompt = draft.normalizedPrompt
        self.profile = connection.cliHermesProfileName ?? connection.resolvedHermesProfileName
        self.name = draft.normalizedName
        self.prompt = prompt
        self.input = prompt
        self.schedule = draft.schedule.expression ?? ""
        self.deliver = draft.normalizedDeliveryTarget.map { [$0] } ?? []
        self.skills = draft.normalizedSkills
        self.model = draft.normalizedModel
        self.provider = draft.normalizedProvider
        self.baseURL = draft.normalizedBaseURL
        self.timezone = draft.normalizedTimezone
        self.script = draft.normalizedScript
        self.workdir = draft.normalizedWorkdir
        self.noAgent = draft.noAgent
    }
}

private struct WorkspaceCronJobMutationResponse: Decodable {
    let ok: Bool?
    let job: CronJob?
    let jobID: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case job
        case jobID = "jobId"
        case error
    }
}

private struct CaelWorkspaceFileReadResponse: Decodable {
    let type: String
    let path: String?
    let content: String
    let contentHash: String?
}

private struct CaelWorkspaceFileWriteRequest: Encodable {
    let action: String
    let path: String
    let content: String
    let expectedContentHash: String?
}

private struct CaelWorkspaceFileWriteResponse: Decodable {
    let ok: Bool
    let path: String?
    let contentHash: String?
    let error: String?
}

private struct CaelWorkspaceFileMutationRequest: Encodable {
    let action: String
    let path: String?
    let from: String?
    let to: String?
}

private struct CaelWorkspaceFileMutationResponse: Decodable {
    let ok: Bool
    let path: String?
    let error: String?
}

private struct CaelWorkspaceFileUploadRequest: Encodable {
    let action: String
    let path: String
    let fileName: String
    let contentBase64: String
}

private struct ToolArtifactsListResponse: Decodable {
    let ok: Bool
    let artifacts: [ToolArtifactSummary]
    let error: String?
}

private struct ToolArtifactDetailResponse: Decodable {
    let ok: Bool
    let artifact: ToolArtifactDetail?
    let error: String?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmingTrailingSlash: String {
        var result = self
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
