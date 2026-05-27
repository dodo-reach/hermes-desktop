import Foundation

struct WorkspaceTasksResponse: Decodable, Sendable {
    let tasks: [WorkspaceTask]
}

struct WorkspaceTaskMutationResponse: Decodable, Sendable {
    let task: WorkspaceTask?
    let error: String?
}

struct WorkspaceTaskLaunchResponse: Decodable, Sendable {
    let sessionId: String?
    let briefing: String?
    let task: WorkspaceTask?
    let error: String?
}

struct WorkspaceTaskDeleteResponse: Decodable, Sendable {
    let ok: Bool?
    let error: String?
}

struct WorkspaceTask: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String
    let column: WorkspaceTaskColumn
    let priority: WorkspaceTaskPriority
    let assignee: String?
    let tags: [String]
    let dueDate: String?
    let position: Int?
    let createdBy: String
    let createdAt: String?
    let updatedAt: String?
    let sessionID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case column
        case priority
        case assignee
        case tags
        case dueDate = "due_date"
        case position
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionID = "session_id"
    }

    var kanbanTask: KanbanTask {
        KanbanTask(
            id: id,
            title: title,
            body: description,
            assignee: assignee,
            status: column.kanbanStatus,
            priority: priority.kanbanPriority,
            createdBy: createdBy,
            createdAt: Self.unixSeconds(from: createdAt),
            startedAt: nil,
            completedAt: column == .done ? Self.unixSeconds(from: updatedAt) : nil,
            workspaceKind: .scratch,
            workspacePath: nil,
            tenant: "workspace",
            result: nil,
            skills: tags,
            spawnFailures: 0,
            workerPID: nil,
            lastSpawnError: nil,
            maxRuntimeSeconds: nil,
            maxRetries: nil,
            lastHeartbeatAt: Self.unixSeconds(from: updatedAt),
            currentRunID: nil,
            parentIDs: [],
            childIDs: [],
            progress: nil,
            commentCount: 0,
            eventCount: 0,
            runCount: 0,
            latestEventAt: Self.unixSeconds(from: updatedAt),
            sessionID: sessionID
        )
    }

    private static func unixSeconds(from value: String?) -> Int? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let number = Double(value) {
            return Int(number > 1_000_000_000_000 ? number / 1000 : number)
        }
        return ISO8601DateFormatter().date(from: value).map { Int($0.timeIntervalSince1970) }
    }
}

enum WorkspaceTaskColumn: String, Codable, CaseIterable, Sendable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case review
    case blocked
    case done
    case deleted

    var kanbanStatus: KanbanTaskStatus {
        switch self {
        case .backlog:
            .triage
        case .todo:
            .ready
        case .inProgress:
            .running
        case .review:
            .review
        case .blocked:
            .blocked
        case .done:
            .done
        case .deleted:
            .archived
        }
    }

    static func fromKanbanStatus(_ status: KanbanTaskStatus) -> WorkspaceTaskColumn {
        switch status {
        case .triage:
            .backlog
        case .todo, .ready:
            .todo
        case .running:
            .inProgress
        case .review:
            .review
        case .blocked:
            .blocked
        case .done:
            .done
        case .archived:
            .deleted
        case .other:
            .backlog
        }
    }
}

enum WorkspaceTaskPriority: String, Codable, Sendable {
    case high
    case medium
    case low

    var kanbanPriority: Int {
        switch self {
        case .high:
            1
        case .medium:
            0
        case .low:
            -1
        }
    }

    static func fromKanbanPriority(_ priority: Int) -> WorkspaceTaskPriority {
        if priority > 0 { return .high }
        if priority < 0 { return .low }
        return .medium
    }
}

extension KanbanBoard {
    static func workspaceTasks(_ tasks: [WorkspaceTask], includeDone: Bool) -> KanbanBoard {
        let visibleTasks = includeDone ? tasks : tasks.filter { $0.column != .done && $0.column != .deleted }
        let kanbanTasks = visibleTasks.map(\.kanbanTask)
        let assigneeCounts = Dictionary(grouping: kanbanTasks.compactMap(\.assignee), by: { $0 })
            .mapValues(\.count)
        let assignees = assigneeCounts
            .map { name, count in KanbanAssignee(name: name, onDisk: false, counts: ["total": count]) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return KanbanBoard(
            databasePath: "/api/hermes-tasks",
            hostWide: true,
            isInitialized: true,
            hasKanbanModule: true,
            hasHermesCLI: false,
            dispatcher: nil,
            latestEventID: nil,
            warning: "Shared Workspace Tasks board from :3077. Advanced Hermes Kanban actions remain available on the SSH boards.",
            tasks: kanbanTasks,
            assignees: assignees,
            tenants: ["workspace"],
            stats: nil
        )
    }
}

