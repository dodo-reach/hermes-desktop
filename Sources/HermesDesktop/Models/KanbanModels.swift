import Foundation

struct KanbanBoardResponse: Codable, Sendable {
    let ok: Bool
    let board: KanbanBoard
}

struct KanbanBoardsResponse: Codable, Sendable {
    let ok: Bool?
    let boards: [KanbanProject]
    let current: String?
    let supportsBoardManagement: Bool

    enum CodingKeys: String, CodingKey {
        case ok
        case boards
        case current
        case supportsBoardManagement = "supports_board_management"
    }

    init(ok: Bool? = nil, boards: [KanbanProject], current: String?, supportsBoardManagement: Bool = false) {
        self.ok = ok
        self.boards = boards
        self.current = current
        self.supportsBoardManagement = supportsBoardManagement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        boards = try container.decodeIfPresent([KanbanProject].self, forKey: .boards) ?? []
        current = try container.decodeIfPresent(String.self, forKey: .current)
        supportsBoardManagement = try container.decodeIfPresent(Bool.self, forKey: .supportsBoardManagement) ?? false
    }
}

struct KanbanTaskDetailResponse: Codable, Sendable {
    let ok: Bool
    let detail: KanbanTaskDetail
}

struct KanbanBoardOperationResponse: Codable, Sendable {
    let ok: Bool?
    let board: KanbanProject?
    let boards: [KanbanProject]?
    let current: String?
    let result: JSONValue?
    let message: String?
}

struct KanbanOperationResponse: Codable, Sendable {
    let ok: Bool
    let message: String?
    let taskID: String?
    let detail: KanbanTaskDetail?
    let dispatch: KanbanDispatchResult?

    enum CodingKeys: String, CodingKey {
        case ok
        case message
        case taskID = "task_id"
        case detail
        case dispatch
    }
}

struct KanbanProject: Codable, Identifiable, Hashable, Sendable {
    static let defaultSlug = "default"
    static let workspaceTasksSlug = "workspace-tasks"
    static let workspaceTasks = KanbanProject(
        slug: workspaceTasksSlug,
        name: "Workspace Tasks",
        description: "Shared :3077 task board used by the web and mobile workspace.",
        icon: "checklist",
        color: "blue",
        isCurrent: true
    )

    let slug: String
    let name: String?
    let description: String?
    let icon: String?
    let color: String?
    let createdAt: Int?
    let archived: Bool
    let databasePath: String?
    let isCurrent: Bool
    let counts: [String: Int]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case slug
        case name
        case description
        case icon
        case color
        case createdAt = "created_at"
        case archived
        case databasePath = "db_path"
        case isCurrent = "is_current"
        case counts
        case total
    }

    init(
        slug: String,
        name: String? = nil,
        description: String? = nil,
        icon: String? = nil,
        color: String? = nil,
        createdAt: Int? = nil,
        archived: Bool = false,
        databasePath: String? = nil,
        isCurrent: Bool = false,
        counts: [String: Int] = [:],
        total: Int? = nil
    ) {
        self.slug = slug
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.createdAt = createdAt
        self.archived = archived
        self.databasePath = databasePath
        self.isCurrent = isCurrent
        self.counts = counts
        self.total = total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        databasePath = try container.decodeIfPresent(String.self, forKey: .databasePath)
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        counts = try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        total = try container.decodeIfPresent(Int.self, forKey: .total)
    }

    var id: String { slug }

    var isDefault: Bool {
        slug == Self.defaultSlug
    }

    var resolvedName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            return trimmedName
        }
        if isDefault {
            return L10n.string("Default")
        }
        return slug
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var resolvedIcon: String {
        let trimmedIcon = icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedIcon.isEmpty ? "rectangle.3.group" : trimmedIcon
    }

    var resolvedDescription: String? {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var taskTotal: Int {
        total ?? counts.values.reduce(0, +)
    }

    var createdDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

struct KanbanBoard: Codable, Hashable, Sendable {
    let databasePath: String
    let hostWide: Bool
    let isInitialized: Bool
    let hasKanbanModule: Bool
    let hasHermesCLI: Bool
    let dispatcher: KanbanDispatcherStatus?
    let latestEventID: Int?
    let warning: String?
    let tasks: [KanbanTask]
    let assignees: [KanbanAssignee]
    let tenants: [String]
    let stats: KanbanStats?

    enum CodingKeys: String, CodingKey {
        case databasePath = "database_path"
        case hostWide = "host_wide"
        case isInitialized = "is_initialized"
        case hasKanbanModule = "has_kanban_module"
        case hasHermesCLI = "has_hermes_cli"
        case dispatcher
        case latestEventID = "latest_event_id"
        case warning
        case tasks
        case assignees
        case tenants
        case stats
    }

    static let empty = KanbanBoard(
        databasePath: "~/.hermes/kanban.db",
        hostWide: true,
        isInitialized: false,
        hasKanbanModule: false,
        hasHermesCLI: false,
        dispatcher: nil,
        latestEventID: nil,
        warning: nil,
        tasks: [],
        assignees: [],
        tenants: [],
        stats: nil
    )

    var visibleStatuses: [KanbanTaskStatus] {
        KanbanTaskStatus.boardStatuses.filter { status in
            status != .archived || tasks.contains(where: { $0.status == .archived })
        }
    }

    func tasks(for status: KanbanTaskStatus) -> [KanbanTask] {
        tasks.filter { $0.status == status }
    }

    func task(id: String?) -> KanbanTask? {
        guard let id else { return nil }
        return tasks.first(where: { $0.id == id })
    }
}

struct KanbanTask: Codable, Identifiable, Hashable, Sendable, TitleIdentifiable {
    let id: String
    let title: String?
    let body: String?
    let assignee: String?
    let status: KanbanTaskStatus
    let priority: Int
    let createdBy: String?
    let createdAt: Int?
    let startedAt: Int?
    let completedAt: Int?
    let workspaceKind: KanbanWorkspaceKind
    let workspacePath: String?
    let tenant: String?
    let result: String?
    let skills: [String]
    let spawnFailures: Int
    let workerPID: Int?
    let lastSpawnError: String?
    let maxRuntimeSeconds: Int?
    let maxRetries: Int?
    let lastHeartbeatAt: Int?
    let currentRunID: Int?
    let parentIDs: [String]
    let childIDs: [String]
    let progress: KanbanTaskProgress?
    let commentCount: Int
    let eventCount: Int
    let runCount: Int
    let latestEventAt: Int?
    let warnings: KanbanTaskWarnings?
    let sessionID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case assignee
        case status
        case priority
        case createdBy = "created_by"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case workspaceKind = "workspace_kind"
        case workspacePath = "workspace_path"
        case tenant
        case result
        case skills
        case spawnFailures = "spawn_failures"
        case workerPID = "worker_pid"
        case lastSpawnError = "last_spawn_error"
        case maxRuntimeSeconds = "max_runtime_seconds"
        case maxRetries = "max_retries"
        case lastHeartbeatAt = "last_heartbeat_at"
        case currentRunID = "current_run_id"
        case parentIDs = "parent_ids"
        case childIDs = "child_ids"
        case progress
        case commentCount = "comment_count"
        case eventCount = "event_count"
        case runCount = "run_count"
        case latestEventAt = "latest_event_at"
        case warnings
        case sessionID = "session_id"
    }

    init(
        id: String,
        title: String?,
        body: String?,
        assignee: String?,
        status: KanbanTaskStatus,
        priority: Int,
        createdBy: String?,
        createdAt: Int?,
        startedAt: Int?,
        completedAt: Int?,
        workspaceKind: KanbanWorkspaceKind,
        workspacePath: String?,
        tenant: String?,
        result: String?,
        skills: [String],
        spawnFailures: Int,
        workerPID: Int?,
        lastSpawnError: String?,
        maxRuntimeSeconds: Int?,
        maxRetries: Int?,
        lastHeartbeatAt: Int?,
        currentRunID: Int?,
        parentIDs: [String],
        childIDs: [String],
        progress: KanbanTaskProgress?,
        commentCount: Int,
        eventCount: Int,
        runCount: Int,
        latestEventAt: Int?,
        warnings: KanbanTaskWarnings? = nil,
        sessionID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.assignee = assignee
        self.status = status
        self.priority = priority
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.workspaceKind = workspaceKind
        self.workspacePath = workspacePath
        self.tenant = tenant
        self.result = result
        self.skills = skills
        self.spawnFailures = spawnFailures
        self.workerPID = workerPID
        self.lastSpawnError = lastSpawnError
        self.maxRuntimeSeconds = maxRuntimeSeconds
        self.maxRetries = maxRetries
        self.lastHeartbeatAt = lastHeartbeatAt
        self.currentRunID = currentRunID
        self.parentIDs = parentIDs
        self.childIDs = childIDs
        self.progress = progress
        self.commentCount = commentCount
        self.eventCount = eventCount
        self.runCount = runCount
        self.latestEventAt = latestEventAt
        self.warnings = warnings
        self.sessionID = sessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        status = try container.decodeIfPresent(KanbanTaskStatus.self, forKey: .status) ?? .other("unknown")
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt)
        startedAt = try container.decodeIfPresent(Int.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Int.self, forKey: .completedAt)
        workspaceKind = try container.decodeIfPresent(KanbanWorkspaceKind.self, forKey: .workspaceKind) ?? .scratch
        workspacePath = try container.decodeIfPresent(String.self, forKey: .workspacePath)
        tenant = try container.decodeIfPresent(String.self, forKey: .tenant)
        result = try container.decodeIfPresent(String.self, forKey: .result)
        skills = try container.decodeIfPresent([String].self, forKey: .skills) ?? []
        spawnFailures = try container.decodeIfPresent(Int.self, forKey: .spawnFailures) ?? 0
        workerPID = try container.decodeIfPresent(Int.self, forKey: .workerPID)
        lastSpawnError = try container.decodeIfPresent(String.self, forKey: .lastSpawnError)
        maxRuntimeSeconds = try container.decodeIfPresent(Int.self, forKey: .maxRuntimeSeconds)
        maxRetries = try container.decodeIfPresent(Int.self, forKey: .maxRetries)
        lastHeartbeatAt = try container.decodeIfPresent(Int.self, forKey: .lastHeartbeatAt)
        currentRunID = try container.decodeIfPresent(Int.self, forKey: .currentRunID)
        parentIDs = try container.decodeIfPresent([String].self, forKey: .parentIDs) ?? []
        childIDs = try container.decodeIfPresent([String].self, forKey: .childIDs) ?? []
        progress = try container.decodeIfPresent(KanbanTaskProgress.self, forKey: .progress)
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        eventCount = try container.decodeIfPresent(Int.self, forKey: .eventCount) ?? 0
        runCount = try container.decodeIfPresent(Int.self, forKey: .runCount) ?? 0
        latestEventAt = try container.decodeIfPresent(Int.self, forKey: .latestEventAt)
        warnings = try container.decodeIfPresent(KanbanTaskWarnings.self, forKey: .warnings)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
    }

    var resolvedTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? id : trimmed
    }

    var trimmedBody: String? {
        trimmedText(body)
    }

    var trimmedResult: String? {
        trimmedText(result)
    }

    var createdDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var latestActivityDate: Date? {
        (latestEventAt ?? completedAt ?? startedAt ?? createdAt)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var isRunning: Bool {
        status == .running
    }

    var hasActiveWarnings: Bool {
        warnings?.hasWarnings == true
    }

    var isBlocked: Bool {
        status == .blocked
    }

    var isTerminal: Bool {
        status == .done || status == .archived
    }

    var canBlock: Bool {
        status == .ready || status == .running
    }

    var canComplete: Bool {
        status == .ready || status == .running || status == .blocked
    }

    var canUnblock: Bool {
        status == .blocked
    }

    var canSpecify: Bool {
        status == .triage
    }

    var priorityLabel: String {
        if priority > 0 {
            return "P+\(priority)"
        }
        if priority < 0 {
            return "P\(priority)"
        }
        return "P0"
    }

    var progressLabel: String? {
        guard let progress, progress.total > 0 else { return nil }
        return L10n.string("%@/%@ done", "\(progress.done)", "\(progress.total)")
    }

    var shortID: String {
        if id.count <= 10 {
            return id
        }
        return String(id.prefix(10))
    }

    func matchesSearch(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let foldingOptions: String.CompareOptions = [.diacriticInsensitive, .caseInsensitive]
        let normalizedQuery = trimmedQuery.folding(options: foldingOptions, locale: Locale.current)
        var haystacks: [String] = [
            id,
            resolvedTitle,
            body ?? "",
            assignee ?? "",
            status.displayTitle,
            tenant ?? "",
            result ?? "",
            workspacePath ?? "",
            createdBy ?? "",
            warnings?.searchText ?? ""
        ]
        haystacks.append(contentsOf: skills)
        haystacks.append(contentsOf: parentIDs)
        haystacks.append(contentsOf: childIDs)

        return haystacks.contains { value in
            value.folding(options: foldingOptions, locale: Locale.current)
                .localizedStandardContains(normalizedQuery)
        }
    }

    private func trimmedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum KanbanTaskStatus: Hashable, Codable, Sendable {
    case triage
    case todo
    case ready
    case running
    case review
    case blocked
    case done
    case archived
    case other(String)

    static let boardStatuses: [KanbanTaskStatus] = [
        .triage,
        .todo,
        .ready,
        .running,
        .review,
        .blocked,
        .done,
        .archived
    ]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "triage":
            self = .triage
        case "todo":
            self = .todo
        case "ready":
            self = .ready
        case "running":
            self = .running
        case "review":
            self = .review
        case "blocked":
            self = .blocked
        case "done":
            self = .done
        case "archived":
            self = .archived
        default:
            self = .other(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .triage:
            "triage"
        case .todo:
            "todo"
        case .ready:
            "ready"
        case .running:
            "running"
        case .review:
            "review"
        case .blocked:
            "blocked"
        case .done:
            "done"
        case .archived:
            "archived"
        case .other(let value):
            value
        }
    }

    var displayTitle: String {
        switch self {
        case .triage:
            "Triage"
        case .todo:
            "Todo"
        case .ready:
            "Ready"
        case .running:
            "Running"
        case .review:
            "Review"
        case .blocked:
            "Blocked"
        case .done:
            "Done"
        case .archived:
            "Archived"
        case .other(let value):
            value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

enum KanbanWorkspaceKind: Hashable, Codable, Sendable {
    case scratch
    case worktree
    case directory
    case other(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "scratch":
            self = .scratch
        case "worktree":
            self = .worktree
        case "dir":
            self = .directory
        default:
            self = .other(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .scratch:
            "scratch"
        case .worktree:
            "worktree"
        case .directory:
            "dir"
        case .other(let value):
            value
        }
    }

    var displayTitle: String {
        switch self {
        case .scratch:
            "Scratch"
        case .worktree:
            "Worktree"
        case .directory:
            "Directory"
        case .other(let value):
            value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct KanbanTaskProgress: Codable, Hashable, Sendable {
    let done: Int
    let total: Int
}

struct KanbanTaskWarnings: Codable, Hashable, Sendable {
    let count: Int
    let kinds: [String: Int]
    let latestAt: Int?

    enum CodingKeys: String, CodingKey {
        case count
        case kinds
        case latestAt = "latest_at"
    }

    init(count: Int, kinds: [String: Int], latestAt: Int?) {
        self.count = count
        self.kinds = kinds
        self.latestAt = latestAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        kinds = try container.decodeIfPresent([String: Int].self, forKey: .kinds) ?? [:]
        latestAt = try container.decodeIfPresent(Int.self, forKey: .latestAt)
    }

    var hasWarnings: Bool {
        count > 0 || !kinds.isEmpty
    }

    var latestDate: Date? {
        latestAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var includesBlockedCompletion: Bool {
        (kinds["completion_blocked_hallucination"] ?? 0) > 0
    }

    var includesSuspectedReferences: Bool {
        (kinds["suspected_hallucinated_references"] ?? 0) > 0
    }

    var displayTitle: String {
        if includesBlockedCompletion && includesSuspectedReferences {
            return "Completion and reference warnings"
        }
        if includesBlockedCompletion {
            return "Completion blocked by phantom card claims"
        }
        if includesSuspectedReferences {
            return "Possible phantom task references"
        }
        return "Kanban recovery warning"
    }

    var displayMessage: String {
        if includesBlockedCompletion {
            return "Hermes Agent rejected a completion because the worker claimed cards that do not exist or were not created by that worker."
        }
        if includesSuspectedReferences {
            return "Hermes Agent found task IDs in the completion text that do not resolve on the board."
        }
        return "Hermes Agent recorded warning events that may need recovery."
    }

    var searchText: String {
        ([displayTitle, displayMessage] + kinds.keys).joined(separator: " ")
    }
}

struct KanbanTaskDetail: Codable, Hashable, Sendable {
    let task: KanbanTask
    let parentIDs: [String]
    let childIDs: [String]
    let comments: [KanbanComment]
    let events: [KanbanEvent]
    let runs: [KanbanRun]
    let workerLog: String?
    let homeChannels: [KanbanHomeChannel]

    enum CodingKeys: String, CodingKey {
        case task
        case parentIDs = "parent_ids"
        case childIDs = "child_ids"
        case comments
        case events
        case runs
        case workerLog = "worker_log"
        case homeChannels = "home_channels"
    }

    init(
        task: KanbanTask,
        parentIDs: [String],
        childIDs: [String],
        comments: [KanbanComment],
        events: [KanbanEvent],
        runs: [KanbanRun],
        workerLog: String?,
        homeChannels: [KanbanHomeChannel] = []
    ) {
        self.task = task
        self.parentIDs = parentIDs
        self.childIDs = childIDs
        self.comments = comments
        self.events = events
        self.runs = runs
        self.workerLog = workerLog
        self.homeChannels = homeChannels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        task = try container.decode(KanbanTask.self, forKey: .task)
        parentIDs = try container.decodeIfPresent([String].self, forKey: .parentIDs) ?? []
        childIDs = try container.decodeIfPresent([String].self, forKey: .childIDs) ?? []
        comments = try container.decodeIfPresent([KanbanComment].self, forKey: .comments) ?? []
        events = try container.decodeIfPresent([KanbanEvent].self, forKey: .events) ?? []
        runs = try container.decodeIfPresent([KanbanRun].self, forKey: .runs) ?? []
        workerLog = try container.decodeIfPresent(String.self, forKey: .workerLog)
        homeChannels = try container.decodeIfPresent([KanbanHomeChannel].self, forKey: .homeChannels) ?? []
    }
}

struct KanbanHomeChannel: Codable, Identifiable, Hashable, Sendable {
    let platform: String
    let chatID: String
    let threadID: String
    let name: String?
    let subscribed: Bool

    enum CodingKeys: String, CodingKey {
        case platform
        case chatID = "chat_id"
        case threadID = "thread_id"
        case name
        case subscribed
    }

    init(
        platform: String,
        chatID: String,
        threadID: String = "",
        name: String? = nil,
        subscribed: Bool = false
    ) {
        self.platform = platform
        self.chatID = chatID
        self.threadID = threadID
        self.name = name
        self.subscribed = subscribed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decode(String.self, forKey: .platform)
        chatID = try container.decode(String.self, forKey: .chatID)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        subscribed = try container.decodeIfPresent(Bool.self, forKey: .subscribed) ?? false
    }

    var id: String {
        "\(platform):\(chatID):\(threadID)"
    }

    var resolvedName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.string("Home") : trimmed
    }

    var displayPlatform: String {
        platform
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var destinationLabel: String {
        threadID.isEmpty ? chatID : "\(chatID) / \(threadID)"
    }
}

struct KanbanComment: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let taskID: String
    let author: String
    let body: String
    let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case author
        case body
        case createdAt = "created_at"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }
}

struct KanbanEvent: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let taskID: String
    let kind: String
    let payload: [String: JSONValue]?
    let createdAt: Int
    let runID: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case kind
        case payload
        case createdAt = "created_at"
        case runID = "run_id"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    var displayPayload: String? {
        guard let payload, !payload.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(JSONValue.object(payload)),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

struct KanbanRun: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let taskID: String
    let profile: String?
    let stepKey: String?
    let status: String
    let outcome: String?
    let summary: String?
    let error: String?
    let metadata: [String: JSONValue]?
    let workerPID: Int?
    let startedAt: Int
    let endedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case profile
        case stepKey = "step_key"
        case status
        case outcome
        case summary
        case error
        case metadata
        case workerPID = "worker_pid"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    var startedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startedAt))
    }

    var endedDate: Date? {
        endedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var resolvedOutcome: String {
        outcome ?? (endedAt == nil ? "running" : status)
    }
}

struct KanbanAssignee: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let onDisk: Bool
    let counts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case name
        case onDisk = "on_disk"
        case counts
    }

    var id: String { name }
}

struct KanbanStats: Codable, Hashable, Sendable {
    let byStatus: [String: Int]
    let byAssignee: [String: [String: Int]]
    let oldestReadyAgeSeconds: Int?
    let now: Int?

    enum CodingKeys: String, CodingKey {
        case byStatus = "by_status"
        case byAssignee = "by_assignee"
        case oldestReadyAgeSeconds = "oldest_ready_age_seconds"
        case now
    }
}

struct KanbanDispatcherStatus: Codable, Hashable, Sendable {
    let running: Bool?
    let message: String?

    var isKnownInactive: Bool {
        running == false
    }
}

struct KanbanDispatchResult: Codable, Hashable, Sendable {
    let reclaimed: Int
    let crashed: [String]
    let timedOut: [String]
    let autoBlocked: [String]
    let promoted: Int
    let spawned: [KanbanSpawnedTask]
    let skippedUnassigned: [String]

    enum CodingKeys: String, CodingKey {
        case reclaimed
        case crashed
        case timedOut = "timed_out"
        case autoBlocked = "auto_blocked"
        case promoted
        case spawned
        case skippedUnassigned = "skipped_unassigned"
    }
}

struct KanbanSpawnedTask: Codable, Hashable, Sendable {
    let taskID: String
    let assignee: String
    let workspace: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case assignee
        case workspace
    }
}

struct KanbanTaskDraft: Equatable {
    var title = ""
    var body = ""
    var assignee = ""
    var priority = 0
    var maxRetriesText = ""
    var tenant = ""
    var skillsText = ""
    var parentIDsText = ""
    var startsInTriage = false

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedBody: String? {
        let value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedAssignee: String? {
        let value = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedTenant: String? {
        let value = tenant.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedMaxRetries: Int? {
        let value = maxRetriesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return Int(value)
    }

    var skills: [String] {
        Self.normalizedCommaList(skillsText)
    }

    var parentIDs: [String] {
        Self.normalizedIDList(parentIDsText)
    }

    var validationError: String? {
        if normalizedTitle.isEmpty {
            return "Task title is required."
        }
        let trimmedMaxRetries = maxRetriesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMaxRetries.isEmpty {
            guard let maxRetries = Int(trimmedMaxRetries), maxRetries > 0 else {
                return "Max retries must be a whole number greater than 0."
            }
        }
        return nil
    }

    static func normalizedCommaList(_ value: String) -> [String] {
        uniquePreservingOrder(
            value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func normalizedIDList(_ value: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        return uniquePreservingOrder(
            value
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func listText(_ values: [String]) -> String {
        values.joined(separator: ", ")
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

struct KanbanBoardDraft: Equatable {
    var slug = ""
    var name = ""
    var description = ""
    var icon = ""
    var color = ""
    var switchAfterCreate = false

    var normalizedSlug: String {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedName: String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedDescription: String? {
        let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedIcon: String? {
        let value = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedColor: String? {
        let value = color.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var validationError: String? {
        if normalizedSlug.isEmpty {
            return "Board slug is required."
        }
        if normalizedSlug.range(of: #"^[a-z0-9][a-z0-9\-_]{0,63}$"#, options: .regularExpression) == nil {
            return "Board slug must be 1-64 lowercase letters, numbers, hyphens, or underscores."
        }
        return nil
    }
}

struct KanbanActionDraft: Equatable {
    var comment = ""
    var result = ""
    var blockReason = ""
    var recoveryReason = ""
    var recoverySummary = ""
    var recoveryMetadata = ""
    var reclaimBeforeReassign = false
    var assignee = ""
    var body = ""
    var tenant = ""
    var priority = 0
    var skillsText = ""
    var parentIDsText = ""
    var childIDsText = ""

    var normalizedComment: String? {
        let value = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedResult: String? {
        let value = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedBlockReason: String? {
        let value = blockReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedRecoveryReason: String? {
        let value = recoveryReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedRecoverySummary: String? {
        let value = recoverySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedRecoveryMetadata: String? {
        let value = recoveryMetadata.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedAssignee: String? {
        let value = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedBodyForUpdate: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedTenantForUpdate: String {
        tenant.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var skills: [String] {
        KanbanTaskDraft.normalizedCommaList(skillsText)
    }

    var parentIDs: [String] {
        KanbanTaskDraft.normalizedIDList(parentIDsText)
    }

    var childIDs: [String] {
        KanbanTaskDraft.normalizedIDList(childIDsText)
    }
}
