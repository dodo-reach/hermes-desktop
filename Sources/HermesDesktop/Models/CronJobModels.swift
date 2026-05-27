import Foundation

struct CronJobListResponse: Decodable {
    let ok: Bool?
    let jobs: [CronJob]
}


struct CronJobOutputResponse: Decodable {
    let ok: Bool?
    let outputs: [CronJobOutput]
    let error: String?
}

struct CronJobOutput: Decodable, Identifiable, Hashable {
    var id: String { filename }
    let filename: String
    let timestamp: String
    let content: String
    let size: Int

    var displayTitle: String {
        filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? timestamp : filename
    }

    var previewContent: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 6000 else { return trimmed.isEmpty ? "No output content captured." : trimmed }
        return String(trimmed.prefix(6000)) + "\n..."
    }
}

struct CronJob: Decodable, Identifiable, Hashable, OptionalModelDisplayable {
    let id: String
    let name: String
    let prompt: String
    let skills: [String]
    let model: String?
    let provider: String?
    let baseURL: String?
    let schedule: CronSchedule?
    let scheduleDisplay: String
    let recurrence: CronRecurrence?
    let enabled: Bool
    let state: CronJobState
    let createdAt: Date?
    let nextRunAt: Date?
    let lastRunAt: Date?
    let lastStatus: String?
    let lastError: String?
    let deliveryTarget: String?
    let origin: CronJobOrigin?
    let lastDeliveryError: String?
    let script: String?
    let workdir: String?
    let noAgent: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case prompt
        case skills
        case model
        case provider
        case baseURL = "base_url"
        case schedule
        case scheduleDisplay = "schedule_display"
        case recurrence
        case enabled
        case state
        case createdAt = "created_at"
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
        case lastStatus = "last_status"
        case lastError = "last_error"
        case lastRunError = "last_run_error"
        case deliveryTarget = "delivery_target"
        case deliver
        case origin
        case lastDeliveryError = "last_delivery_error"
        case script
        case workdir
        case noAgent = "no_agent"
    }

    init(
        id: String,
        name: String,
        prompt: String,
        skills: [String],
        model: String?,
        provider: String?,
        baseURL: String?,
        schedule: CronSchedule?,
        scheduleDisplay: String,
        recurrence: CronRecurrence?,
        enabled: Bool,
        state: CronJobState,
        createdAt: Date?,
        nextRunAt: Date?,
        lastRunAt: Date?,
        lastStatus: String?,
        lastError: String?,
        deliveryTarget: String?,
        origin: CronJobOrigin?,
        lastDeliveryError: String?,
        script: String? = nil,
        workdir: String? = nil,
        noAgent: Bool = false
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.skills = skills
        self.model = model
        self.provider = provider
        self.baseURL = baseURL
        self.schedule = schedule
        self.scheduleDisplay = scheduleDisplay
        self.recurrence = recurrence
        self.enabled = enabled
        self.state = state
        self.createdAt = createdAt
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.lastStatus = lastStatus
        self.lastError = lastError
        self.deliveryTarget = deliveryTarget
        self.origin = origin
        self.lastDeliveryError = lastDeliveryError
        self.script = script
        self.workdir = workdir
        self.noAgent = noAgent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        skills = try container.decodeIfPresent([String].self, forKey: .skills) ?? []
        model = try container.decodeIfPresent(String.self, forKey: .model)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        schedule = try container.decodeIfPresent(CronSchedule.self, forKey: .schedule)
        scheduleDisplay = try container.decodeIfPresent(String.self, forKey: .scheduleDisplay) ?? ""
        recurrence = try container.decodeIfPresent(CronRecurrence.self, forKey: .recurrence)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        state = try container.decodeIfPresent(CronJobState.self, forKey: .state) ?? .scheduled
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        nextRunAt = try container.decodeIfPresent(Date.self, forKey: .nextRunAt)
        lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
        lastStatus = try container.decodeIfPresent(String.self, forKey: .lastStatus)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError) ??
            container.decodeIfPresent(String.self, forKey: .lastRunError)
        if let directDeliveryTarget = try container.decodeIfPresent(String.self, forKey: .deliveryTarget) {
            deliveryTarget = directDeliveryTarget
        } else if let deliverList = try container.decodeIfPresent([String].self, forKey: .deliver) {
            deliveryTarget = deliverList.joined(separator: ",")
        } else {
            deliveryTarget = try container.decodeIfPresent(String.self, forKey: .deliver)
        }
        origin = try container.decodeIfPresent(CronJobOrigin.self, forKey: .origin)
        lastDeliveryError = try container.decodeIfPresent(String.self, forKey: .lastDeliveryError)
        script = try container.decodeIfPresent(String.self, forKey: .script)
        workdir = try container.decodeIfPresent(String.self, forKey: .workdir)
        noAgent = try container.decodeIfPresent(Bool.self, forKey: .noAgent) ?? false
    }

    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }

    var trimmedPrompt: String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var previewPrompt: String {
        if noAgent {
            let scriptLabel = trimmedScript ?? L10n.string("No script configured")
            return L10n.string("Script-only watchdog: %@", scriptLabel)
        }

        guard let trimmedPrompt else {
            return L10n.string("No prompt payload saved for this job.")
        }

        let compact = trimmedPrompt.replacingOccurrences(of: "\n", with: " ")
        return compact.count > 140 ? String(compact.prefix(140)) + "…" : compact
    }

    var resolvedScheduleDisplay: String {
        if let rawScheduleText {
            return CronScheduleFormatter.humanReadableDescription(for: rawScheduleText) ?? rawScheduleText
        }

        return "No schedule metadata"
    }

    var isPaused: Bool {
        state == .paused
    }

    var isRunning: Bool {
        state == .running
    }

    var isActive: Bool {
        state.isActive
    }

    var trimmedScript: String? {
        let trimmed = script?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedWorkdir: String? {
        let trimmed = workdir?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var executionModeTitle: String {
        noAgent ? "Script Only" : "Agent"
    }

    var displayState: String {
        state.displayTitle(isEnabled: enabled)
    }

    func matchesSearch(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let foldingOptions: String.CompareOptions = [.diacriticInsensitive, .caseInsensitive]
        let normalizedQuery = trimmedQuery.folding(options: foldingOptions, locale: Locale.current)
        var haystacks: [String] = [
            id,
            resolvedName,
            prompt,
            resolvedScheduleDisplay,
            rawScheduleText ?? "",
            model ?? "",
            provider ?? "",
            baseURL ?? "",
            deliveryTarget ?? ""
        ]
        haystacks.append(contentsOf: skills)
        haystacks.append(contentsOf: [
            script ?? "",
            workdir ?? "",
            executionModeTitle
        ])

        return haystacks.contains { value in
            value.folding(options: foldingOptions, locale: Locale.current)
                .localizedStandardContains(normalizedQuery)
        }
    }
    var rawScheduleText: String? {
        let expr = schedule?.expr?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !expr.isEmpty {
            return expr
        }

        let display = scheduleDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? nil : display
    }
}

enum CronJobState: Codable, Hashable {
    case scheduled
    case paused
    case running
    case failed
    case error
    case other(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(decodedValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }

    var isActive: Bool {
        self == .scheduled || self == .running
    }

    func displayTitle(isEnabled: Bool) -> String {
        switch self {
        case .scheduled:
            return "Active"
        case .paused:
            return "Paused"
        case .running:
            return "Running"
        case .failed:
            return "Failed"
        case .error:
            return "Error"
        case .other(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return isEnabled ? "Active" : "Paused"
            }
            return trimmed.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private init(decodedValue: String) {
        let normalized = decodedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "scheduled":
            self = .scheduled
        case "paused":
            self = .paused
        case "running":
            self = .running
        case "failed":
            self = .failed
        case "error":
            self = .error
        default:
            self = .other(decodedValue)
        }
    }

    private var encodedValue: String {
        switch self {
        case .scheduled:
            return "scheduled"
        case .paused:
            return "paused"
        case .running:
            return "running"
        case .failed:
            return "failed"
        case .error:
            return "error"
        case .other(let value):
            return value
        }
    }
}

struct CronSchedule: Codable, Hashable {
    let kind: String?
    let expr: String?
    let timezone: String?
}

struct CronRecurrence: Codable, Hashable {
    let times: Int?
    let remaining: Int?
}

struct CronJobOrigin: Codable, Hashable {
    let kind: String?
    let source: String?
    let label: String?
}

enum CronSchedulePreset: String, CaseIterable, Identifiable {
    case afterDelay
    case atDateTime
    case everyInterval
    case hourly
    case daily
    case weekdays
    case weekly
    case monthly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .afterDelay:
            return "One Time After"
        case .atDateTime:
            return "One Time At"
        case .everyInterval:
            return "Every"
        case .hourly:
            return "Hourly"
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .custom:
            return "Custom"
        }
    }
}

enum CronIntervalUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours
    case days

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .minutes:
            return "m"
        case .hours:
            return "h"
        case .days:
            return "d"
        }
    }

    var title: String {
        switch self {
        case .minutes:
            return "Minutes"
        case .hours:
            return "Hours"
        case .days:
            return "Days"
        }
    }

    func displayLabel(for value: Int) -> String {
        switch self {
        case .minutes:
            return L10n.string(value == 1 ? "minute" : "minutes")
        case .hours:
            return L10n.string(value == 1 ? "hour" : "hours")
        case .days:
            return L10n.string(value == 1 ? "day" : "days")
        }
    }
}

enum CronDeliveryPreset: String, CaseIterable, Identifiable {
    case local
    case origin
    case all
    case telegram
    case discord
    case slack
    case whatsapp
    case email
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local:
            return "Local Only"
        case .origin:
            return "Origin Chat"
        case .all:
            return "All Connected Channels"
        case .telegram:
            return "Telegram Home"
        case .discord:
            return "Discord Home"
        case .slack:
            return "Slack Home"
        case .whatsapp:
            return "WhatsApp Home"
        case .email:
            return "Email"
        case .custom:
            return "Custom Target"
        }
    }

    var resolvedValue: String? {
        switch self {
        case .local:
            return "local"
        case .origin:
            return "origin"
        case .all:
            return "all"
        case .telegram:
            return "telegram"
        case .discord:
            return "discord"
        case .slack:
            return "slack"
        case .whatsapp:
            return "whatsapp"
        case .email:
            return "email"
        case .custom:
            return nil
        }
    }

    static func from(deliveryTarget: String?) -> (preset: CronDeliveryPreset, customValue: String) {
        let trimmed = deliveryTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return (.custom, "")
        }

        switch trimmed {
        case "local":
            return (.local, "")
        case "origin":
            return (.origin, "")
        case "all":
            return (.all, "")
        case "telegram":
            return (.telegram, "")
        case "discord":
            return (.discord, "")
        case "slack":
            return (.slack, "")
        case "whatsapp":
            return (.whatsapp, "")
        case "email":
            return (.email, "")
        default:
            return (.custom, trimmed)
        }
    }
}

struct CronScheduleDraft: Hashable {
    var preset: CronSchedulePreset
    var hour: Int
    var minute: Int
    var weekday: Int
    var dayOfMonth: Int
    var intervalValue: Int
    var intervalUnit: CronIntervalUnit
    var oneTimeDate: Date
    var customExpression: String

    init(
        preset: CronSchedulePreset = .daily,
        hour: Int = 9,
        minute: Int = 0,
        weekday: Int = 1,
        dayOfMonth: Int = 1,
        intervalValue: Int = 1,
        intervalUnit: CronIntervalUnit = .hours,
        oneTimeDate: Date = Date().addingTimeInterval(3600),
        customExpression: String = ""
    ) {
        self.preset = preset
        self.hour = max(0, min(hour, 23))
        self.minute = max(0, min(minute, 59))
        self.weekday = max(0, min(weekday, 6))
        self.dayOfMonth = max(1, min(dayOfMonth, 31))
        self.intervalValue = max(1, intervalValue)
        self.intervalUnit = intervalUnit
        self.oneTimeDate = oneTimeDate
        self.customExpression = customExpression
    }

    init(job: CronJob) {
        self = Self.from(expression: job.rawScheduleText)
    }

    static func from(expression: String?) -> CronScheduleDraft {
        guard let expression else { return CronScheduleDraft() }

        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (value, unit) = CronScheduleFormatter.oneTimeDelayComponents(from: trimmed) {
            return CronScheduleDraft(
                preset: .afterDelay,
                intervalValue: value,
                intervalUnit: unit,
                customExpression: trimmed
            )
        }

        if let (value, unit) = CronScheduleFormatter.intervalComponents(from: trimmed) {
            return CronScheduleDraft(
                preset: .everyInterval,
                intervalValue: value,
                intervalUnit: unit,
                customExpression: trimmed
            )
        }

        if let date = CronScheduleFormatter.date(from: trimmed) {
            return CronScheduleDraft(
                preset: .atDateTime,
                oneTimeDate: date,
                customExpression: trimmed
            )
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else {
            return CronScheduleDraft(preset: .custom, customExpression: trimmed)
        }

        let minute = Int(parts[0])
        let hour = Int(parts[1])
        let dayOfMonth = Int(parts[2])
        let month = parts[3]
        let dayOfWeek = parts[4]

        if parts[2] == "*",
           month == "*",
           dayOfWeek == "*",
           let minute,
           parts[1] == "*" {
            return CronScheduleDraft(
                preset: .hourly,
                minute: minute,
                customExpression: trimmed
            )
        }

        guard let minute, let hour, month == "*" else {
            return CronScheduleDraft(preset: .custom, customExpression: trimmed)
        }

        if parts[2] == "*", dayOfWeek == "*" {
            return CronScheduleDraft(
                preset: .daily,
                hour: hour,
                minute: minute,
                customExpression: trimmed
            )
        }

        if parts[2] == "*", dayOfWeek == "1-5" {
            return CronScheduleDraft(
                preset: .weekdays,
                hour: hour,
                minute: minute,
                customExpression: trimmed
            )
        }

        if parts[2] == "*",
           let weekday = CronScheduleFormatter.weekdayIndex(for: dayOfWeek) {
            return CronScheduleDraft(
                preset: .weekly,
                hour: hour,
                minute: minute,
                weekday: weekday,
                customExpression: trimmed
            )
        }

        if dayOfWeek == "*",
           let dayOfMonth {
            return CronScheduleDraft(
                preset: .monthly,
                hour: hour,
                minute: minute,
                dayOfMonth: dayOfMonth,
                customExpression: trimmed
            )
        }

        return CronScheduleDraft(preset: .custom, customExpression: trimmed)
    }

    var expression: String? {
        switch preset {
        case .afterDelay:
            return "\(intervalValue)\(intervalUnit.shortLabel)"
        case .atDateTime:
            return CronScheduleFormatter.localTimestampString(from: oneTimeDate)
        case .everyInterval:
            return "every \(intervalValue)\(intervalUnit.shortLabel)"
        case .hourly:
            return String(format: "%d * * * *", minute)
        case .daily:
            return String(format: "%d %d * * *", minute, hour)
        case .weekdays:
            return String(format: "%d %d * * 1-5", minute, hour)
        case .weekly:
            return String(format: "%d %d * * %d", minute, hour, weekday)
        case .monthly:
            return String(format: "%d %d %d * *", minute, hour, dayOfMonth)
        case .custom:
            let trimmed = customExpression.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    var summary: String {
        guard let expression else { return L10n.string("No schedule") }
        return CronScheduleFormatter.humanReadableDescription(for: expression) ?? expression
    }
}

struct CronJobDraft: Hashable {
    var name: String
    var prompt: String
    var script: String
    var workdir: String
    var noAgent: Bool
    var skillsText: String
    var model: String
    var provider: String
    var baseURL: String
    var deliveryPreset: CronDeliveryPreset
    var customDeliveryTarget: String
    var timezone: String
    var schedule: CronScheduleDraft

    init(
        name: String = "",
        prompt: String = "",
        script: String = "",
        workdir: String = "",
        noAgent: Bool = false,
        skillsText: String = "",
        model: String = "",
        provider: String = "",
        baseURL: String = "",
        deliveryPreset: CronDeliveryPreset = .local,
        customDeliveryTarget: String = "",
        timezone: String = "",
        schedule: CronScheduleDraft = CronScheduleDraft()
    ) {
        self.name = name
        self.prompt = prompt
        self.script = script
        self.workdir = workdir
        self.noAgent = noAgent
        self.skillsText = skillsText
        self.model = model
        self.provider = provider
        self.baseURL = baseURL
        self.deliveryPreset = deliveryPreset
        self.customDeliveryTarget = customDeliveryTarget
        self.timezone = timezone
        self.schedule = schedule
    }

    init(job: CronJob) {
        let parsedDelivery = CronDeliveryPreset.from(deliveryTarget: job.deliveryTarget)
        self.name = job.resolvedName
        self.prompt = job.trimmedPrompt ?? job.prompt
        self.script = job.trimmedScript ?? ""
        self.workdir = job.trimmedWorkdir ?? ""
        self.noAgent = job.noAgent
        self.skillsText = job.skills.joined(separator: ", ")
        self.model = job.model ?? ""
        self.provider = job.provider ?? ""
        self.baseURL = job.baseURL ?? ""
        self.deliveryPreset = parsedDelivery.preset
        self.customDeliveryTarget = parsedDelivery.customValue
        self.timezone = job.schedule?.timezone ?? ""
        self.schedule = CronScheduleDraft(job: job)
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedScript: String? {
        normalizedOptional(script)
    }

    var normalizedWorkdir: String? {
        normalizedOptional(workdir)
    }

    var normalizedSkills: [String] {
        skillsText
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var normalizedModel: String? {
        normalizedOptional(model)
    }

    var normalizedProvider: String? {
        normalizedOptional(provider)
    }

    var normalizedBaseURL: String? {
        normalizedOptional(baseURL)
    }

    var normalizedDeliveryTarget: String? {
        if let resolvedValue = deliveryPreset.resolvedValue {
            return resolvedValue
        }

        return normalizedOptional(customDeliveryTarget)
    }

    var normalizedTimezone: String? {
        switch schedule.preset {
        case .afterDelay, .atDateTime, .everyInterval:
            return nil
        case .hourly, .daily, .weekdays, .weekly, .monthly, .custom:
            break
        }
        return normalizedOptional(timezone)
    }

    var validationError: String? {
        if normalizedName.isEmpty {
            return "A cron job title is required."
        }

        if noAgent {
            if normalizedScript == nil {
                return "A script path is required for script-only jobs."
            }
        } else if normalizedPrompt.isEmpty {
            return "A prompt is required."
        }

        guard let expression = schedule.expression else {
            return "A valid schedule is required."
        }

        if expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "A valid schedule is required."
        }

        if normalizedDeliveryTarget == nil {
            return "A delivery target is required."
        }

        return nil
    }

    private func normalizedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum CronScheduleFormatter {
    private static let weekdaySymbols = [
        "0": "Sun",
        "1": "Mon",
        "2": "Tue",
        "3": "Wed",
        "4": "Thu",
        "5": "Fri",
        "6": "Sat",
        "7": "Sun",
        "sun": "Sun",
        "mon": "Mon",
        "tue": "Tue",
        "wed": "Wed",
        "thu": "Thu",
        "fri": "Fri",
        "sat": "Sat"
    ]

    static let weekdayPickerLabels = [
        "Sunday",
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday"
    ]

    static func humanReadableDescription(for expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)

        if let (value, unit) = oneTimeDelayComponents(from: trimmed) {
            return L10n.string("Once in %@ %@", "\(value)", unit.displayLabel(for: value))
        }

        if let (value, unit) = intervalComponents(from: trimmed) {
            return L10n.string("Every %@ %@", "\(value)", unit.displayLabel(for: value))
        }

        if let date = date(from: trimmed) {
            return L10n.string("Once on %@", DateFormatters.shortDateTimeFormatter().string(from: date))
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else { return nil }

        let minute = parts[0]
        let hour = parts[1]
        let dayOfMonth = parts[2]
        let month = parts[3]
        let dayOfWeek = parts[4]

        if hour == "*", month == "*", dayOfMonth == "*", dayOfWeek == "*",
           let minuteValue = Int(minute) {
            return L10n.string("Every hour at :%@", String(format: "%02d", minuteValue))
        }

        guard let time = formattedTime(hour: hour, minute: minute) else {
            return nil
        }

        if dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            return L10n.string("Every day at %@", time)
        }

        if dayOfMonth == "*", month == "*", dayOfWeek == "1-5" {
            return L10n.string("Every weekday at %@", time)
        }

        if dayOfMonth == "*", month == "*",
           let days = formattedWeekdays(dayOfWeek) {
            return L10n.string("Every %@ at %@", days, time)
        }

        if month == "*", dayOfWeek == "*",
           let day = Int(dayOfMonth) {
            return L10n.string("On day %@ of every month at %@", "\(day)", time)
        }

        return nil
    }

    private static func formattedTime(hour: String, minute: String) -> String? {
        guard let hourValue = Int(hour), let minuteValue = Int(minute),
              (0...23).contains(hourValue), (0...59).contains(minuteValue) else {
            return nil
        }

        return String(format: "%02d:%02d", hourValue, minuteValue)
    }

    private static func formattedWeekdays(_ rawValue: String) -> String? {
        let values = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        guard !values.isEmpty else { return nil }

        let resolved = values.compactMap { weekdaySymbols[$0] }
        guard resolved.count == values.count else { return nil }

        return resolved.map { L10n.string($0) }.joined(separator: ", ")
    }

    static func weekdayIndex(for rawValue: String) -> Int? {
        let lowered = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch lowered {
        case "0", "7", "sun":
            return 0
        case "1", "mon":
            return 1
        case "2", "tue":
            return 2
        case "3", "wed":
            return 3
        case "4", "thu":
            return 4
        case "5", "fri":
            return 5
        case "6", "sat":
            return 6
        default:
            return nil
        }
    }

    static func oneTimeDelayComponents(from value: String) -> (Int, CronIntervalUnit)? {
        durationComponents(from: value)
    }

    static func intervalComponents(from value: String) -> (Int, CronIntervalUnit)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("every ") else { return nil }
        return durationComponents(from: String(trimmed.dropFirst(6)))
    }

    static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = ISO8601DateFormatter.fractionalSecondsFormatter().date(from: trimmed) {
            return date
        }
        if let date = ISO8601DateFormatter().date(from: trimmed) {
            return date
        }
        return localTimestampFormatter.date(from: trimmed)
    }

    static func localTimestampString(from date: Date) -> String {
        localTimestampFormatter.string(from: date)
    }

    private static func durationComponents(from value: String) -> (Int, CronIntervalUnit)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 2,
              let quantity = Int(trimmed.dropLast()) else {
            return nil
        }

        switch trimmed.suffix(1) {
        case "m":
            return (quantity, .minutes)
        case "h":
            return (quantity, .hours)
        case "d":
            return (quantity, .days)
        default:
            return nil
        }
    }

    private static let localTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
