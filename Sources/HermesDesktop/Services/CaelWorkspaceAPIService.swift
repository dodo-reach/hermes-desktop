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
            path: "/api/claude-tasks?include_done=\(includeDoneValue)",
            responseType: WorkspaceTasksResponse.self
        )
        return response.tasks
    }

    @discardableResult
    func createWorkspaceTask(connection: ConnectionProfile, draft: KanbanTaskDraft) async throws -> WorkspaceTask {
        let response = try await postJSON(
            connection: connection,
            path: "/api/claude-tasks",
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
            path: "/api/claude-tasks/\(taskID)",
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
            path: "/api/claude-tasks/\(taskID)?action=move",
            body: WorkspaceTaskMoveRequest(column: column, movedBy: "cael-desktop"),
            responseType: WorkspaceTaskMutationResponse.self
        )
        guard let task = response.task else {
            throw SSHTransportError.invalidResponse(response.error ?? "Workspace API did not return a moved task.")
        }
        return task
    }

    func deleteWorkspaceTask(connection: ConnectionProfile, taskID: String) async throws {
        let response = try await deleteJSON(
            connection: connection,
            path: "/api/claude-tasks/\(taskID)",
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

    private func deleteJSON<Response: Decodable>(
        connection: ConnectionProfile,
        path: String,
        responseType: Response.Type
    ) async throws -> Response {
        try await requestJSON(connection: connection, path: path, method: "DELETE", body: nil, responseType: responseType)
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



private struct WorkspaceMCPTestRequest: Encodable {
    let name: String
}

private struct WorkspaceSecondBrainWriteRequest: Encodable {
    let source: String
    let path: String
    let content: String
    let expectedHash: String
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
